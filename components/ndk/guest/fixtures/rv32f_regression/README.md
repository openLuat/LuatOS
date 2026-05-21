# NDK Guest Source

This directory contains the source code for the guest binaries used by the NDK test suite.

## Purpose

The binaries at `testcase/ndk/ndk_basic/scripts/baremetal.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fcsr.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fmv.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_flwfsw.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fadd.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fadd_first.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fadd_rounding.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fcmp.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fclass.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fcvtsw.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fsubmul.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fsgnj.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fcvt_dyn_rup.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_fbinop_nan.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_hardfloat_mulsub.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_hardfloat_cast.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_hardfloat_fmadd.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_hardfloat_fmsub.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_hfnm.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_hardfloat_div.bin`, `testcase/ndk/ndk_basic/scripts/baremetal_hardfloat_minmax.bin`, and `testcase/ndk/ndk_basic/scripts/baremetal_hardfloat_sqrt.bin` are RISC-V flat binaries used by the NDK tests. This directory exists to:

1. **Document provenance** - The binary originates from the mini-rv32ima upstream project
2. **Make behavior inspectable** - Provide readable source matching observed test behavior
3. **Enable rebuild** - Provides automated build scripts for reproducible compilation

## Build Status

✅ **The source in this directory is now the verified and active implementation:**
- Source is reconstructed from upstream mini-rv32ima project structure
- Build scripts (`build.bat` / `build.ps1`) automatically compile and sync both binaries
- Rebuilt binaries pass current NDK baselines (`ndk_basic`: 42 passed, 0 failed; `ndk_hostabi_basic`: 39 passed, 0 failed)
- Build output is automatically synced to the checked-in test locations

**Provenance verified:**
- Based on mini-rv32ima upstream (`baremetal/baremetal.c`, linker script)
- Simplified to match LuatOS NDK CSR/MMIO contract
- Test logs confirm debug messages match this source
- Exit behavior matches: `Control Store: set val to 00005555`

**Current binary characteristics:**
- Size: ~315 bytes (may vary slightly with toolchain)
- Toolchain: GNU riscv64-unknown-elf-gcc (preferred) or LLVM clang (fallback)
- Format: Flat binary loaded at 0x80000000

## Files

