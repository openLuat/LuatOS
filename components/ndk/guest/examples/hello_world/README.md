# hello_world

## Purpose

Smallest customer-facing RV32IMA guest example. It writes a text marker to exchange memory and then raises the standard completion marker (`0x5555`) through SYSCON.

## Dependencies

- One supported RISC-V toolchain:
  - `riscv64-unknown-elf-gcc` + `riscv64-unknown-elf-objcopy`, or
  - `riscv32-unknown-elf-gcc` + `riscv32-unknown-elf-objcopy`, or
  - `riscv-none-elf-gcc` + `riscv-none-elf-objcopy`, or
  - `clang` + `ld.lld` + `llvm-objcopy`
- PowerShell (`build.ps1`) or CMD (`build.bat`)

## Build

```powershell
cd components\ndk\guest\examples\hello_world
.\build.ps1
```

or

```bat
cd components\ndk\guest\examples\hello_world
build.bat
```

## Run (NDK)

Load `build\hello_world.bin` with `ndk.rv32i(...)`, then execute it with `ndk.exec(...)`.

## Expected Output

- Binary: `components\ndk\guest\examples\hello_world\build\hello_world.bin`
- Exchange words `[0..3]` contain ASCII chunks for `HELLO_NDK_DONE`.
- Guest exits by writing `0x5555` to SYSCON.

