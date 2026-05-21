# NDK Guest Legacy Wrapper

Canonical source/build moved to:

- `components\ndk\guest\fixtures\rv32f_regression`

This directory only preserves legacy entry commands:

- `cmd /c build.bat`
- `powershell -File build.ps1`

Both wrappers forward to the canonical script and still sync outputs to:

- `testcase\ndk\ndk_basic\scripts\*.bin`
- `bsp\pc\test\113.ndk_simple\baremetal.bin`

