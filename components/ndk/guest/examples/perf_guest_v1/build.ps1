#!/usr/bin/env pwsh
#
# build.ps1 — compile the perf-guest-v1 example and copy the resulting
# flat binary to testcase/ndk/ndk_perf_guest/scripts/.
#
# The toolchain is LLVM clang + lld + llvm-objcopy (RISC-V target).
# See components/ndk/guest/examples/build_example.ps1 for the canonical
# args; we duplicate the relevant pieces inline because we need to
# compile several .c files under algos/ rather than just main.c.

$ErrorActionPreference = "Stop"

$exampleDir = $PSScriptRoot
$root       = (Resolve-Path "$exampleDir\..\..").Path
$outputDir  = (Resolve-Path "$root\..\..\testcase\ndk\ndk_perf_guest\scripts" -ErrorAction SilentlyContinue).Path
if (-not $outputDir) {
    $outputDir = "$root\..\..\testcase\ndk\ndk_perf_guest\scripts"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$outputBin = Join-Path $outputDir "perf_guest_v1.bin"

$ndkInclude   = (Resolve-Path "$root\include" -ErrorAction SilentlyContinue).Path
$ndkGuestIncl = (Resolve-Path "$root\guest\include" -ErrorAction SilentlyContinue).Path
$includeArgs  = @()
if ($ndkInclude)   { $includeArgs += @("-I", $ndkInclude) }
if ($ndkGuestIncl) { $includeArgs += @("-I", $ndkGuestIncl) }

$linker = Join-Path $exampleDir "link.ld"
$buildDir = Join-Path $exampleDir "build"
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}
$elf = Join-Path $buildDir "perf_guest_v1.elf"
$map = Join-Path $buildDir "perf_guest_v1.map"
$bin = Join-Path $buildDir "perf_guest_v1.bin"

function Test-Command {
    param([string]$CommandName)
    return [bool](Get-Command $CommandName -ErrorAction SilentlyContinue)
}

if (-not (Test-Command "clang") -or -not (Test-Command "llvm-objcopy") -or -not (Test-Command "ld.lld")) {
    throw "LLVM toolchain not in PATH. Need: clang, ld.lld, llvm-objcopy (RISC-V enabled)."
}

# Collect sources: main.c + every .c under algos/
$sources = @()
$sources += Join-Path $exampleDir "main.c"
$algosDir = Join-Path $exampleDir "algos"
if (Test-Path $algosDir) {
    $sources += @(Get-ChildItem -Path $algosDir -Filter "*.c" | ForEach-Object { $_.FullName })
}

Write-Host "[build] Sources:"
foreach ($s in $sources) { Write-Host "  $s" }

Write-Host "[build] Compiling perf_guest_v1.elf (rv32ima_zicsr)..."
& clang `
    --target=riscv32-unknown-elf `
    -fuse-ld=lld `
    -march=rv32ima_zicsr -mabi=ilp32 `
    -ffreestanding -nostdlib -fno-stack-protector `
    -fdata-sections -ffunction-sections `
    -Os -mno-relax `
    -Wl,-T,$linker -Wl,-Map,$map -Wl,--gc-sections -Wl,--no-relax `
    @includeArgs `
    -o $elf `
    @sources
if ($LASTEXITCODE -ne 0) { throw "clang exited with $LASTEXITCODE" }

Write-Host "[build] Extracting perf_guest_v1.bin..."
& llvm-objcopy -O binary $elf $bin
if ($LASTEXITCODE -ne 0) { throw "llvm-objcopy exited with $LASTEXITCODE" }

$size = (Get-Item $bin).Length
Write-Host "[build] Success: $bin ($size bytes)"

Write-Host "[build] Copying to $outputBin ..."
Copy-Item -Path $bin -Destination $outputBin -Force
Write-Host "[build] Installed: $outputBin"
