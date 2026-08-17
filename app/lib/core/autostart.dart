import 'dart:io';

/// Запуск вместе с входом в систему.
///
/// Источник правды — сама ОС, а не файл настроек: запись мог снять
/// пользователь или чистильщик автозапуска, и тумблер, помнящий своё,
/// показывал бы включённым то, чего давно нет.
abstract final class Autostart {
  static const _name = 'TailCore';
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  /// Android и iOS сюда не попадают: там автозапуск — не файл и не ключ
  /// реестра, а системное разрешение, и делается он в шагах платформы.
  static bool get supported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static Future<bool> isEnabled() async {
    if (Platform.isWindows) {
      final result = await Process.run('reg', [
        'query',
        _runKey,
        '/v',
        _name,
      ], runInShell: true);
      return result.exitCode == 0;
    }
    if (Platform.isLinux || Platform.isMacOS) return _unixFile().existsSync();
    return false;
  }

  static Future<void> setEnabled(bool on) async {
    final exe = Platform.resolvedExecutable;

    if (Platform.isWindows) {
      await Process.run('reg', windowsArgs(on, exe), runInShell: true);
      return;
    }
    if (Platform.isLinux || Platform.isMacOS) {
      final file = _unixFile();
      if (!on) {
        if (file.existsSync()) await file.delete();
        return;
      }
      await file.parent.create(recursive: true);
      await file.writeAsString(
        Platform.isLinux ? desktopEntry(exe) : launchAgent(exe),
      );
    }
  }

  static File _unixFile() {
    final home = Platform.environment['HOME'] ?? '';
    return Platform.isLinux
        ? File('$home/.config/autostart/tailcore.desktop')
        : File('$home/Library/LaunchAgents/com.tailcore.app.plist');
  }

  /// Аргументы `reg` — отдельно от вызова, чтобы их можно было проверить,
  /// не трогая настоящий реестр.
  static List<String> windowsArgs(bool on, String exe) => on
      ? ['add', _runKey, '/v', _name, '/t', 'REG_SZ', '/d', exe, '/f']
      : ['delete', _runKey, '/v', _name, '/f'];

  static String desktopEntry(String exe) =>
      '[Desktop Entry]\n'
      'Type=Application\n'
      'Name=$_name\n'
      'Exec=$exe\n'
      'X-GNOME-Autostart-enabled=true\n';

  static String launchAgent(String exe) =>
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
      '<plist version="1.0"><dict>\n'
      '  <key>Label</key><string>com.tailcore.app</string>\n'
      '  <key>ProgramArguments</key><array><string>$exe</string></array>\n'
      '  <key>RunAtLoad</key><true/>\n'
      '</dict></plist>\n';
}
