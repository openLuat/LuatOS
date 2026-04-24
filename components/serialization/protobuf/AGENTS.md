# AGENTS.md — protobuf component

## Overview

This component provides Lua bindings for Protocol Buffers (protobuf) encoding and decoding. It is built around `pb.h`, a single-header C library compiled as a static implementation inside `luat_lib_protobuf.c`.

Key files:
- `pb.h` — single-header protobuf library (hash tables, type registry, encode/decode)
- `luat_lib_protobuf.c` — Lua binding layer; includes `pb.h` as static implementation via `#define PB_STATIC_API`

---

## Architecture

### Include model

`pb.h` is included with `#define PB_STATIC_API` which causes all `PB_API` symbols to be compiled as `static`. There is exactly one translation unit (`luat_lib_protobuf.c`). Any macro defined **before** `#include "pb.h"` is visible inside the compiled `pb.h` implementation — including `PB_DEBUG_LOG`.

### Key data structures

| Type | Size (ARM 32-bit) | Size (PC 64-bit) | Notes |
|------|-------------------|------------------|-------|
| `pb_Key` | 4 bytes | 8 bytes | `ptrdiff_t` |
| `pb_Entry` | 8 bytes | 16 bytes | `{ptrdiff_t next; pb_Key key;}` |
| `pb_FieldEntry` | 12 bytes | 24 bytes | `{pb_Entry entry; pb_Field *value;}` |
| `pb_TypeEntry` | 12 bytes | 24 bytes | `{pb_Entry entry; pb_Type *value;}` |
| `pb_Table` | 16 bytes | 24 bytes | `{unsigned size; unsigned lastfree; unsigned entry_size:31; unsigned has_zero:1; pb_Entry *hash;}` |
| `pb_HeapBuffer` | 8 bytes | 16 bytes | SSO string buffer |
| `PB_SSO_SIZE` | 8 bytes | 16 bytes | Small-string optimization threshold |

### Hash table (`pb_Table`)

- `entry_size` is a **31-bit bitfield**. This is the critical size field used for all slot arithmetic.
- `has_zero` is a **1-bit bitfield** indicating whether key=0 is stored (special-cased in `pb_nextentry`).
- Slots are at byte offsets `0, entry_size, 2*entry_size, ...` within `hash`.
- `pb_gettable`: direct hash lookup via `pbT_hash` then chaining.
- `pb_nextentry`: iterates all slots by stride. Starts at `i += entry_size` from 0 (or from the last returned entry).

---

## Debug Logging

All internal diagnostic logging is controlled by the `PB_DEBUG_LOG` macro defined in `pb.h`. By default it is a **no-op**. To enable, define it before including `pb.h`:

```c
#define PB_DEBUG_LOG(fmt, ...) LLOGI(fmt, ##__VA_ARGS__)
#include "pb.h"
```

In `luat_lib_protobuf.c`, to enable debug logging, add the define before the existing `#include "pb.h"` line:

```c
/* Uncomment to enable pb.h internal diagnostics: */
/* #define PB_DEBUG_LOG(fmt, ...) LLOGI(fmt, ##__VA_ARGS__) */
#define PB_STATIC_API
#include "pb.h"
```

### What PB_DEBUG_LOG covers

| Location | What it logs |
|----------|-------------|
| `pb_prepbuffsize` | `os_realloc` failures (OOM during buffer growth) |
| `pb_poolalloc` | `os_malloc` failures (OOM during pool page allocation) |
| `pb_resizetable` | `os_malloc` failures during hash table resize |
| `pbL_loadField` | Field registration success (`size` + `entry_size` after each insert) and `pb_newfield` failures |
| `pbL_loadType` | Type registration start and completion (`field_tags` + `types` table sizes) |
| `pb_nextentry` | Per-call: table pointer, `size`, `entry_size`, computed `size` product, `has_zero`, `pentry`; per-slot: offset and key; exhaustion message |

---

## GCC -Os ARM Stack-Slot Aliasing + Strict-Aliasing: General Pattern

This is the class of bugs that caused the ARM encode failure. Two interrelated compiler bugs were triggered simultaneously.

### Bug 1: Strict-aliasing UB (`-fstrict-aliasing`)

The old code cast the iterator state pointer to a different type via `(const pb_Entry**)&e` where `e` was `pb_FieldEntry*` or `pb_TypeEntry*`. This violates C strict-aliasing rules: GCC can assume `pb_FieldEntry*` and `pb_Entry*` don't alias each other, and with `-fstrict-aliasing` (enabled by `-O2` and `-Os`) it may generate incorrect code. Upstream [issue #261](https://github.com/starwing/lua-protobuf/issues/261) documented a segfault caused exactly by this.

