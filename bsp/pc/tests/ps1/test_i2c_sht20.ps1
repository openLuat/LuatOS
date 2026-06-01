param(
    [int]$Port = 18931
)

$ErrorActionPreference = "Stop"
$exe = Join-Path $PSScriptRoot "build\out\luatos-lua.exe"
if (-not (Test-Path $exe)) {
    throw "Binary not found: $exe"
}

function Wait-Ready {
    param([int]$Port, [int]$TimeoutSeconds = 8)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $resp = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/health" -TimeoutSec 1 -UseBasicParsing
            if ($resp.StatusCode -eq 200) { return }
        } catch {}
        Start-Sleep -Milliseconds 200
    }
    throw "web runtime not ready on :$Port"
}

function Get-Json {
    param([string]$Url)
    (Invoke-WebRequest -Uri $Url -TimeoutSec 3 -UseBasicParsing).Content | ConvertFrom-Json
}

Write-Host "=== SHT20 web runtime control surface ===" -ForegroundColor Cyan
$proc = $null
try {
    $proc = Start-Process -FilePath $exe -ArgumentList @("--webc=$Port", "--noexit") -PassThru -WindowStyle Hidden
    Wait-Ready -Port $Port

    $get0 = Get-Json "http://127.0.0.1:$Port/api/mock/sht20"
    if (-not ($get0.ok -eq $true)) { throw "GET /api/mock/sht20 should return ok=true" }
    if ($null -eq $get0.temperature_c -or $null -eq $get0.humidity_rh) { throw "missing default fields" }

    $body = @{ temperature_c = 31.5; humidity_rh = 65.25 } | ConvertTo-Json -Compress
    $post = (Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/mock/sht20" -Method Post -ContentType "application/json" -Body $body -UseBasicParsing).Content | ConvertFrom-Json
    if (-not ($post.ok -eq $true)) { throw "POST /api/mock/sht20 should return ok=true" }
    if ([math]::Abs([double]$post.temperature_c - 31.5) -gt 0.01) { throw "temperature not updated" }
    if ([math]::Abs([double]$post.humidity_rh - 65.25) -gt 0.01) { throw "humidity not updated" }
}
finally {
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}

Write-Host "=== SHT20 I2C command/register/conversion ===" -ForegroundColor Cyan
$common = "..\..\testcase\common\scripts\"
$case = "..\..\testcase\unit_testcase_tools\i2c_sht20\scripts\"
$run = Start-Process -FilePath $exe -ArgumentList @($common, $case) -PassThru -NoNewWindow -Wait
if ($run.ExitCode -ne 0) {
    throw "Lua testcase failed, exit code=$($run.ExitCode)"
}

Write-Host "PASS test_i2c_sht20"
# 运行方式: cd bsp/pc && .\tests\ps1\test_i2c_sht20.ps1
