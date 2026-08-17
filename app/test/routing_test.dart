import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailcore/core/apps.dart';
import 'package:tailcore/core/autostart.dart';
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

  test('WireGuard едет в endpoints, а не к исходящим', () {
    final wg = Server.fromOutbound({
      'type': 'wireguard',
      'tag': 'wg',
      'address': ['10.0.0.2/32'],
      'private_key': 'k',
      'peers': [
        {'address': '1.2.3.4', 'port': 51820, 'public_key': 'p'},
      ],
    })!;

    final config = jsonDecode(buildRunConfig(wg)) as Map<String, dynamic>;
    final endpoints = config['endpoints'] as List;
    expect(endpoints.single['tag'], 'proxy');
    expect(endpoints.single['type'], 'wireguard');
    // Среди исходящих остаётся только direct: положить туда WireGuard —
    // «unknown outbound type» ещё на разборе конфига.
    final outbounds = config['outbounds'] as List;
    expect(outbounds.single['tag'], 'direct');
    expect(config['route']['final'], 'proxy');

    // В конфиге замера — то же разделение, иначе узел не измерится.
    final test = jsonDecode(buildTestConfig([wg])) as Map<String, dynamic>;
    expect((test['endpoints'] as List).single['tag'], wg.id);
    expect(test['outbounds'], isEmpty);
  });

  test('порт и резолвер берутся из настроек', () {
    final config = jsonDecode(
      buildRunConfig(_node(), localPort: 3128, dnsServer: '9.9.9.9'),
    ) as Map<String, dynamic>;

    expect((config['inbounds'] as List).single['listen_port'], 3128);
    final servers = (config['dns'] as Map<String, dynamic>)['servers'] as List;
    expect(servers.single['server'], '9.9.9.9');
    // Туннеля резолвер не касается, пока не попросили.
    expect(servers.single.containsKey('detour'), isFalse);
  });

  test('DNS через туннель не отрезает разрешение адреса самого узла', () {
    final config = jsonDecode(
      buildRunConfig(_node(), dnsThroughTunnel: true),
    ) as Map<String, dynamic>;

    final dns = config['dns'] as Map<String, dynamic>;
    final servers = dns['servers'] as List;
    expect(servers.first['tag'], 'doh');
    expect(servers.first['detour'], 'proxy');
    // Второй резолвер прямой: спрашивать адрес узла через туннель, который
    // ради этого ответа и поднимается, невозможно.
    expect(servers.last['tag'], 'bootstrap');
    expect(servers.last.containsKey('detour'), isFalse);
    expect(dns['final'], 'doh');

    final outbounds = config['outbounds'] as List;
    expect(outbounds.first['domain_resolver'], 'bootstrap');
    expect(outbounds.last['domain_resolver'], 'bootstrap');
  });

  test('настройка переживает перезапуск', () async {
    final dir = Directory.systemTemp.createTempSync('tailcore-prefs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/prefs.json');

    final first = Prefs(storage: file);
    expect(first.bypassGames, isFalse);
    first.setBypassGames(true);
    first.setBypassApp('discord', true);
    first.setLocalPort(3128);
    first.setDnsServer('9.9.9.9');
    first.setDnsThroughTunnel(true);
    await first.save();

    final second = Prefs(storage: file);
    await second.load();
    expect(second.bypassGames, isTrue);
    expect(second.bypassApps, {'discord'});
    expect(second.localPort, 3128);
    expect(second.dnsServer, '9.9.9.9');
    expect(second.dnsThroughTunnel, isTrue);
  });

  test('негодный порт настройку не меняет', () {
    final prefs = Prefs(
      storage: File('${Directory.systemTemp.path}/nope.json'),
    );
    expect(prefs.localPort, defaultLocalPort);

    // Ниже 1024 нужны права администратора, выше 65535 порта не бывает.
    prefs.setLocalPort(80);
    prefs.setLocalPort(70000);
    expect(prefs.localPort, defaultLocalPort);
  });

  test('автозапуск описывается по-разному на каждой ОС', () {
    // Проверяется то, что уходит в систему: реестр трогать из теста
    // нельзя, а ошибиться в ключе или в формате файла — можно.
    expect(Autostart.windowsArgs(true, 'C:\\app\\tailcore.exe'), [
      'add',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
      '/v',
      'TailCore',
      '/t',
      'REG_SZ',
      '/d',
      'C:\\app\\tailcore.exe',
      '/f',
    ]);
    expect(Autostart.windowsArgs(false, 'ignored'), contains('delete'));

    expect(
      Autostart.desktopEntry('/usr/bin/tailcore'),
      contains('[Desktop Entry]'),
    );
    expect(
      Autostart.desktopEntry('/usr/bin/tailcore'),
      contains('Exec=/usr/bin/tailcore'),
    );

    final plist = Autostart.launchAgent('/Applications/TailCore.app/tailcore');
    expect(plist, contains('<key>RunAtLoad</key><true/>'));
    expect(plist, contains('/Applications/TailCore.app/tailcore'));
  });
}
