import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:talecore/main.dart';

/// Ставит размер окна на время теста: оболочка выбирает рейл или нижнюю
/// панель по ширине, так что размер окна здесь — сам предмет проверки.
Future<void> pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const TaleCoreApp());
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

    // Название раздела есть и в панели навигации, и в теле экрана.
    expect(find.text(Section.dashboard.label), findsNWidgets(2));
    expect(find.text(Section.servers.label), findsOneWidget);

    await tester.tap(find.text(Section.servers.label));
    await tester.pumpAndSettle();

    expect(find.text(Section.servers.label), findsNWidgets(2));
    expect(find.text(Section.dashboard.label), findsOneWidget);
  });
}
