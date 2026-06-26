# crypto_hash_demo

## Purpose

Provides a buildable customer example for hash workflows. The guest calls the host MD5 / CRC32 CSRs (`0x230` / `0x231`) and writes the result into the exchange buffer.

## Dependencies

- LLVM/Clang with RISC-V support: `clang` + `ld.lld` + `llvm-objcopy` (≥ 16.0)
- PowerShell or CMD

## Build

```powershell
cd components\ndk\guest\examples\crypto_hash_demo
.\build.ps1
```

or

```bat
cd components\ndk\guest\examples\crypto_hash_demo
build.bat
```

## Run (NDK)

Run `build\crypto_hash_demo.bin` through `ndk.rv32i(...)` + `ndk.exec(...)`, then inspect exchange words.

## Expected Output

- Binary: `components\ndk\guest\examples\crypto_hash_demo\build\crypto_hash_demo.bin`
- Exchange:
  - `[4]` status (`0` on success)
  - `[5]` input length
  - `[6]` output length (`16` for MD5, `4` for CRC32)
- Completion marker `0x5555` written to SYSCON.

