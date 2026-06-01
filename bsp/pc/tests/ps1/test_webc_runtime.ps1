param(
    [int]$Port = 18921
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
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

$proc = $null
$pcconfPath = Join-Path $PSScriptRoot "pcconf\pcconf.json"
$pcconfOriginal = $null

try {
    $pcconfOriginal = Get-Content $pcconfPath -Raw

    $proc = Start-Process -FilePath $exe -ArgumentList @("--webc=$Port", "--noexit") -PassThru -WindowStyle Hidden
    Wait-Ready -Port $Port

    $health = Get-Json "http://127.0.0.1:$Port/api/health"
    if (-not $health.ok) { throw "health.ok expected true" }
    if ($health.service -ne "web-runtime-core") { throw "unexpected service value: $($health.service)" }

    $status = Get-Json "http://127.0.0.1:$Port/api/status"
    if (-not ($status.port -eq $Port)) { throw "status.port should be $Port" }
    if (-not ($status.cadence_sec -in 1,5,15)) { throw "status.cadence_sec invalid" }
    if (-not ($status.history_count -ge 1)) { throw "status.history_count missing" }
    if (-not $status.memory) { throw "status.memory missing" }

    $cfg0 = Get-Json "http://127.0.0.1:$Port/api/config"
    if (-not $cfg0.web_console) { throw "config.web_console missing" }
    if (-not $cfg0.network) { throw "config.network missing" }
    if (-not $cfg0.storage) { throw "config.storage missing" }
    if (-not $cfg0.storage.effective) { throw "config.storage.effective missing" }
    if ([int]$cfg0.web_console.effective_port -ne $Port) {
        throw "effective_port should be $Port"
    }

    $originalWeb = @{
        enabled = [int]$cfg0.web_console.enabled
        port = [int]$cfg0.web_console.port
        refresh_interval = [int]$cfg0.web_console.refresh_interval
    }
    $originalNetworkEnabled = [int]$cfg0.network.enabled
    $originalStorage = @{
        tf_enabled = [int]$cfg0.storage.tf_enabled
        nor_enabled = [int]$cfg0.storage.nor_enabled
        nand_enabled = [int]$cfg0.storage.nand_enabled
        tf_capacity_mb = [int]$cfg0.storage.tf_capacity_mb
        nor_capacity_mb = [int]$cfg0.storage.nor_capacity_mb
        nand_capacity_mb = [int]$cfg0.storage.nand_capacity_mb
        nor_model = [string]$cfg0.storage.nor_model
        nand_model = [string]$cfg0.storage.nand_model
    }

    $toggleNetworkEnabled = if ($originalNetworkEnabled -eq 0) { 1 } else { 0 }
    $toggleStorage = @{
        tf_enabled = if ($originalStorage.tf_enabled -eq 0) { 1 } else { 0 }
        nor_enabled = if ($originalStorage.nor_enabled -eq 0) { 1 } else { 0 }
        nand_enabled = if ($originalStorage.nand_enabled -eq 0) { 1 } else { 0 }
        tf_capacity_mb = if ($originalStorage.tf_capacity_mb -eq 64) { 32 } else { 64 }
        nor_capacity_mb = if ($originalStorage.nor_capacity_mb -eq 16) { 8 } else { 16 }
        nand_capacity_mb = if ($originalStorage.nand_capacity_mb -eq 128) { 64 } else { 128 }
        nor_model = "w25q128"
        nand_model = "w25n01gv"
    }

    $bodyNet = @{
        network = @{ enabled = $toggleNetworkEnabled }
        storage = $toggleStorage
        web_console = @{ refresh_interval = 1 }
    } | ConvertTo-Json -Compress
    $resp = (Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/config" -Method Post -ContentType "application/json" -Body $bodyNet -TimeoutSec 3 -UseBasicParsing).Content | ConvertFrom-Json
    if (-not $resp.ok) { throw "POST /api/config should return ok=true" }

    $cfg1 = Get-Json "http://127.0.0.1:$Port/api/config"
    if ([int]$cfg1.network.enabled -ne $toggleNetworkEnabled) {
        throw "network.enabled should be $toggleNetworkEnabled after POST"
    }
    if ([int]$cfg1.web_console.refresh_interval -ne 1) {
        throw "refresh_interval should be 1 after POST"
    }
    if ([int]$cfg1.web_console.effective_refresh_interval -ne 1) {
        throw "effective_refresh_interval should be 1 after POST"
    }
    if ([int]$cfg1.storage.tf_enabled -ne $toggleStorage.tf_enabled -or
        [int]$cfg1.storage.nor_enabled -ne $toggleStorage.nor_enabled -or
        [int]$cfg1.storage.nand_enabled -ne $toggleStorage.nand_enabled) {
        throw "storage toggle values not applied"
    }
    if ([int]$cfg1.storage.effective.tf_enabled -ne $toggleStorage.tf_enabled -or
        [int]$cfg1.storage.effective.nor_enabled -ne $toggleStorage.nor_enabled -or
        [int]$cfg1.storage.effective.nand_enabled -ne $toggleStorage.nand_enabled) {
        throw "storage effective toggle values not applied"
    }

    $diskCfg = Get-Content $pcconfPath -Raw | ConvertFrom-Json
    if ([int]$diskCfg.network.enabled -ne $toggleNetworkEnabled) {
        throw "pcconf.json network.enabled was not persisted"
    }
    if ([int]$diskCfg.web_console.refresh_interval -ne 1) {
        throw "pcconf.json refresh_interval was not persisted"
    }
    if ([int]$diskCfg.storage.tf_enabled -ne $toggleStorage.tf_enabled -or
        [int]$diskCfg.storage.nor_enabled -ne $toggleStorage.nor_enabled -or
        [int]$diskCfg.storage.nand_enabled -ne $toggleStorage.nand_enabled) {
        throw "pcconf.json storage toggles were not persisted"
    }

    $bodyRestore = @{
        web_console = $originalWeb
        network = @{ enabled = $originalNetworkEnabled }
        storage = $originalStorage
    } | ConvertTo-Json -Compress
    Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/config" -Method Post -ContentType "application/json" -Body $bodyRestore -TimeoutSec 3 -UseBasicParsing | Out-Null

    $cfgRestore = Get-Json "http://127.0.0.1:$Port/api/config"
    if ([int]$cfgRestore.network.enabled -ne $originalNetworkEnabled) {
        throw "network.enabled should restore to original value"
    }
    if ([int]$cfgRestore.web_console.refresh_interval -ne $originalWeb.refresh_interval) {
        throw "refresh_interval should restore to original value"
    }

    $invalidBody = @{ web_console = @{ refresh_interval = 2 } } | ConvertTo-Json -Compress
    try {
        Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/config" -Method Post -ContentType "application/json" -Body $invalidBody -TimeoutSec 3 -UseBasicParsing | Out-Null
        throw "invalid refresh interval should fail"
    } catch {
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -ne 400) {
            throw
        }
    }

    $body1 = @{ web_console = @{ refresh_interval = 1 } } | ConvertTo-Json -Compress
    Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/config" -Method Post -ContentType "application/json" -Body $body1 -UseBasicParsing | Out-Null
    $cfg1b = Get-Json "http://127.0.0.1:$Port/api/config"
    if ($cfg1b.web_console.effective_refresh_interval -ne 1) {
        throw "refresh_interval should be 1 after POST"
    }

    $t1 = Get-Json "http://127.0.0.1:$Port/api/telemetry"
    $c1 = @($t1.history).Count
    Start-Sleep -Seconds 3
    $t2 = Get-Json "http://127.0.0.1:$Port/api/telemetry"
    $c2 = @($t2.history).Count
    if ($c2 -lt ($c1 + 2)) {
        throw "cadence=1s expected >=2 new points, got $c1->$c2"
    }

    $body5 = @{ web_console = @{ refresh_interval = 5 } } | ConvertTo-Json -Compress
    Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/config" -Method Post -ContentType "application/json" -Body $body5 -UseBasicParsing | Out-Null
    $t3 = Get-Json "http://127.0.0.1:$Port/api/telemetry"
    $c3 = @($t3.history).Count
    Start-Sleep -Seconds 2
    $t4 = Get-Json "http://127.0.0.1:$Port/api/telemetry"
    $c4 = @($t4.history).Count
    if ($c4 -gt ($c3 + 1)) {
        throw "cadence=5s expected <=1 new point in 2s, got $c3->$c4"
    }

    $req = [System.Net.HttpWebRequest]::Create("http://127.0.0.1:$Port/api/events")
    $req.Method = "GET"
    $req.Timeout = 3000
    $req.ReadWriteTimeout = 3000
    $res = $req.GetResponse()
    $stream = $res.GetResponseStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $eventBlock = $reader.ReadLine() + "`n" + $reader.ReadLine()
    $reader.Close()
    $res.Close()
    if ($eventBlock -notmatch "event:\s*telemetry") {
        throw "SSE telemetry event not received"
    }

    Write-Host "PASS test_webc_runtime"
}
finally {
    if ($pcconfOriginal -ne $null) {
        [System.IO.File]::WriteAllText($pcconfPath, $pcconfOriginal, (New-Object System.Text.UTF8Encoding($false)))
    }
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
# 运行方式: cd bsp/pc && .\tests\ps1\test_webc_runtime.ps1
