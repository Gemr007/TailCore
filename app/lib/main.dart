import 'package:flutter/material.dart';

import 'screens/dashboard.dart';

void main() => runApp(const TaleCoreApp());

class TaleCoreApp extends StatelessWidget {
  const TaleCoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaleCore',
      debugShowCheckedModeBanner: false,
      // Светлой темы у приложения не предполагается — не тема по умолчанию,
      // а единственная.
      // TODO(шаг 6): IBM Plex Sans + JetBrains Mono, палитра из макетов.
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AppShell(),
    );
  }
}

/// Раздел приложения. Экран подписки и управление устройствами сюда
/// сознательно не входят — они делаются отдельно.
enum Section {
  dashboard('Соединение', Icons.shield_outlined, Icons.shield),
  servers('Серверы', Icons.dns_outlined, Icons.dns),
  settings('Настройки', Icons.tune_outlined, Icons.tune);

  const Section(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Оболочка с навигацией, которая разворачивается в плотность на десктопе
/// и сворачивается в простоту на мобильном: рейл сбоку против панели снизу.
/// Порог по ширине, а не по платформе, — узкое окно на десктопе ведёт себя
/// как телефон, и это правильно.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Section _section = Section.dashboard;

  static const _railBreakpoint = 700.0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final body = SafeArea(
      child: switch (_section) {
        Section.dashboard => const DashboardScreen(),
        // Содержимое приезжает отдельными шагами: Servers — шаг 7,
        // Settings — шаг 10.
        _ => _SectionPlaceholder(section: _section),
      },
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _section.index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final s in Section.values)
                  NavigationRailDestination(
                    icon: Icon(s.icon),
                    selectedIcon: Icon(s.selectedIcon),
                    label: Text(s.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _section.index,
        onDestinationSelected: _select,
        destinations: [
          for (final s in Section.values)
            NavigationDestination(
              icon: Icon(s.icon),
              selectedIcon: Icon(s.selectedIcon),
              label: s.label,
            ),
        ],
      ),
    );
  }

  void _select(int index) => setState(() => _section = Section.values[index]);
}

/// Заглушка ещё не сделанного раздела.
class _SectionPlaceholder extends StatelessWidget {
  const _SectionPlaceholder({required this.section});

  final Section section;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        section.label,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
    );
  }
}
