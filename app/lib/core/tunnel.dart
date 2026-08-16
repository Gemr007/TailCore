/// Мост к Go-ядру. Внутрь уходит конфиг sing-box, наружу приходит статус.
///
/// Мостов физически два, потому что нативные библиотеки собираются
/// по-разному: на десктопе это cgo-библиотека и dart:ffi, на Android —
/// .aar от gomobile и platform channel. Всё остальное приложение об этом
/// различии не знает и работает только с [TunnelCore].
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

/// Состояние туннеля. Строки совпадают с константами Go-пакета `tunnel`.
enum TunnelState {
  stopped,
  starting,
  running;

  static TunnelState parse(String? raw) {
    return TunnelState.values.firstWhere(
      (s) => s.name == raw,
      // Незнакомое состояние — не повод падать: ядро могло уйти вперёд
      // по версии, а «остановлен» это безопасный ответ по умолчанию.
      orElse: () => TunnelState.stopped,
    );
  }
}

class TunnelStatus {
  const TunnelStatus({
    required this.state,
    this.since,
    this.error,
    this.uplink = 0,
    this.downlink = 0,
  });

  final TunnelState state;

  /// Момент выхода в [TunnelState.running]. Null, если туннель не поднят.
  final DateTime? since;

  /// Причина последнего неудачного старта, если она была.
  final String? error;

  /// Байты за текущую сессию, нарастающим итогом. Скорость из них считает
  /// экран: только он знает, сколько прошло между двумя опросами.
  final int uplink;
  final int downlink;

  // Статус опрашивается раз в секунду и почти всегда возвращает то же
  // самое. Без сравнения по значению экран перерисовывался бы вхолостую.
  @override
  bool operator ==(Object other) =>
      other is TunnelStatus &&
      other.state == state &&
      other.since == since &&
      other.error == error &&
      other.uplink == uplink &&
      other.downlink == downlink;

  @override
  int get hashCode => Object.hash(state, since, error, uplink, downlink);

