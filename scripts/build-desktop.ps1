# Собирает ядро в динамическую библиотеку для Windows: core/build/tailcore.dll
# (+ tailcore.h, его читает генератор FFI-биндингов на стороне Flutter).
#
# Нужен gcc в PATH — cgo без C-компилятора не соберётся.
# Для Linux/macOS есть build-desktop.sh, там всё то же самое.

$ErrorActionPreference = 'Stop'
$core = Join-Path $PSScriptRoot '..\core' | Resolve-Path
$out = Join-Path $core 'build'
$tags = (Get-Content (Join-Path $PSScriptRoot 'build-tags.txt') -Raw).Trim()

New-Item -ItemType Directory -Force -Path $out | Out-Null
$env:CGO_ENABLED = '1'

Push-Location $core
try {
    go build -tags $tags -buildmode=c-shared -o (Join-Path $out 'tailcore.dll') ./lib
    if ($LASTEXITCODE -ne 0) { throw "go build failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

Get-ChildItem $out | Select-Object Name, Length
