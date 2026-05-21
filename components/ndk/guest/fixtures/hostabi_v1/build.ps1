#!/usr/bin/env pwsh
# Build script for NDK Host ABI v1 guest fixtures (legacy + RV32C)

$ErrorActionPreference = "Stop"

$fixtureDir = $PSScriptRoot
$repoRoot = (Resolve-Path "$fixtureDir\..\..\..\..\..").Path
$outputDir = "$repoRoot\testcase\ndk\ndk_hostabi_basic\scripts"
$outputBin = "$outputDir\hostabi_v1.bin"
$outputBinRvc = "$outputDir\hostabi_v1_rvc.bin"

$compiler = $null
$objcopy = $null
$objdump = $null
$compilerArgs = @()
$compilerArgsRvc = @()

if (Get-Command riscv32-unknown-elf-gcc -ErrorAction SilentlyContinue) {
    $compiler = "riscv32-unknown-elf-gcc"
    $objcopy = "riscv32-unknown-elf-objcopy"
    $objdump = "riscv32-unknown-elf-objdump"
    $compilerArgs = @("-march=rv32ima_zicsr", "-mabi=ilp32", "-nostdlib", "-nostartfiles")
    $compilerArgsRvc = @("-march=rv32imac_zicsr", "-mabi=ilp32", "-nostdlib", "-nostartfiles")
    Write-Host "[build] Using riscv32-unknown-elf toolchain"
}
elseif (Get-Command riscv64-unknown-elf-gcc -ErrorAction SilentlyContinue) {
    $compiler = "riscv64-unknown-elf-gcc"
    $objcopy = "riscv64-unknown-elf-objcopy"
    $objdump = "riscv64-unknown-elf-objdump"
    $compilerArgs = @("-march=rv32ima_zicsr", "-mabi=ilp32", "-nostdlib", "-nostartfiles")
    $compilerArgsRvc = @("-march=rv32imac_zicsr", "-mabi=ilp32", "-nostdlib", "-nostartfiles")
    Write-Host "[build] Using riscv64-unknown-elf toolchain (32-bit mode)"
}
elseif (Get-Command clang -ErrorAction SilentlyContinue) {
    $compiler = "clang"
    $objcopy = "llvm-objcopy"
    $objdump = "llvm-objdump"
    $compilerArgs = @("--target=riscv32", "-march=rv32ima_zicsr", "-mabi=ilp32", "-nostdlib", "-Os", "-fno-builtin")
    $compilerArgsRvc = @("--target=riscv32", "-march=rv32imac_zicsr", "-mabi=ilp32", "-nostdlib", "-Os", "-fno-builtin")
    Write-Host "[build] Using LLVM clang toolchain"
}
elseif (Test-Path "C:\LLVM\bin\clang.exe") {
    $compiler = "C:\LLVM\bin\clang.exe"
    $objcopy = "C:\LLVM\bin\llvm-objcopy.exe"
    $objdump = "C:\LLVM\bin\llvm-objdump.exe"
    $compilerArgs = @("--target=riscv32", "-march=rv32ima_zicsr", "-mabi=ilp32", "-nostdlib", "-Os", "-fno-builtin")
    $compilerArgsRvc = @("--target=riscv32", "-march=rv32imac_zicsr", "-mabi=ilp32", "-nostdlib", "-Os", "-fno-builtin")
    Write-Host "[build] Using LLVM clang toolchain (C:\LLVM\bin)"
}
else {
    Write-Error "RISC-V toolchain not found. Install riscv32-unknown-elf-gcc, riscv64-unknown-elf-gcc, or LLVM clang"
    exit 1
}

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Write-Host "[build] Compiling legacy variant (rv32ima_zicsr)..."
$elfFile = "$fixtureDir\hostabi_v1.elf"
$allArgs = $compilerArgs + @(
    "-T", "$fixtureDir\linker.ld",
    "-o", $elfFile,
    "$fixtureDir\main.c",
    "$fixtureDir\ndk_stubs.c"
)
& $compiler $allArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Legacy compilation failed"
    exit 1
}

Write-Host "[build] Extracting legacy binary..."
& $objcopy -O binary $elfFile $outputBin
if ($LASTEXITCODE -ne 0) {
    Write-Error "Legacy binary extraction failed"
    exit 1
}
$size = (Get-Item $outputBin).Length
Write-Host "[build] Success: hostabi_v1.bin ($size bytes)"

Write-Host "[build] Compiling RV32C variant (rv32imac_zicsr)..."
$elfFileRvc = "$fixtureDir\hostabi_v1_rvc.elf"
$allArgsRvc = $compilerArgsRvc + @(
    "-T", "$fixtureDir\linker.ld",
    "-o", $elfFileRvc,
    "$fixtureDir\main.c",
    "$fixtureDir\ndk_stubs.c",
    "$fixtureDir\rvc_smoke.S"
)
& $compiler $allArgsRvc
if ($LASTEXITCODE -ne 0) {
    Write-Error "RV32C compilation failed"
    exit 1
}

Write-Host "[build] Verifying compressed instructions..."
$disasm = & $objdump -d -M no-aliases $elfFileRvc 2>&1 | Out-String
if ($disasm -notmatch '\bc\.') {
    Write-Error "RV32C binary does not contain compressed instructions (c. mnemonic not found in disassembly)"
    exit 1
}
$cInstructionCount = ([regex]::Matches($disasm, '\bc\.')).Count
Write-Host "[build] Verified: found $cInstructionCount c. mnemonic(s) in disassembly"

Write-Host "[build] Extracting RV32C binary..."
& $objcopy -O binary $elfFileRvc $outputBinRvc
if ($LASTEXITCODE -ne 0) {
    Write-Error "RV32C binary extraction failed"
    exit 1
}
$sizeRvc = (Get-Item $outputBinRvc).Length
Write-Host "[build] Success: hostabi_v1_rvc.bin ($sizeRvc bytes)"
Write-Host "[build] Output: $outputBin"
Write-Host "[build] Output: $outputBinRvc"

