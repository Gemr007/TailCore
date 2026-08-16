import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailcore/main.dart';
import 'package:tailcore/screens/dashboard.dart';

/// Ставит размер окна на время теста: оболочка выбирает боковую панель или
/// нижнюю, так что размер окна здесь — сам предмет проверки.
Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const TailCoreApp());
  await tester.pumpAndSettle();
}

/// Ищет пункт навигации: название раздела встречается и в хроме, и внутри
/// заглушки экрана, поэтому по одному тексту различить их нельзя.
Finder navItem(Section s) =>
    find.descendant(of: find.byType(InkWell), matching: find.text(s.label));

void main() {
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

    await tester.tap(navItem(Section.servers));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsNothing);
    // Заглушка пишет название раздела в теле экрана — вместе с ярлыком в
    // панели навигации получается два вхождения.
    expect(find.text(Section.servers.label), findsNWidgets(2));
  });

  testWidgets('экран соединения рисуется независимо от доступности ядра', (
    tester,
  ) async {
    await pumpAt(tester, const Size(420, 900));

    // Кнопка и узел из конфига не зависят от того, поднялось ли ядро.
    expect(find.text('Подключить'), findsOneWidget);
    expect(find.text('ams-02 · reality'), findsOneWidget);

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
