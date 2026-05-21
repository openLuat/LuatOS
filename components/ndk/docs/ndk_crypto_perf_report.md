# NDK Crypto Performance Report (Pure Lua vs HostABI C)

## 1. Environment

- Repository: `D:\github\LuatOS`
- Host: Windows (PC simulator, x86 MSVC)
- Build command:
  - `cd bsp\pc`
  - `cmd /c build_windows_32bit_msvc.bat`
- Benchmark command:
  - `cd bsp\pc`
  - `$env:NDK_ONLY_CRYPTO_PERF='1'`
  - `.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_hostabi_basic\scripts\`

## 2. Methodology

- Script: `testcase\ndk\ndk_hostabi_basic\scripts\ndk_crypto_perf_test.lua`
- Compared paths:
  - **Lua path**: pure Lua implementations of MD5 and CRC32 inside the test script
  - **NDK path**: Host ABI crypto commands `CMD_CRYPTO_MD5` / `CMD_CRYPTO_CRC32`, implemented in C in `components\ndk\src\luat_ndk_host_crypto.c`
- Host ABI fixture:
  - `testcase\ndk\guest\build_hostabi_v1.ps1`
  - `testcase\ndk\ndk_hostabi_basic\scripts\hostabi_v1.bin`
- Unified profiles:
  - `64B × 6000` (warmup 200)
  - `256B × 4000` (warmup 120)
  - `512B × 2000` (warmup 80)
- Unified metrics:
  - `elapsed_ms`, `ops/s`, `KB/s`
  - Raw log format: `PERF|tag=...|size=...|iters=...|...`

## 3. Raw Results

| Algo | Path | Size(B) | Iters | Elapsed(ms) | Ops/s | KB/s |
|---|---|---:|---:|---:|---:|---:|
| MD5 | Lua | 64 | 6000 | 190 | 31578.947 | 1973.684 |
| MD5 | NDK C | 64 | 6000 | 167 | 35928.145 | 2245.509 |
| CRC32 | Lua | 64 | 6000 | 168 | 35714.285 | 2232.143 |
| CRC32 | NDK C | 64 | 6000 | 201 | 29850.746 | 1865.672 |
| MD5 | Lua | 256 | 4000 | 274 | 14598.540 | 3649.635 |
| MD5 | NDK C | 256 | 4000 | 123 | 32520.326 | 8130.082 |
| CRC32 | Lua | 256 | 4000 | 138 | 28985.508 | 7246.377 |
| CRC32 | NDK C | 256 | 4000 | 124 | 32258.064 | 8064.516 |
| MD5 | Lua | 512 | 2000 | 241 | 8298.755 | 4149.377 |
| MD5 | NDK C | 512 | 2000 | 60 | 33333.332 | 16666.666 |
| CRC32 | Lua | 512 | 2000 | 123 | 16260.163 | 8130.082 |
| CRC32 | NDK C | 512 | 2000 | 61 | 32786.887 | 16393.443 |

## 4. Comparison Summary

- MD5 NDK/Lua throughput ratio:
  - 64B: `1.14x`
  - 256B: `2.23x`
  - 512B: `4.01x`
- CRC32 NDK/Lua throughput ratio:
  - 64B: `0.84x`
  - 256B: `1.11x`
  - 512B: `2.02x`

## 5. Interpretation

- The pure Lua implementation is a useful baseline for algorithmic cost, but the C path scales better as payload size grows.
- MD5 shows the clearest win for the NDK C implementation once payloads reach 256B and above.
- CRC32 is slightly slower at 64B because fixed host-ABI call overhead dominates, but the NDK C path becomes faster as payload size increases.

## 6. Caveats

- These numbers are **PC simulator** results, not MCU hardware final numbers.
- The Lua side uses straight pure Lua implementations, while the NDK side exercises the host-side C implementation through Host ABI commands.
- This report measures end-to-end API workflow overhead, not only the raw inner loop cost.
