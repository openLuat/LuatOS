# exchange_buffer_demo

## Purpose

Demonstrates a simple request/response layout in the NDK exchange buffer using fixed offsets and deterministic arithmetic.

## Dependencies

- One supported RISC-V toolchain (GNU RISC-V or LLVM; same detection as `build_example.ps1`)
- PowerShell or CMD

## Build

```powershell
cd components\ndk\guest\examples\exchange_buffer_demo
.\build.ps1
```

or

```bat
cd components\ndk\guest\examples\exchange_buffer_demo
build.bat
```

## Run (NDK)

Load `build\exchange_buffer_demo.bin` with `ndk.rv32i(...)`, call `ndk.exec(...)`, then inspect exchange memory.

## Expected Output

- Binary: `components\ndk\guest\examples\exchange_buffer_demo\build\exchange_buffer_demo.bin`
- Request area (`+0x00`): `a=0x12345678`, `b=0x9ABCDEF0`, `control=0xA5A50001`
- Result area (`+0x10`): `sum`, `xorv`, and verdict (`0x900D` when control matches)
- Completion marker `0x5555` written to SYSCON.

