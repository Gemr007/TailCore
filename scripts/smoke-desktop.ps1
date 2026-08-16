# Проверяет, что собранная talecore.dll действительно экспортирует C-ABI и
# что её можно дёргать снаружи Go. Без этого «библиотека собралась» ничего
# не значит: слинковаться и не иметь рабочих символов — обычное дело.

$ErrorActionPreference = 'Stop'
$dll = Join-Path $PSScriptRoot '..\core\build\talecore.dll' | Resolve-Path

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class TaleCore {
    [DllImport(@"$dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr TaleCoreStart(string config);
    [DllImport(@"$dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr TaleCoreStop();
    [DllImport(@"$dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr TaleCoreStatus();
    [DllImport(@"$dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void TaleCoreFree(IntPtr s);
}
"@

# take забирает строку из библиотеки и сразу отдаёт память обратно:
# всё, что пришло из ядра, освобождает вызывающая сторона.
function take([IntPtr]$p) {
    if ($p -eq [IntPtr]::Zero) { return $null }
    $s = [Runtime.InteropServices.Marshal]::PtrToStringAnsi($p)
    [TaleCore]::TaleCoreFree($p)
    return $s
}

$status = (take ([TaleCore]::TaleCoreStatus())) | ConvertFrom-Json
if ($status.state -ne 'stopped') { throw "fresh library reports state '$($status.state)', want 'stopped'" }

$err = take ([TaleCore]::TaleCoreStart('{"outbounds":[{"type":"no-such-protocol"}]}'))
if (-not $err) { throw 'broken config started without an error' }

# Stop на незапущенном ядре — no-op, ошибки быть не должно.
$err = take ([TaleCore]::TaleCoreStop())
if ($err) { throw "stop on idle core returned an error: $err" }

Write-Output 'smoke-desktop: OK'
