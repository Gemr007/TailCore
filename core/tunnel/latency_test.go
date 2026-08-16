package tunnel

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
)

// Меряет задержку через настоящий прокси до настоящего HTTP-сервера и
// отдельно — до узла, которого нет. Первый обязан попасть в ответ, второй
// нет: замер, рапортующий о недоступном узле, хуже отсутствия замера.
func TestLatencyReportsOnlyReachableNodes(t *testing.T) {
	target := httpTestServer(t)

	// Живой узел — локальный SOCKS5, поднятый тем же ядром: так замер
	// проходит весь настоящий путь клиент → прокси → сайт.
	proxyPort := freePort(t)
	err := Start(`{
		"inbounds": [
			{"type": "mixed", "listen": "127.0.0.1", "listen_port": ` +
		strconv.Itoa(proxyPort) + `}
		],
		"outbounds": [{"type": "direct"}]
	}`)
	if err != nil {
		t.Fatalf("local proxy: %v", err)
	}
	defer Stop()

	config := `{
		"outbounds": [
			{"type": "socks", "tag": "alive", "server": "127.0.0.1", "server_port": ` +
		strconv.Itoa(proxyPort) + `},
			{"type": "socks", "tag": "dead", "server": "127.0.0.1", "server_port": ` +
		strconv.Itoa(freePort(t)) + `}
		]
	}`

	raw, err := testWithLink(config, 10, target)
	if err != nil {
		t.Fatalf("test: %v", err)
	}

	var result Result
	if err := json.Unmarshal([]byte(raw), &result); err != nil {
		t.Fatalf("result is not valid json: %s", raw)
	}

	if _, ok := result.Delays["alive"]; !ok {
		t.Errorf("reachable node missing from %v", result.Delays)
	}
	if _, ok := result.Delays["dead"]; ok {
		t.Errorf("unreachable node reported as measured in %v", result.Delays)
	}
	// Причина отказа обязана вернуться: без неё «нет связи» не отличить от
	// «замер не дошёл до узла», и чинить нечего.
	if reason := result.Errors["dead"]; reason == "" {
		t.Error("unreachable node came back without a reason")
	}
}

// Служебные исходящие узлами не являются и в замер попадать не должны:
// иначе пользователь увидит в списке «direct» с прекрасной задержкой.
func TestLatencySkipsServiceOutbounds(t *testing.T) {
	target := httpTestServer(t)

	raw, err := testWithLink(
		`{"outbounds": [{"type": "direct", "tag": "direct"}, {"type": "block", "tag": "block"}]}`,
		5, target,
	)
	if err != nil {
		t.Fatalf("test: %v", err)
	}
	var result Result
	if err := json.Unmarshal([]byte(raw), &result); err != nil {
		t.Fatalf("result is not valid json: %s", raw)
	}
	if len(result.Delays) != 0 || len(result.Errors) != 0 {
		t.Errorf("service outbounds measured: %s", raw)
	}
}

func TestLatencyRejectsBrokenConfig(t *testing.T) {
	if _, err := testWithLink(`{"outbounds": [{"type": "nope"}]}`, 5, "http://x"); err == nil {
		t.Fatal("broken config must be rejected")
	}
}

func httpTestServer(t *testing.T) string {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(
		func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusNoContent)
		},
	))
	t.Cleanup(server.Close)
	return server.URL + "/generate_204"
}
