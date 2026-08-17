import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tailcore/core/prefs.dart';
import 'package:tailcore/core/servers_store.dart';
import 'package:tailcore/core/singbox_config.dart';

/// Хранилище с файлом во временном каталоге: настоящий путь приложения
/// в тестах недоступен, а писать в него из теста и не следует.
ServersStore storeIn(Directory dir, [String name = 'servers.json']) =>
    ServersStore(storage: File('${dir.path}/$name'));

const _links = '''
vless://u1@1.1.1.1:443#fast
trojan://p@2.2.2.2:443#slow
hy2://p@3.3.3.3:36712#quic
''';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('tailcore'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('импорт добавляет узлы и не плодит дубликаты', () async {
    final store = storeIn(dir);

    expect((await store.import(_links)).added, 3);
    expect(store.servers.length, 3);

    // Повторный импорт той же подписки — обычное дело, дублей быть не должно.
    expect((await store.import(_links)).added, 0);
    expect(store.servers.length, 3);
  });

  test('список переживает перезапуск вместе с выбором', () async {
    final store = storeIn(dir);
    await store.import(_links);
    store.select(store.servers[1]);
    await store.save();

    final reopened = storeIn(dir);
    await reopened.load();
    expect(reopened.servers.map((s) => s.name), ['fast', 'slow', 'quic']);
    expect(reopened.active?.name, 'slow');
    expect(reopened.auto, isFalse);
  });

  test('битый файл не мешает запуску', () async {
    File('${dir.path}/servers.json').writeAsStringSync('{ это не json');
    final store = storeIn(dir);
    await store.load();
    expect(store.servers, isEmpty);
  });

  test('фильтр показывает только те протоколы, что есть в списке', () async {
    final store = storeIn(dir);
    await store.import(_links);
    expect(store.protocolFilters, [
      ServersStore.filterAll,
      'HY2',
      'TROJAN',
      'VLESS',
    ]);
    expect(store.sortedByLatency('HY2').map((s) => s.name), ['quic']);
    expect(store.sortedByLatency('TUIC'), isEmpty);
  });

  test('Auto держит самый быстрый узел, ручной выбор — свой', () async {
    final store = storeIn(dir);
    await store.import(_links);

    store.select(store.servers[2]);
    expect(store.active?.name, 'quic');
    expect(store.auto, isFalse);

    store.enableAuto();
    expect(store.auto, isTrue);
    // Замера ещё не было — Auto всё равно обязан куда-то вести.
    expect(store.active, isNotNull);
  });

  test('удаление снимает выбор, а не оставляет его висеть', () async {
    final store = storeIn(dir);
    await store.import(_links);
    final chosen = store.servers[1];
    store.select(chosen);

    store.remove(chosen);
    expect(store.servers.map((s) => s.name), ['fast', 'quic']);
    expect(store.active?.name, 'fast');
  });

  group('конфиги для ядра', () {
    test('рабочий конфиг заворачивает узел в исходящий proxy', () async {
      final store = storeIn(dir);
      await store.import('vless://u@1.1.1.1:443#n');
      final config = jsonDecode(buildRunConfig(store.servers.single));

      final outbounds = config['outbounds'] as List;
      expect(outbounds.first['tag'], 'proxy');
      expect(outbounds.first['type'], 'vless');
      expect(config['route']['final'], 'proxy');
      expect(config['inbounds'].single['listen_port'], defaultLocalPort);
    });

    test('конфиг замера не открывает входящих', () async {
      // Замер поднимает второй экземпляр ядра: занятый порт основного
      // туннеля уронил бы его на старте.
      final store = storeIn(dir);
      await store.import(_links);
      final config = jsonDecode(buildTestConfig(store.servers));

      expect(config.containsKey('inbounds'), isFalse);

      final outbounds = config['outbounds'] as List;
      // Теги — ключи узлов: по ним же придут задержки.
      expect(
        outbounds.map((o) => o['tag']),
        store.servers.map((s) => s.id).toList(),
      );
    });
  });
}