- **`main.c`** - C source code matching verified guest behavior for `baremetal.bin`
- **`fcsr_reset.c`** - Minimal guest that writes `fcsr` before exit for ISA/F-state tests
- **`fmv_roundtrip.S`** - Hand-written guest that round-trips a 32-bit pattern through `FMV.W.X` / `FMV.X.W`
- **`flwfsw_roundtrip.S`** - Hand-written guest that round-trips a 32-bit payload through `FLW` / `FSW`
- **`fadd_simple.S`** - Hand-written guest that performs `FADD.S` on two exact single-precision operands and returns the result bits
- **`fadd_first.S`** - Hand-written guest that makes `FADD.S` the very first FP instruction, then returns the result bits
- **`fadd_rounding.S`** - Hand-written guest that exercises a half-ULP `FADD.S` case to validate host-side RNE handling
- **`fadd_rmm_static.S`** - Hand-written guest that encodes `FADD.S` with static `rm=RMM` (`rm=4`) for unsupported-rounding trap regression
- **`fadd_rmm_dynamic.S`** - Hand-written guest that sets `frm=RMM` (`frm=4`) then executes `FADD.S rm=dyn` for dynamic unsupported-rounding trap regression
- **`fcmp_nan_flags.S`** - Hand-written guest that records `FEQ.S` / `FLT.S` / `FLE.S` NaN results and guest `fflags`
- **`fclass_bits.S`** - Hand-written guest that records `FCLASS.S` results for zero, subnormal, and NaN patterns
- **`fcvt_sw_bits.S`** - Hand-written guest that records `FCVT.S.W` / `FCVT.S.WU` result bits and guest `fflags`
- **`fsubmul_smoke.S`** - Hand-written guest that records exact-bit `FSUB.S` / `FMUL.S` smoke results and guest `fflags`
- **`fsgnj_bits.S`** - Hand-written guest that records exact-bit `FSGNJ.S` / `FSGNJN.S` / `FSGNJX.S` results and guest `fflags`
- **`fcvt_dyn_rup.S`** - Hand-written guest that sets `frm=RUP`, then validates dynamic-rounding `FCVT.S.W`
- **`fbinop_nan_bits.S`** - Hand-written guest that records `FADD.S` / `FSUB.S` / `FMUL.S` NaN result bits for canonical-NaN coverage
- **`hardfloat_mulsub.c`** - Compiler-generated hard-float smoke that evaluates `a * b - c` under `-march=rv32imf_zicsr -mabi=ilp32f`
- **`hardfloat_cast.c`** - Compiler-generated hard-float smoke that forces `FCVT.W.S` / `FCVT.WU.S` via C float-to-int casts under `-march=rv32imf_zicsr -mabi=ilp32f`
- **`hardfloat_fmadd.c`** - Compiler-generated hard-float smoke that contracts `a * b + c` into `FMADD.S` under `-march=rv32imf_zicsr -mabi=ilp32f -ffp-contract=fast`
- **`hardfloat_fmsub.c`** - Compiler-generated hard-float probe that contracts `a * b - c` into `FMSUB.S` under `-march=rv32imf_zicsr -mabi=ilp32f -ffp-contract=fast`
- **`hardfloat_fnm_probe.c`** - Compiler-generated hard-float probe that tries to trigger direct negated fused forms (`FNMADD.S` / `FNMSUB.S`) using C expressions under `-march=rv32imf_zicsr -mabi=ilp32f -ffp-contract=fast`
- **`hardfloat_div.c`** - Compiler-generated hard-float smoke that evaluates `a / b` into `FDIV.S` under `-march=rv32imf_zicsr -mabi=ilp32f`
- **`hardfloat_minmax.c`** - Compiler-generated hard-float smoke that emits `FMIN.S` / `FMAX.S` via `__builtin_fminf` / `__builtin_fmaxf` under `-march=rv32imf_zicsr -mabi=ilp32f`
- **`hardfloat_sqrt.c`** - Compiler-generated hard-float smoke that emits `FSQRT.S` via `__builtin_sqrtf` under `-march=rv32imf_zicsr -mabi=ilp32f`
- **`link.ld`** - Linker script for flat binary at 0x80000000
- **`build.ps1`** - PowerShell build script (auto-detects toolchain, syncs binary)
- **`build.bat`** - Batch wrapper for `build.ps1`
- **`README.md`** - This file

## Build Instructions

### Automated Build (Recommended)

```powershell
cd components\ndk\guest\fixtures\rv32f_regression
cmd /c build.bat
```

兼容入口保持不变（旧命令仍可用）：

```powershell
cd testcase\ndk\ndk_basic\guest
cmd /c build.bat
```

The script will:
1. Auto-detect available toolchain (GNU RISC-V preferred, LLVM fallback)
2. Compile both guest sources with optimized flags
3. Extract flat binaries from ELF outputs
4. **Automatically sync** the resulting artifacts:
   - `testcase\ndk\ndk_basic\scripts\*.bin`（完整回归二进制集合）
   - `bsp\pc\test\113.ndk_simple\baremetal.bin`（PC 快速测试镜像）

Expected output:
```
=== Building RISC-V Baremetal Guest ===
Using GNU toolchain: riscv64-unknown-elf
...
=== Build successful ===
  BIN: build\baremetal.bin (315 bytes)
  ...
=== Build successful: baremetal_fcsr ===
  BIN: build\baremetal_fcsr.bin (...)
...
=== Syncing binary to target locations ===
=== All done! ===
```

### Manual Build

For debugging or custom flags:

