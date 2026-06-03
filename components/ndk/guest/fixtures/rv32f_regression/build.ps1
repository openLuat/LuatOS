#!/usr/bin/env pwsh
# Build script for RISC-V baremetal guest firmware.
# Phase 3+: LLVM clang+ld.lld+llvm-objcopy only (GNU toolchain removed).

$ErrorActionPreference = "Stop"

# === Configuration ===
$LINKER_SCRIPT = "link.ld"
$BUILD_DIR = "build"
$artifacts = @(
    @{
        Source = "main.c"
        Stem = "baremetal"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal.bin",
            "..\..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin"
        )
    },
    @{
        Source = "fcsr_reset.c"
        Stem = "baremetal_fcsr"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fcsr.bin"
        )
    },
    @{
        Source = "fmv_roundtrip.S"
        Stem = "baremetal_fmv"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fmv.bin"
        )
    },
    @{
        Source = "flwfsw_roundtrip.S"
        Stem = "baremetal_flwfsw"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_flwfsw.bin"
        )
    },
    @{
        Source = "fadd_simple.S"
        Stem = "baremetal_fadd"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fadd.bin"
        )
    },
    @{
        Source = "fadd_first.S"
        Stem = "baremetal_fadd_first"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fadd_first.bin"
        )
    },
    @{
        Source = "fadd_rounding.S"
        Stem = "baremetal_fadd_rounding"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fadd_rounding.bin"
        )
    },
    @{
        Source = "fadd_rmm_static.S"
        Stem = "baremetal_fadd_rmm_static"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fadd_rmm_static.bin"
        )
    },
    @{
        Source = "fadd_rmm_dynamic.S"
        Stem = "baremetal_fadd_rmm_dynamic"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fadd_rmm_dynamic.bin"
        )
    },
    @{
        Source = "fcmp_nan_flags.S"
        Stem = "baremetal_fcmp"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fcmp.bin"
        )
    },
    @{
        Source = "fclass_bits.S"
        Stem = "baremetal_fclass"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fclass.bin"
        )
    },
    @{
        Source = "fcvt_sw_bits.S"
        Stem = "baremetal_fcvtsw"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fcvtsw.bin"
        )
    },
    @{
        Source = "fsubmul_smoke.S"
        Stem = "baremetal_fsubmul"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fsubmul.bin"
        )
    },
    @{
        Source = "fsgnj_bits.S"
        Stem = "baremetal_fsgnj"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fsgnj.bin"
        )
    },
    @{
        Source = "fcvt_dyn_rup.S"
        Stem = "baremetal_fcvt_dyn_rup"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fcvt_dyn_rup.bin"
        )
    },
    @{
        Source = "fbinop_nan_bits.S"
        Stem = "baremetal_fbinop_nan"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fbinop_nan.bin"
        )
    },
    @{
        Source = "fcvt_ws_invalid.S"
        Stem = "baremetal_fcvt_ws_invalid"
        March = "rv32imf_zicsr"
        Mabi = "ilp32f"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_fcvt_ws_invalid.bin"
        )
    },
    @{
        Source = "hardfloat_mulsub.c"
        Stem = "baremetal_hardfloat_mulsub"
        March = "rv32imf_zicsr"
        Mabi = "ilp32f"
        CFlags = @(
            "-ffp-contract=off"
        )
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_hardfloat_mulsub.bin"
        )
    },
    @{
        Source = "hardfloat_cast.c"
        Stem = "baremetal_hardfloat_cast"
        March = "rv32imf_zicsr"
        Mabi = "ilp32f"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_hardfloat_cast.bin"
        )
    },
    @{
        Source = "hardfloat_fmadd.c"
        Stem = "baremetal_hardfloat_fmadd"
        March = "rv32imf_zicsr"
        Mabi = "ilp32f"
        CFlags = @(
            "-ffp-contract=fast"
        )
        ExpectedDisassemblyPattern = "(?m)^\s*[0-9a-f]+:\s+.*\bfmadd\.s\b"
        ExpectedDisassemblyMessage = "compiler-emitted fmadd.s"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_hardfloat_fmadd.bin"
        )
    },
    @{
        Source = "hardfloat_fmsub.c"
        Stem = "baremetal_hardfloat_fmsub"
        March = "rv32imf_zicsr"
        Mabi = "ilp32f"
        CFlags = @(
            "-ffp-contract=fast"
        )
        ExpectedDisassemblyPattern = "(?m)^\s*[0-9a-f]+:\s+.*\bfmsub\.s\b"
        ExpectedDisassemblyMessage = "compiler-emitted fmsub.s"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_hardfloat_fmsub.bin"
        )
    },
    @{
        Source = "hardfloat_fnm_probe.c"
        Stem = "baremetal_hfnm"
        March = "rv32imf_zicsr"
        Mabi = "ilp32f"
        CFlags = @(
            "-ffp-contract=fast"
        )
        ExpectedDisassemblyPattern = "(?s)(?=.*\bfnmsub\.s\b)(?=.*\bfnmadd\.s\b)"
        ExpectedDisassemblyMessage = "compiler-emitted fnmsub.s/fnmadd.s"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_hfnm.bin"
        )
    },
    @{
        Source = "hardfloat_div.c"
        Stem = "baremetal_hardfloat_div"
        March = "rv32imf_zicsr"
        Mabi = "ilp32f"
        ExpectedDisassemblyPattern = "(?m)^\s*[0-9a-f]+:\s+.*\bfdiv\.s\b"
        ExpectedDisassemblyMessage = "compiler-emitted fdiv.s"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_hardfloat_div.bin"
        )
    },
    @{
        Source = "hardfloat_minmax.c"
        Stem = "baremetal_hardfloat_minmax"
        March = "rv32imf_zicsr"
        Mabi = "ilp32f"
        ExpectedDisassemblyPattern = "(?ms)^\s*[0-9a-f]+:\s+.*\bfmin\.s\b.*^\s*[0-9a-f]+:\s+.*\bfmax\.s\b"
        ExpectedDisassemblyMessage = "compiler-emitted fmin.s/fmax.s"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_hardfloat_minmax.bin"
        )
    },
    @{
        Source = "hardfloat_sqrt.c"
        Stem = "baremetal_hardfloat_sqrt"
        March = "rv32imf_zicsr"
        Mabi = "ilp32f"
        CFlags = @(
            "-fno-math-errno"
        )
        ExpectedDisassemblyPattern = "(?m)^\s*[0-9a-f]+:\s+.*\bfsqrt\.s\b"
        ExpectedDisassemblyMessage = "compiler-emitted fsqrt.s"
        SyncTargets = @(
            "..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal_hardfloat_sqrt.bin"
        )
    }
)

