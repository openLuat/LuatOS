# crypto_hash_demo

## Purpose

Provides a buildable customer example for hash workflows. It computes MD5 and CRC32 in guest C and writes the result into the exchange buffer.

## Dependencies

- One supported RISC-V toolchain (GNU RISC-V or LLVM)
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

