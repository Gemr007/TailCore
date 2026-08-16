import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailcore/core/servers_store.dart';
import 'package:tailcore/main.dart';
import 'package:tailcore/screens/dashboard.dart';
import 'package:tailcore/screens/servers.dart';

late Directory _dir;

/// Ставит размер окна на время теста: оболочка выбирает боковую панель или
/// нижнюю, так что размер окна здесь — сам предмет проверки.
Future<ServersStore> pumpAt(WidgetTester tester, Size size) async {
  final store = ServersStore(storage: File('${_dir.path}/servers.json'));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(TailCoreApp(store: store));
  await tester.pumpAndSettle();
  return store;
}

/// Ищет пункт навигации: название раздела встречается и в хроме, и внутри
/// заглушки экрана, поэтому по одному тексту различить их нельзя.
Finder navItem(Section s) =>
    find.descendant(of: find.byType(InkWell), matching: find.text(s.label));

Future<void> goTo(WidgetTester tester, Section s) async {
  await tester.tap(navItem(s));
  await tester.pumpAndSettle();
}

/// Импорт пишет список на диск, а внутри testWidgets время фейковое и
/// настоящий файловый ввод-вывод в нём не завершается никогда. runAsync
/// на время операции возвращает настоящий цикл событий.
Future<void> importInto(
  WidgetTester tester,
  ServersStore store,
  String text,
) async {
  await tester.runAsync(() => store.import(text));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('tailcore-widget'));
  tearDown(() => _dir.deleteSync(recursive: true));

  testWidgets('широкое окно получает боковую панель, узкое — нижнюю', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1400, 900));
    expect(find.text('TailCore'), findsWidgets); // бренд в боковой панели
    expect(find.text('ЯДРО'), findsOneWidget); // подвал боковой панели

    await pumpAt(tester, const Size(420, 900));
    expect(find.text('ЯДРО'), findsNothing);
  });

  testWidgets('переключение раздела меняет содержимое', (tester) async {
    await pumpAt(tester, const Size(420, 900));
    expect(find.byType(DashboardScreen), findsOneWidget);

    await goTo(tester, Section.servers);
    expect(find.byType(DashboardScreen), findsNothing);
    expect(find.byType(ServersScreen), findsOneWidget);
  });

  testWidgets('без узлов экран серверов зовёт импортировать', (tester) async {
    await pumpAt(tester, const Size(420, 900));
    await goTo(tester, Section.servers);

    expect(find.text('СПИСОК ПУСТ'), findsOneWidget);
    // Мерить нечего — кнопка замера не показывается.
    expect(find.text('ЗАМЕРИТЬ'), findsNothing);
  });

  testWidgets('импортированный узел появляется в списке и на соединении', (
    tester,
  ) async {
    final store = await pumpAt(tester, const Size(420, 900));
    await importInto(tester, store, 'vless://u@1.2.3.4:8443#ams-02');

    await goTo(tester, Section.servers);
    expect(find.text('ams-02'), findsOneWidget);
    expect(find.text('1.2.3.4:8443'), findsOneWidget);
    expect(find.text('ЗАМЕРИТЬ'), findsOneWidget);
    // Один протокол — выбирать не из чего, чипы не показываем.
    expect(find.text(ServersStore.filterAll), findsNothing);

    await goTo(tester, Section.dashboard);
    expect(find.text('ams-02'), findsOneWidget);
  });

  testWidgets('фильтр по протоколу отсеивает узлы', (tester) async {
    final store = await pumpAt(tester, const Size(420, 900));
    await importInto(
      tester,
      store,
      'vless://u@1.1.1.1:443#v-node\ntrojan://p@2.2.2.2:443#t-node',
    );
    await goTo(tester, Section.servers);

    expect(find.text('v-node'), findsOneWidget);
    expect(find.text('t-node'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('protocol-filter-TROJAN')));
    await tester.pumpAndSettle();

    expect(find.text('t-node'), findsOneWidget);
    expect(find.text('v-node'), findsNothing);
  });

  testWidgets('экран соединения рисуется независимо от доступности ядра', (
    tester,
  ) async {
    await pumpAt(tester, const Size(420, 900));

    expect(find.text('Подключить'), findsOneWidget);
    // Скорости пока нет ни в одном случае: туннель не поднят.
    expect(find.text('—'), findsNWidgets(2));

    // Строка состояния зависит от того, нашлась ли нативная библиотека:
    // с ядром это «без защиты», без ядра — «ядро недоступно». Оба ответа
    // корректны, падение — нет.
    expect(
      find.text('БЕЗ ЗАЩИТЫ').evaluate().length +
          find.text('ЯДРО НЕДОСТУПНО').evaluate().length,
      1,
    );
  });
}