# === Helper Functions ===
function Test-Command {
    param([string]$Command)
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}


function Build-With-LLVM {
    param([hashtable]$Artifact)
    $elfOutput = "$BUILD_DIR\$($Artifact.Stem).elf"
    $binOutput = "$BUILD_DIR\$($Artifact.Stem).bin"
    $mapOutput = "$BUILD_DIR\$($Artifact.Stem).map"
    $march = if ($Artifact.ContainsKey("March") -and $Artifact.March) { $Artifact.March } else { "rv32ima_zicsr" }
    $mabi = if ($Artifact.ContainsKey("Mabi") -and $Artifact.Mabi) { $Artifact.Mabi } else { "ilp32" }
    $extraCFlags = if ($Artifact.ContainsKey("CFlags") -and $Artifact.CFlags) { @($Artifact.CFlags) } else { @() }
    Write-Host "Using LLVM/Clang toolchain ($($Artifact.Source) -> $($Artifact.Stem).bin)" -ForegroundColor Yellow
    
    # Compile and link with Clang
    $clang_args = @(
        "--target=riscv32-unknown-elf",
        "-fuse-ld=lld",
        "-fno-stack-protector",
        "-fdata-sections",
        "-ffunction-sections",
        "-g",
        "-Os",
        "-march=$march",
        "-mabi=$mabi",
        $extraCFlags,
        "-mno-relax",
        "-static",
        "-T", $LINKER_SCRIPT,
        "-nostdlib",
        "-Wl,--no-relax",
        "-Wl,--gc-sections",
        "-Wl,-Map=$mapOutput",
        "-o", $elfOutput,
        $Artifact.Source
    )
    
    Write-Host "Compiling: clang $($clang_args -join ' ')"
    & clang $clang_args
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed with exit code $LASTEXITCODE"
    }
    
    # Extract binary
    Write-Host "Extracting binary: llvm-objcopy -O binary $elfOutput $binOutput"
    & llvm-objcopy -O binary $elfOutput $binOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Binary extraction failed with exit code $LASTEXITCODE"
    }
    
    return
}

