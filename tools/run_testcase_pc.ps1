param(
    [string]$ResultsDir = "pc_test_results_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [int]$TimeoutSec = 60
)

$ErrorActionPreference = "Continue"

# Disable Windows crash error dialog for this process and child processes
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public class WinErr {
    [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);
}
"@
[void][WinErr]::SetErrorMode(0x0002) # SEM_NOGPFAULTERRORBOX

$exe = Resolve-Path "bsp/pc/build/out/luatos-lua.exe"
$common = Resolve-Path "testcase/common/scripts"
$libs = Resolve-Path "script/libs"

New-Item -ItemType Directory -Force -Path $ResultsDir | Out-Null

$tests = Get-ChildItem -Path "testcase" -Recurse -Directory -Filter "scripts" | Where-Object {
    Test-Path (Join-Path $_.FullName "main.lua")
} | ForEach-Object {
    $_.FullName -replace "\\scripts$", ""
} | Where-Object { $_ -notlike "*testcase/common*" } | Sort-Object

$tests | Out-File "$ResultsDir/tests.txt"

$pass = 0
$fail = 0
$timeout = 0
$crash = 0
$unknown = 0
$total = $tests.Count
$idx = 0

foreach ($t in $tests) {
    $idx++
    $name = $t -replace "^.*/testcase/", ""
    $name = $name -replace "/", "__"
    $logfile = Join-Path $ResultsDir "$name.log"
    $testScripts = "$t/scripts"

    Write-Host "[$idx/$total] Running $name ..."
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = '"' + $common + '" "' + $libs + '" "' + $testScripts + '"'
    $psi.RedirectStandardOutput = $logfile
    $psi.RedirectStandardError = $logfile
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)

    $finished = $proc.WaitForExit($TimeoutSec * 1000)
    if (-not $finished) {
        Write-Host "TIMEOUT $name"
        $timeout++
        try { $proc.Kill() } catch {}
        $proc.WaitForExit(5000) | Out-Null
        continue
    }

    $rc = $proc.ExitCode
    $log = Get-Content $logfile -Raw -ErrorAction SilentlyContinue
    if ($rc -eq 139 -or $rc -lt 0) {
        Write-Host "CRASH(exit=$rc) $name"
        $crash++
    } elseif ($rc -eq 124) {
        Write-Host "TIMEOUT $name"
        $timeout++
    } elseif ($rc -ne 0) {
        if ($log -match "### OVERALL_FAIL ###") {
            Write-Host "FAIL $name"
            $fail++
        } else {
            Write-Host "CRASH(exit=$rc) $name"
            $crash++
        }
    } else {
        if ($log -match "### OVERALL_PASS ###" -or $log -match "Total: \d+ passed, 0 failed" -or $log -match "^I/user\.\S+ PASS$") {
            Write-Host "PASS $name"
            $pass++
        } elseif ($log -match "### OVERALL_FAIL ###" -or $log -match "Total: \d+ passed, [1-9]\d* failed") {
            Write-Host "FAIL $name"
            $fail++
        } else {
            Write-Host "UNKNOWN $name"
            $unknown++
        }
    }
}

Write-Host "===== Summary ====="
Write-Host "Total: $total"
Write-Host "PASS: $pass"
Write-Host "FAIL: $fail"
Write-Host "TIMEOUT: $timeout"
Write-Host "CRASH: $crash"
Write-Host "UNKNOWN: $unknown"

@{
    Total = $total
    PASS = $pass
    FAIL = $fail
    TIMEOUT = $timeout
    CRASH = $crash
    UNKNOWN = $unknown
} | Out-File "$ResultsDir/summary.txt"
