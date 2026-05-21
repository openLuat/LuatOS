#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
& "$PSScriptRoot\..\build_example.ps1" -ExampleName "exchange_buffer_demo"
exit $LASTEXITCODE

