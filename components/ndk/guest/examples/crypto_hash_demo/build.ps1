#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
& "$PSScriptRoot\..\build_example.ps1" -ExampleName "crypto_hash_demo"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$bin = Join-Path $PSScriptRoot "build\crypto_hash_demo.bin"
$target = Join-Path $PSScriptRoot "..\..\..\..\..\testcase\ndk\ndk_hostabi_basic\scripts\crypto_hash_demo.bin"
$targetDir = Split-Path $target -Parent
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}
Copy-Item -Path $bin -Destination $target -Force
Write-Host "[build] Synced crypto_hash_demo.bin to $target"
exit 0

