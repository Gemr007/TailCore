# Прогоняет проверки Go-ядра теми же build-тегами, что и сборка.
#
# Отдельный скрипт нужен именно ради тегов: `go test` без них собирает
# другое ядро, чем то, что поедет пользователю, и зелёные тесты перестают
# что-либо значить.

$ErrorActionPreference = 'Stop'
$core = Join-Path $PSScriptRoot '..\core' | Resolve-Path
$tags = (Get-Content (Join-Path $PSScriptRoot 'build-tags.txt') -Raw).Trim()

Push-Location $core
try {
    go vet -tags $tags ./...
    if ($LASTEXITCODE -ne 0) { throw 'go vet failed' }

    go test -count=1 -tags $tags @args ./...
    if ($LASTEXITCODE -ne 0) { throw 'go test failed' }
}
finally {
    Pop-Location
}
