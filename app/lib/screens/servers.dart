import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/prefs.dart';
import '../core/server.dart';
import '../core/servers_store.dart';
import '../theme.dart';
import '../widgets/panel.dart';

/// Экран серверов: сверху Auto, под ним фильтр по протоколу, ниже плоский
/// список, отсортированный по задержке.
///
/// Группировки по странам нет намеренно: пользователь выбирает узел по
/// скорости и протоколу, а не по географии.
///
/// Список разворачивается в таблицу на широком окне и сворачивается в
/// карточки на узком — порог тот же, что у навигации.
class ServersScreen extends StatefulWidget {
  const ServersScreen({super.key, required this.store, required this.prefs});

  final ServersStore store;

  /// Нужны ради замера: он ходит по сети и обязан спрашивать имена у того
  /// же резолвера, что и туннель, — иначе «недоступен» на этом экране и
  /// работающее соединение на соседнем.
  final Prefs prefs;

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  String _filter = ServersStore.filterAll;

  ServersStore get _store => widget.store;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final pad = wide ? 26.0 : 22.0;

    return ListenableBuilder(
      listenable: _store,
      builder: (context, _) {
        // Фильтр мог указывать на протокол, узлы которого удалили.
        final filters = _store.protocolFilters;
        final filter = filters.contains(_filter)
            ? _filter
            : ServersStore.filterAll;
        final rows = _store.sortedByLatency(filter);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              store: _store,
              onImport: _showImport,
              onMeasure: () =>
                  _store.measureAll(dnsServer: widget.prefs.dnsServer),
              pad: pad,
            ),
            if (_store.servers.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
                child: _AutoCard(store: _store),
              ),
              if (filters.length > 2)
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
                  child: _FilterChips(
                    filters: filters,
                    current: filter,
                    onPick: (f) => setState(() => _filter = f),
                  ),
                ),
            ],
            Expanded(
              child: _store.servers.isEmpty
                  ? _EmptyState(onImport: _showImport)
                  : rows.isEmpty
                  ? const _NoMatch()
                  : wide
                  ? _ServerTable(rows: rows, store: _store)
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, 20),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, i) => _ServerCard(
                        server: rows[i],
                        store: _store,
                        onPick: () => _store.select(rows[i]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showImport() async {
    final text = await showDialog<String>(
      context: context,
      builder: (context) => const _ImportDialog(),
    );
    if (text == null || text.trim().isEmpty) return;

    final ({int added, List<({String name, String reason})> skipped}) result;
    try {
      result = await _store.import(text);
    } catch (e) {
      if (!mounted) return;
      _say('Импорт не удался: $e');
      return;
    }
    if (!mounted) return;

    final lines = [
      if (result.added > 0)
        'Добавлено узлов: ${result.added}'
      else
        'Ничего не добавлено: узлы не распознаны или уже есть в списке',
      // Отвергнутые узлы называем поимённо: иначе человек будет искать в
      // списке узел, которого там нет, и не поймёт почему.
      for (final s in result.skipped) 'Пропущен ${s.name}: ${s.reason}',
    ];
    _say(lines.join('\n'));
  }

  void _say(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 6)),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.store,
    required this.onImport,
    required this.onMeasure,
    required this.pad,
  });

  final ServersStore store;
  final VoidCallback onImport;
  final VoidCallback onMeasure;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final count = store.servers.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 12),
      child: Row(
        children: [
          Text('Серверы', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(width: 14),
          if (count > 0)
            Flexible(
              child: Text(
                '$count ${_nodes(count)} · ПО ЗАДЕРЖКЕ',
                overflow: TextOverflow.ellipsis,
                style: monoStyle(size: 10, caps: true, color: C.textMuted),
              ),
            ),
          const Spacer(),
          if (count > 0)
            _TextAction(
              label: store.testing ? 'ЗАМЕР...' : 'ЗАМЕРИТЬ',
              onTap: store.testing ? null : onMeasure,
            ),
          const SizedBox(width: 7),
          _TextAction(label: 'ИМПОРТ', onTap: onImport),
        ],
      ),
    );
  }

  /// Русский счёт узлов: 1 узел, 2 узла, 5 узлов.
  static String _nodes(int n) {
    final tail = n % 100;
    if (tail >= 11 && tail <= 14) return 'узлов';
    return switch (n % 10) {
      1 => 'узел',
      2 || 3 || 4 => 'узла',
      _ => 'узлов',
    };
  }
}

