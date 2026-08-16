import 'dart:convert';

/// Узел, через который сейчас идёт трафик, — ровно то, что о нём знает
/// конфиг, отданный ядру. Отдельного справочника серверов пока нет, он
/// появится на экране серверов.
class Endpoint {
  const Endpoint({
    required this.protocol,
    required this.host,
    required this.port,
    this.tag,
  });

  /// Тип outbound в терминах sing-box: vless, hysteria2, trojan, wireguard…
  final String protocol;
  final String host;
  final int port;

  /// Имя узла из конфига, если автор конфига его задал.
  final String? tag;

  /// Показываемое имя: тег, если он есть, иначе адрес — конфиг без тегов
  /// это норма для импорта из share-ссылки.
  String get name => tag?.isNotEmpty == true ? tag! : host;

  String get address => '$host:$port';

  /// Код протокола для бейджа. sing-box пишет типы в нижнем регистре,
  /// в макете бейджи заглавные.
  String get badge => protocol.toUpperCase();

  /// Вытаскивает исходящее соединение из конфига sing-box.
  ///
  /// direct/block/dns — служебные исходящие, они есть почти в каждом
  /// конфиге и узлом не являются; берём первый настоящий.
  static const _service = {'direct', 'block', 'dns', 'selector', 'urltest'};

  static Endpoint? fromConfig(String configJson) {
    final Object? decoded;
    try {
      decoded = jsonDecode(configJson);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final outbounds = decoded['outbounds'];
    if (outbounds is! List) return null;

    for (final o in outbounds) {
      if (o is! Map<String, dynamic>) continue;
      final type = o['type'];
      final host = o['server'];
      final port = o['server_port'];
      if (type is! String || _service.contains(type)) continue;
      if (host is! String || port is! num) continue;
      return Endpoint(
        protocol: type,
        host: host,
        port: port.toInt(),
        tag: o['tag'] as String?,
      );
    }
    return null;
  }
}
