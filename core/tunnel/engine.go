package tunnel

import (
	"encoding/json"
)

// Названия движков. Они же приезжают в конфиге из приложения.
const (
	EngineSingBox = "singbox"
	EngineXray    = "xray"

	// EngineChain — Xray под sing-box: Xray держит узел и отдаёт локальный
	// socks, sing-box ходит через него и делает всю маршрутизацию.
	EngineChain = "chain"
)

// engine — то немногое, что туннелю нужно от движка: поднять, погасить,
// сказать, сколько байт прошло. Всё остальное у sing-box и Xray устроено
// по-разному, и вытаскивать эти различия наверх незачем.
type engine interface {
	start() error
	close() error
	totals() (up, down int64)
}

// envelope — конверт, которым приложение говорит, каким движком поднимать
// конфиг. Угадывать по содержимому нельзя: у обоих движков в конфиге есть
// и inbounds, и outbounds, и различить их можно только по мелочам, которые
// завтра поменяются.
//
// Конверта может не быть вовсе: тогда это конфиг sing-box, как было до
// появления второго движка.
type envelope struct {
	Engine string          `json:"engine"`
	Config json.RawMessage `json:"config"`

	// Xray — конфиг нижнего движка в цепочке. Пусто у всех движков, кроме
	// chain.
	Xray json.RawMessage `json:"xray"`
}

// split разбирает конверт и возвращает имя движка и его конфиг.
func split(configJSON string) (string, string) {
	e, err := parseEnvelope(configJSON)
	if err != nil || e.Engine == "" || len(e.Config) == 0 {
		return EngineSingBox, configJSON
	}
	return e.Engine, string(e.Config)
}

func parseEnvelope(configJSON string) (envelope, error) {
	var e envelope
	err := json.Unmarshal([]byte(configJSON), &e)
	return e, err
}

// newEngine собирает движок под конфиг, но не запускает его: неудачный
// старт должен оставить состояние нетронутым, а для этого его сперва надо
// собрать целиком.
func newEngine(configJSON string) (engine, error) {
	name, config := split(configJSON)
	switch name {
	case EngineXray:
		return newXrayEngine(config)
	case EngineSingBox:
		return newSingBoxEngine(config)
	case EngineChain:
		e, err := parseEnvelope(configJSON)
		if err != nil {
			return nil, err
		}
		return newChainEngine(string(e.Xray), config)
	default:
		return nil, tunnelError("unknown engine: " + name)
	}
}

// chainEngine — Xray под sing-box.
//
// Xray умеет транспорты, которых нет в sing-box (XHTTP, mKCP), но не умеет
// ничего из нашей маршрутизации: rule-set `.srs` он не читает, правил по
// процессам у него нет вовсе. Поэтому он держит только узел и отдаёт
// локальный socks, а весь роутинг, DNS и счётчики остаются за sing-box —
// иначе включённые настройки молча перестали бы действовать на таких узлах.
type chainEngine struct {
	lower engine
	upper engine
}

func newChainEngine(xrayConfig, singboxConfig string) (engine, error) {
	if xrayConfig == "" {
		return nil, tunnelError("chain engine without an xray config")
	}
	lower, err := newXrayEngine(xrayConfig)
	if err != nil {
		return nil, err
	}
	upper, err := newSingBoxEngine(singboxConfig)
	if err != nil {
		lower.close()
		return nil, err
	}
	return &chainEngine{lower: lower, upper: upper}, nil
}

func (e *chainEngine) start() error {
	// Порядок обязателен: sing-box при старте ходит через нижний socks, и
	// если его ещё нет, соединение не поднимется.
	if err := e.lower.start(); err != nil {
		return err
	}
	if err := e.upper.start(); err != nil {
		e.lower.close()
		return err
	}
	return nil
}

func (e *chainEngine) close() error {
	err := e.upper.close()
	if lowerErr := e.lower.close(); err == nil {
		err = lowerErr
	}
	return err
}

// Счётчики берутся только у sing-box: через него проходит всё, и цифры
// Xray были бы тем же трафиком, посчитанным второй раз.
func (e *chainEngine) totals() (int64, int64) { return e.upper.totals() }
