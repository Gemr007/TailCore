import 'dart:async';

import 'package:flutter/material.dart';

import '../core/tunnel.dart';

/// Временный конфиг, пока нет экрана серверов: без него нечего передать в
/// ядро, а проверить мост надо уже сейчас.
/// TODO(шаг 7): брать конфиг выбранного сервера.
const _placeholderConfig = '''
{
  "inbounds": [
    {"type": "mixed", "tag": "local", "listen": "127.0.0.1", "listen_port": 2080}
  ],
  "outbounds": [{"type": "direct", "tag": "direct"}]
}
''';

/// Первая версия экрана соединения: показывает состояние ядра и умеет его
/// включать и выключать. Кнопка из макета, текущий сервер и скорость —
/// шаг 6, здесь проверяется только сам мост до Go.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  TunnelStatus? _status;
  String? _bridgeError;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    // ponytail: опрос раз в секунду вместо подписки на события ядра —
    // нативной шины событий у нас пока нет. Появится к шагу 6, когда
    // понадобится скорость в реальном времени.
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    TunnelStatus? status;
    String? error;
    try {
      status = await TunnelCore.instance.status();
    } catch (e) {
      // Сюда попадает и отвалившийся мост (нет библиотеки, нет канала),
      // и любая другая беда доступа к ядру.
      error = '$e';
    }
    _apply(status, error);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _apply(_status, null);
    } on TunnelException catch (e) {
      _apply(_status, e.message);
    }
    await _refresh();
  }

  /// Перерисовывает экран только когда что-то реально изменилось: статус
  /// опрашивается раз в секунду и почти всегда возвращает то же самое.
  void _apply(TunnelStatus? status, String? error) {
    if (!mounted || (status == _status && error == _bridgeError)) return;
    setState(() {
      _status = status;
      _bridgeError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status;
    final running = status?.state == TunnelState.running;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 16,
        children: [
          Text(
            switch (status?.state) {
              TunnelState.running => 'Подключено',
              TunnelState.starting => 'Подключение...',
              TunnelState.stopped => 'Отключено',
              null => 'Ядро недоступно',
            },
            style: theme.textTheme.headlineMedium,
          ),
          if (status?.since != null)
            Text(
              'с ${status!.since!.toLocal()}',
              style: theme.textTheme.bodySmall,
            ),
          FilledButton(
            onPressed: () => _run(
              running
                  ? TunnelCore.instance.stop
                  : () => TunnelCore.instance.start(_placeholderConfig),
            ),
            child: Text(running ? 'Отключить' : 'Подключить'),
          ),
          // Ошибку ядра и ошибку самого моста показываем одинаково: для
          // пользователя это одна беда, различать их будет экран ошибок.
          if (_bridgeError != null || status?.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _bridgeError ?? status!.error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
