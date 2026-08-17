package tunnel

import (
	"context"
	"io"
	"net"
	"net/http"
	"strconv"
	"testing"
	"time"

	"golang.org/x/net/proxy"
)

// Конфиг Xray с локальным socks-входящим и прямым исходящим: живой сервер
// для проверки движка не нужен, а путь клиент → Xray → сайт настоящий.
//
// stats и policy здесь не для красоты: без них Xray не считает байты
// вообще, и счётчики туннеля остались бы нулями при работающем соединении.
func xrayConfig(port int) string {
	return `{
	  "engine": "xray",
	  "config": {
	    "log": {"loglevel": "error"},
	    "stats": {},
	    "policy": {"system": {"statsOutboundUplink": true, "statsOutboundDownlink": true}},
	    "inbounds": [{
	      "tag": "local",
	      "listen": "127.0.0.1",
	      "port": ` + strconv.Itoa(port) + `,
	      "protocol": "socks",
	      "settings": {"udp": false}
	    }],
	    "outbounds": [{"tag": "proxy", "protocol": "freedom"}]
	  }
	}`
}

// Движок выбирается конвертом, а не угадыванием по содержимому конфига.
func TestEngineIsChosenByEnvelope(t *testing.T) {
	name, config := split(`{"engine": "xray", "config": {"log": {}}}`)
	if name != EngineXray {
		t.Errorf("engine = %q, want %q", name, EngineXray)
	}
	if config != `{"log": {}}` {
		t.Errorf("config = %q, want the inner object", config)
	}

	// Конфиг без конверта — по-прежнему sing-box: так работали все версии
	// до второго движка, и ломать это нельзя.
	name, config = split(`{"outbounds": [{"type": "direct"}]}`)
	if name != EngineSingBox {
		t.Errorf("bare config engine = %q, want %q", name, EngineSingBox)
	}
	if config != `{"outbounds": [{"type": "direct"}]}` {
		t.Error("bare config must be passed through untouched")
	}

	if _, err := newEngine(`{"engine": "nope", "config": {}}`); err == nil {
		t.Error("unknown engine must be rejected, not silently defaulted")
	}
}

