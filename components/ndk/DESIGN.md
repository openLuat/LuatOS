# NDK Design

> **Status**: Implemented through Phase 3 (helper library + 512 KiB RAM + step-budget removal + doc split + crypto host-call demo + Rust no-std example).
> **Scope**: `components/ndk/` only. Out of scope: tooling, BSP integration, other components.
> **Date**: 2026-06-04
> **Supersedes**: nothing (initial formal design doc; prior architecture lived in `AGENTS.md`).
> **See also**: `AGENTS.md` (developer guide), `README.md` (index), `docs/api-helper.md` (helper API), `docs/csr-abis.md` (full CSR/MMIO tables), `docs/superpowers/specs/2026-05-20-gpio-v2-design.md` and `2026-05-20-uart-v1-design.md` (per-ABI specs).

---

## 1. Goals

- **Sandbox isolation** — guest code cannot escape into host memory or call arbitrary host functions; the only host touch-points are the documented CSRs and one MMIO address.
- **Deterministic cycle count** — every NDK step is counted; the budget is caller-controlled and the inner loop yields at 256-step granularity so `ndk.stop` is responsive.
- **Host-driven MMIO / CSR** — peripheral state lives in the host (`src/luat_ndk_host*.c`); the guest only triggers side-effects through RISC-V `csrrw` instructions.
- **Optional RV32F** — `rv32imf` ISA string enables single-precision FP. `rv32ima` is the default.
- **Up to 512 KiB guest RAM** — `LUAT_NDK_MAX_RAM_SIZE` ceiling (was 32 KiB; raised in Phase 3).
- **PC simulator as the primary validation backend** — Windows + MSVC + xmake. Production firmware support (Air1601 / Air780E / ...) is explicitly out of scope (see §14).
- **Designed for Lua orchestration** — the `ndk.*` API is a Lua module; lifecycle is `__gc`-managed; both sync (`exec`) and async (`thread`) execution are first-class.

## 2. Architecture

### Module layout

| Layer | File | Responsibility |
|---|---|---|
| Lua binding | `binding/luat_lib_ndk.c` | `luaopen_ndk`; `rv32i / setData / getData / exec / thread / stop / reset / info`; error string map; `__gc` finalizer. |
| Public C API (host-side) | `include/luat_ndk.h` | `luat_ndk_t` struct; `luat_ndk_init / deinit / reset / set_data / get_data / exec / start_thread / stop_thread / is_busy / exchange_addr`. |
| Public C ABI (host + guest) | `include/luat_ndk_abi.h` | CSR addresses, opcodes, feature bits, pack/unpack macros, status enums, event header / slot layout. |
| Guest inline helpers | `include/luat_ndk_builtin.h` | `static inline` `csrr`/`csrrw` wrappers for every documented CSR. |
| Guest curated helper | `guest/include/luat_ndk_helper.h` | Phase 3: typed exchange access, log, SYSCON exit, status decoders, byte order, hash calls, event peek. |
| Core simulator | `src/luat_ndk.c` | mini-rv32ima host; `ndk_init / deinit / reset / load_image / exec_inner / start_thread / stop_thread`; RV32F helpers (`ndk_fcvt_s_w`, `ndk_fcvt_w_s`, etc.); threading primitives. |
| CSR dispatch | `src/luat_ndk_host.c` | `luat_ndk_host_othercsr_read / write` — switch on CSR address; SYSCON MMIO handler; log / time / event CSRs. |
| Per-peripheral handlers | `src/luat_ndk_host_event.c` / `_gpio.c` / `_uart.c` / `_crypto.c` | One file per peripheral family. Dispatcher fans out to these. |
| CPU core | `include/mini-rv32ima.h` | Vendored mini-rv32ima (Charles Lohr, MIT / NewBSD), patched with `MINIRV32_LUATOS_RV32C_PATCH` for RV32C support. |
| Examples | `guest/examples/{hello_world, exchange_buffer_demo, gpio_hostabi_demo, crypto_hash_demo}` | 4 customer-facing standalone C projects; all use helper since Phase 3. |
| Regression guests | `guest/fixtures/{rv32f_regression, hostabi_v1}` | Self-contained test programs; `hostabi_v1` keeps its own `ndk_stubs.c` for fixture-level test hooks. |