**Fix**: Use `const pb_Entry *ent` (the correct type for `pb_nextentry`) as the iterator state. Cast to the concrete type (`pb_FieldEntry*`, `pb_TypeEntry*`) only INSIDE the loop body, after `pb_nextentry` has updated `ent`.

### Bug 2: Stack-slot aliasing (`GCC -Os` ARM)

GCC `-Os` on ARM uses a single `push {r0, r1, r2, ...}` prologue to save argument registers AND allocate stack frame space. If a local variable is allocated in the same stack slot as a saved argument, the compiler may skip the `= NULL` initialization store, leaving the local with the argument's value (non-NULL). This was the root cause of the ARM `pb_nextfield` encode failure.

### The vulnerable pattern

Any function where a local pointer is initialized to `NULL` and then passed **by address** to an iterator is potentially vulnerable:

```
push {r0, r1, r2, r4, r5, lr}   ; saves args AND allocates frame space
```

Stack slots `[sp+0]`, `[sp+4]`, `[sp+8]` now hold the saved argument values. GCC may allocate a local pointer in one of these slots and skip its initialization store.

### Pattern 1 — two-step NULL init (preferred code fix: ternary + correct type)

```c
/* VULNERABLE — strict-aliasing UB AND potential stack-slot aliasing: */
pb_FieldEntry *e = NULL;
if (cond) e = (pb_FieldEntry*)pb_gettable(...);
while (pb_nextentry(table, (const pb_Entry**)&e)) { ... }  /* bad cast! */
```

**Fix**: Initialize via ternary (prevents stack-slot aliasing), use `const pb_Entry*` as iterator state (no aliasing violation), cast inside loop:

```c
/* SAFE — correct type + ternary init: */
const pb_FieldEntry *_fe = cond ? (const pb_FieldEntry*)pb_gettable(...) : NULL;
const pb_Entry *ent = _fe ? &_fe->entry : NULL;
while (pb_nextentry(table, &ent)) {          /* no cast on &ent! */
    const pb_FieldEntry *e = (const pb_FieldEntry*)ent;  /* cast AFTER update */
    ...
}
```

The two-level ternary forces the compiler to compute and store each value fresh.

This is why `pb_nextfield` and `pb_nexttype` were fixed this way.

### Pattern 2 — simple NULL init (fix: correct type + pragma)

```c
/* VULNERABLE: */
const pb_TypeEntry *te = NULL;
while (pb_nextentry(table, (const pb_Entry**)&te)) { ... }  /* bad cast! */
```

