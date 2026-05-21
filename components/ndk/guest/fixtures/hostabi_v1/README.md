# hostabi_v1 Fixture

This is the canonical source/build location for the NDK host ABI v1 fixture.

## Build

```powershell
cd components\ndk\guest\fixtures\hostabi_v1
cmd /c build.bat
```

Compatibility wrapper command (unchanged):

```powershell
cd testcase\ndk\guest
.\build_hostabi_v1.ps1
```

## Outputs (unchanged)

- `testcase\ndk\ndk_hostabi_basic\scripts\hostabi_v1.bin`
- `testcase\ndk\ndk_hostabi_basic\scripts\hostabi_v1_rvc.bin`

