// Package tunnel — тонкая обёртка над sing-box: старт, стоп, статус.
//
// Единственное состояние ядра живёт здесь. Наружу (CLI, gomobile, cgo)
// торчат три функции, работающие только со строками, — так один и тот же
// API переживает любой мост: platform channel, FFI, командную строку.
package tunnel

import (
	"context"
	"encoding/json"
	"sync"
	"time"

	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"
)

// Состояния туннеля.
const (
	StateStopped  = "stopped"
	StateStarting = "starting"
	StateRunning  = "running"
)

// snapshot — состояние ядра. Наружу уходит только как JSON из Status(),
// потому что через FFI-границу дешевле всего проходит строка.
type snapshot struct {
	State string `json:"state"`
	// Since — момент выхода в running, RFC3339. Пусто, если не запущен.
	Since string `json:"since,omitempty"`
	// Error — причина последнего неудачного старта. Сбрасывается при следующем Start.
	Error string `json:"error,omitempty"`
	// Uplink/Downlink — байты нарастающим итогом за текущую сессию.
	// Скорость из них считает вызывающая сторона: она и так опрашивает
	// статус по таймеру, и только она знает, какой интервал показывает.
	Uplink   int64 `json:"uplink"`
	Downlink int64 `json:"downlink"`
}

var (
	mu        sync.Mutex
	instance  *box.Box
	traffic   *counter
	state     = StateStopped
	startedAt time.Time
	lastErr   string
)

// Start поднимает туннель по конфигу sing-box в формате JSON.
// Повторный вызов на запущенном ядре — ошибка, а не тихий рестарт:
// перезапуск должен быть явным решением вызывающей стороны.
func Start(configJSON string) error {
	mu.Lock()
	defer mu.Unlock()

	if state != StateStopped {
		return errAlreadyRunning
	}
	lastErr = ""
	state = StateStarting

	ctx := include.Context(context.Background())
	options, err := sjson.UnmarshalExtendedContext[option.Options](ctx, []byte(configJSON))
	if err != nil {
		return fail(err)
	}

	inst, err := box.New(box.Options{Context: ctx, Options: options})
	if err != nil {
		return fail(err)
	}

	// Счётчик вешаем до старта: соединения, проскочившие между Start и
	// AppendTracker, в статистику бы не попали.
	c := &counter{}
	inst.Router().AppendTracker(c)

	if err := inst.Start(); err != nil {
		// Частично поднятый box держит сокеты — закрываем, иначе следующий
		// старт упрётся в занятый порт.
		inst.Close()
		return fail(err)
	}

	instance = inst
	traffic = c
	startedAt = time.Now()
	state = StateRunning
	return nil
}

// Stop гасит туннель. На уже остановленном ядре — no-op, чтобы UI мог
// звать Stop вслепую (например, при выходе из приложения).
func Stop() error {
	mu.Lock()
	defer mu.Unlock()

	if instance == nil {
		state = StateStopped
		return nil
	}
	err := instance.Close()
	instance = nil
	// Счётчики привязаны к сессии: следующий Start начинает с нуля.
	traffic = nil
	state = StateStopped
	startedAt = time.Time{}
	return err
}

// Status возвращает JSON-снимок состояния.
func Status() string {
	mu.Lock()
	s := snapshot{State: state, Error: lastErr}
	if state == StateRunning {
		s.Since = startedAt.Format(time.RFC3339)
	}
	if traffic != nil {
		s.Uplink, s.Downlink = traffic.totals()
	}
	mu.Unlock()

	// Строки и числа не умеют ломать json.Marshal.
	out, _ := json.Marshal(s)
	return string(out)
}

// fail откатывает состояние в stopped и запоминает причину.
// Вызывается только под уже взятым mu.
func fail(err error) error {
	state = StateStopped
	lastErr = err.Error()
	return err
}

type tunnelError string

func (e tunnelError) Error() string { return string(e) }

const errAlreadyRunning = tunnelError("tunnel is already running")
