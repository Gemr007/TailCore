package tunnel

import (
	"encoding/json"
)

// Названия движков. Они же приезжают в конфиге из приложения.
const (
	EngineSingBox = "singbox"
	EngineXray    = "xray"
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
}

// split разбирает конверт и возвращает имя движка и его конфиг.
func split(configJSON string) (string, string) {
	var e envelope
	if err := json.Unmarshal([]byte(configJSON), &e); err != nil {
		return EngineSingBox, configJSON
	}
	if e.Engine == "" || len(e.Config) == 0 {
		return EngineSingBox, configJSON
	}
	return e.Engine, string(e.Config)
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
	default:
		return nil, tunnelError("unknown engine: " + name)
	}
}
