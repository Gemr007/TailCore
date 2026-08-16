# Проверяет, что собранная tailcore.dll действительно экспортирует C-ABI и
# что её можно дёргать снаружи Go. Без этого «библиотека собралась» ничего
# не значит: слинковаться и не иметь рабочих символов — обычное дело.

$ErrorActionPreference = 'Stop'
$dll = Join-Path $PSScriptRoot '..\core\build\tailcore.dll' | Resolve-Path

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class TailCore {
    [DllImport(@"$dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr TailCoreStart(string config);
    [DllImport(@"$dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr TailCoreStop();
    [DllImport(@"$dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr TailCoreStatus();
    [DllImport(@"$dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void TailCoreFree(IntPtr s);
}
"@

# take забирает строку из библиотеки и сразу отдаёт память обратно:
# всё, что пришло из ядра, освобождает вызывающая сторона.
function take([IntPtr]$p) {
    if ($p -eq [IntPtr]::Zero) { return $null }
    $s = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($p)
    [TailCore]::TailCoreFree($p)
    return $s
}

$status = (take ([TailCore]::TailCoreStatus())) | ConvertFrom-Json
if ($status.state -ne 'stopped') { throw "fresh library reports state '$($status.state)', want 'stopped'" }

$err = take ([TailCore]::TailCoreStart('{"outbounds":[{"type":"no-such-protocol"}]}'))
if (-not $err) { throw 'broken config started without an error' }

# Stop на незапущенном ядре — no-op, ошибки быть не должно.
$err = take ([TailCore]::TailCoreStop())
if ($err) { throw "stop on idle core returned an error: $err" }

Write-Output 'smoke-desktop: OK'
