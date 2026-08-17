package tunnel

import (
	"context"
	"strings"
	"testing"

	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"
)

// Протоколы, которые приложение умеет импортировать, обязаны быть в сборке.
// Половина из них спрятана за build-тегами, и без тега конфиг не
// разбирается вовсе — «unknown outbound type». Проверка идёт теми же
// тегами, что и релизная сборка (scripts/build-tags.txt).
//
// NaiveProxy сюда не входит намеренно: его тег тянет Cronet — прибитую к
// платформе библиотеку Chromium, и это решение о размере сборки, а не
// строчка в списке тегов. Импорт таких ссылок отвечает причиной.
func TestImportableProtocolsAreInTheBuild(t *testing.T) {
	outbounds := map[string]string{
		"shadowsocks": `{"type": "shadowsocks", "tag": "n", "server": "1.1.1.1", "server_port": 8388, "method": "aes-256-gcm", "password": "p"}`,
		"vless":       `{"type": "vless", "tag": "n", "server": "1.1.1.1", "server_port": 443, "uuid": "d3b0c442-98fc-4e1b-9dd8-2b1c9d0e1f2a"}`,
		"trojan":      `{"type": "trojan", "tag": "n", "server": "1.1.1.1", "server_port": 443, "password": "p"}`,
		"hysteria2":   `{"type": "hysteria2", "tag": "n", "server": "1.1.1.1", "server_port": 443, "password": "p"}`,
		"tuic":        `{"type": "tuic", "tag": "n", "server": "1.1.1.1", "server_port": 443, "uuid": "d3b0c442-98fc-4e1b-9dd8-2b1c9d0e1f2a"}`,
		"ssh":         `{"type": "ssh", "tag": "n", "server": "1.1.1.1", "server_port": 22, "user": "root", "password": "p"}`,
		"anytls":      `{"type": "anytls", "tag": "n", "server": "1.1.1.1", "server_port": 443, "password": "p"}`,
		"shadowtls":   `{"type": "shadowtls", "tag": "n", "server": "1.1.1.1", "server_port": 443, "version": 3, "password": "p", "tls": {"enabled": true, "server_name": "example.com"}}`,
	}

	for name, outbound := range outbounds {
		t.Run(name, func(t *testing.T) {
			ctx := include.Context(context.Background())
			config := `{"outbounds": [` + outbound + `]}`
			_, err := sjson.UnmarshalExtendedContext[option.Options](ctx, []byte(config))
			if err != nil {
				if strings.Contains(err.Error(), "unknown outbound type") {
					t.Fatalf("%s is missing from the build — check scripts/build-tags.txt: %v", name, err)
				}
				t.Fatalf("%s does not parse: %v", name, err)
			}
		})
	}
}

// Плагины SIP003 ядро исполняет само: obfs-local и v2ray-plugin — часть
// sing-box, внешний бинарник им не нужен.
func TestShadowsocksPluginsAreBuiltIn(t *testing.T) {
	ctx := include.Context(context.Background())
	config := `{"outbounds": [{
		"type": "shadowsocks", "tag": "n",
		"server": "1.1.1.1", "server_port": 8388,
		"method": "aes-256-gcm", "password": "p",
		"plugin": "obfs-local", "plugin_opts": "obfs=http;obfs-host=bing.com"
	}]}`

	options, err := sjson.UnmarshalExtendedContext[option.Options](ctx, []byte(config))
	if err != nil {
		t.Fatalf("shadowsocks with a plugin does not parse: %v", err)
	}
	if len(options.Outbounds) != 1 {
		t.Fatalf("outbounds parsed = %d, want 1", len(options.Outbounds))
	}
}
