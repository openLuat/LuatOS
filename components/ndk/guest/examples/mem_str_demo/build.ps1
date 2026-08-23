#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
& "$PSScriptRoot\..\build_example.ps1" -ExampleName "mem_str_demo"
exit $LASTEXITCODE