/// Плоская кнопка-надпись из макета: рамка, моноширинный верхний регистр.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.chip),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: C.panelBorder),
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Text(
          label,
          style: monoStyle(
            size: 10,
            caps: true,
            color: onTap == null ? C.textFaint : C.textDim,
          ),
        ),
      ),
    );
  }
}

/// Auto — движок сам держит самый быстрый узел.
class _AutoCard extends StatelessWidget {
  const _AutoCard({required this.store});

  final ServersStore store;

  @override
  Widget build(BuildContext context) {
    final on = store.auto;
    final fastest = store.fastest;
    final latency = fastest == null ? null : store.latencyOf(fastest);

    return InkWell(
      onTap: store.enableAuto,
      borderRadius: BorderRadius.circular(Radii.card),
      child: Panel(
        selected: on,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? C.accent : C.hover,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.auto_mode,
                size: 18,
                color: on ? C.onAccent : C.textDim,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Auto',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: C.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    on && fastest != null
                        ? 'держит ${fastest.name}'
                        : 'берёт узел с наименьшей задержкой',
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(size: 10.5, color: C.textDim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Latency(ms: on ? latency : null, idle: !on),
          ],
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.filters,
    required this.current,
    required this.onPick,
  });

  final List<String> filters;
  final String current;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final f in filters)
          InkWell(
            // Код протокола встречается и на чипе, и на бейдже узла —
            // ключ отличает именно чип.
            key: ValueKey('protocol-filter-$f'),
            onTap: () => onPick(f),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: f == current ? C.accent : Colors.transparent,
                border: Border.all(
                  color: f == current ? C.accent : const Color(0xFF2B3742),
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                f,
                style: monoStyle(
                  size: 10,
                  caps: true,
                  color: f == current ? C.onAccent : C.textDim,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Колонки таблицы. Ширины лежат рядом, потому что их читают и шапка, и
/// строки: разъехавшись, они превратят таблицу в кашу.
abstract final class _Col {
  static const dot = 26.0;
  static const protocol = 110.0;

  /// Ровно ширина [_Latency] — колонка выровнена по правому краю значения.
  static const ping = 66.0;
}

/// Десктопная таблица из макета: строки в 44 px, разделители, выбранный
/// узел помечен акцентной полосой слева.
///
/// Колонок из макета здесь меньше, чем нарисовано: REGION и LOAD рисовать
/// нечем — ни подписка, ни sing-box не сообщают ни страну, ни загрузку
/// узла, а выдуманное число в таблице выглядит ровно как измеренное.
class _ServerTable extends StatelessWidget {
  const _ServerTable({required this.rows, required this.store});

  final List<Server> rows;
  final ServersStore store;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(26, 0, 26, 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: C.divider)),
          ),
          child: _row(
            node: Text(
              'УЗЕЛ',
              style: monoStyle(size: 9.5, caps: true, color: C.textFaint),
            ),
            protocol: Text(
              'ПРОТОКОЛ',
              style: monoStyle(size: 9.5, caps: true, color: C.textFaint),
            ),
            ping: Text(
              'ЗАДЕРЖКА',
              textAlign: TextAlign.right,
              style: monoStyle(size: 9.5, caps: true, color: C.textFaint),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: rows.length,
            itemBuilder: (context, i) =>
                _ServerLine(server: rows[i], store: store),
          ),
        ),
      ],
    );
  }

  /// Одна раскладка на шапку и на строки.
  static Widget _row({
    Widget? dot,
    required Widget node,
    required Widget protocol,
    required Widget ping,
  }) {
    return Row(
      children: [
        SizedBox(width: _Col.dot, child: dot),
        Expanded(child: node),
        SizedBox(width: _Col.protocol, child: protocol),
        SizedBox(width: _Col.ping, child: ping),
      ],
    );
  }
}

class _ServerLine extends StatelessWidget {
  const _ServerLine({required this.server, required this.store});

  final Server server;
  final ServersStore store;

  @override
  Widget build(BuildContext context) {
    final selected = store.isSelected(server);
    final ms = store.latencyOf(server);
    final reason = store.failureOf(server);

    return InkWell(
      onTap: () => store.select(server),
      onLongPress: () => _confirmRemove(context, server, store),
      // На десктопе узел удаляют правой кнопкой; долгое нажатие мышью
      // никто искать не станет.
      onSecondaryTap: () => _confirmRemove(context, server, store),
      hoverColor: C.hover,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: BoxDecoration(
          color: selected ? C.selected : Colors.transparent,
          border: Border(
            bottom: const BorderSide(color: C.divider),
            left: BorderSide(
              color: selected ? C.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: _ServerTable._row(
          dot: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: ms != null
                    ? _Latency._color(ms)
                    : reason != null
                    ? C.bad
                    : C.idle,
                shape: BoxShape.circle,
              ),
            ),
          ),
          node: Row(
            children: [
              Flexible(
                child: Text(
                  server.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: C.text,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  server.address,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(size: 10.5, color: C.textFaint),
                ),
              ),
            ],
          ),
          protocol: Align(
            alignment: Alignment.centerLeft,
            child: ProtocolBadge(protocol: server.badge),
          ),
          ping: _Latency(
            ms: ms,
            reason: reason,
            idle: false,
            unmeasurable: server.viaXray,
          ),
        ),
      ),
    );
  }
}