### Boundary rules

- **Guest → host** is a one-way contract: only the CSRs and the single SYSCON MMIO documented in `docs/csr-abis.md` are honored. Any other `csrr` against a non-standard address, or any other MMIO access, is either silently ignored or returns 0.
- **Host → guest** is also restricted: the host reads/writes only the guest's flat RAM (`ctx->ram`); the CPU state is owned by `MiniRV32IMAState` and the host must go through the stepper.
- **Lua → host** goes through `luat_lib_ndk.c`; the Lua module never exposes `luat_ndk_t` directly — only opaque userdata with a metatable.
- **Helper → builtin → abi**: `luat_ndk_helper.h` includes `luat_ndk_builtin.h` which includes `luat_ndk_abi.h`. There is no other transitive dependency; helper has no C compilation unit of its own.

## 3. Guest ABI surface

The ABI a guest binary needs to know is summarized in §7 below and fully tabulated in `docs/csr-abis.md`. High-level groups:

| Group | CSRs | Purpose |
|---|---|---|
| Discovery | `0x13C` magic, `0x13D` version, `0x13E` features, `0x13F` last_error, `0x140` event_slots | Probe host capabilities before using them |
| Time | `0x141` / `0x142` time_us_lo/hi, `0x143` delay_us | Wall-clock and sleep |
| Event | `0x144` event_enable, `0x145` event_pending | Async event ring (header at exchange + 32, slots at +48) |
| GPIO v2 | `0x210..0x214` CONFIG / WRITE / READ / IRQ_STATE / IRQ_CLEAR | Per-pin ownership model |
| UART v1 | `0x220..0x224` CONFIG / TX / RX_STATE / RX_READ / RX_CLEAR | Loopback-backed PC model |
| Crypto v1 | `0x230` MD5, `0x231` CRC32 | Host-computed hashes |
| Debug (legacy) | `0x136..0x138` PRINT_NUM/PTR/STR | Human-readable guest logs |
| Legacy GPIO | `0x200` set, `0x201` get | v1, mostly stubbed |
| Control MMIO | `0x11100000` SYSCON | `0x5555` exit marker |
| Exchange | `0x139` base, `0x13A` size, `0x13B` mem_size | Bulk data region at the tail of RAM |

## 4. Memory layout

### Guest physical address space

```
0x80000000 +-----------------------------+
            |    .text / .rodata / .data  |   <-- image loaded here (MINIRV32_RAM_IMAGE_OFFSET)
            |                             |
            |    free stack / heap        |
            |                             |
            |    ...                      |
            |                             |
exchange_   +-----------------------------+
offset      |    exchange buffer          |   <-- last `exchange_size` bytes of RAM
            |    16B command region       |
            |    16B result region        |
            |    16B event header         |   <-- LUAT_NDK_EVENT_HDR_OFFSET (32)
            |    8B * event_slots slots   |   <-- LUAT_NDK_EVENT_HDR_OFFSET + 16
0x80000000  +-----------------------------+   end of RAM = 0x80000000 + mem_size
            | (out of range)              |
0x10000000  +-----------------------------+
            |    MMIO range (16 MiB)      |   <-- MINIRV32_MMIO_RANGE
0x12000000  +-----------------------------+
```

