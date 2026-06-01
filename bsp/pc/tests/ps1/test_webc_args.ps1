# test_webc_args.ps1
# 集成测试: 验证 --webc=<port> 参数解析与启动行为
# 运行方式: cd bsp/pc && .\tests\ps1\test_webc_args.ps1

param(
    [string]$Exe = "$PSScriptRoot\build\out\luatos-lua.exe"
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

$pcconfPath = Join-Path $PSScriptRoot "pcconf\pcconf.json"
$pcconfOriginal = $null

function Save-Pcconf([int]$enabled, [int]$port, [int]$refresh) {
    $py = @'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
enabled = int(sys.argv[2])
port = int(sys.argv[3])
refresh = int(sys.argv[4])
obj = json.loads(path.read_text(encoding="utf-8"))
obj["web_console"]["enabled"] = enabled
obj["web_console"]["port"] = port
obj["web_console"]["refresh_interval"] = refresh
path.write_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
'@
    python -c $py $pcconfPath $enabled $port $refresh | Out-Null
}

function Run-And-Capture([string[]]$arguments, [int]$timeoutMs = 5000) {
    $logDir = "$PSScriptRoot\pclogs"
    $startAt = Get-Date
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
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
    $logText = ""
    if (Test-Path $logDir) {
        $newestLog = Get-ChildItem -Path $logDir -Filter "luatos_pc_*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -ge $startAt.AddSeconds(-1) } |
            Sort-Object LastWriteTime |
            Select-Object -Last 1
        if ($newestLog) {
            try { $logText = Get-Content $newestLog.FullName -Raw -ErrorAction Stop } catch {}
        }
    }
    return @{
        Code = $p.ExitCode
        Output = ($stdout + "`n" + $stderr + "`n" + $logText)
        TimedOut = (-not $exited)
    }
}

try {
    $pcconfOriginal = Get-Content $pcconfPath -Raw

    Write-Host ""
    Write-Host "=== 测试 1: pcconf 关闭时不应自动启动 ===" -ForegroundColor Cyan
    Save-Pcconf 0 18980 5
    $r1 = Run-And-Capture @() 3000
    if ($r1.Output -match "web console.*127\.0\.0\.1:\d+") {
        Fail "web_console.enabled=0 时不应自动启动 web console`n$($r1.Output)"
    }
    Pass "pcconf 关闭通过"

    Write-Host ""
    Write-Host "=== 测试 2: 端口 0 应明确拒绝 ===" -ForegroundColor Cyan
    $r2 = Run-And-Capture @("--webc=0")
    if ($r2.Code -eq 0) { Fail "非法 --webc=0 应失败退出`n$($r2.Output)" }
    if ($r2.Output -notmatch "无效|invalid|--webc") {
        Fail "非法 --webc=0 应给出清晰错误信息`n$($r2.Output)"
    }
    Pass "端口 0 拒绝通过"

    Write-Host ""
    Write-Host "=== 测试 3: 非法字符串应明确拒绝 ===" -ForegroundColor Cyan
    $r3 = Run-And-Capture @("--webc=abc")
    if ($r3.Code -eq 0) { Fail "非法 --webc 应失败退出`n$($r3.Output)" }
    if ($r3.Output -notmatch "无效|invalid|--webc") {
        Fail "非法 --webc 应给出清晰错误信息`n$($r3.Output)"
    }
    Pass "非法端口拒绝通过"

    Write-Host ""
    Write-Host "所有 --webc 参数测试通过!" -ForegroundColor Green
}
finally {
    if ($pcconfOriginal -ne $null) {
        [System.IO.File]::WriteAllText($pcconfPath, $pcconfOriginal, (New-Object System.Text.UTF8Encoding($false)))
    }
}