/// Мобильная карточка узла: то же самое, но в столбик и с отступами под
/// палец.
class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.store,
    required this.onPick,
  });

  final Server server;
  final ServersStore store;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      onLongPress: () => _confirmRemove(context, server, store),
      borderRadius: BorderRadius.circular(Radii.control),
      child: Panel(
        selected: store.isSelected(server),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: C.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    server.address,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(size: 10, color: C.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ProtocolBadge(protocol: server.badge),
            const SizedBox(width: 10),
            _Latency(
              ms: store.latencyOf(server),
              reason: store.failureOf(server),
              idle: false,
              unmeasurable: server.viaXray,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmRemove(
  BuildContext context,
  Server server,
  ServersStore store,
) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: C.panel,
      title: const Text('Удалить узел?'),
      content: Text(server.name),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Удалить'),
        ),
      ],
    ),
  );
  if (yes ?? false) store.remove(server);
}

/// Задержка узла. Состояния путать нельзя: не мерили, не меряется вовсе,
/// мерили и не ответил, ответил за столько-то.
class _Latency extends StatelessWidget {
  const _Latency({
    required this.ms,
    required this.idle,
    this.reason,
    this.unmeasurable = false,
  });

  final int? ms;
  final bool idle;

  /// Замерить нельзя в принципе, а не «не ответил»: узлы на Xray поднимает
  /// второй движок, а замер умеет только sing-box.
  final bool unmeasurable;

  /// Причина отказа с последнего замера, если он был неудачным.
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (ms) {
      final int v => ('$v ms', _color(v)),
      _ when unmeasurable => ('xray', C.textMuted),
      _ when reason != null => ('нет связи', C.bad),
      _ when idle => ('нажмите', C.textMuted),
      _ => ('—', C.textFaint),
    };
    final label = SizedBox(
      width: 66,
      child: Text(
        text,
        textAlign: TextAlign.right,
        style: monoStyle(size: 11.5, color: color),
      ),
    );
    // Причина прячется в подсказку, а не занимает строку: в списке важна
    // задержка, но починить «нет связи» без причины невозможно.
    final hint = unmeasurable
        ? 'Узел работает через Xray — задержка пока не меряется'
        : reason;
    return hint == null ? label : Tooltip(message: hint, child: label);
  }

  /// Пороги из макета: до 25 мс мгновенно, до 60 приемлемо, дальше плохо.
  static Color _color(int ms) {
    if (ms < 25) return C.ok;
    if (ms < 60) return C.accent;
    return C.bad;
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'НЕТ УЗЛОВ С ЭТИМ ПРОТОКОЛОМ',
        style: monoStyle(size: 11, caps: true, color: C.textFaint),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'СПИСОК ПУСТ',
              style: monoStyle(size: 11, caps: true, color: C.textFaint),
            ),
            const SizedBox(height: 12),
            const Text(
              'Вставьте ссылку на подписку, share-ссылку узла\nили конфиг sing-box.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: C.textMuted, height: 1.5),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onImport, child: const Text('Импорт')),
          ],
        ),
      ),
    );
  }
}

/// Одно поле для всех форматов: пользователь копирует то, что ему
/// прислали, и не обязан знать, JSON это, ссылка или base64.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: C.panel,
      title: const Text('Импорт узлов'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLines: 8,
          minLines: 4,
          style: monoStyle(size: 12, color: C.text),
          decoration: InputDecoration(
            hintText: 'vless://…  ·  конфиг sing-box  ·  содержимое подписки в base64',
            hintStyle: monoStyle(size: 11, color: C.textFaint),
            filled: true,
            fillColor: C.panelSoft,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.control),
              borderSide: const BorderSide(color: C.panelSoftBorder),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final data = await Clipboard.getData(Clipboard.kTextPlain);
            _controller.text = data?.text ?? '';
          },
          child: const Text('Вставить'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Добавить'),
        ),
      ],
    );
  }
}
