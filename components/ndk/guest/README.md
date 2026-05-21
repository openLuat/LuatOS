# NDK Guest Workspace

Canonical NDK guest fixtures and examples now live under `components\ndk\guest`.

## Layout

- `fixtures\rv32f_regression` - canonical source/build for `ndk_basic` guest binaries.
- `fixtures\hostabi_v1` - canonical source/build for host ABI guest binaries.
- `build_hostabi_v1.ps1` - canonical entrypoint for host ABI v1 fixture build.
- `examples\` - minimal standalone guest example skeletons.

## Compatibility

Legacy commands are preserved through wrappers:

- `testcase\ndk\ndk_basic\guest\build.ps1` / `build.bat`
- `testcase\ndk\guest\build_hostabi_v1.ps1`

Those wrappers forward to this workspace and keep output synchronization paths unchanged.

