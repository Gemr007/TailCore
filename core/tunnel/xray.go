package tunnel

import (
	"strings"

	xcore "github.com/xtls/xray-core/core"
	"github.com/xtls/xray-core/features/stats"
	"github.com/xtls/xray-core/infra/conf/serial"

	// Регистрирует протоколы и транспорты Xray. Без этого импорта ядро
	// собирается, но не понимает ни одного outbound'а из конфига.
	_ "github.com/xtls/xray-core/main/distro/all"
)

// Тег исходящего, по которому приложение собирает конфиг Xray. Счётчики
// трафика в Xray именуются по тегу, и знать его надо обеим сторонам.
const xrayProxyTag = "proxy"

// xrayEngine — второй движок. Нужен ровно там, где sing-box бессилен:
// XHTTP, mKCP и прочие транспорты Xray, которых в sing-box нет.
//
// Счётчики здесь устроены иначе, чем в sing-box: Xray считает их сам,
// но только если в конфиге включены stats и политика на исходящий. Конфиг
// приходит из приложения, поэтому счётчик может и не найтись — тогда
// туннель работает, а цифры остаются нулями.
type xrayEngine struct {
	instance *xcore.Instance
	up       stats.Counter
	down     stats.Counter
}

func newXrayEngine(configJSON string) (engine, error) {
	config, err := serial.LoadJSONConfig(strings.NewReader(configJSON))
	if err != nil {
		return nil, err
	}

	instance, err := xcore.New(config)
	if err != nil {
		return nil, err
	}
	return &xrayEngine{instance: instance}, nil
}

func (e *xrayEngine) start() error {
	if err := e.instance.Start(); err != nil {
		e.instance.Close()
		return err
	}
	// Счётчики появляются только после старта: до него менеджера статистики
	// в инстансе ещё нет.
	if manager, ok := e.instance.GetFeature(stats.ManagerType()).(stats.Manager); ok && manager != nil {
		e.up = manager.GetCounter("outbound>>>" + xrayProxyTag + ">>>traffic>>>uplink")
		e.down = manager.GetCounter("outbound>>>" + xrayProxyTag + ">>>traffic>>>downlink")
	}
	return nil
}

func (e *xrayEngine) close() error { return e.instance.Close() }

func (e *xrayEngine) totals() (int64, int64) {
	var up, down int64
	if e.up != nil {
		up = e.up.Value()
	}
	if e.down != nil {
		down = e.down.Value()
	}
	return up, down
}
