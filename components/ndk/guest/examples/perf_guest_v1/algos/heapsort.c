/*
 * perf_heapsort_run — in-place heapsort of int32 little-endian elements.
 *
 * Treats the input as n_elems = in_len / 4 signed 32-bit integers and
 * sorts them ascending using a classic bottom-up max-heap. The sorted
 * array is written back into the same input region (which doubles as
 * the output region per the perf_proto layout).
 *
 * Why heapsort rather than quicksort:
 *   - O(n log n) worst case (no quicksort pathological case on
 *     already-sorted input, which the test fixtures would expose);
 *   - branch-light inner loop, friendlier to the RV32 interpreter;
 *   - no recursion (the guest stack is only 16 bytes of red zone).
 *
 * The Lua baseline is a pure-Lua heapsort written to the same spec
 * (so the comparison is fair). We deliberately do NOT compare
 * against `table.sort`, which is native C — that would degenerate
 * the test into "host C vs Lua" rather than "NDK guest C vs Lua".
 */
#include "luat_ndk_helper.h"
#include "../perf_proto.h"

#include <stdint.h>

/* Read a little-endian int32 at byte offset i. */
static inline int32_t load_i32(const uint8_t *p, uint32_t i) {
    return (int32_t)((uint32_t)p[i]        |
                     ((uint32_t)p[i+1] <<  8) |
                     ((uint32_t)p[i+2] << 16) |
                     ((uint32_t)p[i+3] << 24));
}

/* Store a little-endian int32 at byte offset i. */
static inline void store_i32(uint8_t *p, uint32_t i, int32_t v) {
    p[i+0] = (uint8_t)( v        & 0xFFu);
    p[i+1] = (uint8_t)((v >>  8) & 0xFFu);
    p[i+2] = (uint8_t)((v >> 16) & 0xFFu);
    p[i+3] = (uint8_t)((v >> 24) & 0xFFu);
}

static inline void swap_i32(uint8_t *base, uint32_t i, uint32_t j) {
    int32_t a = load_i32(base, i * 4u);
    int32_t b = load_i32(base, j * 4u);
    store_i32(base, i * 4u, b);
    store_i32(base, j * 4u, a);
}

/* sift_down: restore the max-heap property at index `start` within
 * the range [0, end]. */
static void sift_down(uint8_t *base, uint32_t start, uint32_t end) {
    int32_t root_val = load_i32(base, start * 4u);
    for (;;) {
        uint32_t child = start * 2u + 1u;
        if (child > end) break;
        int32_t child_val = load_i32(base, child * 4u);
        uint32_t swp = start;
        if (child_val > load_i32(base, swp * 4u)) swp = child;
        if (child + 1u <= end &&
            load_i32(base, (child + 1u) * 4u) > load_i32(base, swp * 4u)) {
            swp = child + 1u;
        }
        if (swp == start) break;
        /* swap start <-> swp (use the in-register root_val trick to
         * avoid one redundant load). */
        store_i32(base, start * 4u, load_i32(base, swp * 4u));
        store_i32(base, swp * 4u, root_val);
        start = swp;
        root_val = load_i32(base, start * 4u);
    }
}

uint32_t perf_heapsort_run(const uint8_t *in, uint32_t in_len,
                           uint8_t *out, uint32_t *out_len,
                           uint32_t *elapsed_lo, uint32_t *elapsed_hi) {
    uint32_t t0 = ndk_time_us_lo();

    /* The protocol says: output is written back into the same region
     * (input/output share the payload slot). Cast away the const on
     * `in` for that reason; the dispatcher hands us the same address
     * for both pointers. */
    uint8_t *buf = (uint8_t *)in;

    uint32_t n = in_len / 4u;
    if (n < 2u) {
        /* Nothing to do (single element is trivially sorted). */
        *out_len = in_len;
    } else {
        /* Build the max-heap. Start from the last non-leaf node and
         * sift down each one. */
        for (uint32_t start = n / 2u; start > 0u; start--) {
            sift_down(buf, start - 1u, n - 1u);
        }
        /* Repeatedly swap root with the last unsorted element and
         * sift down the new root. */
        for (uint32_t end = n - 1u; end > 0u; end--) {
            swap_i32(buf, 0u, end);
            sift_down(buf, 0u, end - 1u);
        }
        *out_len = in_len;
    }

    uint32_t t1 = ndk_time_us_lo();

    *elapsed_lo = (t1 >= t0) ? (t1 - t0) : (0u - t0 + t1);
    *elapsed_hi = (t1 >= t0) ? 0u : 1u;

    return PERF_STATUS_OK;
    (void)out;  /* kept for API symmetry; never used in-place. */
}
