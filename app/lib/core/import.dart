import 'dart:convert';

import 'server.dart';

/// Итог разбора: что удалось взять и что пришлось отвергнуть.
///
/// Отвергнутые узлы важны не меньше принятых: узел, который распознан, но
/// не может работать, обязан быть назван вслух. Молча подсунуть вместо
/// него урезанный конфиг — значит отдать пользователю соединение, которое
/// выглядит настроенным и не работает.
class ImportResult {
  const ImportResult(this.servers, this.skipped);

  final List<Server> servers;

  /// Имя узла и причина отказа.
  final List<({String name, String reason})> skipped;

  static const empty = ImportResult([], []);
}

/// Разбор того, что пользователь принёс: конфига sing-box, отдельных
/// share-ссылок или содержимого подписки.
///
/// Формат не спрашивается, а определяется: человек копирует из мессенджера
/// то, что ему прислали, и не обязан знать, JSON это или base64.
ImportResult parseImport(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return ImportResult.empty;

  final fromJson = _parseSingBox(trimmed);
  if (fromJson.isNotEmpty) return ImportResult(fromJson, const []);

  final fromLinks = _parseLinks(trimmed);
  if (fromLinks.servers.isNotEmpty || fromLinks.skipped.isNotEmpty) {
    return fromLinks;
  }

  // Подписки отдают тот же список ссылок, но в base64 и часто без
  // выравнивания.
  final decoded = _base64OrNull(trimmed);
  return decoded == null ? ImportResult.empty : _parseLinks(decoded);
}

List<Server> _parseSingBox(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return const [];
  }

  final List<Object?> outbounds;
  if (json is Map<String, dynamic> && json['outbounds'] is List) {
    outbounds = json['outbounds'] as List;
  } else if (json is List) {
    outbounds = json;
  } else if (json is Map<String, dynamic>) {
    outbounds = [json]; // одиночный outbound
  } else {
    return const [];
  }

  return [
    for (final o in outbounds)
      if (o is Map<String, dynamic>)
        ?Server.fromOutbound(Map<String, dynamic>.from(o)),
  ];
}

