import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailcore/core/import.dart';
import 'package:tailcore/core/server.dart';

void main() {
  group('share-ссылки', () {
    test('VLESS + Reality разбирается со всеми параметрами маскировки', () {
      final s = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@1.2.3.4:8443'
        '?security=reality&sni=www.cloudflare.com&fp=chrome'
        '&pbk=abc123&sid=6ba8&flow=xtls-rprx-vision&type=tcp'
        '#ams-02%20reality',
      );

      expect(s, isNotNull);
      expect(s!.protocol, 'vless');
      expect(s.host, '1.2.3.4');
      expect(s.port, 8443);
      expect(s.name, 'ams-02 reality');
      expect(s.outbound['uuid'], '11111111-2222-3333-4444-555555555555');
      expect(s.outbound['flow'], 'xtls-rprx-vision');

      final tls = s.outbound['tls'] as Map<String, dynamic>;
      expect(tls['server_name'], 'www.cloudflare.com');
      expect(tls['utls'], {'enabled': true, 'fingerprint': 'chrome'});
      expect(tls['reality'], {
        'enabled': true,
        'public_key': 'abc123',
        'short_id': '6ba8',
      });
      // tcp — это отсутствие транспорта, а не транспорт с именем tcp.
      expect(s.outbound.containsKey('transport'), isFalse);
    });

    test('VLESS поверх WebSocket получает транспорт с заголовком Host', () {
      final s = parseShareLink(
        'vless://uuid@example.com:443?type=ws&path=%2Fws&host=cdn.example.com'
        '&security=tls#ws-node',
      );
      expect(s!.outbound['transport'], {
        'type': 'ws',
        'path': '/ws',
        'headers': {'Host': 'cdn.example.com'},
      });
    });

    test('VMess разбирается из base64 с JSON внутри', () {
      final payload = base64.encode(
        utf8.encode(
          jsonEncode({
            'v': '2',
            'ps': 'fra-01',
            'add': '9.9.9.9',
            'port': '2096',
            'id': 'uuid-here',
            'aid': '0',
            'net': 'grpc',
            'path': 'grpcservice',
            'tls': 'tls',
            'sni': 'fra.example.com',
          }),
        ),
      );
      final s = parseShareLink('vmess://$payload');

      expect(s!.protocol, 'vmess');
      expect(s.name, 'fra-01');
      expect(s.port, 2096);
      expect(s.outbound['alter_id'], 0);
      expect(s.outbound['transport'], {
        'type': 'grpc',
        'service_name': 'grpcservice',
      });
      expect((s.outbound['tls'] as Map)['server_name'], 'fra.example.com');
    });

    test('Trojan получает TLS даже без security в ссылке', () {
      // Смысл Trojan в маскировке под HTTPS: без TLS его не бывает.
      final s = parseShareLink('trojan://secret@t.example.com:443#tro');
      expect(s!.outbound['password'], 'secret');
      expect((s.outbound['tls'] as Map)['enabled'], isTrue);
      expect((s.outbound['tls'] as Map)['server_name'], 't.example.com');
    });

    test('Shadowsocks читается в обеих живых формах', () {
      final sip002 = parseShareLink(
        'ss://${base64.encode(utf8.encode('aes-256-gcm:pass'))}@5.5.5.5:8388#ss-new',
      );
      expect(sip002!.outbound['method'], 'aes-256-gcm');
      expect(sip002.outbound['password'], 'pass');
      expect(sip002.host, '5.5.5.5');
      expect(sip002.name, 'ss-new');

      final legacy = parseShareLink(
        'ss://${base64.encode(utf8.encode('chacha20-ietf-poly1305:pw@6.6.6.6:8389'))}#ss-old',
      );
      expect(legacy!.outbound['method'], 'chacha20-ietf-poly1305');
      expect(legacy.outbound['password'], 'pw');
      expect(legacy.host, '6.6.6.6');
      expect(legacy.port, 8389);
    });

    test('Hysteria2 понимает обфускацию и короткую схему hy2', () {
      final s = parseShareLink(
        'hy2://pw@h.example.com:36712?obfs=salamander&obfs-password=zzz'
        '&insecure=1&sni=cdn.example.com#hy',
      );
      expect(s!.protocol, 'hysteria2');
      expect(s.badge, 'HY2');
      expect(s.outbound['obfs'], {'type': 'salamander', 'password': 'zzz'});
      expect((s.outbound['tls'] as Map)['insecure'], isTrue);
    });

    test('TUIC разбирает пару uuid:пароль', () {
      final s = parseShareLink(
        'tuic://uuid-1:secret@t.example.com:443?congestion_control=bbr#tuic',
      );
      expect(s!.outbound['uuid'], 'uuid-1');
      expect(s.outbound['password'], 'secret');
      expect(s.outbound['congestion_control'], 'bbr');
    });

    test('WireGuard-ссылка становится endpoint, а не исходящим', () {
      final s = parseShareLink(
        'wireguard://cHJpdmF0ZUtleQ%3D%3D@1.2.3.4:51820'
        '?publickey=cHVibGljS2V5&address=172.16.0.2/32,fd00::2/128'
        '&mtu=1420&reserved=1,2,3#wg-node',
      );

      expect(s, isNotNull);
      expect(s!.protocol, 'wireguard');
      expect(s.badge, 'WG');
      // Адрес узла берётся у пира: на верхнем уровне его нет вовсе.
      expect(s.host, '1.2.3.4');
      expect(s.port, 51820);
      expect(s.isEndpoint, isTrue);

      // Ключ остаётся base64 — таким его и ждёт ядро; из ссылки снимается
      // только percent-кодирование, которым закрыты «=» в конце.
      expect(s.outbound['private_key'], 'cHJpdmF0ZUtleQ==');
      expect(s.outbound['address'], ['172.16.0.2/32', 'fd00::2/128']);
      expect(s.outbound['mtu'], 1420);

      final peer = (s.outbound['peers'] as List).single as Map;
      expect(peer['public_key'], 'cHVibGljS2V5');
      expect(peer['reserved'], [1, 2, 3]);
    });

    test('SSH и AnyTLS разбираются, NaiveProxy отвергается с причиной', () {
      final ssh = parseShareLink('ssh://root:pw@10.0.0.1:2222#ssh-box');
      expect(ssh!.protocol, 'ssh');
      expect(ssh.port, 2222);
      expect(ssh.outbound['user'], 'root');
      expect(ssh.outbound['password'], 'pw');

      // Порт по умолчанию у SSH свой, и он не 443.
      expect(parseShareLink('ssh://root@10.0.0.1#s')!.port, 22);

      final anytls = parseShareLink('anytls://pw@a.example.com:8443#any');
      expect(anytls!.protocol, 'anytls');
      // AnyTLS без TLS не бывает — как и Trojan.
      expect((anytls.outbound['tls'] as Map)['enabled'], isTrue);

      // NaiveProxy ядру нужен Cronet — узел не собирается, но и не
      // пропадает молча: пользователю называют причину.
      final naive = parseImport(
        'naive+https://user:pw@n.example.com:443#naive',
      );
      expect(naive.servers, isEmpty);
      expect(naive.skipped.single.name, 'naive');
      expect(naive.skipped.single.reason, contains('Cronet'));
    });

    test('плагин Shadowsocks не теряется по дороге', () {
      // obfs-local ядро исполняет само — плагин уезжает в конфиг как есть.
      final obfs = parseShareLink(
        'ss://${base64.encode(utf8.encode('aes-256-gcm:pass'))}@5.5.5.5:8388'
        '?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dbing.com#ss-obfs',
      );
      expect(obfs!.outbound['plugin'], 'obfs-local');
      expect(obfs.outbound['plugin_opts'], 'obfs=http;obfs-host=bing.com');

      // ShadowTLS — это второй исходящий под узлом, а не поле в нём.
      final st = parseShareLink(
        'ss://${base64.encode(utf8.encode('aes-256-gcm:pass'))}@6.6.6.6:443'
        '?plugin=shadow-tls%3Bhost%3Dwww.microsoft.com%3Bpassword%3Dstpw'
        '%3Bversion%3D3#ss-stls',
      );
      expect(st!.protocol, 'shadowsocks');
      final transport = st.extras.single;
      expect(st.outbound['detour'], transport['tag']);
      expect(transport['type'], 'shadowtls');
      expect(transport['version'], 3);
      expect(transport['password'], 'stpw');
      expect((transport['tls'] as Map)['server_name'], 'www.microsoft.com');

      // Незнакомый плагин называется вслух, а не выбрасывается молча.
      final result = parseImport(
        'ss://${base64.encode(utf8.encode('aes-256-gcm:pass'))}@7.7.7.7:8388'
        '?plugin=kcptun#ss-kcp',
      );
      expect(result.servers, isEmpty);
      expect(result.skipped.single.reason, contains('kcptun'));
    });

    test('незнакомая схема и мусор не роняют импорт', () {
      expect(parseShareLink('magnet:?xt=urn:btih:whatever'), isNull);
      expect(parseShareLink('vless://@:0'), isNull);
      expect(parseShareLink('просто текст'), isNull);
    });
  });

  group('parseImport', () {
    test('читает конфиг sing-box и пропускает служебные исходящие', () {
      final servers = parseImport('''
        {
          "outbounds": [
            {"type": "direct", "tag": "direct"},
            {"type": "block", "tag": "block"},
            {"type": "vless", "tag": "n1", "server": "1.1.1.1", "server_port": 443, "uuid": "u"},
            {"type": "trojan", "tag": "n2", "server": "2.2.2.2", "server_port": 443, "password": "p"}
          ]
        }
      ''');
      expect(servers.servers.map((s) => s.name), ['n1', 'n2']);
    });

    test('исходящий, на который ссылается detour, узлом не считается', () {
      // Так записывают ShadowTLS в конфиге sing-box: два исходящих, из
      // которых узел — только верхний.
      final result = parseImport('''
        {
          "outbounds": [
            {"type": "shadowsocks", "tag": "ss", "server": "1.1.1.1",
             "server_port": 443, "method": "aes-256-gcm", "password": "p",
             "detour": "stls"},
            {"type": "shadowtls", "tag": "stls", "server": "1.1.1.1",
             "server_port": 443, "version": 3, "password": "s"}
          ]
        }
      ''');

      final node = result.servers.single;
      expect(node.name, 'ss');
      expect(node.extras.single['tag'], 'stls');
    });

    test('читает список ссылок построчно', () {
      final servers = parseImport('''
        vless://u@1.1.1.1:443#a
        trojan://p@2.2.2.2:443#b
      ''');
      expect(servers.servers.map((s) => s.name), ['a', 'b']);
    });

    test('читает подписку в base64 без выравнивания', () {
      final links = 'vless://u@1.1.1.1:443#a\ntrojan://p@2.2.2.2:443#b';
      final sub = base64.encode(utf8.encode(links)).replaceAll('=', '');
      expect(parseImport(sub).servers.map((s) => s.name), ['a', 'b']);
    });

    test('узел на XHTTP собирается для Xray, а не отвергается', () {
      // Форма взята с настоящей подписки пользователя.
      final result = parseImport(
        'vless://u@xh.example.com:443?type=xhttp&path=%2Fchunk'
        '&host=cdn.example.com&security=tls&sni=cdn.example.com&fp=chrome'
        '#через-xhttp',
      );

      final s = result.servers.single;
      expect(s.viaXray, isTrue);
      expect(s.host, 'xh.example.com');
      expect(s.port, 443);
      // Ключ узла отличает движок: тот же адрес встречается в подписке и
      // обычным узлом, и узлом на XHTTP.
      expect(s.id, startsWith('xray+'));

      // Исходящий в формате Xray, а не sing-box: протокол отдельно, адрес
      // внутри settings.
      expect(s.outbound['protocol'], 'vless');
      final vnext = ((s.outbound['settings'] as Map)['vnext'] as List).single;
      expect(vnext['address'], 'xh.example.com');
      expect((vnext['users'] as List).single['id'], 'u');

      final stream = s.outbound['streamSettings'] as Map;
      expect(stream['network'], 'xhttp');
      expect(stream['security'], 'tls');
      expect((stream['xhttpSettings'] as Map)['path'], '/chunk');
      expect((stream['tlsSettings'] as Map)['fingerprint'], 'chrome');
    });

    test('mKCP и Reality тоже уходят на Xray', () {
      final kcp = parseImport(
        'vless://u@k.example.com:2052?type=kcp&headerType=srtp&seed=zzz#kcp',
      ).servers.single;
      expect(kcp.viaXray, isTrue);
      final kcpStream = kcp.outbound['streamSettings'] as Map;
      expect(kcpStream['network'], 'kcp');
      expect((kcpStream['kcpSettings'] as Map)['header'], {'type': 'srtp'});
      expect((kcpStream['kcpSettings'] as Map)['seed'], 'zzz');

      // Reality поверх Xray-транспорта описывается по-своему.
      final reality = parseImport(
        'vless://u@r.example.com:443?type=xhttp&security=reality'
        '&pbk=key&sid=ab&sni=www.example.com&fp=chrome#reality-xhttp',
      ).servers.single;
      final settings =
          (reality.outbound['streamSettings'] as Map)['realitySettings'] as Map;
      expect(settings['publicKey'], 'key');
      expect(settings['shortId'], 'ab');
      expect(settings['serverName'], 'www.example.com');
    });

    test('узел на Xray переживает сохранение и чтение', () {
      final saved = parseImport(
        'vless://u@xh.example.com:443?type=xhttp&security=tls#xhttp',
      ).servers.single;
      final restored = Server.fromJson(saved.toJson())!;

      expect(restored.viaXray, isTrue);
      expect(restored.id, saved.id);
      expect(restored.host, 'xh.example.com');
      expect(restored.outbound['protocol'], 'vless');
    });

    test('обычные узлы и узлы на Xray разъезжаются по движкам', () {
      // Форма взята с настоящей подписки: рядом с обычными узлами приходят
      // узлы на XHTTP, которого в sing-box нет.
      final result = parseImport('''
        vless://u@ok.example.com:443?type=tcp&security=reality&pbk=k&sid=1#обычный
        vless://u@xh.example.com:443?type=xhttp&path=%2Fchunk&security=tls#через-xhttp
        vless://u@kcp.example.com:443?type=kcp&security=tls#через-kcp
      ''');

      expect(result.skipped, isEmpty);
      expect(result.servers.map((s) => s.name), [
        'обычный',
        'через-xhttp',
        'через-kcp',
      ]);
      expect(result.servers.map((s) => s.viaXray), [false, true, true]);
    });

    test('транспорт, неизвестный обоим движкам, отвергается с причиной', () {
      final result = parseImport(
        'vless://u@x.example.com:443?type=невиданный&security=tls#странный',
      );
      expect(result.servers, isEmpty);
      expect(result.skipped.single.reason, contains('невиданный'));
    });

    test('пустой и бессмысленный ввод дают пустой список, а не ошибку', () {
      expect(parseImport('').servers, isEmpty);
      expect(parseImport('   ').servers, isEmpty);
      expect(parseImport('{"outbounds": []}').servers, isEmpty);
      expect(parseImport('здесь нет конфигов').servers, isEmpty);
    });
  });

  group('WireGuard .conf', () {
    const conf = '''
[Interface]
PrivateKey = cHJpdmF0ZUtleQ==
Address = 10.13.13.2/32, fd00::2/128
MTU = 1420
DNS = 1.1.1.1

[Peer]
PublicKey = cHVibGljS2V5
PresharedKey = cHNr
Endpoint = vpn.example.com:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
''';

    test('файл провайдера разбирается целиком', () {
      final result = parseImport(conf);
      expect(result.skipped, isEmpty);

      final s = result.servers.single;
      expect(s.protocol, 'wireguard');
      expect(s.host, 'vpn.example.com');
      expect(s.port, 51820);
      expect(s.outbound['private_key'], 'cHJpdmF0ZUtleQ==');
      expect(s.outbound['address'], ['10.13.13.2/32', 'fd00::2/128']);

      final peer = (s.outbound['peers'] as List).single as Map;
      expect(peer['public_key'], 'cHVibGljS2V5');
      expect(peer['pre_shared_key'], 'cHNr');
      expect(peer['allowed_ips'], ['0.0.0.0/0', '::/0']);
    });

    test('адрес без длины префикса дополняется, а не отбрасывается', () {
      final s = parseImport(
        conf.replaceAll(
          'Address = 10.13.13.2/32, fd00::2/128',
          'Address = 10.13.13.2',
        ),
      ).servers.single;
      expect(s.outbound['address'], ['10.13.13.2/32']);
    });

    test('файл без ключа пира отвергается с причиной, а не наполовину', () {
      final result = parseImport(
        conf.replaceAll('PublicKey = cHVibGljS2V5', ''),
      );
      expect(result.servers, isEmpty);
      expect(result.skipped.single.reason, contains('ключей'));
    });

    test('AmneziaWG опознаётся и не притворяется обычным WireGuard', () {
      // Ключи обфускации меняют сам протокол: собрать из такого файла
      // обычный WireGuard — значит отдать узел, который не подключится и
      // не объяснит почему.
      final result = parseImport(
        conf.replaceAll(
          'MTU = 1420',
          'MTU = 1420\nJc = 4\nJmin = 40\nJmax = 70\nS1 = 15\nH1 = 1234567',
        ),
      );

      expect(result.servers, isEmpty);
      expect(result.skipped.single.reason, contains('AmneziaWG'));
      // Причина называет найденные параметры: по ним видно, что это не
      // догадка парсера.
      expect(result.skipped.single.reason, contains('jc'));
    });
  });

  group('Server', () {
    test('ключ узла переживает переименование', () {
      // Провайдер свободно меняет имена узлов в подписке; выбор
      // пользователя от этого слетать не должен.
      final before = parseShareLink('vless://u@1.1.1.1:443#старое имя')!;
      final after = parseShareLink('vless://u@1.1.1.1:443#новое имя')!;
      expect(before.id, after.id);
    });

    test('узел переживает сохранение и чтение', () {
      final before = parseShareLink(
        'vless://u@1.1.1.1:443?security=reality&pbk=k&fp=chrome#n',
      )!;
      final after = Server.fromJson(jsonDecode(jsonEncode(before.toJson())));
      expect(after!.id, before.id);
      expect(after.name, before.name);
      expect(after.outbound, before.outbound);
    });
  });
}
