/// Узел, через который может пойти трафик.
///
/// Внутри лежит готовый outbound sing-box, а не наши собственные поля:
/// протоколов больше десятка, у каждого своя горсть параметров, и держать
/// их зеркало в Dart значило бы переписывать схему sing-box за ним следом.
/// Наружу торчит только то, что рисуется в списке.
class Server {
  Server({
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    required this.outbound,
    this.extras = const [],
  });

  /// Имя из share-ссылки или тега конфига; если его нет — адрес.
  final String name;

  /// Тип outbound в терминах sing-box: vless, hysteria2, shadowsocks…
  final String protocol;
  final String host;
  final int port;

  /// Готовый к отправке в ядро узел. Для большинства протоколов это
  /// outbound; для WireGuard — endpoint, у него в конфиге отдельный массив.
  /// Имя поля осталось прежним: оно же лежит ключом в сохранённом списке.
  final Map<String, dynamic> outbound;

  /// Исходящие, без которых узел не работает, но которые сами узлами не
  /// являются. Так устроен ShadowTLS: маскирующий транспорт отдельным
  /// исходящим, а прокси ходит через него по `detour`.
  final List<Map<String, dynamic>> extras;

  /// WireGuard в sing-box 1.13 живёт не среди исходящих, а в `endpoints`.
  /// Положить его к остальным — получить «unknown outbound type» на старте.
  bool get isEndpoint => protocol == 'wireguard';

  /// Код протокола для бейджа. Hysteria2 в макете подписан HY2, потому что
  /// колонка узкая, а не потому что sing-box его так зовёт.
  String get badge => switch (protocol) {
    'hysteria2' => 'HY2',
    'shadowsocks' => 'SS',
    'wireguard' => 'WG',
    _ => protocol.toUpperCase(),
  };

  String get address => '$host:$port';

  /// Устойчивый ключ узла. Считается по адресу и протоколу: пересохранение
  /// подписки не должно ронять выбор пользователя, а имя узла провайдер
  /// меняет свободно.
  String get id => '$protocol://$host:$port';

  Map<String, dynamic> toJson() => {
    'name': name,
    'protocol': protocol,
    'host': host,
    'port': port,
    'outbound': outbound,
    if (extras.isNotEmpty) 'extras': extras,
  };

  static Server? fromJson(Map<String, dynamic> json) {
    final outbound = json['outbound'];
    if (outbound is! Map) return null;
    return fromOutbound(
      Map<String, dynamic>.from(outbound),
      extras: [
        for (final e in (json['extras'] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ],
    );
  }

  /// Служебные исходящие sing-box: они есть почти в каждом конфиге и узлами
  /// не являются.
  static const _service = {'direct', 'block', 'dns', 'selector', 'urltest'};

  /// Собирает узел из outbound sing-box. null — если это служебный
  /// исходящий или в нём нет адреса, по которому можно подключиться.
  static Server? fromOutbound(
    Map<String, dynamic> outbound, {
    List<Map<String, dynamic>> extras = const [],
  }) {
    final type = outbound['type'];
    if (type is! String || _service.contains(type)) return null;

    // У WireGuard адреса на верхнем уровне нет: подключаются к пиру, а их
    // может быть несколько. Показываем первого — в списке всё равно одна
    // строка, а ключ узла должен быть устойчивым.
    final source = type == 'wireguard'
        ? ((outbound['peers'] as List?)?.firstOrNull as Map?)
        : outbound;
    final host = source?[type == 'wireguard' ? 'address' : 'server'];
    final port = source?[type == 'wireguard' ? 'port' : 'server_port'];
    if (host is! String || host.isEmpty || port is! num) return null;

    final tag = outbound['tag'];
    return Server(
      name: tag is String && tag.isNotEmpty ? tag : '$host:${port.toInt()}',
      protocol: type,
      host: host,
      port: port.toInt(),
      outbound: outbound,
      extras: extras,
    );
  }
}
