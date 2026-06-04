# nonleaf_call_demo

## Purpose

Regression for the `NDK_GUEST_START` link-register bug. Exercises the
exact code shape that used to trap with `mcause=1, mtval=0`:

- `main()` calls a real (non-inline) helper function.
- `main()` returns naturally — no `ndk_exit_ok()` safety net.

If the helper macro still emits a `JALR` with `rd=x0`, this guest
fails the smoke test on `mcause=1, mtval=0`. After the fix, the host
sees `main()`'s `ret` land in the wfi park loop and reports success.

## Dependencies

- LLVM/Clang with RISC-V support: `clang` + `ld.lld` + `llvm-objcopy` (≥ 16.0)
- PowerShell

## Build

```powershell
cd components\ndk\guest\examples\nonleaf_call_demo
.\build.ps1
```

## Run (NDK)

Use `ndk.rv32i("...nonleaf_call_demo.bin", mem, exchange)` and
execute with `ndk.exec(...)`. The smoke test that drives this
example lives at `bsp/pc/test/116.ndk_examples_smoke/`.

## Expected Output

- Binary: `components\ndk\guest\examples\nonleaf_call_demo\build\nonleaf_call_demo.bin`
- Exchange on entry: `[1]=a`, `[2]=b` (any uint32 values the host seeds).
- Exchange on exit:  `[0] = compute(a, b) = (a*31) ^ (b + 0x9E3779B9)`, `[1]`, `[2]` unchanged.
- Completion: `main()` returns 0; the host reports `ok=true` with `ret=0`
  (no SYSCON 0x5555 write — this is the natural-return exit path).

## Disassembly expectations

`_start` should contain `jalr ra, 0x0(t0)` (link register written), not
`jalr zero, 0x0(t0)`. `main` should have a real frame
(`addi sp,sp,-N; sw ra,N(sp); ...; lw ra,N(sp); ret`).
