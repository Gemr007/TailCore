// Package tunnel — тонкая обёртка над sing-box: старт, стоп, статус.
//
// Единственное состояние ядра живёт здесь. Наружу (CLI, gomobile, cgo)
// торчат три функции, работающие только со строками, — так один и тот же
// API переживает любой мост: platform channel, FFI, командную строку.
package tunnel

import (
	"encoding/json"
	"sync"
	"time"
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
	current   engine
	state     = StateStopped
	startedAt time.Time
	lastErr   string
)

// Start поднимает туннель по конфигу в формате JSON.
//
// Движок выбирается конвертом `{"engine": "...", "config": {...}}`; конфиг
// без конверта считается конфигом sing-box — так было до появления второго
// движка, и ломать это незачем.
//
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

	next, err := newEngine(configJSON)
	if err != nil {
		return fail(err)
	}
	if err := next.start(); err != nil {
		return fail(err)
	}

	current = next
	startedAt = time.Now()
	state = StateRunning
	return nil
}

// Stop гасит туннель. На уже остановленном ядре — no-op, чтобы UI мог
// звать Stop вслепую (например, при выходе из приложения).
func Stop() error {
	mu.Lock()
	defer mu.Unlock()

	if current == nil {
		state = StateStopped
		return nil
	}
	err := current.close()
	// Счётчики привязаны к сессии вместе с движком: следующий Start
	// начинает с нуля.
	current = nil
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
	if current != nil {
		s.Uplink, s.Downlink = current.totals()
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
