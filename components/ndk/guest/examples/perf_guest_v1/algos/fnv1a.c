/*
 * perf_fnv1a_run — FNV-1a 32-bit hash, guest-side C implementation.
 *
 * Reference: http://www.isthe.com/chongo/tech/comp/fnv/
 *   offset basis = 0x811C9DC5
 *   FNV prime    = 0x01000193
 *
 * For each byte b:
 *     h = (h ^ b) * FNV_PRIME
 *
 * The hash is self-contained, fully deterministic, and uses only
 * 32-bit integer ops — no look-up tables, no SIMD, no host-ABI calls.
 * This is the canonical "smallest non-trivial byte stream digest"
 * algorithm to compare against a pure-Lua baseline.
 *
 * Output: 4 bytes (uint32_t little-endian) appended to the payload.
 */
#include "luat_ndk_helper.h"
#include "../perf_proto.h"

#include <stdint.h>

#define FNV1A_32_OFFSET_BASIS  0x811C9DC5u
#define FNV1A_32_PRIME         0x01000193u

uint32_t perf_fnv1a_run(const uint8_t *in, uint32_t in_len,
                        uint8_t *out, uint32_t *out_len,
                        uint32_t *elapsed_lo, uint32_t *elapsed_hi) {
    ndk_lprint("F1\n");
    /* Time the work. We sample CSR 0x141/0x142 (ndk_time_us_*) before
     * and after, in microseconds. The dispatcher in main.c copies
     * elapsed_lo/hi into result[2..3] when PERF_CTRL_LAST_CHUNK set. */
    uint32_t t0 = ndk_time_us_lo();

    uint32_t h = FNV1A_32_OFFSET_BASIS;
    for (uint32_t i = 0; i < in_len; i++) {
        h ^= (uint32_t)in[i];
        h *= FNV1A_32_PRIME;
    }

    uint32_t t1 = ndk_time_us_lo();

    ndk_store32_le(out, h);
    *out_len    = 4u;
    /* High half: only update if the counter rolled over t1 < t0.
     * For sub-second runs this is always 0; kept for correctness on
     * very long payloads that would wrap. */
    *elapsed_lo = (t1 >= t0) ? (t1 - t0) : (0u - t0 + t1);
    *elapsed_hi = (t1 >= t0) ? 0u : 1u;

    return PERF_STATUS_OK;
}
