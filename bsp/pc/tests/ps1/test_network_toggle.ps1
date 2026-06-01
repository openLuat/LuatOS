param(
    [string]$Exe = "$PSScriptRoot\build\out\luatos-lua.exe"
)

$ErrorActionPreference = "Stop"

function Fail([string]$msg) {
    Write-Host "FAIL: $msg" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $Exe)) {
    Fail "找不到模拟器二进制: $Exe`n请先运行 build_windows_32bit_msvc.bat"
}
$Exe = (Resolve-Path $Exe).Path

$pcconfPath = Join-Path $PSScriptRoot "pcconf\pcconf.json"
$pcconfOriginal = $null

try {
    if (-not (Test-Path $pcconfPath)) {
        Fail "找不到配置文件: $pcconfPath"
    }
    $pcconfOriginal = Get-Content $pcconfPath -Raw
    $cfg = $pcconfOriginal | ConvertFrom-Json
    if (-not $cfg.network) {
        $cfg | Add-Member -MemberType NoteProperty -Name network -Value (@{ enabled = 0 })
    }
    else {
        $cfg.network.enabled = 0
    }
    [System.IO.File]::WriteAllText($pcconfPath, ($cfg | ConvertTo-Json -Depth 16 -Compress), (New-Object System.Text.UTF8Encoding($false)))

    $env:PCCONF_EXPECT_NETWORK_ENABLED = "0"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.WorkingDirectory = $PSScriptRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $commonScripts = (Resolve-Path (Join-Path $PSScriptRoot "..\..\testcase\common\scripts")).Path
    $pcconfScripts = (Resolve-Path (Join-Path $PSScriptRoot "..\..\testcase\unit_testcase_tools\pcconf\scripts")).Path
    $psi.Arguments = '"' + $commonScripts + '" "' + $pcconfScripts + '"'

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    [void]$p.Start()
    if (-not $p.WaitForExit(60000)) {
        try { $p.Kill() } catch {}
        $p.WaitForExit()
        Fail "网络关闭回归测试超时"
    }

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    if ($p.ExitCode -ne 0) {
        Fail "网络关闭回归测试失败, exit=$($p.ExitCode)`n$stdout`n$stderr"
    }

    Write-Host "PASS test_network_toggle"
}
finally {
    if ($pcconfOriginal -ne $null) {
        [System.IO.File]::WriteAllText($pcconfPath, $pcconfOriginal, (New-Object System.Text.UTF8Encoding($false)))
    }
    Remove-Item Env:PCCONF_EXPECT_NETWORK_ENABLED -ErrorAction SilentlyContinue
}
# 运行方式: cd bsp/pc && .\tests\ps1\test_network_toggle.ps1
