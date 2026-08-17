import 'package:flutter/material.dart';

import 'core/prefs.dart';
import 'core/servers_store.dart';
import 'screens/dashboard.dart';
import 'screens/servers.dart';
import 'screens/settings.dart';
import 'theme.dart';

void main() => runApp(const TailCoreApp());

class TailCoreApp extends StatefulWidget {
  const TailCoreApp({super.key, this.store, this.prefs});

  /// Хранилище узлов. Подставляется в тестах; в приложении создаётся здесь
  /// и живёт всё время работы.
  final ServersStore? store;

  /// Настройки. Подставляются в тестах по той же причине.
  final Prefs? prefs;

  @override
  State<TailCoreApp> createState() => _TailCoreAppState();
}

class _TailCoreAppState extends State<TailCoreApp> {
  late final ServersStore _store = widget.store ?? ServersStore();
  late final Prefs _prefs = widget.prefs ?? Prefs();

  @override
  void initState() {
    super.initState();
    // Список узлов и настройки не нужны для первого кадра: экраны рисуются
    // с пустыми значениями и наполняются, когда файлы прочитаны.
    unawaited(_store.load());
    unawaited(_prefs.load());
  }

  @override
  void dispose() {
    _store.dispose();
    _prefs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TailCore',
      debugShowCheckedModeBanner: false,
      // Светлой темы у приложения не предполагается — не тема по умолчанию,
      // а единственная.
      theme: buildTheme(),
      home: AppShell(store: _store, prefs: _prefs),
    );
  }
}

/// Раздел приложения. Экран подписки и управление устройствами сюда
/// сознательно не входят — они делаются отдельно.
enum Section {
  dashboard('Соединение', '1'),
  servers('Серверы', '2'),
  settings('Настройки', '3');

  const Section(this.label, this.key);

  final String label;

  /// Цифра рядом с пунктом в боковой панели — как в макете.
  final String key;
}

/// Оболочка с навигацией, которая разворачивается в плотность на десктопе
/// и сворачивается в простоту на мобильном: боковая панель против панели
/// снизу. Порог по ширине, а не по платформе, — узкое окно на десктопе
/// ведёт себя как телефон, и это правильно.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store, required this.prefs});

  final ServersStore store;
  final Prefs prefs;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Section _section = Section.dashboard;

  static const _sidebarBreakpoint = 700.0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _sidebarBreakpoint;
    final body = SafeArea(
      child: switch (_section) {
        Section.dashboard => DashboardScreen(
          store: widget.store,
          prefs: widget.prefs,
        ),
        Section.servers => ServersScreen(store: widget.store),
        Section.settings => SettingsScreen(prefs: widget.prefs),
      },
    );

    return Scaffold(
      body: wide
          ? Row(
              children: [
                _Sidebar(current: _section, onSelect: _select),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: wide
          ? null
          : _TabBar(current: _section, onSelect: _select),
    );
  }

  void _select(Section s) => setState(() => _section = s);
}

/// Боковая панель десктопа: разделы, а внизу — состояние ядра, которое на
/// плотном экране полезнее пустоты.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.onSelect});

  final Section current;
  final ValueChanged<Section> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 212,
      decoration: const BoxDecoration(
        color: C.chrome,
        border: Border(right: BorderSide(color: C.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 4, 8, 18),
              child: Row(
                children: [
                  _BrandMark(),
                  SizedBox(width: 9),
                  Text(
                    'TailCore',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.15,
                      color: C.text,
                    ),
                  ),
                ],
              ),
            ),
            for (final s in Section.values)
              _SidebarItem(
                section: s,
                selected: s == current,
                onTap: () => onSelect(s),
              ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.fromLTRB(9, 12, 9, 0),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: C.divider)),
              ),
              child: Column(
                children: [
                  // TODO(шаг 18): TUN появится здесь, когда его будет что
                  // показывать.
                  _CoreFact(label: 'ЯДРО', value: 'sing-box 1.13.18'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final Section section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      hoverColor: C.hover,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
        decoration: BoxDecoration(
          color: selected ? C.hover : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border(
            left: BorderSide(
              color: selected ? C.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              child: Text(
                section.key,
                textAlign: TextAlign.center,
                style: monoStyle(size: 11, color: C.textMuted),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              section.label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? C.text : C.textDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoreFact extends StatelessWidget {
  const _CoreFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    // Панель фиксированной ширины, а значение приходит из ядра и длину
    // не гарантирует — режем его, а не ломаем раскладку.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: monoStyle(size: 10, caps: true, color: C.textFaint)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(size: 10, color: C.textDim),
          ),
        ),
      ],
    );
  }
}

/// Нижняя панель мобильного: те же разделы, но подписи моноширинные и
/// заглавные — это ярлыки, а не предложения.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.current, required this.onSelect});

  final Section current;
  final ValueChanged<Section> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: C.chrome,
        border: Border(top: BorderSide(color: C.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final s in Section.values)
              Expanded(
                child: InkWell(
                  onTap: () => onSelect(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      s.label,
                      textAlign: TextAlign.center,
                      style: monoStyle(
                        size: 9.5,
                        caps: true,
                        color: s == current ? C.accent : C.textFaint,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        color: C.accent,
        borderRadius: BorderRadius.circular(2.5),
      ),
    );
  }
}
