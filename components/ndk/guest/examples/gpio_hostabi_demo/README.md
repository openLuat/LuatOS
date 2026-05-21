# gpio_hostabi_demo

## Purpose

Shows a minimal GPIO host-ABI flow from guest side: config, write, and read via CSR commands (`0x210/0x211/0x212`).

## Dependencies

- One supported RISC-V toolchain (GNU RISC-V or LLVM)
- Host runtime with GPIO host-ABI enabled for meaningful status codes
- PowerShell or CMD

## Build

```powershell
cd components\ndk\guest\examples\gpio_hostabi_demo
.\build.ps1
```

or

```bat
cd components\ndk\guest\examples\gpio_hostabi_demo
build.bat
```

## Run (NDK)

Use `ndk.rv32i("...gpio_hostabi_demo.bin", mem, exchange)` and execute with `ndk.exec(...)`.

## Expected Output

- Binary: `components\ndk\guest\examples\gpio_hostabi_demo\build\gpio_hostabi_demo.bin`
- Exchange:
  - `[0]` GPIO config return status
  - `[1]` GPIO write return status
  - `[2]` GPIO read return value/status
  - `[3]` pin number (`5`)
  - `[4]` requested level (`1`)
- Completion marker `0x5555` written to SYSCON.

