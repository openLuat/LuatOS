# hostabi_v1 Legacy Shim

Canonical source/build moved to:

- `components\ndk\guest\fixtures\hostabi_v1`

Legacy entry command remains unchanged:

```powershell
cd testcase\ndk\guest
.\build_hostabi_v1.ps1
```

The wrapper forwards to canonical scripts and preserves output paths:

- `testcase\ndk\ndk_hostabi_basic\scripts\hostabi_v1.bin`
- `testcase\ndk\ndk_hostabi_basic\scripts\hostabi_v1_rvc.bin`

