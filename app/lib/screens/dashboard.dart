import 'dart:async';

import 'package:flutter/material.dart';

import '../core/prefs.dart';
import '../core/server.dart';
import '../core/servers_store.dart';
import '../core/singbox_config.dart';
import '../core/tunnel.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.store, required this.prefs});

  final ServersStore store;
  final Prefs prefs;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _pollInterval = Duration(seconds: 1);

  TunnelStatus? _status;

  /// Ядро недоступно как таковое: нет библиотеки, нет канала.
  String? _bridgeError;

  /// Причина отказа последнего действия пользователя. Хранится отдельно от
  /// [_bridgeError], потому что опрос статуса не имеет права её стирать:
  /// иначе сообщение о неудачном подключении исчезало бы в том же кадре,
  /// в котором появилось.
  String? _actionError;

  Timer? _poll;
  bool _busy = false;

  /// Предыдущий замер счётчиков — из разницы с ним и получается скорость.
  TunnelStatus? _previous;
  DateTime? _previousAt;
  double? _upSpeed;
  double? _downSpeed;

  Server? get _server => widget.store.active;

  @override
  void initState() {
    super.initState();
    _refresh();
    // ponytail: опрос по таймеру вместо подписки на события ядра —
    // событийной шины у ядра пока нет, а раз в секунду это ровно тот темп,
    // с которым и так обновляются цифры скорости.
    _poll = Timer.periodic(_pollInterval, (_) => _refresh());
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
    if (!mounted) return;
    _updateSpeed(status);
    _apply(status, error);
  }

  /// Считает скорость по разнице счётчиков между двумя опросами.
  /// Обнуляется на любом разрыве сессии: после перезапуска ядра счётчики
  /// начинаются с нуля, и разница с прошлым замером стала бы отрицательной.
  void _updateSpeed(TunnelStatus? status) {
    final now = DateTime.now();
    final before = _previous;
    final beforeAt = _previousAt;

    if (status == null || status.state != TunnelState.running) {
      _previous = null;
      _previousAt = null;
      _upSpeed = null;
      _downSpeed = null;
      return;
    }

    if (before != null &&
        beforeAt != null &&
        before.since == status.since &&
        status.uplink >= before.uplink &&
        status.downlink >= before.downlink) {
      final seconds = now.difference(beforeAt).inMicroseconds / 1e6;
      if (seconds > 0) {
        _upSpeed = (status.uplink - before.uplink) / seconds;
        _downSpeed = (status.downlink - before.downlink) / seconds;
      }
    } else {
      _upSpeed = null;
      _downSpeed = null;
    }

    _previous = status;
    _previousAt = now;
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final running = _status?.state == TunnelState.running;
    final server = _server;
    if (!running && server == null) {
      setState(() => _actionError = 'Сначала добавьте узел на экране серверов');
      return;
    }
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      if (running) {
        await TunnelCore.instance.stop();
      } else {
        final bypassGames = widget.prefs.bypassGames;
        await TunnelCore.instance.start(
          buildRunConfig(
            server!,
            bypassGames: bypassGames,
            // Путь к кэшу спрашиваем только когда он нужен: без rule-set'ов
            // кэшировать нечего, а лишний поход в плагин — лишний отказ.
            cachePath: bypassGames ? await singboxCachePath() : null,
          ),
        );
      }
    } on TunnelException catch (e) {
      if (mounted) setState(() => _actionError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh();
  }

  /// Перерисовывает экран только когда что-то изменилось: статус
  /// опрашивается раз в секунду и в покое возвращает одно и то же.
  ///
  /// Пока туннель поднят, перерисовываем всегда: время в сети считается по
  /// часам, а не по счётчикам, и в тихом туннеле иначе замирало бы.
  void _apply(TunnelStatus? status, String? bridgeError) {
    final ticking = status?.state == TunnelState.running;
    if (!ticking && status == _status && bridgeError == _bridgeError) return;
    setState(() {
      _status = status;
      _bridgeError = bridgeError;
    });
  }

  /// Что показать пользователю: недоступное ядро важнее отказа действия,
  /// а отказ действия — важнее того, что ядро помнит с прошлого раза.
  String? get _errorLine => _bridgeError ?? _actionError ?? _status?.error;

  TunnelState get _state => _status?.state ?? TunnelState.stopped;
  bool get _connected => _state == TunnelState.running;

  Duration? get _uptime {
    final since = _status?.since;
    return since == null ? null : DateTime.now().difference(since);
  }

  String get _statusLine {
    if (_status == null) return 'ЯДРО НЕДОСТУПНО';
    return switch (_state) {
      TunnelState.running => 'ТУННЕЛЬ ПОДНЯТ · ${_server?.badge ?? 'DIRECT'}',
      TunnelState.starting => 'ПОДКЛЮЧЕНИЕ...',
      TunnelState.stopped => 'БЕЗ ЗАЩИТЫ',
    };
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    // Слушаем хранилище: активный узел меняется на соседнем экране.
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) => wide ? _buildDesktop() : _buildMobile(),
    );
  }

  // --- Мобильная раскладка: одна крупная кнопка и ничего лишнего ---

  Widget _buildMobile() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
      child: Column(
        children: [
          const _BrandRow(),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ConnectButton(
                  connected: _connected,
                  busy: _busy,
                  uptime: _uptime,
                  onTap: _toggle,
                ),
                const SizedBox(height: 26),
                _StatusLine(text: _statusLine, connected: _connected),
              ],
            ),
          ),
          if (_server != null) _ServerCard(server: _server!),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SpeedTile(
                  label: '↓ ЗАГРУЗКА',
                  speed: _downSpeed,
                  accent: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SpeedTile(label: '↑ ОТДАЧА', speed: _upSpeed),
              ),
            ],
          ),
          if (_errorLine != null) _ErrorLine(text: _errorLine!),
        ],
      ),
    );
  }

  // --- Десктопная раскладка: всё состояние одной полосой ---

  Widget _buildDesktop() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: C.divider)),
          ),
          // Две группы, разведённые по краям, как в макете: слева «что за
          // соединение», справа «сколько через него идёт».
          //
          // Правая группа не гибкая: в Row негибкие дети получают свою
          // естественную ширину первыми, а левая забирает остаток и при
          // нехватке переносит поля. Раздели пополам — и левая начала бы
          // переноситься там, где места ещё вдоволь.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 28,
                  runSpacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ConnectPill(
                      connected: _connected,
                      busy: _busy,
                      onTap: _toggle,
                    ),
                    _Field(label: 'АКТИВНЫЙ УЗЕЛ', value: _server?.name ?? '—'),
                    _Field(
                      label: 'ПРОТОКОЛ',
                      value: _server?.badge ?? '—',
                      monoValue: true,
                    ),
                    _Field(
                      label: 'ВРЕМЯ В СЕТИ',
                      value: formatUptime(_connected ? _uptime : null),
                      monoValue: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 28),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 26,
                children: [
                  _Field(
                    label: '↓ ЗАГРУЗКА',
                    value: formatSpeed(_downSpeed),
                    monoValue: true,
                    accent: true,
                    alignEnd: true,
                  ),
                  _Field(
                    label: '↑ ОТДАЧА',
                    value: formatSpeed(_upSpeed),
                    monoValue: true,
                    alignEnd: true,
                  ),
                  _Field(
                    label: 'АДРЕС ВЫХОДА',
                    value: _connected ? (_server?.address ?? '—') : '—',
                    monoValue: true,
                    alignEnd: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_errorLine != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 16, 26, 0),
            child: _ErrorLine(text: _errorLine!),
          ),
        // Таблица серверов и лог-полоса из макета приезжают отдельными
        // шагами: серверы — шаг 7, лог — шаг 19.
        const Spacer(),
      ],
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: C.accent,
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
        const SizedBox(width: 9),
        const Text(
          'TailCore',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.16,
            color: C.text,
          ),
        ),
      ],
    );
  }
}

