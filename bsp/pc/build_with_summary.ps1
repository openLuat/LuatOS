param(
    [ValidateSet("x86", "i386", "armv6")]
    [string]$Arch = "x86",

    [ValidateSet("0", "1")]
    [string]$Vm64 = "1",

    [ValidateSet("y", "n")]
    [string]$Gui = "n",

    [ValidateSet("y", "n")]
    [string]$Mgba = "n",

    [ValidateSet("summary", "full")]
    [string]$Mode = $(if ($env:LUAT_BUILD_MODE) { $env:LUAT_BUILD_MODE } else { "summary" }),

    [string]$Platform = "windows",

    [string]$Toolchain = "msvc",

    [switch]$Clean,

    [switch]$SkipPkgSearchDir,

    [string]$ConfigureMode
)

$ErrorActionPreference = "Stop"

$logDir = Join-Path $PSScriptRoot "build\logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $logDir ("pc_build_{0}.log" -f $timestamp)

$noisePatterns = @(
    "components\airui\lvgl9\",
    "components/airui/lvgl9/",
    "components\mbedtls\",
    "components/mbedtls/",
    "components\mbedtls3\",
    "components/mbedtls3/",
    "components\network\lwip22\",
    "components/network/lwip22/",
    "components\multimedia\amr_decode\",
    "components/multimedia/amr_decode/",
    "components\multimedia\opus\",
    "components/multimedia/opus/",
    "components\fatfs\",
    "components/fatfs/",
    "components\lfs\",
    "components/lfs/",
    "components\iconv\",
    "components/iconv/",
    "windows kits\",
    "windows kits/",
    "lua\src\",
    "lua/src/"
)

function Write-Section {
    param([string]$Message)
    Write-Host "[pc-build] $Message"
}

function Test-IsWarning {
    param([string]$Line)
    return $Line -match '(?i)(: warning [a-z]*\d+)|(\bwarning\b:)'
}

function Test-IsError {
    param([string]$Line)
    return $Line -match '(?i)(: error [a-z]*\d+)|(\bfatal error\b)|(\berror\b:)|(undefined reference)|(collect2: error)|(ninja: build stopped)|(LINK : fatal error)|(LNK\d+)'
}

function Test-IsNoiseWarning {
    param([string]$Line)

    $normalized = $Line.ToLowerInvariant()
    foreach ($pattern in $noisePatterns) {
        if ($normalized.Contains($pattern.ToLowerInvariant())) {
            return $true
        }
    }
    return $false
}

function Get-WarningCode {
    param([string]$Line)

    $match = [regex]::Match($Line, '(?i)warning\s+([A-Z]+\d+)')
    if ($match.Success) {
        return $match.Groups[1].Value.ToUpperInvariant()
    }
    return "UNKNOWN"
}

