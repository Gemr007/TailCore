@TestOn('windows || linux || mac-os')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:talecore/core/tunnel.dart';

/// Гоняет десктопный мост против настоящей cgo-библиотеки — того же кода,
/// что поедет в приложение. Разбор JSON проверяется отдельно и без ядра;
/// здесь предмет проверки именно граница FFI: передача конфига внутрь,
/// проброс ошибки наружу и владение памятью.
///
/// Библиотеку надо собрать заранее (scripts/build-desktop.ps1|sh) и дать
/// её найти — этим занимается scripts/test-app.ps1.
void main() {
  test('старт, статус и остановка через FFI', () async {
    final core = TunnelCore.instance;

    expect((await core.status()).state, TunnelState.stopped);

    // Конфиг с занятым портом не отличить от сломанного, поэтому берём
    // порт, свободный прямо сейчас.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    await core.start('''
      {
        "inbounds": [
          {"type": "mixed", "listen": "127.0.0.1", "listen_port": $port}
        ],
        "outbounds": [{"type": "direct"}]
      }
    ''');

    final running = await core.status();
    expect(running.state, TunnelState.running);
    expect(running.since, isNotNull);

    await core.stop();
    expect((await core.status()).state, TunnelState.stopped);
  });

  test('ошибка ядра доезжает до Dart, а не теряется на границе', () async {
    final core = TunnelCore.instance;

    await expectLater(
      core.start('{"outbounds": [{"type": "no-such-protocol"}]}'),
      throwsA(
        isA<TunnelException>().having(
          (e) => e.message,
          'message',
          contains('no-such-protocol'),
        ),
      ),
    );

    // Неудачный старт не должен оставить ядро в подвешенном состоянии.
    final status = await core.status();
    expect(status.state, TunnelState.stopped);
    expect(status.error, contains('no-such-protocol'));
  });
}
