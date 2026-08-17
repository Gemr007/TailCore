import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/apps.dart';
import '../core/autostart.dart';
import '../core/prefs.dart';
import '../theme.dart';
import '../widgets/panel.dart';

/// Экран настроек.
///
/// Экраны подписки и управления устройствами в эту итерацию не входят
/// вовсе — их здесь не должно появиться даже с оговоркой.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.prefs, this.os});

  final Prefs prefs;

  /// ОС, под которую показывать идентификаторы приложений. Подставляется в
  /// тестах; в приложении — настоящая система пользователя.
  final TargetOs? os;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Автозапуск читается у системы, а не из настроек: запись мог снять
  /// кто угодно. null — ещё не прочитали.
  bool? _autostart;

  Prefs get prefs => widget.prefs;

  @override
  void initState() {
    super.initState();
    if (Autostart.supported) _readAutostart();
  }

  Future<void> _readAutostart() async {
    final on = await Autostart.isEnabled();
    if (mounted) setState(() => _autostart = on);
  }

  Future<void> _setAutostart(bool on) async {
    // Показываем то, что подтвердила система: если запись не удалась,
    // тумблер обязан вернуться, а не остаться в желаемом положении.
    await Autostart.setEnabled(on);
    await _readAutostart();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.sizeOf(context).width >= 700 ? 26.0 : 22.0;
    final targetOs = widget.os ?? currentOs();
    final apps = appTemplatesFor(targetOs);

    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) => ListView(
        padding: EdgeInsets.fromLTRB(pad, 20, pad, 20),
        children: [
          Text('Настройки', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          const _SectionLabel('РОУТИНГ'),
          const SizedBox(height: 8),
          _ToggleRow(
            label: 'Игры мимо VPN',
            hint: 'игровой трафик идёт напрямую, минуя туннель',
            value: prefs.bypassGames,
            onTap: () => prefs.setBypassGames(!prefs.bypassGames),
          ),
          const SizedBox(height: 10),
          // Конфиг собирается в момент подключения: перещёлкнуть тумблер на
          // поднятом туннеле и ждать перемен — значит смотреть на старый
          // маршрут и не понимать почему.
          Text(
            'Список игровых доменов ядро скачивает через туннель при\n'
            'подключении. Изменение применяется со следующего подключения.',
            style: monoStyle(size: 10.5, color: C.textFaint),
          ),
          const SizedBox(height: 24),
          const _SectionLabel('ПРИЛОЖЕНИЯ МИМО VPN'),
          const SizedBox(height: 8),
          if (apps.isEmpty)
            // Единственная ветка, где раздела нет вовсе: iOS не сообщает
            // приложению, какой процесс открыл соединение.
            Text(
              'Эта система не позволяет определить, какое приложение\n'
              'открыло соединение, — исключать по приложению нечем.',
              style: monoStyle(size: 10.5, color: C.textFaint),
            )
          else
            for (final app in apps) ...[
              _ToggleRow(
                label: app.name,
                // Показываем ровно тот идентификатор, по которому ядро
                // будет искать приложение на этой ОС.
                hint: app.idsFor(targetOs).join(' · '),
                value: prefs.bypassApps.contains(app.id),
                onTap: () => prefs.setBypassApp(
                  app.id,
                  !prefs.bypassApps.contains(app.id),
                ),
              ),
              const SizedBox(height: 6),
            ],

          const SizedBox(height: 24),
          const _SectionLabel('СОЕДИНЕНИЕ'),
          const SizedBox(height: 8),
          _PortRow(prefs: prefs),
          const SizedBox(height: 6),
          _DnsRow(prefs: prefs),
          const SizedBox(height: 6),
          _ToggleRow(
            label: 'DNS через туннель',
            hint: 'иначе провайдер видит, какие имена вы спрашиваете',
            value: prefs.dnsThroughTunnel,
            onTap: () => prefs.setDnsThroughTunnel(!prefs.dnsThroughTunnel),
          ),

          const SizedBox(height: 24),
          const _SectionLabel('СИСТЕМА'),
          const SizedBox(height: 8),
          if (Autostart.supported)
            _ToggleRow(
              label: 'Запускать при входе в систему',
              hint: _autostart == null
                  ? 'проверяем…'
                  : 'состояние берётся у ОС',
              value: _autostart ?? false,
              onTap: _autostart == null
                  ? null
                  : () => _setAutostart(!_autostart!),
            ),
          const SizedBox(height: 6),
          // Оба тумблера ниже нечем включить: пока трафик идёт через
          // локальный прокси, перехватывать и обрывать нечего. Показать их
          // рабочими значило бы соврать — показываем выключенными и с
          // причиной.
          const _ToggleRow(
            label: 'Kill switch',
            hint: 'заработает вместе с системным туннелем — шаг 18',
            value: false,
            onTap: null,
          ),
          const SizedBox(height: 6),
          const _ToggleRow(
            label: 'Режим TUN',
            hint: 'весь трафик системы через туннель — шаги 17 и 18',
            value: false,
            onTap: null,
          ),
        ],
      ),
    );
  }
}

