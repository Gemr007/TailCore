import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailcore/core/prefs.dart';
import 'package:tailcore/core/server.dart';
import 'package:tailcore/core/singbox_config.dart';

Server _node() => Server.fromOutbound({
  'type': 'vless',
  'tag': 'ams-02',
  'server': '1.2.3.4',
  'server_port': 8443,
  'uuid': 'u',
})!;

Map<String, dynamic> _config({required bool bypassGames}) {
  return jsonDecode(
    buildRunConfig(
      _node(),
      bypassGames: bypassGames,
      cachePath: '/tmp/singbox-cache.db',
    ),
  ) as Map<String, dynamic>;
}

void main() {
  test('без тумблера в конфиге нет ни правил, ни rule-set', () {
    final route = _config(bypassGames: false)['route'] as Map<String, dynamic>;

    expect(route['final'], 'proxy');
    expect(route.containsKey('rules'), isFalse);
    expect(route.containsKey('rule_set'), isFalse);
    // Кэш нужен только rule-set'ам — без них он лишний файл на диске.
    expect(_config(bypassGames: false).containsKey('experimental'), isFalse);
  });

  test('тумблер уводит игровые домены в direct', () {
    final config = _config(bypassGames: true);
    final route = config['route'] as Map<String, dynamic>;

    expect(route['rules'], [
      {'rule_set': gamesRuleSet, 'outbound': 'direct'},
    ]);
    // Остальное по-прежнему идёт в туннель.
    expect(route['final'], 'proxy');

    final ruleSet = (route['rule_set'] as List).single as Map<String, dynamic>;
    expect(ruleSet['type'], 'remote');
    expect(ruleSet['tag'], gamesRuleSet);
    // Формат .srs, а не устаревшее поле geosite.
    expect(ruleSet['format'], 'binary');
    expect(ruleSet['url'], endsWith('$gamesRuleSet.srs'));
    // Загрузка идёт через туннель: напрямую этот адрес недоступен ровно
    // там, где VPN и нужен.
    expect(ruleSet['download_detour'], 'proxy');

    expect(config['experimental'], {
      'cache_file': {'enabled': true, 'path': '/tmp/singbox-cache.db'},
    });
  });

  test('настройка переживает перезапуск', () async {
    final dir = Directory.systemTemp.createTempSync('tailcore-prefs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/prefs.json');

    final first = Prefs(storage: file);
    expect(first.bypassGames, isFalse);
    first.setBypassGames(true);
    await first.save();

    final second = Prefs(storage: file);
    await second.load();
    expect(second.bypassGames, isTrue);
  });
}
