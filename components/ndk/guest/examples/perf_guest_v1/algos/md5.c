/*
 * perf_md5_run — MD5 (RFC 1321), guest-side C implementation.
 *
 * IMPORTANT: this MUST NOT call ndk_hash_md5 (CSR 0x230) or any other
 * host-ABI shortcut. The whole point of the perf test is to compare
 * guest-implemented MD5 against a pure-Lua implementation; using
 * CSR 0x230 would degenerate the test into "host C vs Lua".
 *
 * Reference: RFC 1321 (https://www.rfc-editor.org/rfc/rfc1321).
 *
 * Output: 16 bytes (4 × uint32_t little-endian) appended to the payload.
 */
#include "luat_ndk_helper.h"
#include "../perf_proto.h"

#include <stdint.h>

/* Per-round shift amounts (RFC 1321 §3.4 step 4.1). */
static const uint32_t md5_s[64] = {
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20, 5,  9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
};

/* Precomputed "K" constants — RFC 1321 §3.4 step 3.4 (floor(2^32 * abs(sin(i+1))).
 * We bake the table into .rodata rather than computing it at boot —
 * 256 bytes of constant data is cheaper than the libc sin() call. */
static const uint32_t md5_k[64] = {
    0xD76AA478u, 0xE8C7B756u, 0x242070DBu, 0xC1BDCEEEu,
    0xF57C0FAFu, 0x4787C62Au, 0xA8304613u, 0xFD469501u,
    0x698098D8u, 0x8B44F7AFu, 0xFFFF5BB1u, 0x895CD7BEu,
    0x6B901122u, 0xFD987193u, 0xA679438Eu, 0x49B40821u,
    0xF61E2562u, 0xC040B340u, 0x265E5A51u, 0xE9B6C7AAu,
    0xD62F105Du, 0x02441453u, 0xD8A1E681u, 0xE7D3FBC8u,
    0x21E1CDE6u, 0xC33707D6u, 0xF4D50D87u, 0x455A14EDu,
    0xA9E3E905u, 0xFCEFA3F8u, 0x676F02D9u, 0x8D2A4C8Au,
    0xFFFA3942u, 0x8771F681u, 0x6D9D6122u, 0xFDE5380Cu,
    0xA4BEEA44u, 0x4BDECFA9u, 0xF6BB4B60u, 0xBEBFBC70u,
    0x289B7EC6u, 0xEAA127FAu, 0xD4EF3085u, 0x04881D05u,
    0xD9D4D039u, 0xE6DB99E5u, 0x1FA27CF8u, 0xC4AC5665u,
    0xF4292244u, 0x432AFF97u, 0xAB9423A7u, 0xFC93A039u,
    0x655B59C3u, 0x8F0CCC92u, 0xFFEFF47Du, 0x85845DD1u,
    0x6FA87E4Fu, 0xFE2CE6E0u, 0xA3014314u, 0x4E0811A1u,
    0xF7537E82u, 0xBD3AF235u, 0x2AD7D2BBu, 0xEB86D391u
};

#define F(x, y, z) (((x) & (y)) | (~(x) & (z)))
#define G(x, y, z) (((x) & (z)) | ((y) & ~(z)))
#define H(x, y, z) ((x) ^ (y) ^ (z))
#define I(x, y, z) ((y) ^ ((x) | ~(z)))

/* Process a single 64-byte block. The state registers (a/b/c/d) are
 * updated in place. */