ImportResult _parseLinks(String text) {
  final servers = <Server>[];
  final skipped = <({String name, String reason})>[];

  for (final raw in text.split(RegExp(r'[\r\n]+'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parsed = parseNode(line);
    if (parsed.server != null) {
      servers.add(parsed.server!);
    } else if (parsed.unsupported != null) {
      skipped.add((name: parsed.name, reason: parsed.unsupported!));
    }
  }
  return ImportResult(servers, skipped);
}

/// Разбирает одну share-ссылку в узел. null — если схема незнакома или
/// в ссылке нет адреса.
Server? parseShareLink(String link) => parseNode(link).server;

/// Разбирает ссылку, различая три исхода: узел готов; узел распознан, но
/// работать на нашем ядре не может; это вообще не ссылка на узел.
({Server? server, String? unsupported, String name}) parseNode(String link) {
  const nothing = (server: null, unsupported: null, name: '');
  final scheme = link.split('://').first.toLowerCase();

  // vmess:// не URI, а base64 от JSON — Uri.parse на нём бессмыслен.
  if (scheme == 'vmess') {
    final outbound = _vmess(link);
    if (outbound == null) return nothing;
    return (
      server: Server.fromOutbound(outbound),
      unsupported: null,
      name: '${outbound['tag'] ?? ''}',
    );
  }

  final Uri uri;
  try {
    uri = Uri.parse(link);
  } on FormatException {
    return nothing;
  }
  if (uri.host.isEmpty && scheme != 'ss') return nothing;

  final name = uri.fragment.isNotEmpty
      ? Uri.decodeComponent(uri.fragment)
      : uri.host;

  // Транспорт проверяем до сборки outbound: узел с транспортом, которого
  // ядро не знает, нельзя ни собрать, ни тихо упростить до TCP.
  final unsupported = _unsupportedTransport(uri.queryParameters['type']);
  if (unsupported != null && (scheme == 'vless' || scheme == 'vmess' || scheme == 'trojan')) {
    return (server: null, unsupported: unsupported, name: name);
  }

  final outbound = switch (scheme) {
    'vless' => _vless(uri),
    'trojan' => _trojan(uri),
    'ss' => _shadowsocks(link, uri),
    'hysteria2' || 'hy2' => _hysteria2(uri),
    'tuic' => _tuic(uri),
    'socks' || 'socks5' => _socks(uri),
    'http' || 'https' => _http(uri, tls: scheme == 'https'),
    _ => null,
  };
  if (outbound == null) return nothing;

  if (uri.fragment.isNotEmpty) outbound['tag'] = name;
  return (server: Server.fromOutbound(outbound), unsupported: null, name: name);
}

/// Транспорты Xray, которых нет в sing-box. Причина пишется человеческим
/// языком: пользователю нужно понять, что делать, а не что сломалось.
String? _unsupportedTransport(String? type) {
  return switch (type) {
    null || '' || 'tcp' || 'raw' || 'ws' || 'grpc' || 'http' || 'h2' ||
    'httpupgrade' => null,
    'xhttp' || 'splithttp' => 'транспорт XHTTP — нужен Xray-core',
    'kcp' || 'mkcp' => 'транспорт mKCP — нужен Xray-core',
    'quic' => 'транспорт QUIC от Xray — нужен Xray-core',
    _ => 'неизвестный транспорт $type',
  };
}

// --- Протоколы ---

Map<String, dynamic>? _vless(Uri uri) {
  final uuid = uri.userInfo;
  if (uuid.isEmpty) return null;
  final q = uri.queryParameters;
  return {
    'type': 'vless',
    'server': uri.host,
    'server_port': uri.port,
    'uuid': uuid,
    if (q['flow']?.isNotEmpty ?? false) 'flow': q['flow'],
    // xudp — то, что умеет большинство серверов; sing-box без этого
    // отправляет UDP по одному соединению на пакет.
    'packet_encoding': 'xudp',
    ...?_tls(uri),
    ...?_transport(uri),
  };
}

Map<String, dynamic>? _vmess(String link) {
  // vmess:// — это base64 от JSON, а не URI: у формата своя история.
  final payload = _base64OrNull(link.substring('vmess://'.length));
  if (payload == null) return null;
  final Object? json;
  try {
    json = jsonDecode(payload);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, dynamic>) return null;

  final port = int.tryParse('${json['port']}');
  final host = json['add'];
  if (host is! String || host.isEmpty || port == null) return null;

  final network = '${json['net'] ?? 'tcp'}';
  final tlsOn = '${json['tls'] ?? ''}' == 'tls';
  final sni = '${json['sni'] ?? json['host'] ?? ''}';

  return {
    'type': 'vmess',
    'tag': '${json['ps'] ?? ''}',
    'server': host,
    'server_port': port,
    'uuid': '${json['id'] ?? ''}',
    'alter_id': int.tryParse('${json['aid'] ?? 0}') ?? 0,
    'security': '${json['scy'] ?? 'auto'}',
    if (tlsOn)
      'tls': {
        'enabled': true,
        if (sni.isNotEmpty) 'server_name': sni,
        'utls': {'enabled': true, 'fingerprint': 'chrome'},
      },
    ...?_transportFrom(
      network: network,
      path: '${json['path'] ?? ''}',
      host: '${json['host'] ?? ''}',
      serviceName: '${json['path'] ?? ''}',
    ),
  };
}

Map<String, dynamic>? _trojan(Uri uri) {
  final password = uri.userInfo;
  if (password.isEmpty) return null;
  return {
    'type': 'trojan',
    'server': uri.host,
    'server_port': uri.port,
    'password': Uri.decodeComponent(password),
    // Trojan без TLS не бывает: весь смысл протокола в маскировке под HTTPS.
    ...?_tls(uri, defaultEnabled: true),
    ...?_transport(uri),
  };
}

Map<String, dynamic>? _shadowsocks(String link, Uri uri) {
  // Две живые формы: SIP002 с base64 только в userInfo и старая, где в
  // base64 завёрнуто всё вместе с адресом.
  var method = '';
  var password = '';
  var host = uri.host;
  var port = uri.port;

  if (host.isNotEmpty && uri.userInfo.isNotEmpty) {
    final creds = _base64OrNull(uri.userInfo) ?? Uri.decodeComponent(uri.userInfo);
    final split = creds.indexOf(':');
    if (split < 0) return null;
    method = creds.substring(0, split);
    password = creds.substring(split + 1);
  } else {
    final body = link.substring('ss://'.length).split('#').first;
    final decoded = _base64OrNull(body);
    if (decoded == null) return null;
    final at = decoded.lastIndexOf('@');
    final colon = decoded.lastIndexOf(':');
    if (at < 0 || colon < at) return null;
    method = decoded.substring(0, decoded.indexOf(':'));
    password = decoded.substring(decoded.indexOf(':') + 1, at);
    host = decoded.substring(at + 1, colon);
    port = int.tryParse(decoded.substring(colon + 1)) ?? 0;
  }

  if (host.isEmpty || port == 0 || method.isEmpty) return null;
  return {
    'type': 'shadowsocks',
    'server': host,
    'server_port': port,
    'method': method,
    'password': password,
  };
}

Map<String, dynamic>? _hysteria2(Uri uri) {
  final q = uri.queryParameters;
  final obfs = q['obfs'];
  return {
    'type': 'hysteria2',
    'server': uri.host,
    'server_port': uri.port,
    'password': Uri.decodeComponent(uri.userInfo),
    if (obfs != null && obfs.isNotEmpty)
      'obfs': {'type': obfs, 'password': q['obfs-password'] ?? ''},
    // Hysteria2 работает поверх QUIC, TLS у него не опция.
    ...?_tls(uri, defaultEnabled: true),
  };
}

Map<String, dynamic>? _tuic(Uri uri) {
  final creds = uri.userInfo.split(':');
  if (creds.first.isEmpty) return null;
  final q = uri.queryParameters;
  return {
    'type': 'tuic',
    'server': uri.host,
    'server_port': uri.port,
    'uuid': creds.first,
    'password': creds.length > 1 ? Uri.decodeComponent(creds[1]) : '',
    if (q['congestion_control']?.isNotEmpty ?? false)
      'congestion_control': q['congestion_control'],
    if (q['udp_relay_mode']?.isNotEmpty ?? false)
      'udp_relay_mode': q['udp_relay_mode'],
    ...?_tls(uri, defaultEnabled: true),
  };
}

Map<String, dynamic> _socks(Uri uri) {
  final creds = uri.userInfo.split(':');
  return {
    'type': 'socks',
    'server': uri.host,
    'server_port': uri.port,
    'version': '5',
    if (creds.first.isNotEmpty) 'username': Uri.decodeComponent(creds.first),
    if (creds.length > 1) 'password': Uri.decodeComponent(creds[1]),
  };
}

Map<String, dynamic> _http(Uri uri, {required bool tls}) {
  final creds = uri.userInfo.split(':');
  return {
    'type': 'http',
    'server': uri.host,
    'server_port': uri.port,
    if (creds.first.isNotEmpty) 'username': Uri.decodeComponent(creds.first),
    if (creds.length > 1) 'password': Uri.decodeComponent(creds[1]),
    if (tls) 'tls': {'enabled': true, 'server_name': uri.host},
  };
}

// --- Общие куски ---

/// Блок tls, включая Reality. Возвращает null, когда шифрования нет и
/// добавлять в outbound нечего.
Map<String, dynamic>? _tls(Uri uri, {bool defaultEnabled = false}) {
  final q = uri.queryParameters;
  final security = q['security'] ?? (defaultEnabled ? 'tls' : 'none');
  if (security == 'none' || security.isEmpty) return null;

  final sni = q['sni'] ?? q['peer'] ?? uri.host;
  final alpn = q['alpn']?.split(',').where((s) => s.isNotEmpty).toList();
  final fingerprint = q['fp'];
  final publicKey = q['pbk'];

  return {
    'tls': {
      'enabled': true,
      if (sni.isNotEmpty) 'server_name': sni,
      if (q['allowInsecure'] == '1' || q['insecure'] == '1') 'insecure': true,
      if (alpn != null && alpn.isNotEmpty) 'alpn': alpn,
      if (fingerprint != null && fingerprint.isNotEmpty)
        'utls': {'enabled': true, 'fingerprint': fingerprint},
      if (security == 'reality' && (publicKey?.isNotEmpty ?? false))
        'reality': {
          'enabled': true,
          'public_key': publicKey,
          if (q['sid']?.isNotEmpty ?? false) 'short_id': q['sid'],
        },
    },
  };
}

Map<String, dynamic>? _transport(Uri uri) {
  final q = uri.queryParameters;
  return _transportFrom(
    network: q['type'] ?? 'tcp',
    path: q['path'] ?? '',
    host: q['host'] ?? '',
    serviceName: q['serviceName'] ?? '',
  );
}

/// Транспорт в терминах sing-box. tcp — отсутствие блока transport,
/// а не его вид.
Map<String, dynamic>? _transportFrom({
  required String network,
  required String path,
  required String host,
  required String serviceName,
}) {
  return switch (network) {
    'ws' => {
      'transport': {
        'type': 'ws',
        if (path.isNotEmpty) 'path': path,
        if (host.isNotEmpty)
          'headers': {'Host': host},
      },
    },
    'grpc' => {
      'transport': {
        'type': 'grpc',
        if (serviceName.isNotEmpty) 'service_name': serviceName,
      },
    },
    'httpupgrade' => {
      'transport': {
        'type': 'httpupgrade',
        if (path.isNotEmpty) 'path': path,
        if (host.isNotEmpty) 'host': host,
      },
    },
    'http' || 'h2' => {
      'transport': {
        'type': 'http',
        if (host.isNotEmpty) 'host': [host],
        if (path.isNotEmpty) 'path': path,
      },
    },
    _ => null,
  };
}

/// Декодирует base64, прощая url-safe алфавит и отсутствие выравнивания:
/// в подписках встречается и то, и другое.
String? _base64OrNull(String raw) {
  var s = raw.trim().replaceAll('-', '+').replaceAll('_', '/');
  s = s.replaceAll(RegExp(r'\s'), '');
  if (s.isEmpty) return null;
  s = s.padRight(s.length + (4 - s.length % 4) % 4, '=');
  try {
    return utf8.decode(base64.decode(s));
  } catch (_) {
    return null;
  }
}
