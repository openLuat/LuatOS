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

$toolchains = @()
if ((Test-Command "riscv64-unknown-elf-gcc") -and (Test-Command "riscv64-unknown-elf-objcopy")) {
    $toolchains += @{
        Name = "GNU riscv64-unknown-elf"
        Cc = "riscv64-unknown-elf-gcc"
        Objcopy = "riscv64-unknown-elf-objcopy"
        Args = @(
            "-march=rv32ima_zicsr", "-mabi=ilp32",
            "-ffreestanding", "-nostdlib", "-fno-stack-protector",
            "-fdata-sections", "-ffunction-sections", "-Os",
            "-Wl,-T,$linker", "-Wl,-Map,$map", "-Wl,--gc-sections"
        )
    }
}
if ((Test-Command "riscv32-unknown-elf-gcc") -and (Test-Command "riscv32-unknown-elf-objcopy")) {
    $toolchains += @{
        Name = "GNU riscv32-unknown-elf"
        Cc = "riscv32-unknown-elf-gcc"
        Objcopy = "riscv32-unknown-elf-objcopy"
        Args = @(
            "-march=rv32ima_zicsr", "-mabi=ilp32",
            "-ffreestanding", "-nostdlib", "-fno-stack-protector",
            "-fdata-sections", "-ffunction-sections", "-Os",
            "-Wl,-T,$linker", "-Wl,-Map,$map", "-Wl,--gc-sections"
        )
    }
}
if ((Test-Command "riscv-none-elf-gcc") -and (Test-Command "riscv-none-elf-objcopy")) {
    $toolchains += @{
        Name = "GNU riscv-none-elf"
        Cc = "riscv-none-elf-gcc"
        Objcopy = "riscv-none-elf-objcopy"
        Args = @(
            "-march=rv32ima_zicsr", "-mabi=ilp32",
            "-ffreestanding", "-nostdlib", "-fno-stack-protector",
            "-fdata-sections", "-ffunction-sections", "-Os",
            "-Wl,-T,$linker", "-Wl,-Map,$map", "-Wl,--gc-sections"
        )
    }
}
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
    throw "No usable RISC-V toolchain found. Install one of: riscv64-unknown-elf-gcc, riscv32-unknown-elf-gcc, riscv-none-elf-gcc, or clang+ld.lld+llvm-objcopy."
}

foreach ($tc in $toolchains) {
    Write-Host "[build] Trying $($tc.Name)..."
    try {
        & $tc.Cc @($tc.Args + @("-o", $elf, $source))
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

