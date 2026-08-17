import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'apps.dart';
import 'prefs.dart';
import 'server.dart';

/// Разрешение имён. Блок обязателен, а не «по умолчанию сойдёт».
///
/// DNS поверх HTTPS, а не системный резолвер: sing-box в режиме local шлёт
/// собственные UDP-запросы на системный сервер, а в сетях, где тот отвечает
/// только штатному стеку ОС, они уходят в таймаут — и клиент показывает все
/// узлы недоступными, ничего не объясняя.
///
/// [throughTunnel] уводит запросы в туннель — иначе провайдер видит, какие
/// имена спрашивает человек, даже когда сам трафик зашифрован. Резолвер при
/// этом раздваивается: адрес самого узла спрашивать через туннель, который
/// ещё не поднят, невозможно, поэтому для него остаётся прямой `bootstrap`.
Map<String, dynamic> dnsConfig({
  required String server,
  bool throughTunnel = false,
}) {
  return {
    'servers': [
      {
        'type': 'https',
        'tag': 'doh',
        'server': server,
        if (throughTunnel) 'detour': 'proxy',
      },
      if (throughTunnel)
        {'type': 'https', 'tag': 'bootstrap', 'server': server},
    ],
    if (throughTunnel) 'final': 'doh',
    // prefer_ipv4 здесь не вкусовщина: AAAA-запросы в таких сетях чаще
    // всего повисают до таймаута и съедают всё время подключения.
    'strategy': 'prefer_ipv4',
  };
}

/// Rule-set с доменами игровых сервисов из sing-geosite.
///
/// Формат `.srs` — текущий у sing-box; поле `geosite` из старых конфигов
/// объявлено устаревшим и в новых ядрах не работает.
const gamesRuleSet = 'geosite-category-games';
const _gamesRuleSetUrl =
    'https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/$gamesRuleSet.srs';

/// Файл, в котором ядро держит скачанные rule-set'ы.
Future<String> singboxCachePath() async {
  final dir = await getApplicationSupportDirectory();
  return '${dir.path}/singbox-cache.db';
}

/// Правило «эти приложения идут напрямую» под конкретную ОС.
///
/// null — исключать нечего или платформа не умеет опознавать процессы.
/// Поле правила выбирается по [os], а не по тому, где собрано приложение:
/// `process_name` на десктопе, `package_name` на Android.
Map<String, dynamic>? bypassAppsRule(Set<String> bypassApps, TargetOs os) {
  final field = processRuleField(os);
  if (field == null || bypassApps.isEmpty) return null;

  final ids = [
    for (final t in appTemplates)
      if (bypassApps.contains(t.id)) ...t.idsFor(os),
  ];
  if (ids.isEmpty) return null;
  return {field: ids, 'outbound': 'direct'};
}

