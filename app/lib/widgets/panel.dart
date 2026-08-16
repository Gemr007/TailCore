import 'package:flutter/material.dart';

import '../theme.dart';

/// Карточка-панель из макета. В макете таких прямоугольников десятки, и
/// отличаются они только оттенком фона, поэтому вариант живёт флагом, а не
/// вторым виджетом.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.soft = false,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsets padding;

  /// Приглушённый вариант — плитки статистики.
  final bool soft;

  /// Выделенное состояние: подсветка фона и акцентная рамка.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: selected
            ? C.selected
            : soft
            ? C.panelSoft
            : C.panel,
        border: Border.all(
          color: selected
              ? C.accent.withValues(alpha: 0.4)
              : soft
              ? C.panelSoftBorder
              : C.panelBorder,
        ),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: child,
    );
  }
}

/// Бейдж протокола — VLESS, HY2, TUIC, WG. Всегда моноширинный и заглавный:
/// это код, а не слово.
class ProtocolBadge extends StatelessWidget {
  const ProtocolBadge({super.key, required this.protocol, this.filled = false});

  final String protocol;

  /// Залитый вариант для выбранного протокола.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? C.accent : Colors.transparent,
        border: Border.all(color: filled ? C.accent : const Color(0xFF2B3742)),
        borderRadius: BorderRadius.circular(Radii.chip),
      ),
      child: Text(
        protocol,
        style: monoStyle(
          size: 9.5,
          caps: true,
          weight: FontWeight.w700,
          color: filled ? C.onAccent : const Color(0xFFB5C1CB),
        ),
      ),
    );
  }
}
