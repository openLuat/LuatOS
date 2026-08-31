# test_log_dir.ps1
# 验证 --log-dir=<path>：空路径拒绝；合法路径把 luatos_pc_*.log 写到指定目录
# 运行方式: cd bsp/pc && .\tests\ps1\test_log_dir.ps1

param(
    [string]$Exe = "$PSScriptRoot\..\..\build\out\luatos-lua.exe"
)

$ErrorActionPreference = "Stop"

function Fail([string]$msg) {
    Write-Host "FAIL: $msg" -ForegroundColor Red
    exit 1
}

function Pass([string]$msg) {
    Write-Host "PASS: $msg" -ForegroundColor Green
}

if (-not (Test-Path $Exe)) {
    Fail "找不到模拟器二进制: $Exe`n请先运行 build_windows_32bit_msvc.bat"
}
$Exe = (Resolve-Path $Exe).Path

function Run-And-Capture([string[]]$arguments, [string]$cwd, [int]$timeoutMs = 4000) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $cwd
    $psi.Arguments = ($arguments | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join " "

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()

    $exited = $p.WaitForExit($timeoutMs)
    if (-not $exited) {
        try { $p.Kill() } catch {}
        $p.WaitForExit()
    }

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    return @{
        Code = $p.ExitCode
        Output = ($stdout + "`n" + $stderr)
        TimedOut = (-not $exited)
    }
}

$scratch = Join-Path $env:TEMP ("luatos-log-dir-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $scratch | Out-Null
$cwd = Join-Path $scratch "cwd"
$logDir = Join-Path $scratch "logs\lua_demo\pclogs"
New-Item -ItemType Directory -Path $cwd | Out-Null

try {
    Write-Host ""
    Write-Host "=== 测试 1: 空 --log-dir= 应拒绝 ===" -ForegroundColor Cyan
    $r1 = Run-And-Capture @("--log-dir=") $cwd 3000
    if ($r1.Code -eq 0) { Fail "空 --log-dir= 应失败退出`n$($r1.Output)" }
    if ($r1.Output -notmatch "invalid --log-dir|--log-dir") {
        Fail "空 --log-dir= 应给出错误信息`n$($r1.Output)"
    }
    Pass "空路径拒绝通过"

    Write-Host ""
    Write-Host "=== 测试 2: --log-dir 无等号应拒绝 ===" -ForegroundColor Cyan
    $r2 = Run-And-Capture @("--log-dir") $cwd 3000
    if ($r2.Code -eq 0) { Fail "单独 --log-dir 应失败退出`n$($r2.Output)" }
    if ($r2.Output -notmatch "--log-dir") {
        Fail "单独 --log-dir 应给出错误信息`n$($r2.Output)"
    }
    Pass "无等号拒绝通过"

    Write-Host ""
    Write-Host "=== 测试 3: 指定目录应写出 luatos_pc_*.log 且不污染 cwd/pclogs ===" -ForegroundColor Cyan
    $r3 = Run-And-Capture @("--log-dir=$logDir") $cwd 4000
    $written = @()
    if (Test-Path $logDir) {
        $written = @(Get-ChildItem -Path $logDir -Filter "luatos_pc_*.log" -ErrorAction SilentlyContinue)
    }
    if ($written.Count -lt 1) {
        Fail "未在 --log-dir 目录找到 luatos_pc_*.log`n$dir=$logDir`n$($r3.Output)"
    }
    $cwdPclogs = Join-Path $cwd "pclogs"
    if (Test-Path $cwdPclogs) {
        Fail "cwd 下不应再创建 pclogs: $cwdPclogs"
    }
    Pass "指定目录写出通过 ($($written[0].Name))"

    Write-Host ""
    Write-Host "所有 --log-dir 参数测试通过!" -ForegroundColor Green
}
finally {
    try { Remove-Item -Recurse -Force $scratch } catch {}
}
