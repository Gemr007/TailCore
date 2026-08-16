# Прогоняет тесты приложения так, чтобы тест FFI-моста нашёл ядро.
#
# dart:ffi открывает библиотеку по имени, а не по пути, поэтому каталог
# сборки ядра надо положить в PATH — иначе тест упадёт на «не найдена».

$ErrorActionPreference = 'Stop'
$root = Join-Path $PSScriptRoot '..' | Resolve-Path
$build = Join-Path $root 'core\build'

if (-not (Test-Path (Join-Path $build 'tailcore.dll'))) {
    throw 'core/build/tailcore.dll not found — run scripts/build-desktop.ps1 first'
}

$env:Path = "$build;$env:Path"
Push-Location (Join-Path $root 'app')
try {
    flutter test @args
    if ($LASTEXITCODE -ne 0) { throw "flutter test failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}
