# NDK Guest Legacy Wrapper

Canonical source for `ndk_basic` baremetal guest now lives here:

- `main.c` — minimal RV32IMA guest used by `ndk_basic` lifecycle tests
- `link.ld` — flat binary linker script
- `build.ps1` / `build.bat` — self-contained LLVM build entrypoints

Both entrypoints build `baremetal.bin` and sync outputs to:

- `..\scripts\baremetal.bin`
- `..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin`
