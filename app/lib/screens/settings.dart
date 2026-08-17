import 'package:flutter/material.dart';

import '../core/prefs.dart';
import '../theme.dart';
import '../widgets/panel.dart';

/// Экран настроек.
///
/// Пока здесь только роутинг — остальное (kill switch, TUN, автозапуск,
/// DNS) приезжает шагом 10. Экраны подписки и управления устройствами в эту
/// итерацию не входят вовсе.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.prefs});

  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.sizeOf(context).width >= 700 ? 26.0 : 22.0;

    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => ListView(
        padding: EdgeInsets.fromLTRB(pad, 20, pad, 20),
        children: [
          Text('Настройки', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          const _SectionLabel('РОУТИНГ'),
          const SizedBox(height: 8),
          _ToggleRow(
            label: 'Игры мимо VPN',
            hint: 'игровой трафик идёт напрямую, минуя туннель',
            value: prefs.bypassGames,
            onTap: () => prefs.setBypassGames(!prefs.bypassGames),
          ),
          const SizedBox(height: 10),
          // Конфиг собирается в момент подключения: перещёлкнуть тумблер на
          // поднятом туннеле и ждать перемен — значит смотреть на старый
          // маршрут и не понимать почему.
          Text(
            'Список игровых доменов ядро скачивает через туннель при\n'
            'подключении. Изменение применяется со следующего подключения.',
            style: monoStyle(size: 10.5, color: C.textFaint),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: monoStyle(size: 10, caps: true, color: C.textMuted),
    );
  }
}

/// Строка-переключатель из макета: название, пояснение и плоский тумблер.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 13.5, color: C.text),
                  ),
                  const SizedBox(height: 3),
                  Text(hint, style: monoStyle(size: 10.5, color: C.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Switch(value: value),
          ],
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 23,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? C.accent : C.hover,
        border: Border.all(color: value ? C.accent : C.panelBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Align(
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: value ? C.onAccent : C.textMuted,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
