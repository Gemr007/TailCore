import 'dart:io';

/// ОС, под которую резолвятся идентификаторы приложений.
///
/// Своё перечисление, а не `Platform.operatingSystem` строкой: список
/// исключений обязан отличать Windows от Android, и проверять это надо
/// компилятором, а не сравнением строк в трёх местах.
enum TargetOs { windows, linux, macos, android, ios }

TargetOs currentOs() {
  if (Platform.isWindows) return TargetOs.windows;
  if (Platform.isMacOS) return TargetOs.macos;
  if (Platform.isAndroid) return TargetOs.android;
  if (Platform.isIOS) return TargetOs.ios;
  return TargetOs.linux;
}

/// Поле правила sing-box, которым на этой ОС опознаётся приложение.
///
/// null — опознать нельзя: на iOS система не сообщает приложению, какой
/// процесс открыл соединение. Это не недоделка, а свойство платформы, и
/// список исключений там показывать нечем.
String? processRuleField(TargetOs os) => switch (os) {
  TargetOs.android => 'package_name',
  TargetOs.ios => null,
  _ => 'process_name',
};

/// Приложение из списка исключений.
///
/// Идентификаторы у каждой ОС свои, и хранятся они все сразу: одно и то же
/// приложение — это `Discord.exe` на Windows и `com.discord` на Android.
/// Зашить одну платформу — ровно та ошибка, что была в макете, где везде
/// показывались macOS-идентификаторы.
class AppTemplate {
  const AppTemplate({
    required this.id,
    required this.name,
    this.windows = const [],
    this.linux = const [],
    this.macos = const [],
    this.android = const [],
  });

  /// Ключ в настройках. Не меняется при переименовании приложения.
  final String id;
  final String name;

  /// Имена процессов и имя пакета. Списком, потому что у одного приложения
  /// их бывает несколько: Steam — это ещё и `steamwebhelper`.
  final List<String> windows;
  final List<String> linux;
  final List<String> macos;
  final List<String> android;

  List<String> idsFor(TargetOs os) => switch (os) {
    TargetOs.windows => windows,
    TargetOs.linux => linux,
    TargetOs.macos => macos,
    TargetOs.android => android,
    TargetOs.ios => const [],
  };
}

/// Приложения, которые чаще всего просят пустить мимо туннеля: игровые
/// клиенты, голос и браузеры.
///
/// Список — заготовка, а не полнота: приложений бесконечно много, а руками
/// добавленное исключение — отдельная задача.
const appTemplates = [
  AppTemplate(
    id: 'steam',
    name: 'Steam',
    windows: ['steam.exe', 'steamwebhelper.exe'],
    linux: ['steam', 'steamwebhelper'],
    macos: ['steam_osx'],
    android: ['com.valvesoftware.android.steam.community'],
  ),
  AppTemplate(
    id: 'epic',
    name: 'Epic Games',
    windows: ['EpicGamesLauncher.exe'],
    macos: ['EpicGamesLauncher'],
  ),
  AppTemplate(
    id: 'battlenet',
    name: 'Battle.net',
    windows: ['Battle.net.exe'],
    macos: ['Battle.net'],
  ),
  AppTemplate(
    id: 'riot',
    name: 'Riot Games',
    windows: ['RiotClientServices.exe', 'LeagueofLegends.exe'],
    macos: ['RiotClientServices'],
  ),
  AppTemplate(
    id: 'discord',
    name: 'Discord',
    windows: ['Discord.exe'],
    linux: ['Discord', 'discord'],
    macos: ['Discord'],
    android: ['com.discord'],
  ),
  AppTemplate(
    id: 'telegram',
    name: 'Telegram',
    windows: ['Telegram.exe'],
    linux: ['telegram-desktop', 'Telegram'],
    macos: ['Telegram'],
    android: ['org.telegram.messenger'],
  ),
  AppTemplate(
    id: 'chrome',
    name: 'Google Chrome',
    windows: ['chrome.exe'],
    linux: ['chrome', 'google-chrome'],
    macos: ['Google Chrome'],
    android: ['com.android.chrome'],
  ),
  AppTemplate(
    id: 'firefox',
    name: 'Firefox',
    windows: ['firefox.exe'],
    linux: ['firefox'],
    macos: ['firefox'],
    android: ['org.mozilla.firefox'],
  ),
  AppTemplate(
    id: 'edge',
    name: 'Microsoft Edge',
    windows: ['msedge.exe'],
    linux: ['microsoft-edge'],
    macos: ['Microsoft Edge'],
    android: ['com.microsoft.emmx'],
  ),
  AppTemplate(
    id: 'spotify',
    name: 'Spotify',
    windows: ['Spotify.exe'],
    linux: ['spotify'],
    macos: ['Spotify'],
    android: ['com.spotify.music'],
  ),
  AppTemplate(
    id: 'qbittorrent',
    name: 'qBittorrent',
    windows: ['qbittorrent.exe'],
    linux: ['qbittorrent'],
    macos: ['qbittorrent'],
  ),
];

/// Приложения, которые на этой ОС вообще можно опознать. Показывать
/// пользователю Epic Games на Android незачем: сопоставлять там нечего.
List<AppTemplate> appTemplatesFor(TargetOs os) => [
  for (final t in appTemplates)
    if (t.idsFor(os).isNotEmpty) t,
];