`exchange_offset = mem_size - exchange_size`. Guests compute their stack top as `exchange_offset - 16` (the helper's `ndk_stack_top()` does this).

### Per-context invariants

- `ram_size` is between `LUAT_NDK_DEFAULT_RAM_SIZE` (8 KiB) and `LUAT_NDK_MAX_RAM_SIZE` (512 KiB).
- `exchange_size` is strictly less than `ram_size`; default 4 KiB.
- The image must fit in `exchange_offset` bytes (not in `ram_size`).
- `event_slots = min(8, (exchange_size - 48) / 8)`; always at least 0, but in practice `exchange_size >= 1024` so always at least `121`.

## 5. Execution model

`ndk_exec_inner` (in `src/luat_ndk.c`):

```
reset trap_pending, last_mcause, last_mtval, last_trap
left = step_budget
unlimited = (step_budget == 0)

while (unlimited || left > 0) && !trap_pending && !stop_requested:
    chunk = unlimited ? NDK_STEP_CHUNK : min(left, NDK_STEP_CHUNK)
    ret = MiniRV32IMAStep(ctx, core, ram, PC, elapsed_us, chunk)
    if ret == 0x5555:                     // SYSCON exit
        return OK
    if !unlimited: left -= chunk
    if core->mcause != 0: break           // any trap

if stop_requested: return TIMEOUT
if mcause == 11:                          // ecall
    retval = a0
    return OK
if trap_pending || mcause: return TRAP
if !unlimited && left == 0: return TIMEOUT
return OK
```

### Exit paths

| Path | Trigger | Returned rc | Returned payload |
|---|---|---|---|
| Normal exit | guest writes `0x5555` to SYSCON | `LUAT_NDK_OK` | `retval = 0` |
| `ecall` exit | guest `ecall` (`mcause = 11`) | `LUAT_NDK_OK` | `retval = a0` |
| Trap | illegal instr / load fault / ... (`mcause ∈ {0,1,2,3,7,8,9,10,12,13,...}`) | `LUAT_NDK_ERR_TRAP` | `mcause`, `mtval` |
| Stop | `ndk.stop(ctx, wait_ms)` interrupted | `LUAT_NDK_ERR_TIMEOUT` | `mcause`, `mtval` |
| Step budget | `step_budget != 0 && left == 0` | `LUAT_NDK_ERR_TIMEOUT` | `mcause`, `mtval` |
| Async busy | `ndk.exec` while `ndk.thread` is running | `LUAT_NDK_ERR_BUSY` | — |

### Yielding

`MiniRV32IMAStep` takes a `count` argument; the wrapper uses `NDK_STEP_CHUNK = 256`. This bounds the maximum uninterrupted time inside the stepper to ~256 instructions, which is what makes `ndk.stop` responsive even with `step_budget = 0`. The `elapsed_us` argument is a wall-clock budget per step (default 100 us); the stepper uses it to advance its internal timer.

## 6. Step budget policy

| Caller | `step_budget` | Behavior |
|---|---|---|
| `ndk.exec(ctx, {steps = 0, elapsed = N})` | 0 | **Unlimited** (Phase 3 change) — runs until SYSCON / ecall / trap / `ndk.stop`. |
| `ndk.exec(ctx, {steps = 100000, elapsed = N})` | 100000 | Caps at 100 k instructions. |
| `ndk.exec(ctx)` (no opts) | 0 | Same as `steps = 0`: unlimited. |

The `steps = 0` semantic was previously "use default `NDK_DEFAULT_STEP_BUDGET = 32768`". Phase 3 changes it to unlimited because the 32 k default was a hard cap that frequently bit guests with longer loops. The chunked loop (256 steps) preserves `ndk.stop` responsiveness without an arbitrary cap.

**Operational escape hatch**: unbounded guests must be paired with a Lua-side `ndk.stop(ctx, 1000)` (or smaller timeout) for graceful shutdown. The Lua testcase already uses this pattern in `test_ndk_busy_and_stop_restart_sequence`.

## 7. CSRs and MMIO

Full table in `docs/csr-abis.md`. Quick reference:

| CSR addr | Read / Write | Description |
|---|---|---|
| `0x136` | W | PRINT_NUM — log signed/unsigned 32-bit |
| `0x137` | W | PRINT_PTR — log pointer / hex |
| `0x138` | W | PRINT_STR — log C string (≤120 B) |
| `0x139` | R | EXCHANGE_BASE |
| `0x13A` | R | EXCHANGE_SIZE |
| `0x13B` | R | MEMORY_SIZE |
| `0x13C` | R | HOST_MAGIC (`0x4E444B31` = "NDK1") |
| `0x13D` | R | HOST_VERSION (`0x00010000`) |
| `0x13E` | R | HOST_FEATURES bit map |
| `0x13F` | R | LAST_ERROR |
| `0x140` | R | EVENT_SLOTS |
| `0x141` | R | TIME_US_LO |
| `0x142` | R | TIME_US_HI |
| `0x143` | W | DELAY_US |
| `0x144` | W | EVENT_ENABLE |
| `0x145` | R | EVENT_PENDING |
| `0x200` | W | GPIO_SET (legacy, v1) |
| `0x201` | R | GPIO_GET (legacy, v1) |
| `0x210` | RW | GPIO_CONFIG v2 (request/response via `csrrw a0, csr, a0`) |
| `0x211` | RW | GPIO_WRITE v2 |
| `0x212` | RW | GPIO_READ v2 |
| `0x213` | RW | GPIO_IRQ_STATE v2 |
| `0x214` | RW | GPIO_IRQ_CLEAR v2 |
| `0x220` | RW | UART_CONFIG v1 |
| `0x221` | RW | UART_TX v1 |
| `0x222` | RW | UART_RX_STATE v1 |
| `0x223` | RW | UART_RX_READ v1 |
| `0x224` | RW | UART_RX_CLEAR v1 |
| `0x230` | RW | CRYPTO_MD5 v1 — returns status |
| `0x231` | RW | CRYPTO_CRC32 v1 — returns CRC32 value |
| `0x11100000` | W (MMIO) | SYSCON — `0x5555` exit marker |

### GPIO v2 request/response pattern

`csrrw a0, csr, a0` is the load-link / request primitive. The guest packs the request into `a0`; the host's `OTHERCSR_READ` hook fires (not the WRITE hook, to avoid double-applying the side-effect), inspects the request in `regs[10]`, calls the per-peripheral handler, and returns the response in `*value` (which the core then writes back into `a0`). The WRITE hook is a deliberate no-op for these CSRs. Documented at `src/luat_ndk_host.c:77-93`.

## 8. Threading and lifecycle

### State machine

```
            init / reset
DEINIT ────────────────────▶ IDLE
                              │
                              │ exec()
                              ▼
                          RUNNING
                              │
                              │ finish (SYSCON / ecall / trap / timeout)
                              ▼
                            IDLE
                              │
                              │ start_thread()
                              ▼
                          RUNNING ──── stop() ──▶ STOPPING
                                                    │
                                                    │ finish
                                                    ▼
                                                  IDLE
                              │
                              │ reset()
                              ▼
                          RESETTING ──── finish ──▶ IDLE
```

Implemented in `luat_ndk_state_t` (`include/luat_ndk.h:59-65`) and `ndk_state_active()` (`src/luat_ndk.c:722-724`). All transitions go through the `luat_ndk_lock` / `ndk_unlock` critical section.

### Async execution

`ndk.start_thread` spawns an RTOS task (`luat_rtos_task_handle worker`); `ndk.stop_thread` sets `stop_request = 1` and polls every `NDK_STOP_POLL_MS = 10` ms up to `NDK_DEINIT_WAIT_MS = 1000` ms. The polling loop relies on the 256-step chunking in §5.

### `__gc` finalization

The Lua userdata's `__gc` calls `luat_ndk_stop_thread` with `LUAT_WAIT_FOREVER` then `luat_ndk_deinit`. This is the only safe way to free a context from Lua; the binding is structured so that even an error in `rv32i` doesn't leak the userdata.

## 9. Lua binding

| API | Purpose |
|---|---|
| `ndk.rv32i(path, mem_size, exchange_size, opts)` | Create + load. Returns userdata or `nil, err`. |
| `ndk.setData(ctx, data, offset)` | Write to exchange. |
| `ndk.getData(ctx, [buff], len, offset)` | Read from exchange. |
| `ndk.exec(ctx, opts)` | Sync run. Returns `true, retval` or `false, err, mcause, mtval`. |
| `ndk.thread(ctx, opts)` | Async run. Returns thread id or `nil, "busy"`. |
| `ndk.stop(ctx, wait_ms)` | Stop async thread. Idempotent. |
| `ndk.reset(ctx)` | Reload image + zero RAM + PC=0x80000000. |
| `ndk.info(ctx)` | Get state. Returns a table of fields documented in `docs/lua-api.md`. |
| `ndk.utest(case)` (with `LUAT_USE_UTEST`) | Run internal unit test. |

Error string map (`ndk_errstr`):

| Code | String |
|---|---|
| `LUAT_NDK_OK` (0) | `"ok"` |
| `LUAT_NDK_ERR_PARAM` (-1) | `"invalid param"` |
| `LUAT_NDK_ERR_NOMEM` (-2) | `"no memory"` |
| `LUAT_NDK_ERR_IO` (-3) | `"io error"` |
| `LUAT_NDK_ERR_IMAGE_TOO_LARGE` (-4) | `"image too large"` |
| `LUAT_NDK_ERR_BUSY` (-5) | `"busy"` |
| `LUAT_NDK_ERR_TRAP` (-6) | `"trap"` |
| `LUAT_NDK_ERR_TIMEOUT` (-7) | `"timeout"` |

## 10. Guest-side helper library

`components/ndk/guest/include/luat_ndk_helper.h` — header-only, ~250 lines, 8 groups: constants, startup, exchange, byte order, log, GPIO pack, status decoders, host hash, event peek. See `docs/api-helper.md` for the full reference.

**Why header-only**: every wrapper is `static inline` (1-3 asm instructions); a separate `.c` would add no value. Examples pick it up via the `-I` flag the build script already uses for `luat_ndk_builtin.h` / `luat_ndk_abi.h`.

**Out of scope**: memcpy wrappers, printf-style varargs, FP helpers, UART RX user-space buffering. The first three duplicate compiler builtins or require significant code; the last is what the existing `ndk_uart_*` CSRs already provide.

**Future direction**: a Rust `ndk-helper` crate is the natural follow-up. Not in this PR.

## 11. Build and toolchain

### Guest

- RISC-V GNU (`riscv64-unknown-elf` / `riscv32-unknown-elf` / `riscv-none-elf`) or LLVM `clang` + `ld.lld` + `llvm-objcopy`.
- Build flags: `-march=rv32ima_zicsr -mabi=ilp32 -ffreestanding -nostdlib -fno-stack-protector -fdata-sections -ffunction-sections -Os -Wl,--gc-sections`.
- Per-example `build.ps1` delegates to `components/ndk/guest/examples/build_example.ps1`.
- The `rust_hello_world` example uses `rustup target add riscv32imac-unknown-none-elf` + `rustup component add rust-src` + `cargo install cargo-binutils`, built by its own `build.ps1`.

### PC firmware

- `bsp/pc/build_windows_32bit_msvc.bat` (NOT raw `xmake -y`).
- Incremental: 10-30 s; cold: 2-5 min.
- Output: `bsp/pc/build/out/luatos-lua.exe`.
- NDK sources are pulled in via `bsp/pc/xmake.lua:213-216`:
  ```lua
  add_includedirs(luatos.."components/ndk/include",{public = true})
  add_files(luatos.."components/ndk/src/*.c")
  add_files(luatos.."components/ndk/binding/*.c")
  ```

### Module registration

`bsp/pc/port/luat_base_mini.c:130-132` (guarded by `LUAT_USE_NDK`):
```c
{"ndk", luaopen_ndk},
```

## 12. Test matrix

| Suite | File | Baseline | Coverage |
|---|---|---|---|
| `ndk_basic` | `testcase/ndk/ndk_basic/scripts/ndk_test.lua` | 42 passed, 0 failed | Lifecycle, RV32F regression (20+ binaries), exchange, info, error paths. Phase 3: `MEM_SIZE = 64 KiB` (was 32 KiB). |
| `ndk_hostabi_basic` | `testcase/ndk/ndk_hostabi_basic/scripts/ndk_hostabi_test.lua` | 39 passed, 0 failed | Host ABI v1 command chain (META / GPIO v2 / UART v1 / Crypto v1), `ndk_crypto_perf_test.lua` benchmark. |
| Smoke 113 | `bsp/pc/test/113.ndk_simple/main.lua` | passes | Lifecycle. Phase 3: **512 KiB RAM smoke** (`assert(info.mem == 512*1024)`). |
| RV32F regression | `guest/fixtures/rv32f_regression` | 20+ .S pass | FADD / FSUBMUL / FCLASS / FCMP / FSGNJ / FMV / FLWFSW / FCVT.* / FCSR / hardfloat_*. |
| Host ABI v1 | `guest/fixtures/hostabi_v1` | 39/39 cmd chain pass | Full command op dispatch + RV32C variant. |

## 13. Phase changelog

| Phase | Date | Summary |
|---|---|---|
| 0 | 2025-12 | mini-rv32ima bring-up. 32 KiB RAM ceiling. baremetal.bin + simple smoke. |
| 1 | 2026-05 | Host ABI v1 + GPIO v2 + UART v1. `hostabi_v1` fixture + `ndk_stubs.c`. `event ring`. |
| 2 | 2026-05 | RV32F float extension (`rv32imf`). Host-backed rounding (RNE/RTZ/RDN/RUP). |
| 2b | 2026-05 | RMM (`rm/frm=4`) limitation: trap as illegal, with `baremetal_fadd_rmm_static/dynamic.bin` regression. |
| 3 | 2026-06 | This PR. `luat_ndk_helper.h` (header-only guest standard library). `LUAT_NDK_MAX_RAM_SIZE` 32 KiB → 512 KiB. `step_budget = 0` semantics: unlimited (was default 32768). 4 C examples refactored to use helper. `crypto_hash_demo` switches from pure-software MD5/CRC32 to host CSR 0x230/0x231. README → `docs/*.md` split. `DESIGN.md` (this file). |

## 14. Non-goals

- **No real-time guarantees** — the stepper is best-effort; the host is free to schedule other tasks between chunks.
- **No in-RV debugger** — no GDB stub, no breakpoint support, no single-step from outside.
- **No multi-core** — each `luat_ndk_t` is single-core. Multiple contexts run on the host thread, not on the guest.
- **No MMU** — Sv32 (or any paging) is not supported. Guests see a flat 32-bit address space and the entire 16 MiB MMIO region is a no-op except for `0x11100000`.
- **No privileged-mode guests** — M-mode only. There's no S-mode / U-mode handling and no attempt to virtualize CSRs.
- **No production firmware support** — only the PC emulator is validated. No Air1601 / Air780E / Air8000 / etc. integration; bringing NDK onto a real BSP is a separate effort.
- **No on-disk persistence** — images are loaded from VFS at `ndk.rv32i` time and discarded on deinit. No save/restore of CPU state.
- **No Rust wrapper crate** — `luat_ndk_helper.h` is C-only `static inline`. A future `ndk-helper` crate is documented as follow-up but not in this PR.

## 15. Acceptance criteria

- [x] `nndk_hostabi_basic` regression holds at **39 passed, 0 failed**.
- [x] `ndk_basic` regression holds at **42 passed, 0 failed** (with `MEM_SIZE = 64 KiB`).
- [x] `bsp/pc/test/113.ndk_simple` smoke test asserts `info.mem == 512*1024` and passes.
- [x] 4 C examples each compile and produce a `<name>.bin` artifact:
  - `hello_world`, `exchange_buffer_demo`, `gpio_hostabi_demo`, `crypto_hash_demo` (C)
- [x] `crypto_hash_demo` calls host CSR 0x230 / 0x231 (the host returns a non-error status and the resulting MD5 / CRC32 values match the expected ones — verifiable by a `ndk.info.features` bit5 = 1 plus a 16-byte MD5 verification step added in the testcase).
- [x] `README.md` reduced to a ~70-line index pointing to `docs/*.md` and `DESIGN.md`.
- [x] `DESIGN.md` (this file) merged.
- [x] `hostabi_v1` fixture's `ndk_stubs.c` remains as out-of-line test hooks (intentional, documented).
- [x] `docs/changelog.md` initial entry summarises Phase 3.
