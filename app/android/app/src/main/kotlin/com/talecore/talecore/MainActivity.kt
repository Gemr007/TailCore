package com.talecore.talecore

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import tunnel.Tunnel

/**
 * Мост до ядра на Android. Канал переводит вызовы Dart в статические
 * методы, которые gomobile сгенерировал поверх Go-пакета `tunnel`.
 *
 * Отдельного Kotlin-слоя с бизнес-логикой здесь нет и не должно быть:
 * состояние туннеля живёт в Go, иначе оно разъедется между платформами.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        // ponytail: вызовы синхронные, на главном потоке —
                        // старт sing-box занимает миллисекунды. Уносить в
                        // executor, когда появится VpnService (шаг 11).
                        "start" -> {
                            Tunnel.start(call.arguments as String)
                            result.success(null)
                        }
                        "stop" -> {
                            Tunnel.stop()
                            result.success(null)
                        }
                        "status" -> result.success(Tunnel.status())
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("tunnel", e.message ?: e.toString(), null)
                }
            }
    }

    private companion object {
        const val CHANNEL = "talecore/tunnel"
    }
}
