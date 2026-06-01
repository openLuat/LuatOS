param(
    [int]$Port = 18941
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

function Post-Json {
    param([string]$Url, [object]$Body)
    $payload = $Body | ConvertTo-Json -Compress
    (Invoke-WebRequest -Uri $Url -Method Post -ContentType "application/json" -Body $payload -TimeoutSec 3 -UseBasicParsing).Content | ConvertFrom-Json
}

function Post-Json-WithStatus {
    param([string]$Url, [object]$Body)
    $payload = $Body | ConvertTo-Json -Compress
    try {
        Invoke-WebRequest -Uri $Url -Method Post -ContentType "application/json" -Body $payload -TimeoutSec 3 -UseBasicParsing | Out-Null
        return 200
    } catch {
        if ($_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode.value__
        }
        throw
    }
}

$proc = $null
try {
    $proc = Start-Process -FilePath $exe -ArgumentList @("--webc=$Port", "--noexit") -PassThru -WindowStyle Hidden
    Wait-Ready -Port $Port

    $r1 = Post-Json -Url "http://127.0.0.1:$Port/api/uart31/inject" -Body @{
        direction = "rx"
        encoding = "utf8"
        payload = "Hello世界"
    }
    if (-not $r1.ok) { throw "rx utf8 inject failed" }

    $r2 = Post-Json -Url "http://127.0.0.1:$Port/api/uart31/inject" -Body @{
        direction = "rx"
        encoding = "hex"
        payload = "\x41\x0A\x42"
    }
    if (-not $r2.ok) { throw "rx hex inject failed" }

    $r3 = Post-Json -Url "http://127.0.0.1:$Port/api/uart31/inject" -Body @{
        direction = "tx"
        encoding = "hex"
        payload = "0x43 0x44"
    }
    if (-not $r3.ok) { throw "tx hex inject failed" }

    $badStatus = Post-Json-WithStatus -Url "http://127.0.0.1:$Port/api/uart31/inject" -Body @{
        direction = "loop"
        encoding = "utf8"
        payload = "bad"
    }
    if ($badStatus -ne 400) { throw "invalid direction should return 400, got $badStatus" }

    $console = Get-Json "http://127.0.0.1:$Port/api/uart31/console"
    if (-not $console.ok) { throw "console query failed" }
    if (@($console.items).Count -lt 3) { throw "expected >=3 uart31 console items" }
    if (-not ($console.items[0].direction -and $console.items[0].len -ge 1)) { throw "uart31 console item contract incomplete" }

    $allHex = @($console.items | ForEach-Object { $_.payload_hex }) -join "|"
    if ($allHex -notmatch "\\x41\\x0A\\x42") { throw "hex display payload missing expected escaped bytes" }
    if ($allHex -notmatch "\\x43\\x44") { throw "tx payload missing expected escaped bytes" }

    $allUtf8 = @($console.items | ForEach-Object { $_.payload_utf8 }) -join "|"
    if ($allUtf8 -notmatch "Hello世界") { throw "utf8 display payload missing expected content" }

    Write-Host "PASS test_webc_uart31_console"
}
finally {
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
# 运行方式: cd bsp/pc && .\tests\ps1\test_webc_uart31_console.ps1
