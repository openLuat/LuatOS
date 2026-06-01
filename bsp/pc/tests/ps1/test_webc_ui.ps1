param(
    [int]$Port = 18951
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

function Get-Text {
    param([string]$Url)
    (Invoke-WebRequest -Uri $Url -TimeoutSec 3 -UseBasicParsing).Content
}

function Get-Response {
    param([string]$Url)
    Invoke-WebRequest -Uri $Url -TimeoutSec 3 -UseBasicParsing
}

$uiRoot = Join-Path $PSScriptRoot "port\webc_ui"
foreach ($asset in @("index.html", "app.js", "style.css")) {
    if (-not (Test-Path (Join-Path $uiRoot $asset))) {
        throw "missing UI asset: $asset"
    }
}

$proc = $null
try {
    $proc = Start-Process -FilePath $exe -ArgumentList @("--webc=$Port", "--noexit") -PassThru -WindowStyle Hidden
    Wait-Ready -Port $Port

    $html = Get-Text "http://127.0.0.1:$Port/"
    foreach ($needle in @(
        'id="dashboard"',
        'id="uart31"',
        'id="uart32-gnss"',
        'id="sht20"',
        'id="storage"',
        'id="network"',
        'id="config"',
        '/webc_ui/style.css',
        '/webc_ui/app.js'
    )) {
        if ($html -notmatch [regex]::Escape($needle)) {
            throw "html missing expected marker: $needle"
        }
    }

    $cssResp = Get-Response "http://127.0.0.1:$Port/webc_ui/style.css"
    if ($cssResp.Headers["Content-Type"] -notmatch "text/css") {
        throw "style.css should be served as text/css"
    }
    $css = $cssResp.Content
    if ($css -notmatch "\.topbar") {
        throw "style.css missing expected selector"
    }

    $js = Get-Text "http://127.0.0.1:$Port/webc_ui/app.js"
    foreach ($needle in @(
        "EventSource",
        "/api/health",
        "/api/status",
        "/api/telemetry",
        "/api/config",
        "/api/events",
        "/api/uart31/console",
        "/api/uart31/inject",
        "/api/uart32/gnss",
        "/api/uart32/gnss/config",
        "/api/mock/sht20"
    )) {
        if ($js -notmatch [regex]::Escape($needle)) {
            throw "app.js missing expected marker: $needle"
        }
    }

    $status = (Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/status" -TimeoutSec 3 -UseBasicParsing).Content | ConvertFrom-Json
    foreach ($field in @("lua_peak", "sys_peak")) {
        if (-not ($status.memory.PSObject.Properties.Name -contains $field)) {
            throw "status.memory missing field: $field"
        }
    }

    Write-Host "PASS test_webc_ui"
}
finally {
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
# 运行方式: cd bsp/pc && .\tests\ps1\test_webc_ui.ps1
