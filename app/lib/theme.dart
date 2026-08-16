import 'package:flutter/material.dart';

/// Токены из макета, направление 3a «Cyan on slate».
///
/// Значения лежат константами, а не в ThemeExtension: их читают и виджеты,
/// и разметка, а лишний слой доступа к четырём десяткам цветов ничего не
/// упрощает.
abstract final class C {
  static const bg = Color(0xFF0B0F14);

  /// Панели и карточки. soft — вариант для плиток статистики.
  static const panel = Color(0xFF111820);
  static const panelBorder = Color(0xFF202B36);
  static const panelSoft = Color(0xFF101720);
  static const panelSoftBorder = Color(0xFF1C2731);

  /// Хром: боковая панель на десктопе, таб-бар на мобильном.
  static const chrome = Color(0xFF0D131A);
  static const divider = Color(0xFF18222C);
  static const hover = Color(0xFF16202A);
  static const selected = Color(0xFF14202A);

  static const text = Color(0xFFE6EDF3);
  static const textDim = Color(0xFF9BA8B3);
  static const textMuted = Color(0xFF6F7D88);
  static const textFaint = Color(0xFF5D6B77);

  static const accent = Color(0xFF2DD4BF);
  static const onAccent = Color(0xFF04120F);

  /// Сигнальные: «быстро/работает» и «плохо/оборвалось».
  static const ok = Color(0xFF4ADE80);
  static const bad = Color(0xFFF87171);
  static const idle = Color(0xFF4B5966);
}

abstract final class Radii {
  static const card = 14.0;
  static const control = 12.0;
  static const chip = 5.0;
}

const sans = 'IBM Plex Sans';
const mono = 'JetBrains Mono';

/// Моноширинный стиль для всего, что является данными, а не текстом:
/// цифры, адреса, коды протоколов, служебные подписи. Разрядка и верхний
/// регистр в макете — часть этого стиля, поэтому [caps] здесь же.
TextStyle monoStyle({
  double size = 11,
  Color color = C.textDim,
  FontWeight weight = FontWeight.w400,
  bool caps = false,
}) {
  return TextStyle(
    fontFamily: mono,
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: caps ? size * 0.11 : 0,
    height: 1.2,
  );
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: C.accent,
    onPrimary: C.onAccent,
    secondary: C.accent,
    onSecondary: C.onAccent,
    surface: C.panel,
    onSurface: C.text,
    error: C.bad,
    onError: C.onAccent,
    outline: C.panelBorder,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    fontFamily: sans,
    dividerColor: C.divider,
    dividerTheme: const DividerThemeData(color: C.divider, thickness: 1),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        color: C.text,
      ),
      titleMedium: TextStyle(
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
        color: C.text,
      ),
      bodyMedium: TextStyle(fontSize: 13, color: C.text),
      bodySmall: TextStyle(fontSize: 12, color: C.textMuted),
    ),
  );
}
