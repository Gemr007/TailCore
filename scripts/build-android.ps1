# Собирает ядро в Android-библиотеку: app/android/app/libs/tailcore.aar.
#
# gomobile bind навешивает Java-обёртку прямо на пакет core/tunnel —
# отдельный слой-переходник не нужен, его сигнатуры (string in, error out)
# уже совместимы с bind.
#
# Требуется: ANDROID_HOME с установленным NDK и JDK в PATH.

$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..' | Resolve-Path
$core = Join-Path $root 'core'
$out = Join-Path $root 'app\android\app\libs\tailcore.aar'

if (-not $env:ANDROID_HOME) { throw 'ANDROID_HOME is not set' }
$ndk = Get-ChildItem (Join-Path $env:ANDROID_HOME 'ndk') -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name | Select-Object -Last 1
if (-not $ndk) { throw "no NDK found under $env:ANDROID_HOME\ndk" }
$env:ANDROID_NDK_HOME = $ndk.FullName

New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null

Push-Location $core
try {
    go install golang.org/x/mobile/cmd/gomobile
    if ($LASTEXITCODE -ne 0) { throw "go install gomobile failed" }

    gomobile init
    if ($LASTEXITCODE -ne 0) { throw "gomobile init failed" }

    # androidapi 21 — минимум, который ещё поддерживает VpnService без
    # оговорок; поднимем, когда упрёмся в конкретное API.
    gomobile bind -target=android -androidapi 21 -tags with_utls -o $out `
        github.com/Gemr007/TailCore/core/tunnel
    if ($LASTEXITCODE -ne 0) { throw "gomobile bind failed" }
}
finally {
    Pop-Location
}

Get-Item $out | Select-Object Name, Length
