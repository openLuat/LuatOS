/* nonleaf_call_demo — regression for NDK_GUEST_START link-register bug
 *
 * This guest exercises the call path that exposed the bug in
 * components/ndk/guest/include/luat_ndk_helper.h:NDK_GUEST_START — a
 * non-inline helper function called from main().  Before the fix, the
 * helper macro emitted `jalr zero, t0` (no link), so main()'s `ret`
 * would jump to ra=0 (host zeroed GPRs at reset) and the stepper would
 * raise mcause=1 / mtval=0 (instruction access fault at PC=0).
 *
 * main() also intentionally does NOT call ndk_exit_ok(); the natural
 * `return 0;` is the path that has to keep working.  Exchange buffer:
 *   [0] compute(a, b) — written by the helper
 *   [1] input a (read from exchange on entry, untouched here)
 *   [2] input b (read from exchange on entry, untouched here)
 */
#include "luat_ndk_helper.h"

/* non-inline: out-of-line definition forces the compiler to emit a
 * real `call`/`ret` pair and a frame for main().  This is the exact
 * shape that triggered the regression.  noinline is needed because at
 * -Os clang is otherwise willing to inline a static single-call helper
 * even without always_inline. */
__attribute__((noinline)) static uint32_t compute(uint32_t a, uint32_t b) {
    return (a * 31u) ^ (b + 0x9E3779B9u);
}

static int main(void) {
    volatile uint32_t *ex = ndk_exchange_u32(0);
    ex[0] = compute(ex[1], ex[2]);
    return 0;
}

NDK_GUEST_START(main)
