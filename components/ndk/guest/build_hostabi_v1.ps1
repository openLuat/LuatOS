#!/usr/bin/env pwsh
# Canonical hostabi v1 entrypoint under components/ndk/guest

$ErrorActionPreference = "Stop"
$script = "$PSScriptRoot\fixtures\hostabi_v1\build.ps1"
if (-not (Test-Path $script)) {
    throw "Canonical script not found: $script"
}
& $script @args
exit $LASTEXITCODE