static void md5_process_block(uint32_t state[4], const uint8_t block[64]) {
    uint32_t a = state[0], b = state[1], c = state[2], d = state[3];
    uint32_t x[16];

    /* Decode the 64-byte block into 16 little-endian 32-bit words. */
    for (int i = 0; i < 16; i++) {
        x[i] = ((uint32_t)block[i*4 + 0])        |
               ((uint32_t)block[i*4 + 1] <<  8) |
               ((uint32_t)block[i*4 + 2] << 16) |
               ((uint32_t)block[i*4 + 3] << 24);
    }

    for (int i = 0; i < 64; i++) {
        uint32_t f, g;
        if (i < 16) {
            f = F(b, c, d);
            g = i;
        } else if (i < 32) {
            f = G(b, c, d);
            g = (5 * i + 1) & 15u;
        } else if (i < 48) {
            f = H(b, c, d);
            g = (3 * i + 5) & 15u;
        } else {
            f = I(b, c, d);
            g = (7 * i) & 15u;
        }
        uint32_t temp = d;
        d = c;
        c = b;
        /* (a + f + K[i] + x[g]) mod 2^32, then rotate left by S[i]. */
        uint32_t sum = a + f + md5_k[i] + x[g];
        b = c + ((sum << md5_s[i]) | (sum >> (32 - md5_s[i])));
        a = temp;
        (void)g;  /* used only via x[g] above */
    }

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
}

uint32_t perf_md5_run(const uint8_t *in, uint32_t in_len,
                      uint8_t *out, uint32_t *out_len,
                      uint32_t *elapsed_lo, uint32_t *elapsed_hi) {
    uint32_t t0 = ndk_time_us_lo();

    /* Init state (RFC 1321 §3.3 step 3.3.1). */
    uint32_t state[4] = {
        0x67452301u, 0xEFCDAB89u, 0x98BADCFEu, 0x10325476u
    };

    /* Process whole blocks. We need a scratch buffer for the padded
     * tail block; it lives in .bss (NOT the guest stack, which only
     * has a 16-byte red zone per luat_ndk_helper.h — putting a 64-byte
     * buffer on the stack would trigger mcause=7 store access fault
     * on the first write). */
    static uint8_t buf[64];

    /* We rely on the input being fully inside the exchange buffer
     * (the dispatcher enforces bounds). For chunked runs the caller
     * would need to handle the partial-block case differently; for
     * the perf suite in_len is always small enough to fit one chunk. */
    uint32_t i = 0;
    while (i + 64 <= in_len) {
        md5_process_block(state, in + i);
        i += 64;
    }

    /* Build the trailing block(s): message bits || 1 || 0..0 || length-in-bits (LE64).
     * The trailing block is at most 128 bytes (when the message is 56..64 mod 64
     * bytes long, the 1 + length doesn't fit and we need an extra block). */
    uint32_t tail = in_len - i;
    if (tail > 0) {
        /* Copy whatever tail bytes we have. */
        for (uint32_t k = 0; k < tail; k++) {
            buf[k] = in[i + k];
        }
    }
    /* Always set the 0x80 terminator. */
    buf[tail] = 0x80u;
    /* Zero out the rest up to byte 56. */
    for (uint32_t k = tail + 1; k < 56; k++) {
        buf[k] = 0u;
    }

    if (tail < 56) {
        /* Length fits in this block. */
        uint64_t bits = (uint64_t)in_len * 8u;
        for (int k = 0; k < 8; k++) {
            buf[56 + k] = (uint8_t)((bits >> (k * 8)) & 0xFFu);
        }
        md5_process_block(state, buf);
    } else {
        /* Need an extra block. Zero the bytes 56..63 of the first. */
        for (uint32_t k = 56; k < 64; k++) {
            buf[k] = 0u;
        }
        md5_process_block(state, buf);
        /* Second trailing block: all zeros except the length. */
        for (uint32_t k = 0; k < 56; k++) {
            buf[k] = 0u;
        }
        uint64_t bits = (uint64_t)in_len * 8u;
        for (int k = 0; k < 8; k++) {
            buf[56 + k] = (uint8_t)((bits >> (k * 8)) & 0xFFu);
        }
        md5_process_block(state, buf);
    }

    uint32_t t1 = ndk_time_us_lo();

    /* Write the 16-byte digest, little-endian. */
    ndk_store32_le(out +  0, state[0]);
    ndk_store32_le(out +  4, state[1]);
    ndk_store32_le(out +  8, state[2]);
    ndk_store32_le(out + 12, state[3]);

    *out_len    = 16u;
    *elapsed_lo = (t1 >= t0) ? (t1 - t0) : (0u - t0 + t1);
    *elapsed_hi = (t1 >= t0) ? 0u : 1u;

    return PERF_STATUS_OK;
}
