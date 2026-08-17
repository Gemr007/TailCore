import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailcore/core/apps.dart';
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

  test('один и тот же выбор даёт разные правила на разных ОС', () {
    const chosen = {'discord'};

    // Ровно та ошибка, что была в макете: идентификаторы одной платформы,
    // показанные и отданные ядру независимо от того, где всё запущено.
    expect(bypassAppsRule(chosen, TargetOs.windows), {
      'process_name': ['Discord.exe'],
      'outbound': 'direct',
    });
    expect(bypassAppsRule(chosen, TargetOs.android), {
      'package_name': ['com.discord'],
      'outbound': 'direct',
    });
    expect(bypassAppsRule(chosen, TargetOs.macos), {
      'process_name': ['Discord'],
      'outbound': 'direct',
    });

    // На iOS процесс не опознать — правило не собирается вовсе, а не
    // собирается пустым или чужим.
    expect(bypassAppsRule(chosen, TargetOs.ios), isNull);
    // Приложения, которого на этой ОС нет, тоже не должно быть в правиле.
    expect(bypassAppsRule({'epic'}, TargetOs.android), isNull);
    expect(bypassAppsRule(const {}, TargetOs.windows), isNull);
  });

  test('исключённые приложения попадают в правила конфига', () {
    final config = jsonDecode(
      buildRunConfig(_node(), bypassApps: {'steam'}, os: TargetOs.windows),
    ) as Map<String, dynamic>;
    final rules = (config['route'] as Map<String, dynamic>)['rules'] as List;

    expect(rules, [
      {
        'process_name': ['steam.exe', 'steamwebhelper.exe'],
        'outbound': 'direct',
      },
    ]);
  });

  test('правило приложений проверяется раньше доменного', () {
    final config = jsonDecode(
      buildRunConfig(
        _node(),
        bypassGames: true,
        bypassApps: {'discord'},
        os: TargetOs.windows,
      ),
    ) as Map<String, dynamic>;
    final rules = (config['route'] as Map<String, dynamic>)['rules'] as List;

    expect(rules.length, 2);
    expect((rules.first as Map).containsKey('process_name'), isTrue);
    expect((rules.last as Map)['rule_set'], gamesRuleSet);
  });

  test('настройка переживает перезапуск', () async {
    final dir = Directory.systemTemp.createTempSync('tailcore-prefs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/prefs.json');

    final first = Prefs(storage: file);
    expect(first.bypassGames, isFalse);
    first.setBypassGames(true);
    first.setBypassApp('discord', true);
    await first.save();

    final second = Prefs(storage: file);
    await second.load();
    expect(second.bypassGames, isTrue);
    expect(second.bypassApps, {'discord'});
  });
}
