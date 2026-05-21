#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
& "$PSScriptRoot\..\build_example.ps1" -ExampleName "hello_world"
exit $LASTEXITCODE

