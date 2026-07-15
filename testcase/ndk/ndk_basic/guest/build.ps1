#!/usr/bin/env pwsh
# Build script for the canonical ndk_basic baremetal guest (RV32IMA only).
# Phase 3+: LLVM clang+ld.lld+llvm-objcopy only.

$ErrorActionPreference = "Stop"

$Source = "main.c"
$LinkerScript = "link.ld"
$BuildDir = "build"
$Stem = "baremetal"
$SyncTargets = @(
    "..\scripts\baremetal.bin",
    "..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin"
)

function Test-Command {
    param([string]$Command)
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

if (-not ((Test-Command "clang") -and (Test-Command "ld.lld") -and (Test-Command "llvm-objcopy"))) {
    Write-Host "`n=== ERROR: LLVM toolchain not found ===" -ForegroundColor Red
    Write-Host "Need: clang, ld.lld, llvm-objcopy (LLVM with RISC-V target, >= 16.0)" -ForegroundColor Yellow
    Write-Host "Get a prebuilt LLVM from https://releases.llvm.org/ and add bin/ to PATH." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $Source)) {
    throw "Error: $Source not found. Please run this script from the guest directory."
}
if (-not (Test-Path $LinkerScript)) {
    throw "Error: $LinkerScript not found. Please run this script from the guest directory."
}

if (-not (Test-Path $BuildDir)) {
    New-Item -ItemType Directory -Path $BuildDir | Out-Null
}

$ElfOutput = "$BuildDir\$Stem.elf"
$BinOutput = "$BuildDir\$Stem.bin"
$MapOutput = "$BuildDir\$Stem.map"

Write-Host "=== Building RISC-V Baremetal Guest Fixtures ===" -ForegroundColor Cyan
Write-Host "Using LLVM/Clang toolchain ($Source -> $Stem.bin)" -ForegroundColor Yellow

$clang_args = @(
    "--target=riscv32-unknown-elf",
    "-fuse-ld=lld",
    "-fno-stack-protector",
    "-fdata-sections",
    "-ffunction-sections",
    "-g",
    "-Os",
    "-march=rv32ima_zicsr",
    "-mabi=ilp32",
    "-mno-relax",
    "-static",
    "-T", $LinkerScript,
    "-nostdlib",
    "-Wl,--no-relax",
    "-Wl,--gc-sections",
    "-Wl,-Map=$MapOutput",
    "-o", $ElfOutput,
    $Source
)

Write-Host "Compiling: clang $($clang_args -join ' ')"
& clang $clang_args
if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE"
}

Write-Host "Extracting binary: llvm-objcopy -O binary $ElfOutput $BinOutput"
& llvm-objcopy -O binary $ElfOutput $BinOutput
if ($LASTEXITCODE -ne 0) {
    throw "Binary extraction failed with exit code $LASTEXITCODE"
}

$bin_size = (Get-Item $BinOutput).Length
Write-Host "`n=== Build successful: $Stem ===" -ForegroundColor Green
Write-Host "  ELF: $ElfOutput"
Write-Host "  BIN: $BinOutput ($bin_size bytes)"
Write-Host "  MAP: $MapOutput"

Write-Host "`n=== Syncing $Stem.bin to target locations ===" -ForegroundColor Cyan
foreach ($target in $SyncTargets) {
    $target_dir = Split-Path $target -Parent
    if (-not (Test-Path $target_dir)) {
        New-Item -ItemType Directory -Path $target_dir -Force | Out-Null
    }
    $target_abs = (Resolve-Path $target_dir).Path + "\" + (Split-Path $target -Leaf)
    Write-Host "  Copying to: $target_abs"
    Copy-Item -Path $BinOutput -Destination $target_abs -Force
}

Write-Host "`n=== All done! ===" -ForegroundColor Green
Write-Host "Guest binary rebuilt and synced successfully."
exit 0