function Get-WarningArea {
    param([string]$Line)

    $normalized = $Line.ToLowerInvariant().Replace('/', '\')
    if ($normalized.Contains("windows kits\") -or $normalized.Contains("microsoft visual studio\") -or $normalized.Contains("program files\")) {
        return "system"
    }
    if ($normalized.Contains("\bsp\pc\") -or $normalized.StartsWith("src\") -or $normalized.StartsWith("port\") -or $normalized.StartsWith("win32\") -or $normalized.StartsWith("include\") -or $normalized.StartsWith("ui\")) {
        return "bsp/pc"
    }
    if ($normalized.Contains("\luat\")) {
        return "luat"
    }
    if ($normalized.Contains("\lua\")) {
        return "lua"
    }
    if ($normalized.Contains("\components\")) {
        return "components"
    }
    return "other"
}

function Format-TopSummary {
    param(
        [string[]]$Lines,
        [scriptblock]$KeySelector,
        [int]$Limit = 8
    )

    $counts = @{}
    foreach ($line in $Lines) {
        $key = & $KeySelector $line
        if (-not $counts.ContainsKey($key)) {
            $counts[$key] = 0
        }
        $counts[$key] += 1
    }

    $items = $counts.GetEnumerator() |
        Sort-Object -Property @{Expression = 'Value'; Descending = $true}, @{Expression = 'Name'; Descending = $false} |
        Select-Object -First $Limit |
        ForEach-Object { "{0} x{1}" -f $_.Name, $_.Value }

    return ($items -join ', ')
}

function Show-CommandOutput {
    param(
        [string[]]$Lines,
        [string]$Step,
        [int]$ExitCode
    )

    if ($Mode -eq "full") {
        foreach ($line in $Lines) {
            Write-Host $line
        }
        return
    }

    $coreWarnings = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]
    $noiseWarningCount = 0

    foreach ($line in $Lines) {
        if (Test-IsError $line) {
            $errors.Add($line)
            continue
        }

        if (Test-IsWarning $line) {
            if (Test-IsNoiseWarning $line) {
                $noiseWarningCount += 1
            }
            else {
                $coreWarnings.Add($line)
            }
        }
    }

    if ($errors.Count -gt 0) {
        Write-Section "$Step failed with $($errors.Count) error line(s)"
        foreach ($line in $errors) {
            Write-Host $line
        }
    }
    elseif ($coreWarnings.Count -gt 0) {
        Write-Section "$Step emitted $($coreWarnings.Count) visible warning line(s)"
        $codeSummary = Format-TopSummary -Lines $coreWarnings -KeySelector ${function:Get-WarningCode}
        if ($codeSummary) {
            Write-Section "$Step warning codes: $codeSummary"
        }

        $areaSummary = Format-TopSummary -Lines $coreWarnings -KeySelector ${function:Get-WarningArea} -Limit 5
        if ($areaSummary) {
            Write-Section "$Step warning areas: $areaSummary"
        }

        $sampleLines = @($coreWarnings | Select-Object -First 12)
        Write-Section "$Step sample warnings (up to 12 lines)"
        foreach ($line in $sampleLines) {
            Write-Host $line
        }
        if ($coreWarnings.Count -gt $sampleLines.Count) {
            Write-Section "$Step omitted $($coreWarnings.Count - $sampleLines.Count) additional visible warning line(s); see $logPath"
        }
    }
    else {
        Write-Section "$Step completed without visible warnings"
    }

    if ($noiseWarningCount -gt 0) {
        Write-Section "$Step suppressed $noiseWarningCount third-party warning line(s); see $logPath"
    }

    if ($ExitCode -ne 0 -and $errors.Count -eq 0) {
        Write-Section "$Step failed; check full log: $logPath"
    }
}

function Invoke-XmakeStep {
    param(
        [string]$Step,
        [string[]]$Arguments
    )

    Write-Section ("{0}: xmake {1}" -f $Step, ($Arguments -join ' '))
    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        & xmake @Arguments *> $tmpFile
        $exitCode = $LASTEXITCODE
        $lines = @()
        if (Test-Path $tmpFile) {
            $lines = Get-Content -Path $tmpFile
        }

        Add-Content -Path $logPath -Value ("=== {0}: xmake {1} ===" -f $Step, ($Arguments -join ' '))
        if ($lines.Count -gt 0) {
            Add-Content -Path $logPath -Value $lines
        }

        Show-CommandOutput -Lines $lines -Step $Step -ExitCode $exitCode
        if ($exitCode -ne 0) {
            exit $exitCode
        }
    }
    finally {
        Remove-Item -Path $tmpFile -ErrorAction SilentlyContinue
    }
}

Push-Location $PSScriptRoot
try {
    Write-Section "mode=$Mode clean=$($Clean.IsPresent) arch=$Arch vm64=$Vm64 gui=$Gui mgba=$Mgba"
    Write-Section "full log: $logPath"

    $env:VM_64bit = $Vm64
    $env:LUAT_USE_GUI = $Gui
    if ($Mgba -eq "y") {
        $env:LUAT_USE_MGBA = "y"
    }
    else {
        Remove-Item Env:LUAT_USE_MGBA -ErrorAction SilentlyContinue
    }

    Invoke-XmakeStep -Step "theme" -Arguments @("g", "--theme=plain")

    if ($Clean.IsPresent -or $env:LUAT_BUILD_CLEAN -eq "1") {
        Invoke-XmakeStep -Step "clean" -Arguments @("clean", "-a")
    }

    $configureArgs = @("f", "-a", $Arch, "-y", "-p", $Platform)
    if ($Toolchain) {
        $configureArgs += "--toolchain=$Toolchain"
    }
    if ($ConfigureMode) {
        $configureArgs += @("-m", $ConfigureMode)
    }
    Invoke-XmakeStep -Step "configure" -Arguments $configureArgs

    if (-not $SkipPkgSearchDir.IsPresent) {
        Invoke-XmakeStep -Step "pkg searchdir" -Arguments @("g", "--pkg_searchdirs=$PSScriptRoot\pkgs")
    }

    Invoke-XmakeStep -Step "build" -Arguments @("-y")
    Write-Section "Build completed successfully"
}
finally {
    Pop-Location
}