**Fix**: Use `const pb_Entry*` (removes strict-aliasing UB), cast inside loop, add pragma (prevents stack-slot aliasing since ternary doesn't apply):

```c
#pragma GCC push_options
#pragma GCC optimize ("O1")
/* SAFE: */
const pb_Entry *e = NULL;
while (pb_nextentry(table, &e)) {
    const pb_TypeEntry *te = (const pb_TypeEntry*)e;  /* cast AFTER update */
    ...
}
#pragma GCC pop_options
```

This is used for `pb_free`, `pb_deltype`, and `pb_sortfield`.

### Functions fixed in this file

| Function | Args | Bug | Fix applied |
|----------|------|-----|-------------|
| `pb_nextentry` | 2 | bitfield misoptimization | local `size_t es` |
| `pb_nextfield` | 3 | strict-aliasing + stack-slot | `const pb_Entry *ent` + ternary |
| `pb_nexttype` | 2 | strict-aliasing + stack-slot | `const pb_Entry *ent` + ternary |
| `pb_free` | 1 | strict-aliasing + stack-slot | `const pb_Entry *e` + pragma O1 |
| `pb_sortfield` | 1 | stack-slot (passes NULL to pb_nextfield) | pragma O1 |
| `pb_deltype` | 2 | strict-aliasing + stack-slot | `const pb_Entry *e` + pragma O1 |

### Checklist for new iterator functions

If you add a function that uses `pb_nextentry` or `pb_nextfield`:
1. Does it declare a local pointer and pass `&ptr` to the iterator?
2. **Never** cast `(const pb_Entry**)&ptr` — always use a separate `const pb_Entry *ent` variable.
3. Does it use Pattern 1 (conditional init)? → Use ternary init for `ent`.
4. Does it use Pattern 2 (simple NULL init)? → Add `#pragma GCC optimize("O1")`.

---



### Symptom
`protobuf.encode()` returned an empty string on ARM M7 modules while working correctly on the PC simulator.

### Root cause (confirmed by disassembly)

**Two functions** required `-Os` protection, not just one:

#### 1. `pb_nextentry` — bitfield misoptimization
GCC `-Os` on ARM could misread the 31-bit `entry_size` bitfield through a `const` pointer, causing the loop stride to be 0. Fixed by reading `t->entry_size` into a plain `size_t es` local, and guarding the function with `#pragma GCC optimize("O1")`.

#### 2. `pb_nextfield` — stack slot aliasing bug (the actual root cause)
GCC `-Os` miscompiles `pb_nextfield` on ARM. The local `const pb_FieldEntry *e = NULL` is supposed to start as NULL, but the optimizer:
- allocates `e` in the same stack slot where the `pfield` argument was saved by the prologue (`push {r0, r1, r2, r4, r5, lr}`)
- **never zeroes that slot** — so `e` starts with the value `pfield` (non-NULL!) instead of NULL
- **discards the return value of `pb_gettable`** — the non-NULL branch cannot update `e` correctly either

As a result, `pb_nextentry` is called with `*pentry = pfield_addr` (the address of the caller's `pb_Field*` variable). This is garbage as a `pb_Entry*`: `i = pfield_addr - hash_addr` is a huge number, `i < size` is immediately false, and `pb_nextentry` returns 0. No fields are iterated.

**Evidence from disassembly of Os `.o` file:**
```
 0: push {r0, r1, r2, r4, r5, lr}    ; [sp+4] = r1 = pfield (NOT zeroed as NULL!)
 ...
12: bl pb_gettable                    ; result in r0 — immediately discarded below
16: add r1, sp, #4                    ; r1 = &[sp+4] = &pfield (contains pfield, not NULL)
18: mov r0, r4
1a: bl pb_nextentry                   ; called with *pentry = pfield_addr ← WRONG
```

The fix is a ternary initialization for `pb_nextfield` (and `pb_nexttype`), and `#pragma GCC optimize("O1")` for `pb_nextentry`, `pb_free`, `pb_sortfield`, and `pb_deltype` in `luat_lib_pb.h`.

### Diagnostic approach that worked

Add `PB_DEBUG_LOG` calls **inside** `pb_nextentry` itself (not just the surrounding Lua binding code). This is critical because:
- External reads of `t->field_tags.size/entry_size` from the binding layer showed correct values (8/12).
- Slot dump from the binding layer showed correct keys at correct offsets.
- `pb_gettable` worked correctly.
- Only by logging INSIDE `pb_nextentry` was the actual computed `size` / `entry_size` visible.

### Systematic debugging steps used

1. Add `LLOGI` in the Lua binding (`Lpb_load`, `Lpb_encode`) to see high-level state — confirmed load succeeded, type found, field_count=3.
2. Add logs to `pbL_loadField` / `pbL_loadType` in `pb.h` — confirmed `entry_size=12` correct during AND after load on ARM.
3. Add logs in `Lpb_encode` to test `pb_nextfield` vs `pb_field(t,1)` — confirmed iteration fails while direct lookup works.
4. Add raw hash slot dump in `Lpb_encode` — confirmed all entries at correct offsets with correct keys.
5. Add logs **inside `pb_nextentry`** — decisive step revealing what the function actually computed.
6. Generate two `.o` files (O1 vs Os), disassemble with `arm-none-eabi-objdump`, and compare `pb_nextfield` — pinpointed the exact stack-slot aliasing bug.

### Key insights

- When iterating fails but direct lookup works on the SAME table, the bug is in the iterator's compiled form, not the data.
- GCC `-Os` is not guaranteed to be equivalent to `-O1` for code involving local pointer variables aliased through stack slots on ARM 32-bit.
- Check relocation records (`objdump -r`) to verify which symbol a `bl` actually calls.
- When `-O1` works and `-Os` does not, compare disassembly of the **calling** function (e.g., `pb_nextfield`), not just the function that fails (e.g., `pb_nextentry`).

### Size differences (ARM 32-bit vs PC 64-bit)

| Item | ARM | PC |
|------|-----|----|
| `sizeof(pb_HeapBuffer)` | 8 | 16 |
| `PB_SSO_SIZE` | 8 | 16 |
| `sizeof(pb_Entry)` | 8 | 16 |
| `sizeof(pb_FieldEntry)` | 12 | 24 |
| `sizeof(pb_Table)` | 16 | 24 |

These differences mean any code with raw pointer arithmetic must be verified on both platforms.

---

## Testing

```powershell
# Build PC simulator
cd bsp/pc && xmake -y

# Run protobuf test
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\protobuf\protobuf_basic\scripts\
```
