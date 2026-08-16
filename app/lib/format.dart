/// Форматирование чисел, которые видит пользователь.
library;

const _dash = '—';

/// Скорость в вид «84.6 MB/s». null — когда скорости ещё нет: туннель
/// не поднят или прошёл всего один опрос и разницу не с чем считать.
String formatSpeed(double? bytesPerSecond) {
  if (bytesPerSecond == null || bytesPerSecond < 0) return _dash;
  const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
  var value = bytesPerSecond;
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // Байты дробными не бывают, всё остальное — с одним знаком, как в макете.
  final text = unit == 0 ? value.round().toString() : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// Длительность соединения в вид «01:02:03». Часы не отбрасываются даже
/// нулевые: ширина строки не должна прыгать раз в час.
String formatUptime(Duration? d) {
  if (d == null || d.isNegative) return _dash;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}