// Полный цикл на движке Xray: поднимается, отдаёт статус, считает трафик,
// гаснет. Счётчики проверяются настоящим запросом через прокси — цифры,
// которые никогда не менялись, ничего не доказывают.
func TestXrayEngineStartsCountsAndStops(t *testing.T) {
	target := httpTestServer(t)
	port := freePort(t)

	if err := Start(xrayConfig(port)); err != nil {
		t.Fatalf("start: %v", err)
	}
	defer Stop()

	if got := decode(t).State; got != StateRunning {
		t.Fatalf("state after start = %q, want %q", got, StateRunning)
	}

	if err := fetchThroughSocks(port, target); err != nil {
		t.Fatalf("request through xray: %v", err)
	}

	// Счётчики Xray обновляются не мгновенно после закрытия соединения.
	var s snapshot
	for range 20 {
		s = decode(t)
		if s.Uplink > 0 && s.Downlink > 0 {
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if s.Uplink == 0 || s.Downlink == 0 {
		t.Errorf("traffic counters stayed at zero: up=%d down=%d", s.Uplink, s.Downlink)
	}

	if err := Stop(); err != nil {
		t.Fatalf("stop: %v", err)
	}
	if got := decode(t).State; got != StateStopped {
		t.Fatalf("state after stop = %q, want %q", got, StateStopped)
	}
}

// Цепочка: Xray держит узел и отдаёт локальный socks, sing-box ходит через
// него. Проверяется весь путь целиком — запрос через входящий sing-box
// должен дойти до сайта и попасть в счётчики sing-box, а не Xray.
func TestChainEngineRoutesThroughBothCores(t *testing.T) {
	target := httpTestServer(t)
	bridgePort := freePort(t)
	entryPort := freePort(t)

	config := `{
	  "engine": "chain",
	  "xray": {
	    "log": {"loglevel": "error"},
	    "inbounds": [{
	      "tag": "bridge", "listen": "127.0.0.1", "port": ` + strconv.Itoa(bridgePort) + `,
	      "protocol": "socks", "settings": {"udp": true}
	    }],
	    "outbounds": [{"tag": "proxy", "protocol": "freedom"}]
	  },
	  "config": {
	    "log": {"level": "error"},
	    "inbounds": [{
	      "type": "mixed", "tag": "local",
	      "listen": "127.0.0.1", "listen_port": ` + strconv.Itoa(entryPort) + `
	    }],
	    "outbounds": [
	      {"type": "socks", "tag": "proxy", "server": "127.0.0.1", "server_port": ` +
		strconv.Itoa(bridgePort) + `, "version": "5"},
	      {"type": "direct", "tag": "direct"}
	    ],
	    "route": {"final": "proxy"}
	  }
	}`

	if err := Start(config); err != nil {
		t.Fatalf("start chain: %v", err)
	}
	defer Stop()

	if got := decode(t).State; got != StateRunning {
		t.Fatalf("state after start = %q, want %q", got, StateRunning)
	}

	if err := fetchThroughSocks(entryPort, target); err != nil {
		t.Fatalf("request through the chain: %v", err)
	}

	s := decode(t)
	if s.Uplink == 0 || s.Downlink == 0 {
		t.Errorf("counters stayed at zero: up=%d down=%d", s.Uplink, s.Downlink)
	}
}

// Верхний движок не поднялся — нижний обязан погаснуть следом: иначе Xray
// остался бы висеть на порту, а туннель считался бы остановленным.
func TestChainEngineDoesNotLeaveXrayRunning(t *testing.T) {
	bridgePort := freePort(t)
	busy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer busy.Close()
	takenPort := busy.Addr().(*net.TCPAddr).Port

	config := `{
	  "engine": "chain",
	  "xray": {
	    "log": {"loglevel": "error"},
	    "inbounds": [{
	      "tag": "bridge", "listen": "127.0.0.1", "port": ` + strconv.Itoa(bridgePort) + `,
	      "protocol": "socks", "settings": {}
	    }],
	    "outbounds": [{"tag": "proxy", "protocol": "freedom"}]
	  },
	  "config": {
	    "inbounds": [{
	      "type": "mixed", "tag": "local",
	      "listen": "127.0.0.1", "listen_port": ` + strconv.Itoa(takenPort) + `
	    }],
	    "outbounds": [{"type": "direct", "tag": "direct"}]
	  }
	}`

	if err := Start(config); err == nil {
		Stop()
		t.Fatal("start must fail: the sing-box inbound port is taken")
	}
	if got := decode(t).State; got != StateStopped {
		t.Fatalf("state after failed start = %q, want %q", got, StateStopped)
	}

	// Порт моста снова свободен только если Xray закрылся.
	listener, err := net.Listen("tcp", "127.0.0.1:"+strconv.Itoa(bridgePort))
	if err != nil {
		t.Fatalf("xray is still holding the bridge port: %v", err)
	}
	listener.Close()
}

func TestXrayRejectsBrokenConfig(t *testing.T) {
	err := Start(`{"engine": "xray", "config": {"outbounds": [{"protocol": "no-such-protocol"}]}}`)
	if err == nil {
		Stop()
		t.Fatal("broken xray config must not start")
	}
	s := decode(t)
	if s.State != StateStopped {
		t.Errorf("state after failed start = %q, want %q", s.State, StateStopped)
	}
	if s.Error == "" {
		t.Error("failed start must leave a reason in status")
	}
}

// fetchThroughSocks ходит по ссылке через локальный socks5 — тот самый
// путь, которым пойдёт трафик пользователя.
func fetchThroughSocks(port int, url string) error {
	dialer, err := proxy.SOCKS5("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)), nil, proxy.Direct)
	if err != nil {
		return err
	}
	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
				return dialer.Dial(network, addr)
			},
		},
	}
	response, err := client.Get(url)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	_, err = io.Copy(io.Discard, response.Body)
	return err
}
