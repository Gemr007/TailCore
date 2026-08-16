import 'package:flutter_test/flutter_test.dart';
import 'package:tailcore/format.dart';

void main() {
  group('formatSpeed', () {
    test('переходит через единицы и держит один знак', () {
      expect(formatSpeed(0), '0 B/s');
      expect(formatSpeed(512), '512 B/s');
      expect(formatSpeed(1024), '1.0 KB/s');
      expect(formatSpeed(1024 * 1024 * 84.6), '84.6 MB/s');
    });

    test('без данных показывает прочерк, а не ноль', () {
      // Ноль означает «тишина в туннеле», прочерк — «мерить нечего».
      // Путать их нельзя.
      expect(formatSpeed(null), '—');
      expect(formatSpeed(-1), '—');
    });
  });

  group('formatUptime', () {
    test('часы не отбрасываются даже нулевые', () {
      expect(formatUptime(const Duration(seconds: 7)), '00:00:07');
      expect(
        formatUptime(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '01:02:03',
      );
      expect(formatUptime(const Duration(hours: 30)), '30:00:00');
    });

    test('без соединения — прочерк', () {
      expect(formatUptime(null), '—');
    });
  });
}
