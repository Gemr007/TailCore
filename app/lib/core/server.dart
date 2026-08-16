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
  });

  /// Имя из share-ссылки или тега конфига; если его нет — адрес.
  final String name;

  /// Тип outbound в терминах sing-box: vless, hysteria2, shadowsocks…
  final String protocol;
  final String host;
  final int port;

  /// Готовый к отправке в ядро outbound.
  final Map<String, dynamic> outbound;

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
  };

  static Server? fromJson(Map<String, dynamic> json) {
    final outbound = json['outbound'];
    if (outbound is! Map) return null;
    return fromOutbound(Map<String, dynamic>.from(outbound));
  }

  /// Служебные исходящие sing-box: они есть почти в каждом конфиге и узлами
  /// не являются.
  static const _service = {
    'direct',
    'block',
    'dns',
    'selector',
    'urltest',
  };

  /// Собирает узел из outbound sing-box. null — если это служебный
  /// исходящий или в нём нет адреса, по которому можно подключиться.
  static Server? fromOutbound(Map<String, dynamic> outbound) {
    final type = outbound['type'];
    final host = outbound['server'];
    final port = outbound['server_port'];
    if (type is! String || _service.contains(type)) return null;
    if (host is! String || host.isEmpty || port is! num) return null;

    final tag = outbound['tag'];
    return Server(
      name: tag is String && tag.isNotEmpty ? tag : '$host:${port.toInt()}',
      protocol: type,
      host: host,
      port: port.toInt(),
      outbound: outbound,
    );
  }
}