/// Порт локального прокси. Отдельным полем, а не тумблером: чужой процесс
/// на 2080 — самая частая причина, по которой ядро не поднимается.
class _PortRow extends StatefulWidget {
  const _PortRow({required this.prefs});

  final Prefs prefs;

  @override
  State<_PortRow> createState() => _PortRowState();
}

class _PortRowState extends State<_PortRow> {
  late final _controller = TextEditingController(
    text: '${widget.prefs.localPort}',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Ввод принимается только целиком и только осмысленный: наполовину
  /// набранный номер порта не должен уезжать в настройки посимвольно.
  void _submit(String text) {
    final port = int.tryParse(text);
    if (port == null || port < 1024 || port > 65535) {
      _controller.text = '${widget.prefs.localPort}';
      return;
    }
    widget.prefs.setLocalPort(port);
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Локальный порт',
                  style: TextStyle(fontSize: 13.5, color: C.text),
                ),
                const SizedBox(height: 3),
                Text(
                  '127.0.0.1 · 1024–65535',
                  style: monoStyle(size: 10.5, color: C.textMuted),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 72,
            child: TextField(
              controller: _controller,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: monoStyle(size: 12, color: C.text),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                filled: true,
                fillColor: C.panelSoft,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.chip),
                  borderSide: const BorderSide(color: C.panelSoftBorder),
                ),
              ),
              onSubmitted: _submit,
              onTapOutside: (_) {
                FocusScope.of(context).unfocus();
                _submit(_controller.text);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Выбор резолвера. Готовые адреса, а не поле ввода: сперва надо, чтобы
/// работали эти, а свой адрес — отдельная задача.
class _DnsRow extends StatelessWidget {
  const _DnsRow({required this.prefs});

  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DNS-сервер',
            style: TextStyle(fontSize: 13.5, color: C.text),
          ),
          const SizedBox(height: 3),
          Text(
            'DoH, адрес числом — резолверу не нужен резолвер',
            style: monoStyle(size: 10.5, color: C.textMuted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final entry in dnsPresets.entries)
                _DnsChip(
                  address: entry.key,
                  name: entry.value,
                  selected: prefs.dnsServer == entry.key,
                  onTap: () => prefs.setDnsServer(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DnsChip extends StatelessWidget {
  const _DnsChip({
    required this.address,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String address;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey('dns-$address'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? C.accent : Colors.transparent,
          border: Border.all(
            color: selected ? C.accent : const Color(0xFF2B3742),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$name · $address',
          style: monoStyle(size: 10, color: selected ? C.onAccent : C.textDim),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: monoStyle(size: 10, caps: true, color: C.textMuted),
    );
  }
}

/// Строка-переключатель из макета: название, пояснение и плоский тумблер.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool value;

  /// null — переключить нельзя. Строка при этом гаснет: выключенный
  /// тумблер, который не поддаётся, должен выглядеть выключенным, а не
  /// сломанным.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final off = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Panel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: off ? C.textMuted : C.text,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hint,
                    style: monoStyle(
                      size: 10.5,
                      color: off ? C.textFaint : C.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _Switch(value: value, dim: off),
          ],
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.value, this.dim = false});

  final bool value;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 23,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: value ? C.accent : C.hover,
        border: Border.all(color: value ? C.accent : C.panelBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Align(
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: value
                ? C.onAccent
                : dim
                ? C.idle
                : C.textMuted,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