/// Конфиг для подключения к выбранному узлу.
///
/// [cachePath] нужен только вместе с [bypassGames]: без кэша список доменов
/// скачивается заново при каждом подключении. [os] подставляется в тестах —
/// в приложении берётся настоящая система пользователя. [bridgePort] нужен
/// только узлам на Xray: на нём Xray отдаёт socks, через который ходит
/// sing-box.
String buildRunConfig(
  Server server, {
  bool bypassGames = false,
  String? cachePath,
  Set<String> bypassApps = const {},
  TargetOs? os,
  int localPort = defaultLocalPort,
  String dnsServer = defaultDnsServer,
  bool dnsThroughTunnel = false,
  int bridgePort = defaultBridgePort,
}) {
  final appsRule = bypassAppsRule(bypassApps, os ?? currentOs());
  // Порядок правил — порядок проверки: приложение опознаётся точнее, чем
  // домен, поэтому его исключение идёт первым.
  final rules = [
    ?appsRule,
    if (bypassGames) {'rule_set': gamesRuleSet, 'outbound': 'direct'},
  ];

  // Узел на Xray sing-box не понимает: вместо него в конфиг встаёт socks
  // до локального моста, который поднимет Xray. Роутинг, DNS и счётчики
  // при этом остаются здесь и работают как для любого другого узла.
  final proxyNode = server.viaXray
      ? {
          'type': 'socks',
          'tag': 'proxy',
          'server': '127.0.0.1',
          'server_port': bridgePort,
          'version': '5',
        }
      : {
          ...server.outbound,
          'tag': 'proxy',
          // Имя самого узла разрешается напрямую: спрашивать его через
          // туннель, который поднимается ради этого ответа, некому.
          if (dnsThroughTunnel) 'domain_resolver': 'bootstrap',
        };

  final singbox = {
    'log': {'level': 'warn'},
    'dns': dnsConfig(server: dnsServer, throughTunnel: dnsThroughTunnel),
    'inbounds': [
      {
        'type': 'mixed',
        'tag': 'local',
        'listen': '127.0.0.1',
        'listen_port': localPort,
      },
    ],
    // WireGuard живёт в отдельном массиве: положить его к исходящим —
    // получить «unknown outbound type: wireguard» ещё на разборе конфига.
    if (server.isEndpoint) 'endpoints': [proxyNode],
    'outbounds': [
      if (!server.isEndpoint) proxyNode,
      // Транспорт под узлом (ShadowTLS) — отдельный исходящий: без него
      // detour у прокси указывает в пустоту, и ядро не стартует.
      ...server.extras,
      {
        'type': 'direct',
        'tag': 'direct',
        // То, что идёт мимо туннеля, и имена себе разрешает мимо него:
        // крюк через туннель ради адреса игрового сервера бессмыслен.
        if (dnsThroughTunnel) 'domain_resolver': 'bootstrap',
      },
    ],
    'route': {
      if (rules.isNotEmpty) 'rules': rules,
      if (bypassGames)
        'rule_set': [
          {
            'type': 'remote',
            'tag': gamesRuleSet,
            'format': 'binary',
            'url': _gamesRuleSetUrl,
            // Качаем через сам туннель, а не напрямую: raw.githubusercontent
            // недоступен ровно в тех сетях, ради которых ставят VPN, и
            // прямая загрузка там уронила бы подключение целиком.
            'download_detour': 'proxy',
            'update_interval': '7d',
          },
        ],
      'final': 'proxy',
    },
    if (bypassGames && cachePath != null)
      'experimental': {
        'cache_file': {'enabled': true, 'path': cachePath},
      },
  };

  // Обычный узел уезжает конфигом sing-box без конверта — так же, как до
  // появления второго движка.
  if (!server.viaXray) return jsonEncode(singbox);

  return jsonEncode({
    'engine': 'chain',
    'xray': _xrayBridge(server, bridgePort),
    'config': singbox,
  });
}

/// Локальный порт, на котором Xray отдаёт socks для sing-box. Настройкой не
/// стал намеренно: моста не видно снаружи, и выбирать его пользователю
/// незачем — приложение подбирает свободный само.
const defaultBridgePort = 2081;

/// Свободный порт под мост. Спрашиваем его у системы, а не берём константу:
/// занятый мост уронил бы подключение, а объяснить это пользователю нечем —
/// порта, который он не выбирал, он и не видит.
Future<int> freeBridgePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Конфиг Xray: узел и socks для sing-box над ним. Больше здесь ничего и
/// не нужно — роутинг, DNS и счётчики остаются наверху.
Map<String, dynamic> _xrayBridge(Server server, int bridgePort) {
  return {
    'log': {'loglevel': 'warning'},
    'inbounds': [
      {
        'tag': 'bridge',
        'listen': '127.0.0.1',
        'port': bridgePort,
        'protocol': 'socks',
        // UDP нужен: без него через мост не пройдут ни DNS, ни QUIC.
        'settings': {'udp': true},
      },
    ],
    'outbounds': [
      {...server.outbound, 'tag': 'proxy'},
    ],
  };
}

/// Конфиг для замера задержки: просто все узлы, каждый со своим тегом.
///
/// Группы urltest здесь нет: ядро меряет каждый исходящий напрямую. Так
/// не приходится ждать фоновую проверку группы, которая при совпадении по
/// времени возвращала бы пустой результат без ошибки.
///
/// Входящих нет намеренно — замер поднимает второй экземпляр ядра, и
/// занятый порт основного туннеля уронил бы его на старте.
String buildTestConfig(
  List<Server> servers, {
  String dnsServer = defaultDnsServer,
}) {
  return jsonEncode({
    'log': {'level': 'error'},
    // Через туннель здесь спрашивать нечего: туннеля нет, есть десяток
    // узлов, каждый со своим тегом.
    'dns': dnsConfig(server: dnsServer),
    // Тегом служит ключ узла: по нему же приходит ответ с задержками.
    // WireGuard уезжает в endpoints — ядро меряет и их тоже.
    //
    // Узлы на Xray сюда не попадают: этот конфиг поднимает sing-box, а он
    // их исходящих не понимает. Мерить их нечем, пока замер не научится
    // поднимать цепочку.
    'outbounds': [
      for (final s in servers)
        if (!s.viaXray) ...[
          if (!s.isEndpoint) {...s.outbound, 'tag': s.id},
          ...s.extras,
        ],
    ],
    if (servers.any((s) => s.isEndpoint && !s.viaXray))
      'endpoints': [
        for (final s in servers)
          if (s.isEndpoint && !s.viaXray) {...s.outbound, 'tag': s.id},
      ],
  });
}
