/*
 * Exact binary64 -> decimal conversion for components/printf.
 *
 * The implementation in printf_dtoa.c is adapted from newlib's mprec.c and
 * dtoa.c, which derive from David M. Gay's dtoa.  See printf_dtoa.c for the
 * original copyright notice.
 */
#ifndef PRINTF_DTOA_H
#define PRINTF_DTOA_H

#include <stddef.h>
#include <stdint.h>

/* Exact-path build switch, mpaland style: enabled unless disabled.
 *
 *   PRINTF_DISABLE_SUPPORT_DTOA  BSP config / build may opt out (32-bit or
 *                                flash-constrained builds)
 *   PRINTF_ENABLE_SUPPORT_DTOA   force it back on (e.g. 32-bit testing)
 *
 * The BSP header is picked up when the build makes it available; when it is
 * not visible the exact path stays enabled, so a 64-bit build cannot silently
 * fall back to the 9-digit formatter. */
#if defined(__has_include)
#  if __has_include("luat_conf_bsp.h")
#    include "luat_conf_bsp.h"
#  endif
#endif

#if defined(PRINTF_ENABLE_SUPPORT_DTOA)
#  undef PRINTF_DISABLE_SUPPORT_DTOA
#endif

#if defined(PRINTF_DISABLE_SUPPORT_FLOAT)
#  define PRINTF_DISABLE_SUPPORT_DTOA 1
#endif

#ifndef PRINTF_DISABLE_SUPPORT_DTOA
#  define PRINTF_SUPPORT_DTOA 1
#endif

/* Scratch space for the big integers.  The context lives on the stack of the
 * caller and never allocates from the heap.  3 KiB was sized from the peak
 * allocation of a double conversion (see the test driver). */
#ifndef PRINTF_DTOA_POOL_BYTES
#define PRINTF_DTOA_POOL_BYTES 3072
#endif

#define PRINTF_DTOA_KMAX 15

struct dtoa_bigint {
    struct dtoa_bigint *_next;
    int _k, _maxwds, _sign, _wds;
    uint32_t _x[1];
};

typedef struct printf_dtoa_ctx {
    struct dtoa_bigint **freelist;
    struct dtoa_bigint *p5s;
    struct dtoa_bigint *result;
    int result_k;
    int err;
    size_t used;                    /* high-water mark, for tests */
    uint64_t pool[PRINTF_DTOA_POOL_BYTES / 8];
} printf_dtoa_ctx;

void printf_dtoa_ctx_init(printf_dtoa_ctx *ctx);

/* dtoa modes (same as David Gay's dtoa):
 *   2: max(1, ndigits) significant digits, trailing zeros suppressed
 *   3: through ndigits past the decimal point, trailing zeros suppressed
 * Returns a NUL-terminated digit string living in ctx->pool; *rve points at
 * its end, *decpt is the decimal point position (value = 0.digits * 10^decpt)
 * and *sign is 1 for negative values (including -0).  Returns NULL if the
 * scratch pool is too small. */
char *printf_dtoa(printf_dtoa_ctx *ctx, double d, int mode, int ndigits,
                  int *decpt, int *sign, char **rve);

#endif
