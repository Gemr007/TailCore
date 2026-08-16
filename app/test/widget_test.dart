import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tailcore/main.dart';
import 'package:tailcore/screens/dashboard.dart';

/// Ставит размер окна на время теста: оболочка выбирает рейл или нижнюю
/// панель по ширине, так что размер окна здесь — сам предмет проверки.
Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const TailCoreApp());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('широкое окно получает рейл, узкое — нижнюю панель', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1400, 900));
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    await pumpAt(tester, const Size(420, 900));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('переключение раздела меняет содержимое', (tester) async {
    await pumpAt(tester, const Size(420, 900));

    // Стартуем на соединении: в панели навигации его название есть один раз,
    // в теле — экран соединения.
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.text(Section.servers.label), findsOneWidget);

    await tester.tap(find.text(Section.servers.label));
    await tester.pumpAndSettle();

    // У заглушки название раздела написано в теле — значит, оно встретится
    // дважды: в панели и на экране.
    expect(find.text(Section.servers.label), findsNWidgets(2));
    expect(find.byType(DashboardScreen), findsNothing);
  });
}
