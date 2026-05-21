#!/usr/bin/env pwsh
# Compatibility wrapper: forwards to canonical script under components/ndk/guest

$ErrorActionPreference = "Stop"
$script = Resolve-Path "$PSScriptRoot\..\..\..\..\components\ndk\guest\fixtures\rv32f_regression\build.ps1"
$scriptDir = Split-Path $script -Parent
Push-Location $scriptDir
try {
    & $script @args
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
