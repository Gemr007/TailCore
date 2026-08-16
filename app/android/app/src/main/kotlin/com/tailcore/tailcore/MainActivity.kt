package com.tailcore.tailcore

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
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
                        // Замер держит поток занятым секундами — на
                        // главном он подвесил бы интерфейс.
                        "test" -> {
                            val config = call.argument<String>("config") ?: ""
                            val timeout = call.argument<Int>("timeout") ?: 10
                            runOffMainThread(result) { Tunnel.test(config, timeout.toLong()) }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("tunnel", e.message ?: e.toString(), null)
                }
            }
    }

    /** Выполняет работу в фоне и отвечает каналу с главного потока: MethodChannel
     *  требует именно этого. */
    private fun runOffMainThread(result: MethodChannel.Result, work: () -> String) {
        worker.execute {
            val reply = try {
                Result.success(work())
            } catch (e: Exception) {
                Result.failure(e)
            }
            main.post {
                reply.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error("tunnel", it.message ?: it.toString(), null) },
                )
            }
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onDestroy() {
        worker.shutdown()
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "tailcore/tunnel"
    }
}
