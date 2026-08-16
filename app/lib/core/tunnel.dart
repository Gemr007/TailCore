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
  const TunnelStatus({required this.state, this.since, this.error});

  final TunnelState state;

  /// Момент выхода в [TunnelState.running]. Null, если туннель не поднят.
  final DateTime? since;

  /// Причина последнего неудачного старта, если она была.
  final String? error;

  // Статус опрашивается раз в секунду и почти всегда возвращает то же
  // самое. Без сравнения по значению экран перерисовывался бы вхолостую.
  @override
  bool operator ==(Object other) =>
      other is TunnelStatus &&
      other.state == state &&
      other.since == since &&
      other.error == error;

  @override
  int get hashCode => Object.hash(state, since, error);

  factory TunnelStatus.fromJson(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final since = map['since'] as String?;
    return TunnelStatus(
      state: TunnelState.parse(map['state'] as String?),
      since: since == null ? null : DateTime.tryParse(since),
      error: map['error'] as String?,
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
}

// --- Десктоп: dart:ffi поверх cgo-библиотеки ---

typedef _StartNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _VoidToStringNative = Pointer<Utf8> Function();
typedef _FreeNative = Void Function(Pointer<Utf8>);
typedef _Free = void Function(Pointer<Utf8>);

class _FfiCore extends TunnelCore {
  _FfiCore() : _lib = DynamicLibrary.open(_libraryFileName);

  final DynamicLibrary _lib;

  static String get _libraryFileName {
    if (Platform.isWindows) return 'talecore.dll';
    if (Platform.isMacOS) return 'libtalecore.dylib';
    return 'libtalecore.so';
  }

  late final _start = _lib.lookupFunction<_StartNative, _StartNative>(
    'TaleCoreStart',
  );
  late final _stop = _lib
      .lookupFunction<_VoidToStringNative, _VoidToStringNative>('TaleCoreStop');
  late final _status = _lib
      .lookupFunction<_VoidToStringNative, _VoidToStringNative>(
        'TaleCoreStatus',
      );
  late final _Free _free = _lib.lookupFunction<_FreeNative, _Free>(
    'TaleCoreFree',
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
}

// --- Android: platform channel поверх .aar от gomobile ---

class _ChannelCore extends TunnelCore {
  static const _channel = MethodChannel('talecore/tunnel');

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

  Future<void> _invoke(String method, [Object? arg]) async {
    try {
      await _channel.invokeMethod<void>(method, arg);
    } on PlatformException catch (e) {
      throw TunnelException(e.message ?? e.code);
    }
  }
}
