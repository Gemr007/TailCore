import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'servers_store.dart' show unawaited;

const defaultLocalPort = 2080;

/// Cloudflare: отвечает быстрее прочих в большинстве сетей, где эта штука
/// вообще нужна.
const defaultDnsServer = '1.1.1.1';

/// Готовые резолверы. Свой адрес руками — отдельная задача: сперва надо,
/// чтобы работали эти.
const dnsPresets = {
  '1.1.1.1': 'Cloudflare',
  '8.8.8.8': 'Google',
  '9.9.9.9': 'Quad9',
  '94.140.14.14': 'AdGuard',
};

/// Настройки приложения.
///
/// Отдельно от [ServersStore]: список узлов приходит из подписки и меняется
/// сам, настройки ставит человек — смешивать их в одном файле значит терять
/// настройки при каждой перезаписи списка.
class Prefs extends ChangeNotifier {
  Prefs({this.storage});

  /// Файл настроек. В тестах подставляется свой; в приложении определяется
  /// при первом [load].
  File? storage;

  bool _bypassGames = false;

  /// Игровой трафик идёт напрямую, мимо туннеля. Игры чувствительны к
  /// задержке, и лишний крюк через узел им дороже, чем скрытность.
  bool get bypassGames => _bypassGames;

  void setBypassGames(bool value) {
    if (_bypassGames == value) return;
    _bypassGames = value;
    notifyListeners();
    unawaited(save());
  }

  final Set<String> _bypassApps = {};

  /// Приложения, чей трафик идёт мимо туннеля. Хранятся ключами шаблонов,
  /// а не именами процессов: имя процесса у одного приложения своё на
  /// каждой ОС, а настройка переезжает вместе с человеком.
  Set<String> get bypassApps => Set.unmodifiable(_bypassApps);

  void setBypassApp(String id, bool on) {
    final changed = on ? _bypassApps.add(id) : _bypassApps.remove(id);
    if (!changed) return;
    notifyListeners();
    unawaited(save());
  }

  int _localPort = defaultLocalPort;

  /// Порт локального прокси. Настройка, а не константа: 2080 занят чаще,
  /// чем кажется, и человеку нечем починить чужой процесс на своём порту.
  int get localPort => _localPort;

  String _dnsServer = defaultDnsServer;

  /// Адрес DoH-резолвера. Числом, а не именем: резолверу, которому самому
  /// нужен резолвер, неоткуда взяться на старте.
  String get dnsServer => _dnsServer;

  bool _dnsThroughTunnel = false;

  /// Спрашивать DNS через туннель. Выключено по умолчанию — так работало
  /// до появления настройки, и это единственный режим, проверенный на
  /// живой подписке.
  bool get dnsThroughTunnel => _dnsThroughTunnel;

  void setLocalPort(int port) {
    if (_localPort == port || port < 1024 || port > 65535) return;
    _localPort = port;
    notifyListeners();
    unawaited(save());
  }

  void setDnsServer(String server) {
    if (_dnsServer == server || server.isEmpty) return;
    _dnsServer = server;
    notifyListeners();
    unawaited(save());
  }

  void setDnsThroughTunnel(bool value) {
    if (_dnsThroughTunnel == value) return;
    _dnsThroughTunnel = value;
    notifyListeners();
    unawaited(save());
  }

  Future<File> _file() async {
    final existing = storage;
    if (existing != null) return existing;
    final dir = await getApplicationSupportDirectory();
    return storage = File('${dir.path}/prefs.json');
  }

  Future<void> load() async {
    final file = await _file();
    if (!await file.exists()) return;

    final Object? json;
    try {
      json = jsonDecode(await file.readAsString());
    } on FormatException {
      // Битые настройки — не повод не запуститься: значения по умолчанию
      // рабочие, а падение на старте из-за одной строки в файле — нет.
      return;
    }
    if (json is! Map<String, dynamic>) return;

    _bypassGames = json['bypass_games'] as bool? ?? false;
    _localPort = json['local_port'] as int? ?? defaultLocalPort;
    _dnsServer = json['dns_server'] as String? ?? defaultDnsServer;
    _dnsThroughTunnel = json['dns_through_tunnel'] as bool? ?? false;
    _bypassApps
      ..clear()
      ..addAll([
        for (final id in (json['bypass_apps'] as List? ?? const []))
          if (id is String) id,
      ]);
    notifyListeners();
  }

  Future<void> save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'bypass_games': _bypassGames,
        'bypass_apps': _bypassApps.toList(),
        'local_port': _localPort,
        'dns_server': _dnsServer,
        'dns_through_tunnel': _dnsThroughTunnel,
      }),
    );
  }
}
