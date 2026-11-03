# =====================================================================
# 把「当前电脑时间」写进 code/app/build_stamp.lua
# 烧录前运行一次，设备上电后就会把 RTC 校准到这一刻，
# 做到「什么时候烧录，情绪日历的今天就是哪天」。
# 只改 stamp 那一行，文件里的注释原样保留。
# =====================================================================
$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$lua = Join-Path $root "code\app\build_stamp.lua"

if (-not (Test-Path $lua)) {
    Write-Host "[ERR] not found: $lua" -ForegroundColor Red
    exit 1
}

$now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$text = [System.IO.File]::ReadAllText($lua, [System.Text.Encoding]::UTF8)

if ($text -match '(?m)^\s*stamp\s*=') {
    $new = [regex]::Replace($text, '(?m)^\s*stamp\s*=\s*.*$', "    stamp = `"$now`",")
} else {
    $new = $text + "`n-- added by tools/update_stamp.ps1`nreturn { stamp = `"$now`" }`n"
}

[System.IO.File]::WriteAllText($lua, $new, $utf8)

Write-Host ""
Write-Host "  Build stamp written: $now" -ForegroundColor Green
Write-Host "  File: code/app/build_stamp.lua"
Write-Host ""
Write-Host "  Now flash this folder. The device RTC will be set to that moment,"
Write-Host "  so the calendar's 'today' is exactly the day you flash it."
Write-Host ""
