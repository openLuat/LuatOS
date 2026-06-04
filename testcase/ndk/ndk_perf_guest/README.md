# ndk_perf_guest

NDK guest-C-implementation performance suite.

Compares the **time the LuatOS host takes to run a pure-Lua
implementation of a small algorithm** against **the time the NDK
guest-C implementation of the same algorithm takes** (guest C
loaded as a flat RV32IMA binary inside the NDK interpreter).

The whole point of the test is to measure NDK **guest** C vs Lua,
not host C vs Lua. The MD5/CRC32 host-ABI shortcuts (CSR 0x230 /
0x231) are explicitly forbidden in the guest: see
`components/ndk/guest/examples/perf_guest_v1/perf_proto.h`.

## Algorithms

| algo_id | name | category | sizes (B) |
|---:|---|---|---|
| 0x10 | FNV-1a 32-bit | arithmetic / bit twiddling | 64, 256, 1024, 2048 |
| 0x11 | CRC32 IEEE  | arithmetic / bit twiddling | 64, 256, 1024, 2048 |
| 0x20 | Base64 encode | string / encoding | 64, 256, 512, 1024 |
| 0x30 | MD5  | crypto hash | 64, 256, 1024, 2048 |
| 0x40 | heapsort int32 | sort / search | n_elems = 16, 64, 256 |

### Profile sizing notes

- The exchange buffer is **4 KiB** (`EXCHANGE_SIZE = 4096`).
  `PAYLOAD_OFFSET = 64` so the per-chunk payload cap is **4032 B**.
- Base64 expands input by 4/3 + padding. The largest size where
  `L + 4*ceil(L/3) ≤ 4032` is `L = 1726`; the test caps at **1024 B**
  for a comfortable headroom. (MD5/CRC32/FNV-1a are in-place or
  fixed-output so they can run at the full 2048 B; heapsort is
  in-place so up to `n_elems=256` = 1024 B works.)

## Current status

31/31 tests passing on PC as of the most recent run:

| algo | passing | sizes |
|---|---|---|
| FNV-1a 32  | 4/4 | 64, 256, 1024, 2048 |
| CRC32 IEEE | 4/4 | 64, 256, 1024, 2048 |
| Base64     | 4/4 | 64, 256, 512, 1024 |
| MD5        | 4/4 | 64, 256, 1024, 2048 |
| heapsort   | 4/4 | n_elems=16, 64, 256 |
| smoke      | 11/11 | 5 base64 vectors, crc32/md5/fnv1a/heapsort basics |

Total: 31/31 (smoke + vs_lua + perf for each algo × sizes).

`ndk_basic` 42/0 and `ndk_hostabi_basic` 39/0 baselines unchanged.

## Recent bug-fix history (2026-06)

A first end-to-end pass surfaced five distinct bugs that all
presented as `mcause=7 mtval=0xFFFFFFFC` (store access fault at the
top of the red zone) or `mcause=7 mtval=-4`. They were
fixed in this order on the `feat/ndk-perf-guest-impl` branch:

1. **`perf_guest_v1/_start` missing `__attribute__((naked))`** —
   clang -Os still emitted a function prologue that
   `addi sp,sp,-0x10; sw ra,0xc(sp)` over the uninitialised sp=0.
   Fix: rewrite `_start` as naked + bare inline asm.
2. **Dispatcher passed `&produced` (init 0) as `out_len`** — every
   expanding algo (Base64) saw `out_cap=0` and reported
   `BAD_BOUNDS` even for trivially-fitting inputs. Fix: pass `&out_cap`.
3. **Lua baseline `base64_lua` had multiple 0/1-indexed bugs** —
   `rem==2/3/4` checks (should be `rem==1/2`), loop condition
   `i+3<=n` (should be `i+2<=n`), missing `rem==1` branch for
   single-byte inputs.
4. **Lua baseline `siftdown_lua` used 0-indexed heap-child
   offsets in a 1-indexed array** — odd-sized heaps lost
   the second-to-last swap.
5. **NDK mini-rv32ima trap handler now dumps the full
   guest register file** (x0..x31 + mcause/mtval/mepc/mstatus/
   mtvec/extraflags) so you can read the same ABI names from
   `llvm-objdump -d guest.elf` and pinpoint the trap PC
   without manual symbol lookup.

Full write-up in `components/ndk/docs/changelog.md` and
`components/ndk/docs/troubleshooting.md` (Q9, Q10).

## Build

The guest image must be built first. From the worktree root:

```bash
cd components/ndk/guest/examples/perf_guest_v1
pwsh -File build.ps1
```

The build script compiles `main.c` + every `algos/*.c` with the
LLVM clang RISC-V backend (`rv32ima_zicsr`, `ilp32`) and copies the
resulting `perf_guest_v1.bin` into this directory's `scripts/`.

## Run

### PC

```bash
cd bsp/pc
./build/out/luatos-lua.exe \
    ../../testcase/common/scripts \
    ../../testcase/ndk/ndk_perf_guest/scripts
```

### air1601 (COM10, 6 000 000 baud)

```bash
CLI=/d/github/luatos-cli/target/release/luatos-cli.exe
SOC=/d/github/luatos-sdk-ccm42xx-gcc/csdk/project/luatos/out/LuatOS-SoC_V1021_Air1601.soc

"$CLI" flash test --soc "$SOC" --port COM10 --baud 6000000 \
    --script /d/github/LuatOS/testcase/common/scripts \
    --script /d/github/LuatOS/testcase/ndk/ndk_perf_guest/scripts \
    --timeout 180 \
    --keyword '### OVERALL_PASS ###' \
    --fail-keyword '### OVERALL_FAIL ###' \
    --fail-keyword panic --fail-keyword hardfault \
    --format json > /d/logs/ndk_perf_air1601.json
```

The air1601 side requires an NDK BSP port — see
`bsp/air1601/patches/ndk_port.patch` (in the final commit).

## Output

Each `measure()` call emits two `log.info` lines:

```
I/perf     [fnv1a_32.lua] size=64B iters=6000 warmup=200 elapsed=87ms ops=68965.5/s kbps=4310.3
I/perf_raw PERF|tag=fnv1a_32.lua|size=64|iters=6000|warmup=200|elapsed_ms=87|ops_s=68965.500|kb_s=4310.344
```

The `PERF|...` line is pipe-delimited key=value and can be parsed
by any log scraper into CSV / JSON. The `bsp/pc/tests/ps1/test_ndk_perf.ps1`
wrapper does that on PC; a Python one-liner does it on the air1601
JSON output.

## What goes into the report

The NDK perf report lives at
`components/ndk/docs/ndk_perf_report.md` and is updated by hand after
the suite runs. PC and air1601 results go in two adjacent tables so
the platform contrast is one glance.
