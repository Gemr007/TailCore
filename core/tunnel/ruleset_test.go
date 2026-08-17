package tunnel

import (
	"context"
	"testing"

	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"
)

// Конфиг с доменным роутингом в том виде, в каком его собирает приложение
// (app/lib/core/singbox_config.dart) при включённом тумблере «игры мимо
// VPN». Ядро должно понимать эту форму: remote rule-set формата .srs,
// правило на него и файл кэша.
//
// Проверка только на разбор — скачивание списка требует сети и живого узла,
// а собирается ядро с теми же тегами, что и релизное (см. test-core.ps1).
const rulesetConfig = `{
  "log": {"level": "warn"},
  "outbounds": [
    {"type": "direct", "tag": "proxy"},
    {"type": "direct", "tag": "direct"}
  ],
  "route": {
    "rules": [{"rule_set": "geosite-category-games", "outbound": "direct"}],
    "rule_set": [
      {
        "type": "remote",
        "tag": "geosite-category-games",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-games.srs",
        "download_detour": "proxy",
        "update_interval": "7d"
      }
    ],
    "final": "proxy"
  },
  "experimental": {"cache_file": {"enabled": true, "path": "singbox-cache.db"}}
}`

func TestRuleSetConfigIsUnderstood(t *testing.T) {
	ctx := include.Context(context.Background())
	options, err := sjson.UnmarshalExtendedContext[option.Options](ctx, []byte(rulesetConfig))
	if err != nil {
		t.Fatalf("config with a remote rule-set does not parse: %v", err)
	}

	if len(options.Route.RuleSet) != 1 {
		t.Fatalf("rule-sets parsed = %d, want 1", len(options.Route.RuleSet))
	}
	set := options.Route.RuleSet[0]
	if set.Type != "remote" {
		t.Errorf("rule-set type = %q, want remote", set.Type)
	}
	// Формат обязателен: без него ядро не знает, .srs перед ним или json.
	if set.Format != "binary" {
		t.Errorf("rule-set format = %q, want binary", set.Format)
	}
	if set.RemoteOptions.DownloadDetour != "proxy" {
		t.Errorf("download detour = %q, want proxy", set.RemoteOptions.DownloadDetour)
	}
	if options.Experimental == nil || options.Experimental.CacheFile == nil ||
		!options.Experimental.CacheFile.Enabled {
		t.Error("cache file is off: rule-sets would be re-downloaded on every start")
	}
}
