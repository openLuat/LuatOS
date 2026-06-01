param(
    [int]$Port = 18922
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
    $proc = Start-Process -FilePath $exe -ArgumentList @("--webc=$Port","--noexit") -PassThru -WindowStyle Hidden
    Wait-Ready -Port $Port

    $s0 = Get-Json "http://127.0.0.1:$Port/api/uart32/gnss"
    if (-not $s0.ok) { throw "gnss status should be ok" }
    if ($s0.mode -ne "fixed") { throw "default GNSS mode should be fixed" }

    $fixedBody = @{
        mode = "fixed"
        running = $true
        fixed = @{
            lat = 39.9070
            lon = 116.3910
            speed_knots = 0.5
            course = 15
        }
    } | ConvertTo-Json -Compress
    Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/uart32/gnss/config" -Method Post -ContentType "application/json" -Body $fixedBody -UseBasicParsing | Out-Null
    Start-Sleep -Milliseconds 1200
    $s1 = Get-Json "http://127.0.0.1:$Port/api/uart32/gnss"
    if ($s1.mode -ne "fixed") { throw "mode should switch to fixed" }
    if (-not ($s1.emit_count -ge 1)) { throw "fixed mode should emit NMEA" }
    if ($s1.last_nmea -notmatch '^\$GPRMC,') { throw "last_nmea should be GPRMC" }
    if ($s1.last_nmea -notmatch '\*[0-9A-F]{2}$') { throw "last_nmea should include checksum" }

    $kml = '<kml><Document><Placemark><LineString><coordinates>116.391,39.907,0 116.392,39.908,0</coordinates></LineString></Placemark></Document></kml>'
    $kmlBody = @{
        mode = "kml"
        running = $true
        source_text = $kml
    } | ConvertTo-Json -Compress
    Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/uart32/gnss/config" -Method Post -ContentType "application/json" -Body $kmlBody -UseBasicParsing | Out-Null
    $s2 = Get-Json "http://127.0.0.1:$Port/api/uart32/gnss"
    if ($s2.mode -ne "kml") { throw "mode should switch to kml" }
    if ($s2.total_points -ne 2) { throw "kml LineString should parse 2 points" }
    if (-not ($s2.running -eq $true)) { throw "running should remain true" }

    $fileBody = @{
        mode = "file"
        running = $true
        source_text = "39.909,116.393`n39.910,116.394"
    } | ConvertTo-Json -Compress
    Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/uart32/gnss/config" -Method Post -ContentType "application/json" -Body $fileBody -UseBasicParsing | Out-Null
    $s3 = Get-Json "http://127.0.0.1:$Port/api/uart32/gnss"
    if ($s3.mode -ne "file") { throw "mode should switch to file" }
    if ($s3.total_points -ne 2) { throw "file import should parse 2 points" }

    $badStatus = Post-Json-WithStatus -Url "http://127.0.0.1:$Port/api/uart32/gnss/config" -Body @{
        mode = "fixed"
        fixed = @{
            lon = 116.3910
        }
    }
    if ($badStatus -ne 400) { throw "missing fixed.lat should return 400, got $badStatus" }

    Write-Host "PASS test_webc_uart32_gnss"
}
finally {
    if ($proc -and -not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force
    }
}
# 运行方式: cd bsp/pc && .\tests\ps1\test_webc_uart32_gnss.ps1
