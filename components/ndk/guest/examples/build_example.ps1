#!/usr/bin/env pwsh

param(
    [string]$ExampleName
)

$ErrorActionPreference = "Stop"

function Test-Command {
    param([string]$CommandName)
    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

$root = $PSScriptRoot
$exampleDir = if ($ExampleName) { Join-Path $root $ExampleName } else { $PWD.Path }
$exampleDir = (Resolve-Path $exampleDir -ErrorAction Stop).Path

$source = Join-Path $exampleDir "main.c"
$linker = Join-Path $exampleDir "link.ld"
$buildDir = Join-Path $exampleDir "build"

# Include paths for luat_ndk_helper.h / luat_ndk_builtin.h / luat_ndk_abi.h.
# $root = $PSScriptRoot = components/ndk/guest/examples
# components/ndk/include        -> ABI + host API + builtin helpers
# components/ndk/guest/include  -> curated guest-side helper
$ndkInclude   = Join-Path $root "..\..\include"
$ndkGuestIncl = Join-Path $root "..\..\guest\include"
$ndkInclude   = (Resolve-Path $ndkInclude   -ErrorAction SilentlyContinue).Path
$ndkGuestIncl = (Resolve-Path $ndkGuestIncl -ErrorAction SilentlyContinue).Path
$includeArgs  = @()
if ($ndkInclude)   { $includeArgs += @("-I", $ndkInclude)   }
if ($ndkGuestIncl) { $includeArgs += @("-I", $ndkGuestIncl) }

if (-not (Test-Path $source)) {
    throw "Missing source file: $source"
}
if (-not (Test-Path $linker)) {
    throw "Missing linker script: $linker"
}
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

$stem = Split-Path $exampleDir -Leaf
$elf = Join-Path $buildDir "$stem.elf"
$bin = Join-Path $buildDir "$stem.bin"
$map = Join-Path $buildDir "$stem.map"

# We use LLVM clang only. The GNU RISC-V toolchain was removed in
# Phase 3 simplification — keeping only one toolchain removes the
# "which one is it" foot-gun (different -march defaults, different
# -mabi defaults, different C-extension handling).
$toolchains = @()
if ((Test-Command "clang") -and (Test-Command "llvm-objcopy") -and (Test-Command "ld.lld")) {
    $toolchains += @{
        Name = "LLVM clang"
        Cc = "clang"
        Objcopy = "llvm-objcopy"
        Args = @(
            "--target=riscv32-unknown-elf", "-fuse-ld=lld",
            "-march=rv32ima_zicsr", "-mabi=ilp32",
            "-ffreestanding", "-nostdlib", "-fno-stack-protector",
            "-fdata-sections", "-ffunction-sections", "-Os", "-mno-relax",
            "-Wl,-T,$linker", "-Wl,-Map,$map", "-Wl,--gc-sections", "-Wl,--no-relax"
        )
    }
}

if ($toolchains.Count -eq 0) {
    throw "No usable LLVM toolchain found. Need: clang, ld.lld, llvm-objcopy (LLVM with RISC-V target). See https://releases.llvm.org/ — Windows builds must enable the RISC-V backend."
}

foreach ($tc in $toolchains) {
    Write-Host "[build] Trying $($tc.Name)..."
    try {
        & $tc.Cc @($tc.Args + $includeArgs + @("-o", $elf, $source))
        if ($LASTEXITCODE -ne 0) {
            throw "compiler exited with $LASTEXITCODE"
        }
        & $tc.Objcopy -O binary $elf $bin
        if ($LASTEXITCODE -ne 0) {
            throw "objcopy exited with $LASTEXITCODE"
        }
        $size = (Get-Item $bin).Length
        Write-Host "[build] Success: $bin ($size bytes)"
        exit 0
    } catch {
        Write-Warning "[build] $($tc.Name) failed: $_"
    }
}

throw "All detected toolchains failed for example '$stem'. See compiler output above."