function Assert-ArtifactDisassembly {
    param(
        [hashtable]$Artifact,
        [string]$ElfPath,
        [string]$Objdump
    )

    if (-not $Artifact.ContainsKey("ExpectedDisassemblyPattern")) {
        return
    }
    if (-not $Objdump) {
        throw "Cannot verify disassembly for $($Artifact.Source): no objdump command configured"
    }

    $pattern = $Artifact.ExpectedDisassemblyPattern
    $label = if ($Artifact.ContainsKey("ExpectedDisassemblyMessage") -and $Artifact.ExpectedDisassemblyMessage) {
        $Artifact.ExpectedDisassemblyMessage
    } else {
        $pattern
    }

    Write-Host "Verifying disassembly contains $label"
    $disassembly = & $Objdump -d $ElfPath | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "Disassembly failed for $ElfPath with exit code $LASTEXITCODE"
    }
    if ($disassembly -notmatch $pattern) {
        throw "Expected $label in disassembly for $($Artifact.Source), but it was not found.`n$disassembly"
    }
}

function Build-AllArtifacts {
    param(
        [scriptblock]$BuildAction,
        [string]$Objdump
    )

    foreach ($artifact in $artifacts) {
        & $BuildAction $artifact
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed for $($artifact.Source) with exit code $LASTEXITCODE"
        }

        $elfOutput = "$BUILD_DIR\$($artifact.Stem).elf"
        $binOutput = "$BUILD_DIR\$($artifact.Stem).bin"
        $mapOutput = "$BUILD_DIR\$($artifact.Stem).map"
        if (-not (Test-Path $elfOutput)) {
            throw "Build failed: $elfOutput not generated"
        }
        if (-not (Test-Path $binOutput)) {
            throw "Build failed: $binOutput not generated"
        }
        if (-not (Test-Path $mapOutput)) {
            throw "Build failed: $mapOutput not generated"
        }

        $bin_size = (Get-Item $binOutput).Length
        Write-Host "`n=== Build successful: $($artifact.Stem) ===" -ForegroundColor Green
        Write-Host "  ELF: $elfOutput"
        Write-Host "  BIN: $binOutput ($bin_size bytes)"
        Write-Host "  MAP: $mapOutput"

        Assert-ArtifactDisassembly -Artifact $artifact -ElfPath $elfOutput -Objdump $Objdump

        Write-Host "`n=== Syncing $($artifact.Stem).bin to target locations ===" -ForegroundColor Cyan
        foreach ($target in $artifact.SyncTargets) {
            $target_abs = (Resolve-Path $target -ErrorAction SilentlyContinue).Path
            if (-not $target_abs) {
                $target_dir = Split-Path $target -Parent
                if ($target_dir -and -not (Test-Path $target_dir)) {
                    New-Item -ItemType Directory -Path $target_dir -Force | Out-Null
                }
                $target_abs = (Resolve-Path $target_dir).Path + "\" + (Split-Path $target -Leaf)
            }

            Write-Host "  Copying to: $target_abs"
            Copy-Item -Path $binOutput -Destination $target_abs -Force
        }
    }
}

# === Main Build Logic ===
Write-Host "=== Building RISC-V Baremetal Guest Fixtures ===" -ForegroundColor Cyan
 
# Ensure we're in the guest directory
if (-not (Test-Path $LINKER_SCRIPT)) {
    throw "Error: $LINKER_SCRIPT not found. Please run this script from the guest directory."
}
foreach ($artifact in $artifacts) {
    if (-not (Test-Path $artifact.Source)) {
        throw "Error: $($artifact.Source) not found. Please run this script from the guest directory."
    }
}

# Create build directory
if (-not (Test-Path $BUILD_DIR)) {
    New-Item -ItemType Directory -Path $BUILD_DIR | Out-Null
}

# Toolchain: LLVM only (Phase 3 simplification)
if (-not ((Test-Command "clang") -and (Test-Command "ld.lld") -and (Test-Command "llvm-objcopy"))) {
    Write-Host "`n=== ERROR: LLVM toolchain not found ===" -ForegroundColor Red
    Write-Host "Need: clang, ld.lld, llvm-objcopy (LLVM with RISC-V target, >= 16.0)" -ForegroundColor Yellow
    Write-Host "Get a prebuilt LLVM from https://releases.llvm.org/ and add bin/ to PATH." -ForegroundColor Yellow
    exit 1
}

try {
    Build-AllArtifacts -BuildAction ${function:Build-With-LLVM} -Objdump "llvm-objdump"
    Write-Host "`n=== All done! ===" -ForegroundColor Green
    Write-Host "Guest binaries rebuilt and synced successfully."
    exit 0
} catch {
    throw "LLVM build failed: $_"
}
