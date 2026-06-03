# AGENTS.md — components/ndk

NDK (Native Development Kit) is the **RISC-V RV32IMA simulator** component in LuatOS. It runs MiniRV32IMA binary images in a sandboxed RV32 environment and exposes GPIO / UART / CRYPTO host-side peripherals through a CSR-based ABI.

For the user-facing API and the full CSR/MMIO table, see `components/ndk/README.md`. This document is the **development guide**: ABI internals, floating-point handling, threading model, ndk-specific coding conventions, and the canonical regression chain.

---

## Scope

This `AGENTS.md` covers:
- Adding new peripheral CSRs (the most common change)
- Guest ↔ Host ABI protocol
- Float (RV32F) implementation
- Threading and synchronization
- Coding conventions specific to ndk
- The NDK regression chain (RV32C + Host ABI + basic suite)

Out of scope (see `components/ndk/README.md`):
- Lua API (`ndk.rv32i`, `ndk.exec`, `ndk.thread`, `ndk.stop`, `ndk.reset`, `ndk.info`, `ndk.setData`, `ndk.getData`)
- Full CSR/MMIO address table
- End-to-end build & run instructions for the PC simulator

---

## Where to Look

| Task | Location |
|------|----------|
| Lua binding (entry points) | `binding/luat_lib_ndk.c` |
| Core simulator / lifecycle / FP | `src/luat_ndk.c` |
| CSR read/write dispatcher | `src/luat_ndk_host.c` |
| GPIO v2 peripheral | `src/luat_ndk_host_gpio.c` |
| UART v1 peripheral | `src/luat_ndk_host_uart.c` |
| CRYPTO v1 (MD5/CRC32) | `src/luat_ndk_host_crypto.c` |
| Event ring buffer | `src/luat_ndk_host_event.c` |
| ABI constants, CSR addresses, status codes | `include/luat_ndk_abi.h` |
| Host-side API | `include/luat_ndk_host.h` |
| Guest inline helpers (csrw wrappers) | `include/luat_ndk_builtin.h` |
| mini-rv32ima CPU core | `include/mini-rv32ima.h` |
| Guest fixtures (rv32f_regression, hostabi_v1) | `guest/fixtures/` |
| Regression suite | `testcase/ndk/ndk_basic/`, `testcase/ndk/ndk_hostabi_basic/` |

---

## ABI Communication

Guest ↔ Host uses RISC-V `csrrw` against CSR addresses defined in `include/luat_ndk_abi.h`. The full table is in `components/ndk/README.md` § CSR/MMIO 接口; only the class layout is summarized here:

- **Metadata class** (`0x13C`-`0x13F`): magic / version / features / last_error
- **Time class** (`0x141`-`0x143`): time_lo / time_hi / delay_us
- **Event class** (`0x144`-`0x145`): event_enable / event_pending
- **GPIO v2** (`0x210`-`0x214`): config / write_v2 / read_v2 / irq_state / irq_clear
- **UART v1** (`0x220`-`0x224`): config / tx / rx_state / rx_read / rx_clear
- **CRYPTO v1** (`0x230`-`0x231`): md5 / crc32

All new peripherals MUST follow the same pattern:
1. Define a CSR address range in `luat_ndk_abi.h` and a `LUAT_NDK_<PERIPHERAL>_STATUS_*` enum.
2. Add a handler branch in `luat_ndk_host_othercsr_write` / `_read` in `src/luat_ndk_host.c`.
3. Expose Guest-side inline accessors in `include/luat_ndk_builtin.h` so user Guest code does not write raw `csrw` asm.

---

## Floating-Point (RV32F)

`src/luat_ndk.c` implements RV32IMF FPU semantics. Key invariants:

- Uses `fenv_t` for host-side floating-point environment; cross-platform (GCC + MSVC).
- All FP arithmetic goes through `volatile` intermediates to prevent the host compiler from optimizing across the simulator boundary.
- NaN / Inf / sNaN are normalized correctly.
- RISC-V rounding mode (`rm` / `frm` 0..3 → RNE / RTZ / RDN / RUP) maps to host `FE_*`.

**Current limitation**: `RMM` (`rm` / `frm` 4) is **not** supported and traps as illegal-instruction. Do not enable `RMM` in fixtures; the regression `baremetal_fadd_rmm_static.bin` (`rm=4`) and `baremetal_fadd_rmm_dynamic.bin` (`frm=4 + rm=dyn`) exist precisely to lock this behaviour down.

---

## Threading Model

- **Sync mode** (`ndk.exec`): runs guest code on the calling thread.
- **Async mode** (`ndk.thread`): spawns an RTOS task for background execution; pair with `ndk.stop` to terminate.
- Thread safety: `ndk_lock` / `ndk_unlock` + critical section.
- **Atomic counters**: any counter touched by more than one thread (e.g. `ndk_thread_count`) MUST use `InterlockedIncrement` / `InterlockedDecrement` (MSVC) or `__sync_add_and_fetch` / `__sync_sub_and_fetch` (GCC). Plain `++` / `--` on a shared counter is a data race.

---

## Coding Conventions (ndk-specific)

In addition to the project-wide rules in the root `AGENTS.md`:

- **Address arithmetic**: when computing differences of two `uint32_t` addresses/offsets, cast each operand to `uint64_t` *before* subtraction — `uint32_t` wraps silently at zero.
- **Macro definitions**: when a macro body mixes `&` and `|` (or any other low-precedence operator), wrap the **entire expression** in parentheses so caller-side precedence cannot silently change semantics.
- **Resource cleanup**: if the same `free` / `release` / `memset-to-zero` sequence appears in 3+ places, extract a helper (the canonical example is `ndk_free_fields()` in `src/luat_ndk.c`) rather than duplicating the pattern.
- **CSR handler shape**: keep the read/write dispatch in `luat_ndk_host.c`; per-peripheral logic belongs in its own `luat_ndk_host_<peripheral>.c` file.
- **`volatile` in FP paths**: do not remove `volatile` from FP intermediates in `luat_ndk.c` — they are load-bearing for the simulator.