```powershell
cd components\ndk\guest\fixtures\rv32f_regression
mkdir build -ErrorAction SilentlyContinue

# GNU toolchain (preferred)
riscv64-unknown-elf-gcc -march=rv32ima_zicsr -mabi=ilp32 `
  -ffreestanding -nostdlib -fno-stack-protector `
  -fdata-sections -ffunction-sections -Os -g `
  -Wl,-T,link.ld -Wl,-Map,build\baremetal.map -Wl,--gc-sections `
  -o build\baremetal.elf main.c

riscv64-unknown-elf-objcopy -O binary build\baremetal.elf build\baremetal.bin

riscv64-unknown-elf-gcc -march=rv32ima_zicsr -mabi=ilp32 `
  -ffreestanding -nostdlib -fno-stack-protector `
  -fdata-sections -ffunction-sections -Os -g `
  -Wl,-T,link.ld -Wl,-Map,build\baremetal_fcsr.map -Wl,--gc-sections `
  -o build\baremetal_fcsr.elf fcsr_reset.c

riscv64-unknown-elf-objcopy -O binary build\baremetal_fcsr.elf build\baremetal_fcsr.bin

# Manual sync
copy build\baremetal.bin ..\..\..\..\..\testcase\ndk\ndk_basic\scripts\baremetal.bin
copy build\baremetal.bin ..\..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin
copy build\baremetal_fcsr.bin ..\scripts\baremetal_fcsr.bin
```

### Toolchain Requirements

**Option 1: GNU RISC-V Toolchain** (preferred)
- `riscv64-unknown-elf-gcc` / `riscv64-unknown-elf-objcopy`
- OR `riscv32-unknown-elf-gcc` / `riscv32-unknown-elf-objcopy`
- OR `riscv-none-elf-gcc` / `riscv-none-elf-objcopy` (xPack toolchain)
- Download: [xPack RISC-V GCC](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases)

**Option 2: LLVM/Clang** (fallback)
- `clang` + `ld.lld` + `llvm-objcopy` with RISC-V target support
- Download: [LLVM Releases](https://releases.llvm.org/)

See `components/ndk/README.md` for detailed setup instructions.

## Provenance

This source is based on **mini-rv32ima** by CNLohr:
- **Project**: https://github.com/cnlohr/mini-rv32ima  
- **License**: MIT-x11 or NewBSD (compatible with LuatOS MIT license)
- **Original reference**: `baremetal/baremetal.c`, `baremetal/baremetal.S`, `baremetal/flatfile.lds`

The reconstruction simplifies the upstream to match only the behavior observed in LuatOS NDK tests, removing unused code paths (delay loops, assembly demo functions, timer access, etc.).

## What the Guest Does

**Observed in test logs from the checked-in binary (`scripts/baremetal.bin`):**

1. **Logs via CSR writes**:
   - CSR 0x136: `nprint` - print number
   - CSR 0x137: `pprint` - print pointer (hex)
   - CSR 0x138: `lprint` - print string (pass guest address)

2. **Debug output**:
   ```
   main is at: 0x80000014
   Buffer is at: 0x80001120
   Stack top is at: 0x8000113F
   Testing strlen optimization:
   Length of teststr1: 13
   Length of teststr2: 71
   ```

   **Note**: Addresses (e.g., `0x80000014`) vary by compiler version, optimization level, and toolchain. The message pattern and key values (`13`, `71`, `0x5555`) remain stable.

   Runtime output is emitted as separate `vm:` / `vm num:` log lines. The block above shows the logical sequence in merged form.

3. **Exits via control store**:
   - Writes `0x5555` to `SYSCON` (0x11100000)
   - Runtime logs: `Control Store: set val to 00005555`

## Memory Layout

```
0x80000000  ┌──────────────┐
            │ .text        │  Entry point + main code
            ├──────────────┤
            │ .rodata      │  String literals
            ├──────────────┤
            │ .data        │  Initialized data
            ├──────────────┤
            │ .bss         │  Uninitialized data
            ├──────────────┤
            │ .stack (4KB) │  Grows down from _sstack
            └──────────────┘
```

The LuatOS runtime allocates RAM (8-32KB) and places an exchange area at the end for host-guest data transfer. The guest binary itself doesn't use the exchange area in current tests.

## Layout Notes

This fixture is now maintained under `components/ndk/guest/fixtures/rv32f_regression` as the canonical source/build location.

`testcase\ndk\ndk_basic\guest\build.ps1` and `build.bat` are compatibility wrappers that forward to this directory so existing CI/dev commands remain unchanged.

## Related Documentation

- **NDK Runtime & Build Guide**: `components/ndk/README.md` — comprehensive zero-to-verification guide
- **Runtime Implementation**: `components/ndk/src/luat_ndk.c`  
- **CSR Handlers**: `components/ndk/src/luat_ndk_host.c`
- **Testcases**: `testcase/ndk/ndk_basic/scripts/ndk_test.lua`