/// Круглая кнопка соединения — смысловой центр мобильного экрана.
class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.connected,
    required this.busy,
    required this.uptime,
    required this.onTap,
  });

  final bool connected;
  final bool busy;
  final Duration? uptime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 232,
      height: 232,
      child: Center(
        // InkWell, а не GestureDetector: он фокусируется с клавиатуры и
        // срабатывает по Enter. Главная кнопка приложения, доступная только
        // мышью, — это дефект, а не упрощение.
        child: InkWell(
          onTap: busy ? null : onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            width: 196,
            height: 196,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? C.accent : C.panelSoft,
              border: Border.all(color: connected ? C.accent : C.panelBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  connected ? 'Отключить' : 'Подключить',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.19,
                    color: connected ? C.onAccent : C.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  connected ? formatUptime(uptime) : 'НАЖМИТЕ ДЛЯ СТАРТА',
                  style: monoStyle(
                    size: 11,
                    caps: true,
                    color: (connected ? C.onAccent : C.text).withValues(
                      alpha: 0.72,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Плоская кнопка-пилюля для десктопа: на плотном экране круг на пол-окна
/// был бы неуместен.
class _ConnectPill extends StatelessWidget {
  const _ConnectPill({
    required this.connected,
    required this.busy,
    required this.onTap,
  });

  final bool connected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = connected ? C.accent : C.textDim;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(9),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          color: connected ? C.accent.withValues(alpha: 0.10) : C.panelSoft,
          border: Border.all(
            color: connected ? C.accent.withValues(alpha: 0.4) : C.panelBorder,
          ),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 11),
            Text(
              connected ? 'Подключено' : 'Отключено',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text, required this.connected});

  final String text;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: connected ? C.ok : C.idle,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(text, style: monoStyle(size: 11.5, caps: true)),
      ],
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.server});

  final Server server;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  server.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  server.address,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(size: 11, color: C.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ProtocolBadge(protocol: server.badge),
        ],
      ),
    );
  }
}

class _SpeedTile extends StatelessWidget {
  const _SpeedTile({
    required this.label,
    required this.speed,
    this.accent = false,
  });

  final String label;
  final double? speed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Panel(
      soft: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: monoStyle(size: 9.5, caps: true, color: C.textMuted),
          ),
          const SizedBox(height: 5),
          Text(
            formatSpeed(speed),
            style: monoStyle(
              size: 17,
              weight: FontWeight.w500,
              color: accent ? C.accent : C.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Подпись-значение для плотной десктопной полосы.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.monoValue = false,
    this.accent = false,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool monoValue;
  final bool accent;

  /// Поля правой группы прижаты к краю окна, поэтому и подпись со
  /// значением выравниваются вправо.
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: monoStyle(size: 9.5, caps: true, color: C.textMuted),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: monoValue
              ? monoStyle(size: 13, color: accent ? C.accent : C.text)
              : const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: C.text,
                ),
        ),
      ],
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: monoStyle(size: 11, color: C.bad),
      ),
    );
  }
}