  factory TunnelStatus.fromJson(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final since = map['since'] as String?;
    return TunnelStatus(
      state: TunnelState.parse(map['state'] as String?),
      since: since == null ? null : DateTime.tryParse(since),
      error: map['error'] as String?,
      uplink: (map['uplink'] as num?)?.toInt() ?? 0,
      downlink: (map['downlink'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Ошибка, пришедшая из ядра. Отдельный тип нужен, чтобы UI мог отличить
/// «ядро отказалось стартовать» от сбоя самого моста.
class TunnelException implements Exception {
  const TunnelException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class TunnelCore {
  /// Реализация выбирается один раз по платформе. Для iOS, когда до него
  /// дойдёт дело, здесь появится третья ветка — остальной код не изменится.
  static final TunnelCore instance = Platform.isAndroid
      ? _ChannelCore()
      : _FfiCore();

  Future<void> start(String configJson);
  Future<void> stop();
  Future<TunnelStatus> status();

  /// Меряет задержку до узлов конфига.
  ///
  /// Узел попадает либо в delays, либо в errors: «не ответил» и «ответил
  /// за 0 мс» — разные вещи, а причина отказа нужна, чтобы «нет связи»
  /// можно было починить, а не только увидеть.
  Future<TestResult> test(String configJson, {Duration timeout});
}

typedef TestResult = ({Map<String, int> delays, Map<String, String> errors});

/// Разбирает ответ замера. Ядро отдаёт либо результат, либо объект с
/// ключом error: на границе C возвращаемое значение одно.
TestResult _decodeTest(String raw) {
  final json = jsonDecode(raw);
  if (json is! Map<String, dynamic>) {
    throw const TunnelException('core returned a malformed test result');
  }
  final failed = json['error'];
  if (failed is String) throw TunnelException(failed);

  final delays = json['delays'];
  final errors = json['errors'];
  return (
    delays: {
      if (delays is Map)
        for (final e in delays.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
    },
    errors: {
      if (errors is Map)
        for (final e in errors.entries) '${e.key}': '${e.value}',
    },
  );
}

// --- Десктоп: dart:ffi поверх cgo-библиотеки ---

typedef _StartNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _VoidToStringNative = Pointer<Utf8> Function();
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _Free = void Function(Pointer<Utf8>);
typedef _TestNative = Pointer<Utf8> Function(Pointer<Utf8>, Int32);
typedef _Test = Pointer<Utf8> Function(Pointer<Utf8>, int);

String get _libraryFileName {
  if (Platform.isWindows) return 'tailcore.dll';
  if (Platform.isMacOS) return 'libtailcore.dylib';
  return 'libtailcore.so';
}

/// Замер держит поток занятым на все свои секунды, поэтому выполняется в
/// отдельном изоляте. Функция верхнеуровневая: в изолят нельзя передать
/// замыкание над объектом, а состояние ядра всё равно живёт в процессе, а
/// не в изоляте.
String _testInIsolate((String, int) args) {
  final (config, seconds) = args;
  final lib = DynamicLibrary.open(_libraryFileName);
  final test = lib.lookupFunction<_TestNative, _Test>('TailCoreTest');
  final free = lib.lookupFunction<_FreeNative, _Free>('TailCoreFree');

  final nativeConfig = config.toNativeUtf8();
  try {
    final result = test(nativeConfig, seconds);
    if (result == nullptr) return '{}';
    final raw = result.toDartString();
    free(result);
    return raw;
  } finally {
    malloc.free(nativeConfig);
  }
}

class _FfiCore extends TunnelCore {
  _FfiCore() : _lib = DynamicLibrary.open(_libraryFileName);

  final DynamicLibrary _lib;

  late final _start = _lib.lookupFunction<_StartNative, _StartNative>(
    'TailCoreStart',
  );
  late final _stop = _lib
      .lookupFunction<_VoidToStringNative, _VoidToStringNative>('TailCoreStop');
  late final _status = _lib
      .lookupFunction<_VoidToStringNative, _VoidToStringNative>(
        'TailCoreStatus',
      );
  late final _Free _free = _lib.lookupFunction<_FreeNative, _Free>(
    'TailCoreFree',
  );

  /// Забирает строку у ядра и сразу отдаёт память обратно: всё, что пришло
  /// через границу C, освобождает вызывающая сторона.
  String? _take(Pointer<Utf8> p) {
    if (p == nullptr) return null;
    final value = p.toDartString();
    _free(p);
    return value;
  }

  void _check(Pointer<Utf8> p) {
    final error = _take(p);
    if (error != null) throw TunnelException(error);
  }

  @override
  Future<void> start(String configJson) async {
    // ponytail: вызов синхронный — sing-box поднимает слушатели за миллисекунды
    // и сервер на старте не набирает. Если появится долгий старт (TUN,
    // проверка подписки), уносить в Isolate.run.
    final config = configJson.toNativeUtf8();
    try {
      _check(_start(config));
    } finally {
      malloc.free(config);
    }
  }

  @override
  Future<void> stop() async => _check(_stop());

  @override
  Future<TunnelStatus> status() async {
    final raw = _take(_status());
    if (raw == null) throw const TunnelException('core returned no status');
    return TunnelStatus.fromJson(raw);
  }

  @override
  Future<TestResult> test(
    String configJson, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final raw = await Isolate.run(
      () => _testInIsolate((configJson, timeout.inSeconds)),
    );
    return _decodeTest(raw);
  }
}

// --- Android: platform channel поверх .aar от gomobile ---

class _ChannelCore extends TunnelCore {
  static const _channel = MethodChannel('tailcore/tunnel');

  @override
  Future<void> start(String configJson) => _invoke('start', configJson);

  @override
  Future<void> stop() => _invoke('stop');

  @override
  Future<TunnelStatus> status() async {
    final raw = await _channel.invokeMethod<String>('status');
    if (raw == null) throw const TunnelException('core returned no status');
    return TunnelStatus.fromJson(raw);
  }

  @override
  Future<TestResult> test(
    String configJson, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final raw = await _channel.invokeMethod<String>('test', {
        'config': configJson,
        'timeout': timeout.inSeconds,
      });
      return _decodeTest(raw ?? '{}');
    } on PlatformException catch (e) {
      throw TunnelException(e.message ?? e.code);
    }
  }

  Future<void> _invoke(String method, [Object? arg]) async {
    try {
      await _channel.invokeMethod<void>(method, arg);
    } on PlatformException catch (e) {
      throw TunnelException(e.message ?? e.code);
    }
  }
}
