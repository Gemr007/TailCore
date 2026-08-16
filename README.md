# TaleCore

Кроссплатформенный VPN-клиент. Android, Windows, Linux, macOS.
iOS в первую итерацию не входит, но архитектура его не исключает.

## Архитектура

```
┌──────────────────────────────────────────┐
│  app/        Flutter (Dart) — весь UI    │
│              Dashboard / Servers / Settings│
└───────────────┬──────────────────────────┘
                │  FFI (desktop) / MethodChannel (Android)
┌───────────────▼──────────────────────────┐
│  core/       Go — движок                 │
│              sing-box (основной)         │
│              Xray-core (VLESS/Reality/   │
│              XTLS/XHTTP специфика)       │
└───────────────┬──────────────────────────┘
                │
        ОС: TUN / VpnService
```

Ядро собирается как нативная библиотека, а не как отдельный процесс:

| Платформа | Сборка | Артефакт |
|-----------|--------|----------|
| Android | `gomobile bind` | `.aar` |
| Windows | `cgo` + `-buildmode=c-shared` | `.dll` |
| Linux | `cgo` + `-buildmode=c-shared` | `.so` |
| macOS | `cgo` + `-buildmode=c-shared` | `.dylib` |

Подход по мотивам Hiddify (как ориентир архитектуры, без заимствования кода).

## Каталоги

- `app/` — Flutter-приложение, единственное место, где живёт UI.
- `core/` — Go-модуль движка: запуск/остановка туннеля, статус, статистика.
  Наружу отдаёт узкий C-ABI, одинаковый для всех платформ.
- `scripts/` — сборка нативных библиотек и CI.

## Протоколы

Первая итерация: SOCKS, HTTP(S), Shadowsocks, Trojan, VMess, VLESS,
VLESS+Reality/XTLS, TUIC, Hysteria, Hysteria2, WireGuard, SSH.

Позже отдельными шагами: AnyTLS, ShadowTLS, NaiveProxy, AmneziaWG, Mieru,
Juicity, TrustTunnel, olcRTC.

## Маршрутизация

**По доменам** — rule-sets в формате `.srs` (актуальный формат sing-box;
устаревшее поле `geosite` не используем). Источники:
v2fly/domain-list-community, SagerNet/sing-geosite. Обязательная фича первой
итерации — вывод игрового трафика из туннеля через `category-games`.

**По приложениям** — идентификатор зависит от платформы:

| Платформа | Поле в конфиге sing-box |
|-----------|-------------------------|
| Windows / Linux / macOS | `process_name`, `process_path` |
| Android | `package_name` |
| iOS | недоступно на уровне ОС |

Идентификаторы приложений резолвятся по реальной ОС пользователя в рантайме,
а не зашиваются под одну платформу. Список исключений в общем UI-компоненте
должен быть платформо-условным, чтобы iOS можно было добавить, ничего не
ломая.

## Дизайн

Тёмная тема, IBM Plex Sans + JetBrains Mono, бейджи протоколов.
Плотность интерфейса на десктопе (ориентир — Throne), простота на мобильном
(ориентир — Streisand): одна дизайн-система, которая разворачивается в
плотность и сворачивается в простоту.

Экраны подписки/оплаты и управления устройствами в эту итерацию не входят.

## Сборка ядра

sing-box прячет часть протоколов за build-тегами, без них конфиг падает уже
на старте (`uTLS is not included in this build`). Собирать и тестировать
только с тегами:

```
cd core
go build -tags with_utls ./...
go test  -tags with_utls ./...
go run   -tags with_utls ./cmd/talecore testdata/vless.json
```

Текущий набор тегов: `with_utls` (uTLS-отпечатки для VLESS+Reality/XTLS).
По мере добавления протоколов сюда доедут `with_quic` (TUIC, Hysteria/2),
`with_wireguard`, `with_gvisor` (TUN).

## Нативные библиотеки

```
scripts/build-desktop.ps1   # Windows: core/build/talecore.dll + .h
scripts/build-desktop.sh    # Linux/macOS: core/build/libtalecore.so|.dylib
scripts/smoke-desktop.ps1   # дёргает C-ABI собранной .dll снаружи Go
scripts/build-android.ps1   # app/android/libs/talecore.aar (4 ABI)
```

Десктоп получает C-ABI: `TaleCoreStart`/`Stop`/`Status`/`Free`, все строки
владеет вызывающая сторона. Android получает Java-класс `tunnel.Tunnel` —
gomobile навешивает обёртку прямо на пакет `core/tunnel`, промежуточный
слой не нужен:

```java
tunnel.Tunnel.start(configJson);   // throws Exception
tunnel.Tunnel.status();            // -> JSON
tunnel.Tunnel.stop();              // throws Exception
```

Для Android нужны `ANDROID_HOME` с установленным NDK и JDK в PATH.
Артефакты сборки в git не попадают.

## Приложение

```
cd app
flutter analyze
flutter run -d windows      # или -d linux / -d macos / -d <android-device>

scripts/test-app.ps1        # тесты; кладёт core/build в PATH, иначе
                            # тест FFI-моста не найдёт ядро
```

Ядро должно быть собрано до запуска приложения: и CMake на десктопе, и
Gradle на Android падают, если библиотеки нет. Это осознанно — молча
подсунуть протухшую копию ядра хуже, чем не собраться.

Навигация переключается по ширине окна, а не по платформе: от 700 px —
рейл сбоку (плотность десктопа), уже — панель снизу (простота мобильного).
Узкое окно на десктопе ведёт себя как телефон, и это осознанно.

## Мост Flutter ↔ ядро

`app/lib/core/tunnel.dart` прячет за собой две разные реализации, потому
что нативные библиотеки собираются по-разному:

| Платформа | Механизм | Что вызывается |
|-----------|----------|----------------|
| Windows/Linux/macOS | `dart:ffi` | `TaleCoreStart/Stop/Status/Free` |
| Android | `MethodChannel` `talecore/tunnel` | `tunnel.Tunnel.start/stop/status` |

Остальное приложение работает только с `TunnelCore` и о различии не знает.
Когда дойдёт дело до iOS, здесь появится третья ветка — код экранов не
изменится.

## Статус

Итерация 1, шаг 5 из 13 — Dart дёргает ядро и показывает его состояние на
экране соединения. Кнопка пока стартует заглушечный конфиг: выбор сервера
делается на шаге 7.
