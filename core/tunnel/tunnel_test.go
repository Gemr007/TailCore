package tunnel

import (
	"encoding/json"
	"net"
	"os"
	"strconv"
	"strings"
	"testing"
)

// staticConfig отдаёт testdata/vless.json с портом входящего, свободным
// прямо сейчас: 2080 из конфига по умолчанию на машине разработчика вполне
// может быть занят другим клиентом.
func staticConfig(t *testing.T) string {
	t.Helper()
	config, err := os.ReadFile("../testdata/vless.json")
	if err != nil {
		t.Fatal(err)
	}
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := l.Addr().(*net.TCPAddr).Port
	l.Close()
	return strings.Replace(string(config), `"listen_port": 2080`, `"listen_port": `+strconv.Itoa(port), 1)
}

// decode распаковывает JSON из Status() — иначе тест проверял бы подстроки.
func decode(t *testing.T) snapshot {
	t.Helper()
	var s snapshot
	if err := json.Unmarshal([]byte(Status()), &s); err != nil {
		t.Fatalf("status is not valid json: %v", err)
	}
	return s
}

// Проверяет весь цикл на реальном статическом VLESS-конфиге: он должен
// разбираться, подниматься (VLESS-исходящий подключается лениво, живой
// сервер для этого не нужен) и корректно гаситься.
func TestStartStopOnStaticVLESSConfig(t *testing.T) {
	config := staticConfig(t)

	if got := decode(t).State; got != StateStopped {
		t.Fatalf("state before start = %q, want %q", got, StateStopped)
	}

	if err := Start(config); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer Stop()

	s := decode(t)
	if s.State != StateRunning {
		t.Fatalf("state after start = %q, want %q", s.State, StateRunning)
	}
	if s.Since == "" {
		t.Error("running tunnel has no start time")
	}

	if err := Start(config); err == nil {
		t.Error("second start on a running tunnel must fail")
	}
	// Отказ во втором старте не должен ронять уже работающий туннель.
	if got := decode(t).State; got != StateRunning {
		t.Fatalf("state after rejected restart = %q, want %q", got, StateRunning)
	}

	if err := Stop(); err != nil {
		t.Fatalf("stop: %v", err)
	}
	if got := decode(t).State; got != StateStopped {
		t.Fatalf("state after stop = %q, want %q", got, StateStopped)
	}

	// Stop на остановленном ядре — no-op, UI зовёт его вслепую.
	if err := Stop(); err != nil {
		t.Errorf("second stop: %v", err)
	}
}

func TestStartRejectsBrokenConfig(t *testing.T) {
	if err := Start(`{"outbounds": [{"type": "no-such-protocol"}]}`); err == nil {
		t.Fatal("broken config must not start")
	}

	s := decode(t)
	if s.State != StateStopped {
		t.Errorf("state after failed start = %q, want %q", s.State, StateStopped)
	}
	if s.Error == "" {
		t.Error("failed start must leave an error in status")
	}
	if !strings.Contains(s.Error, "no-such-protocol") {
		t.Errorf("error %q does not mention the actual problem", s.Error)
	}
}
