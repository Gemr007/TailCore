import 'package:flutter_test/flutter_test.dart';
import 'package:talecore/core/tunnel.dart';

void main() {
  test('разбирает статус работающего туннеля', () {
    final s = TunnelStatus.fromJson(
      '{"state":"running","since":"2026-08-16T12:00:00Z"}',
    );
    expect(s.state, TunnelState.running);
    expect(s.since, DateTime.utc(2026, 8, 16, 12));
    expect(s.error, isNull);
  });

  test('разбирает статус с ошибкой старта', () {
    final s = TunnelStatus.fromJson('{"state":"stopped","error":"boom"}');
    expect(s.state, TunnelState.stopped);
    expect(s.since, isNull);
    expect(s.error, 'boom');
  });

  test('незнакомое состояние не роняет приложение', () {
    // Ядро может уйти вперёд по версии и прислать состояние, которого мы
    // не знаем. Считаем такое отключённым, но не падаем.
    expect(
      TunnelStatus.fromJson('{"state":"teleporting"}').state,
      TunnelState.stopped,
    );
  });

  test('одинаковые статусы равны — на этом держится отказ от перерисовки', () {
    const a = TunnelStatus(state: TunnelState.running);
    const b = TunnelStatus(state: TunnelState.running);
    const c = TunnelStatus(state: TunnelState.stopped);
    expect(a, b);
    expect(a, isNot(c));
  });
}
