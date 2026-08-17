import 'dart:convert';

import 'package:path_provider/path_provider.dart';

import 'server.dart';

/// Локальный порт прокси. Пока константа; настройкой станет на экране
/// настроек, системным туннелем — на шаге TUN.
const localProxyPort = 2080;

/// Разрешение имён. Блок обязателен, а не «по умолчанию сойдёт».
///
/// TODO(шаг 10): выбор резолвера — настройка. Сейчас запросы идут мимо
/// туннеля; когда появится экран настроек, DNS должен ходить через него.
const _dns = {
  'servers': [
    // DNS поверх HTTPS, а не системный резолвер: sing-box в режиме local
    // шлёт собственные UDP-запросы на системный сервер, а в сетях, где тот
    // отвечает только штатному стеку ОС, они уходят в таймаут — и клиент
    // показывает все узлы недоступными, ничего не объясняя.
    //
    // Адрес задан числом намеренно: резолвер, которому самому нужен
    // резолвер, на старте не поднимется.
    {'type': 'https', 'tag': 'doh', 'server': '1.1.1.1'},
  ],
  // prefer_ipv4 здесь не вкусовщина: AAAA-запросы в таких сетях чаще всего
  // повисают до таймаута и съедают всё время подключения.
  'strategy': 'prefer_ipv4',
};

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

/// Конфиг для подключения к выбранному узлу.
///
/// [cachePath] нужен только вместе с [bypassGames]: без кэша список доменов
/// скачивается заново при каждом подключении.
String buildRunConfig(
  Server server, {
  bool bypassGames = false,
  String? cachePath,
}) {
  return jsonEncode({
    'log': {'level': 'warn'},
    'dns': _dns,
    'inbounds': [
      {
        'type': 'mixed',
        'tag': 'local',
        'listen': '127.0.0.1',
        'listen_port': localProxyPort,
      },
    ],
    'outbounds': [
      {...server.outbound, 'tag': 'proxy'},
      {'type': 'direct', 'tag': 'direct'},
    ],
    'route': {
      if (bypassGames) ...{
        'rules': [
          {'rule_set': gamesRuleSet, 'outbound': 'direct'},
        ],
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
      },
      'final': 'proxy',
    },
    if (bypassGames && cachePath != null)
      'experimental': {
        'cache_file': {'enabled': true, 'path': cachePath},
      },
  });
}

/// Конфиг для замера задержки: просто все узлы, каждый со своим тегом.
///
/// Группы urltest здесь нет: ядро меряет каждый исходящий напрямую. Так
/// не приходится ждать фоновую проверку группы, которая при совпадении по
/// времени возвращала бы пустой результат без ошибки.
///
/// Входящих нет намеренно — замер поднимает второй экземпляр ядра, и
/// занятый порт основного туннеля уронил бы его на старте.
String buildTestConfig(List<Server> servers) {
  return jsonEncode({
    'log': {'level': 'error'},
    'dns': _dns,
    // Тегом служит ключ узла: по нему же приходит ответ с задержками.
    'outbounds': [
      for (final s in servers) {...s.outbound, 'tag': s.id},
    ],
  });
}
