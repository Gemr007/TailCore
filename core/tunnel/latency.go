package tunnel

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/common/urltest"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"
)

// Ссылка для замера. 204 без тела — самый дешёвый ответ, который можно
// получить от живого интернета.
const probeURL = "https://www.gstatic.com/generate_204"

// Служебные исходящие: они есть в любом конфиге и узлами не являются.
var serviceOutbounds = map[string]bool{
	"direct":   true,
	"block":    true,
	"dns":      true,
	"selector": true,
	"urltest":  true,
}

// Result — ответ замера. Причины отказов возвращаются наравне с
// задержками: «нет связи» без объяснения не даёт ни пользователю, ни
// разработчику ни одной зацепки, а причины у отказа бывают очень разные —
// от неразрешённого имени до закрытого порта.
type Result struct {
	Delays map[string]uint16 `json:"delays"`
	Errors map[string]string `json:"errors"`
}

// Test меряет задержку до каждого узла конфига и возвращает JSON с
// задержками и причинами отказов. Узел не попадает в delays, если не
// ответил: «не ответил» и «ответил за 0 мс» — разные вещи.
//
// Замер идёт через сам sing-box, а не через TCP-коннект на адрес узла:
// половина протоколов из списка (TUIC, Hysteria/2) живёт поверх QUIC, и
// TCP-проба до их порта провалилась бы, ничего не сказав о задержке.
//
// Каждый outbound проверяется напрямую, без группы urltest: группа
// запускает собственную фоновую проверку при старте, и её URLTest в это
// время возвращает пустой результат без ошибки — то есть «все узлы
// недоступны» на ровном месте.
//
// Конфиг не должен содержать входящих: Test поднимает отдельный экземпляр
// ядра, и занятый порт основного туннеля уронил бы замер.
func Test(configJSON string, timeoutSeconds int) (string, error) {
	return testWithLink(configJSON, timeoutSeconds, probeURL)
}

// testWithLink — тот же замер, но по указанной ссылке. Наружу не торчит:
// ссылка нужна только тестам, чтобы не ходить в интернет.
func testWithLink(configJSON string, timeoutSeconds int, link string) (string, error) {
	if timeoutSeconds <= 0 {
		timeoutSeconds = 10
	}

	ctx := include.Context(context.Background())
	options, err := sjson.UnmarshalExtendedContext[option.Options](ctx, []byte(configJSON))
	if err != nil {
		return "", err
	}

	inst, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		return "", err
	}
	if err := inst.Start(); err != nil {
		inst.Close()
		return "", err
	}
	defer inst.Close()

	testCtx, cancel := context.WithTimeout(ctx, time.Duration(timeoutSeconds)*time.Second)
	defer cancel()

	// Endpoints перечисляются отдельно: WireGuard в sing-box 1.13 — не
	// исходящий, а endpoint, и в Outbounds() его нет. Без этой строки
	// WireGuard-узлы молча не мерялись бы вовсе — ни задержки, ни ошибки.
	nodes := inst.Outbound().Outbounds()
	for _, e := range inst.Endpoint().Endpoints() {
		nodes = append(nodes, e)
	}

	out, err := json.Marshal(measure(testCtx, nodes, link))
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// measure опрашивает узлы одновременно: последовательный обход упёрся бы
// в самый медленный узел, помноженный на длину списка.
func measure(ctx context.Context, outbounds []adapter.Outbound, link string) Result {
	result := Result{
		Delays: map[string]uint16{},
		Errors: map[string]string{},
	}
	var (
		mu sync.Mutex
		wg sync.WaitGroup
	)

	for _, outbound := range outbounds {
		tag := outbound.Tag()
		if tag == "" || serviceOutbounds[outbound.Type()] {
			continue
		}
		wg.Add(1)
		go func() {
			defer wg.Done()
			delay, err := urltest.URLTest(ctx, link, outbound)
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				result.Errors[tag] = err.Error()
				return
			}
			result.Delays[tag] = delay
		}()
	}

	wg.Wait()
	return result
}
