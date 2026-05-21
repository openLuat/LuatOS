#!/usr/bin/env pwsh
# Compatibility wrapper: forwards to canonical script under components/ndk/guest

$ErrorActionPreference = "Stop"
$script = Resolve-Path "$PSScriptRoot\..\..\..\components\ndk\guest\build_hostabi_v1.ps1"
& $script @args
exit $LASTEXITCODE