---

## Development Recipes

### How to Add a New Peripheral CSR

1. **Define address & status codes** in `include/luat_ndk_abi.h`:
   - Pick a free CSR address from the appropriate peripheral class range.
   - Add `LUAT_NDK_<PERIPHERAL>_STATUS_OK`, `_BUSY`, `_ERROR`, etc.
2. **Implement the handler** in `src/luat_ndk_host_<peripheral>.c`:
   - Implement `luat_ndk_host_<peripheral>_csr_read()` / `_write()`.
   - Wire it into the dispatcher in `src/luat_ndk_host.c::luat_ndk_host_othercsr_write/read`.
3. **Expose a Guest-side accessor** in `include/luat_ndk_builtin.h`:
   - Wrap `csrrw` in an inline asm helper; do not let user Guest code write raw `csrw`.
4. **Add a fixture & test**:
   - Extend `guest/fixtures/hostabi_v1/` to cover the new CSR.
   - Add a Lua case under `testcase/ndk/ndk_hostabi_basic/`.
5. **Rebuild guest fixture**: run `components/ndk/guest/build_hostabi_v1.ps1`, then run the regression chain (see below).

### How to Debug a Guest Program

- Guest writes to `NDK_CSR_PRINT_STR` / `NDK_CSR_PRINT_NUM` / `NDK_CSR_PRINT_PTR` to emit log lines.
- Host side captures and prints them in `luat_ndk_host_othercsr_write`.
- A normal exit writes `0x5555` to the SYSCON MMIO at `0x11100000`.
- A failing test typically shows either `exec fail timeout` (binary corrupted / source mismatch) or `can't open /luadb/baremetal.bin` (fixture not synced). Re-run `components/ndk/guest/fixtures/rv32f_regression/build.bat` to refresh.

### How to Verify ABI Compatibility

Run the `ndk_hostabi_basic` suite on the PC simulator:

```powershell
Set-Location bsp\pc
cmd /c build_windows_32bit_msvc.bat
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_hostabi_basic\scripts\
```

Expected baseline: `Total: 39 passed, 0 failed`. The `ndk_basic` suite covers core lifecycle (baseline 42 / 0). See the regression chain below for the full sequence.

---

## NDK RV32C / Host ABI 经验 (canonical)

These rules are enforced by the regression chain. Do not loosen them.

- **Host ABI guest fixture must use `zicsr` in `-march`** — `testcase/ndk/guest/build_hostabi_v1.ps1` should use `rv32ima_zicsr` / `rv32imac_zicsr` for both GNU and LLVM paths because the fixture emits `csrr/csrrw`. Plain `rv32ima` / `rv32imac` is not robust on post-split ISA toolchains.

- **`-march=rv32imac` alone is not proof that compressed instructions are present** — keep an explicit `rvc_smoke.S`, disassemble with `objdump -d -M no-aliases`, and assert the output contains `c.` mnemonics before accepting the generated RV32C binary.

- **Keep `.option norvc` local to CSR helper inline asm** — in `components/ndk/include/luat_ndk_builtin.h` and `testcase/ndk/guest/hostabi_v1/ndk_stubs.c`, `norvc` is an intentional fixed-width CSR boundary. Do not remove it just because the guest now supports RV32C, and do not expand it to file-global scope.

- **RV32C support in mini-rv32ima must use low-halfword-first fetch** — read the low 16 bits, decide 16/32-bit length from `ir16 & 0x3`, enforce 2-byte PC alignment, and trap on unsupported / all-zero compressed halfwords (`0x0000`) instead of treating them as no-ops.

### NDK regression chain (canonical)

```powershell
# 1. Rebuild Host ABI guest fixture (covers crypto + RV32C)
Set-Location components\ndk\guest
.\build_hostabi_v1.ps1

# 2. Rebuild ndk_basic guest fixture
Set-Location ..\..\testcase\ndk\ndk_basic\guest
.\build.ps1

# 3. Rebuild PC simulator
Set-Location ..\..\..\..\..\bsp\pc
cmd /c build_windows_32bit_msvc.bat

# 4. Run both suites
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_hostabi_basic\scripts\
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_basic\scripts\
```

Expected output: `Total: 39 passed, 0 failed` (hostabi) and `Total: 42 passed, 0 failed` (basic).

---

## Anti-Patterns

- ❌ Do NOT invent a new CSR address outside the ranges in `luat_ndk_abi.h`.
- ❌ Do NOT call guest-side raw `csrw` from user code — always go through `luat_ndk_builtin.h`.
- ❌ Do NOT touch `ndk_thread_count` (or any other shared counter) with plain `++`/`--` — use atomics.
- ❌ Do NOT skip the regression chain after touching the CSR dispatcher.
- ❌ Do NOT remove `volatile` from FP intermediates in `luat_ndk.c`.
- ❌ Do NOT remove `.option norvc` from the CSR helper inline asm.
- ❌ Do NOT enable `RMM` (`rm` / `frm` 4) in new fixtures — currently traps as illegal-instruction.

---

## Related Docs

- **User-facing runtime API & full CSR/MMIO table**: `components/ndk/README.md`
- **GPIO v2 design**: `docs/superpowers/specs/2026-05-20-gpio-v2-design.md`
- **UART v1 design**: `docs/superpowers/specs/2026-05-20-uart-v1-design.md`
- **mini-rv32ima upstream**: https://github.com/cnlohr/mini-rv32ima
