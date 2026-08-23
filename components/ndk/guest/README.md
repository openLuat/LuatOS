# NDK Guest Workspace

Canonical NDK guest fixtures and examples now live under `components\ndk\guest`.

## Layout

- `fixtures\hostabi_v1` - canonical source/build for host ABI guest binaries.
- `build_hostabi_v1.ps1` - canonical entrypoint for host ABI v1 fixture build.
- `examples\` - minimal standalone guest example skeletons.

## Compatibility

Legacy `baremetal.bin` build commands are preserved through wrappers:

- `testcase\ndk\ndk_basic\guest\build.ps1` / `build.bat`

Those wrappers build the canonical `baremetal.bin` and still sync outputs to:

- `testcase\ndk\ndk_basic\scripts\baremetal.bin`
- `bsp\pc\test\113.ndk_simple\baremetal.bin`
