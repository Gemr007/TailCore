package tunnel

import (
	"encoding/json"
	"io"
	"net"
	"strconv"
	"strings"
	"testing"
	"time"
)

// Гоняет настоящий трафик через поднятый туннель и проверяет, что счётчик
// его увидел. Без этого «статистика есть» означает лишь, что в JSON
// появились два нуля.
func TestCounterSeesRealTraffic(t *testing.T) {
	// Эхо-сервер играет роль сайта, до которого ходит клиент.
	echo, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer echo.Close()
	go func() {
		for {
			c, err := echo.Accept()
			if err != nil {
				return
			}
			go func() {
				defer c.Close()
				io.Copy(c, c)
			}()
		}
	}()

	proxyPort := freePort(t)
	config := `{
		"inbounds": [
			{"type": "mixed", "listen": "127.0.0.1", "listen_port": ` + strconv.Itoa(proxyPort) + `}
		],
		"outbounds": [{"type": "direct"}]
	}`
	if err := Start(config); err != nil {
		t.Fatal(err)
	}
	defer Stop()

	if up, down := totals(t); up != 0 || down != 0 {
		t.Fatalf("fresh tunnel already counted %d/%d bytes", up, down)
	}

	payload := strings.Repeat("x", 4096)
	echoThrough(t, proxyPort, echo.Addr().String(), payload)

	up, down := totals(t)
	if up < int64(len(payload)) {
		t.Errorf("uplink = %d bytes, want at least %d", up, len(payload))
	}
	if down < int64(len(payload)) {
		t.Errorf("downlink = %d bytes, want at least %d", down, len(payload))
	}
}

func freePort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func totals(t *testing.T) (up, down int64) {
	t.Helper()
	var s snapshot
	if err := json.Unmarshal([]byte(Status()), &s); err != nil {
		t.Fatal(err)
	}
	return s.Uplink, s.Downlink
}

// echoThrough гоняет payload туда-обратно через SOCKS5-вход туннеля.
func echoThrough(t *testing.T, proxyPort int, target, payload string) {
	t.Helper()
	conn, err := net.DialTimeout("tcp", "127.0.0.1:"+strconv.Itoa(proxyPort), 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(10 * time.Second))

	host, portStr, _ := net.SplitHostPort(target)
	port, _ := strconv.Atoi(portStr)

	// Приветствие SOCKS5 без аутентификации.
	if _, err := conn.Write([]byte{5, 1, 0}); err != nil {
		t.Fatal(err)
	}
	if _, err := io.ReadFull(conn, make([]byte, 2)); err != nil {
		t.Fatal(err)
	}
	// CONNECT на IPv4-адрес эхо-сервера.
	req := []byte{5, 1, 0, 1}
	req = append(req, net.ParseIP(host).To4()...)
	req = append(req, byte(port>>8), byte(port))
	if _, err := conn.Write(req); err != nil {
		t.Fatal(err)
	}
	if _, err := io.ReadFull(conn, make([]byte, 10)); err != nil {
		t.Fatal(err)
	}

	if _, err := conn.Write([]byte(payload)); err != nil {
		t.Fatal(err)
	}
	got := make([]byte, len(payload))
	if _, err := io.ReadFull(conn, got); err != nil {
		t.Fatal(err)
	}
	if string(got) != payload {
		t.Fatal("echo mismatch — traffic did not survive the tunnel")
	}
}
