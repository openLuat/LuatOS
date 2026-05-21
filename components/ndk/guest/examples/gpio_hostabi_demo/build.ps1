#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
& "$PSScriptRoot\..\build_example.ps1" -ExampleName "gpio_hostabi_demo"
exit $LASTEXITCODE

