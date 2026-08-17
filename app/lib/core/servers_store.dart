import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'import.dart';
import 'server.dart';
import 'singbox_config.dart';
import 'tunnel.dart';

/// Список узлов, выбор активного и результаты замеров.
///
/// Одно место на всё приложение: экран серверов пишет сюда, экран
/// соединения читает. ChangeNotifier, а не внешний пакет состояния —
/// у нас один разделяемый объект, городить вокруг него контейнер не из
/// чего.
class ServersStore extends ChangeNotifier {
  ServersStore({this.storage});

  /// Файл со списком узлов. В тестах подставляется свой; в приложении
  /// определяется при первом [load].
  File? storage;

  final List<Server> _servers = [];
  List<Server> get servers => List.unmodifiable(_servers);

  /// Задержка по ключу узла. Отсутствие ключа значит «не мерили».
  final Map<String, int> _latency = {};

  /// Причина отказа по ключу узла: узел мерили, и он не ответил. Причину
  /// храним, а не только факт, — «нет связи» без объяснения не даёт
  /// пользователю ни одной зацепки.
  final Map<String, String> _failures = {};

  String? _selectedId;
  bool _auto = false;
  bool _testing = false;

  /// Auto — движок сам держит узел с наименьшей задержкой.
  bool get auto => _auto;
  bool get testing => _testing;

  int? latencyOf(Server s) => _latency[s.id];
  bool isUnreachable(Server s) => _failures.containsKey(s.id);

  /// Причина, по которой узел не ответил на последнем замере.
  String? failureOf(Server s) => _failures[s.id];

  /// Узел, с которым надо работать: в режиме Auto — самый быстрый из
  /// измеренных, иначе выбранный вручную.
  Server? get active {
    if (_servers.isEmpty) return null;
    if (_auto) return fastest;
    return _byId(_selectedId) ?? _servers.first;
  }

  /// Самый быстрый измеренный узел. Пока замера не было — первый в списке:
  /// Auto без данных всё равно должен куда-то вести.
  Server? get fastest {
    final measured = _servers.where((s) => _latency.containsKey(s.id)).toList();
    if (measured.isEmpty) return _servers.firstOrNull;
    measured.sort((a, b) => _latency[a.id]!.compareTo(_latency[b.id]!));
    return measured.first;
  }

  bool isSelected(Server s) => !_auto && active?.id == s.id;

  /// Узлы, отсортированные по задержке. Неизмеренные уходят вниз: список
  /// «по задержке» без задержки — это просто исходный порядок.
  List<Server> sortedByLatency(String protocolFilter) {
    final filtered = _servers.where((s) {
      return protocolFilter == filterAll || s.badge == protocolFilter;
    }).toList();
    filtered.sort((a, b) {
      final x = _latency[a.id] ?? _unmeasured;
      final y = _latency[b.id] ?? _unmeasured;
      return x.compareTo(y);
    });
    return filtered;
  }

  /// Коды протоколов, которые реально есть в списке, плюс «все». Показывать
  /// фильтр по протоколу, которого у пользователя нет, незачем.
  List<String> get protocolFilters {
    final badges = _servers.map((s) => s.badge).toSet().toList()..sort();
    return [filterAll, ...badges];
  }

  static const filterAll = 'ВСЕ';
  static const _unmeasured = 1 << 30;

  Server? _byId(String? id) {
    if (id == null) return null;
    for (final s in _servers) {
      if (s.id == id) return s;
    }
    return null;
  }

  // --- Действия ---

  void select(Server s) {
    _auto = false;
    _selectedId = s.id;
    notifyListeners();
    unawaited(save());
  }

  void enableAuto() {
    _auto = true;
    notifyListeners();
    unawaited(save());
  }

  void remove(Server s) {
    _servers.removeWhere((x) => x.id == s.id);
    _latency.remove(s.id);
    _failures.remove(s.id);
    if (_selectedId == s.id) _selectedId = null;
    notifyListeners();
    unawaited(save());
  }

  /// Добавляет узлы из принесённого текста или по ссылке на подписку.
  ///
  /// Возвращает, сколько узлов оказалось новыми, и какие пришлось
  /// отвергнуть: повторный импорт той же подписки не должен плодить
  /// дубликаты, а отвергнутый узел обязан быть назван вслух.
  Future<({int added, List<({String name, String reason})> skipped})> import(
    String input,
  ) async {
    final text = _looksLikeUrl(input) ? await _fetch(input.trim()) : input;
    final incoming = parseImport(text);

    final known = _servers.map((s) => s.id).toSet();
    var added = 0;
    for (final s in incoming.servers) {
      if (known.add(s.id)) {
        _servers.add(s);
        added++;
      }
    }
    if (added > 0) {
      notifyListeners();
      await save();
    }
    return (added: added, skipped: incoming.skipped);
  }

  static bool _looksLikeUrl(String input) {
    final t = input.trim();
    return !t.contains('\n') &&
        (t.startsWith('http://') || t.startsWith('https://'));
  }

  /// Тянет подписку. User-Agent важен: панели отдают по нему разные
  /// форматы, и без него та же ссылка может вернуть конфиг Xray вместо
  /// списка ссылок.
  Future<String> _fetch(String url) async {
    final client = HttpClient()..userAgent = 'TailCore';
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'подписка ответила ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      return await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  /// Меряет задержку до всех узлов разом: ядро само ходит по ссылке через
  /// каждый outbound.
  Future<void> measureAll() async {
    if (_testing || _servers.isEmpty) return;
    _testing = true;
    notifyListeners();
    try {
      final result = await TunnelCore.instance.test(buildTestConfig(_servers));
      _latency
        ..clear()
        ..addAll(result.delays);
      _failures
        ..clear()
        ..addAll(result.errors);
    } finally {
      _testing = false;
      notifyListeners();
    }
  }

  // --- Хранение ---

  Future<File> _file() async {
    final existing = storage;
    if (existing != null) return existing;
    final dir = await getApplicationSupportDirectory();
    return storage = File('${dir.path}/servers.json');
  }

  Future<void> load() async {
    final file = await _file();
    if (!await file.exists()) return;

    final Object? json;
    try {
      json = jsonDecode(await file.readAsString());
    } on FormatException {
      // Битый файл — не повод не запуститься: список узлов не то, ради
      // чего стоит падать на старте.
      return;
    }
    if (json is! Map<String, dynamic>) return;

    _servers
      ..clear()
      ..addAll([
        for (final s in (json['servers'] as List? ?? const []))
          if (s is Map<String, dynamic>) ?Server.fromJson(s),
      ]);
    _selectedId = json['selected'] as String?;
    _auto = json['auto'] as bool? ?? false;
    notifyListeners();
  }

  Future<void> save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'servers': [for (final s in _servers) s.toJson()],
        'selected': _selectedId,
        'auto': _auto,
      }),
    );
  }
}

/// Сохранение не должно задерживать отрисовку, но и молча теряться тоже.
/// Общий помощник: тем же способом сохраняются и настройки.
void unawaited(Future<void> future) {
  future.catchError((Object e) {
    debugPrint('tailcore store: $e');
  });
}
