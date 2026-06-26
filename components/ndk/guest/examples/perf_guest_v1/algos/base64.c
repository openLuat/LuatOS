/*
 * perf_base64_run — Base64 encoder (RFC 4648 §4), guest-side C impl.
 *
 * Maps 3 input bytes -> 4 output chars using the standard alphabet:
 *   ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/
 * Trailing partial groups (1 or 2 leftover bytes) are zero-padded
 * and emitted with '=' / '==' as the RFC specifies.
 *
 * The decoder isn't benchmarked separately because it isn't on the
 * critical path of any common LuatOS use case; encoding alone is
 * the representative workload.
 *
 * Output: 4 * ceil(in_len / 3) bytes of ASCII, appended to the payload.
 */
#include "luat_ndk_helper.h"
#include "../perf_proto.h"

#include <stdint.h>

/* RFC 4648 §4 alphabet. */
static const char b64_alphabet[64] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    "0123456789+/";

/* Encode `in_len` bytes from `in` into `out`. The output is exactly
 * 4 * ceil(in_len / 3) bytes; `out_cap` must be at least that large.
 * Returns the actual number of bytes written, or 0 on cap underflow. */
static uint32_t base64_encode(const uint8_t *in, uint32_t in_len,
                              uint8_t *out, uint32_t out_cap) {
    uint32_t out_needed = 4u * ((in_len + 2u) / 3u);
    if (out_cap < out_needed) return 0u;

    uint32_t i = 0, o = 0;
    /* Whole triplets first. */
    while (i + 3u <= in_len) {
        uint32_t v = ((uint32_t)in[i] << 16) |
                     ((uint32_t)in[i+1] <<  8) |
                     ((uint32_t)in[i+2]);
        out[o++] = (uint8_t)b64_alphabet[(v >> 18) & 0x3Fu];
        out[o++] = (uint8_t)b64_alphabet[(v >> 12) & 0x3Fu];
        out[o++] = (uint8_t)b64_alphabet[(v >>  6) & 0x3Fu];
        out[o++] = (uint8_t)b64_alphabet[ v        & 0x3Fu];
        i += 3u;
    }
    /* Trailing partial group, if any. */
    uint32_t rem = in_len - i;
    if (rem == 1u) {
        uint32_t v = (uint32_t)in[i] << 16;
        out[o++] = (uint8_t)b64_alphabet[(v >> 18) & 0x3Fu];
        out[o++] = (uint8_t)b64_alphabet[(v >> 12) & 0x3Fu];
        out[o++] = '=';
        out[o++] = '=';
    } else if (rem == 2u) {
        uint32_t v = ((uint32_t)in[i] << 16) | ((uint32_t)in[i+1] << 8);
        out[o++] = (uint8_t)b64_alphabet[(v >> 18) & 0x3Fu];
        out[o++] = (uint8_t)b64_alphabet[(v >> 12) & 0x3Fu];
        out[o++] = (uint8_t)b64_alphabet[(v >>  6) & 0x3Fu];
        out[o++] = '=';
    }
    return o;
}

uint32_t perf_base64_run(const uint8_t *in, uint32_t in_len,
                         uint8_t *out, uint32_t *out_len,
                         uint32_t *elapsed_lo, uint32_t *elapsed_hi) {
    uint32_t t0 = ndk_time_us_lo();

    /* Compute the worst-case output size, then check fit. */
    uint32_t needed = 4u * ((in_len + 2u) / 3u);
    if (needed == 0u) {
        /* Empty input is a valid Base64 case (empty string). */
        *out_len = 0u;
    } else {
        uint32_t produced = base64_encode(in, in_len, out, *out_len);
        *out_len = produced;
        if (produced < needed) {
            uint32_t t1 = ndk_time_us_lo();
            *elapsed_lo = (t1 >= t0) ? (t1 - t0) : (0u - t0 + t1);
            *elapsed_hi = (t1 >= t0) ? 0u : 1u;
            return PERF_STATUS_BAD_BOUNDS;
        }
    }

    uint32_t t1 = ndk_time_us_lo();

    *elapsed_lo = (t1 >= t0) ? (t1 - t0) : (0u - t0 + t1);
    *elapsed_hi = (t1 >= t0) ? 0u : 1u;

    return PERF_STATUS_OK;
}
