#include <stdio.h>
#include <string.h>
#include <stdint.h>

#include "../src/h264_bitstream.h"
#include "../src/h264_common.h"

extern int h264_cavlc_decode_block(H264BitStream *bs, int16_t *coeffs,
                                    int max_coeff, int nC);

#define CHECK(cond, msg) do { \
    if (!(cond)) { fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); return 1; } \
} while(0)

/* ---- Encode a coeff_token for nC >= 8 (fixed 6-bit code) ---- */
/* Upper 4 bits = TotalCoeff, lower 2 = TrailingOnes */
static void encode_coeff_token_nc8(uint8_t *buf, int *bit_pos,
                                    int total_coeff, int trailing_ones)
{
    uint32_t code = (uint32_t)((total_coeff << 2) | trailing_ones);
    int i;
    for (i = 5; i >= 0; i--) {
        int byte_idx = *bit_pos >> 3;
        int bit_idx  = 7 - (*bit_pos & 7);
        if ((code >> i) & 1) buf[byte_idx] |= (1 << bit_idx);
        (*bit_pos)++;
    }
}

/* Write a single bit */
static void write_bit(uint8_t *buf, int *bit_pos, int b) {
    int byte_idx = *bit_pos >> 3;
    int bit_idx  = 7 - (*bit_pos & 7);
    if (b) buf[byte_idx] |= (1 << bit_idx);
    (*bit_pos)++;
}

/* Write n bits from value (MSB first) */
static void write_bits(uint8_t *buf, int *bit_pos, uint32_t v, int n) {
    int i;
    for (i = n-1; i >= 0; i--)
        write_bit(buf, bit_pos, (v >> i) & 1);
}


int test_cavlc(void) {
    int16_t coeffs[16];
    H264BitStream bs;

    /* ---- Test 1: nC>=8, TotalCoeff=0 ---- */
    /* code = (0 << 2) | 0 = 0b000000, 6 bits */
    {
        uint8_t buf[4] = {0};
        int bp = 0;
        encode_coeff_token_nc8(buf, &bp, 0, 0);
        /* total_zeros: not needed since TotalCoeff=0 */
        bs_init(&bs, buf, 4);
        memset(coeffs, 0xAA, sizeof(coeffs));
        int ret = h264_cavlc_decode_block(&bs, coeffs, 16, 8);
        CHECK(ret == H264_OK, "nc8 TC=0 ret");
        /* All should be zero */
        int i, all_zero = 1;
        for (i = 0; i < 16; i++) if (coeffs[i] != 0) { all_zero = 0; break; }
        CHECK(all_zero, "nc8 TC=0 all zero");
    }

    /* ---- Test 2: nC>=8, TotalCoeff=1, TrailingOnes=1 ---- */
    /* code = (1<<2)|1 = 0b000101, 6 bits
     * TrailingOnes sign: 1 bit (0 = positive => +1)
     * total_zeros: TotalCoeff < max_coeff => need total_zeros
     *   for TotalCoeff=1, tzVlcIndex=1:
     *   total_zeros=0: code=1, len=1
     * So total_zeros = 0 => 1 bit "1"
     * run_before[0] = zeros_left = 0 => not read
     */
    {
        uint8_t buf[4] = {0};
        int bp = 0;
        encode_coeff_token_nc8(buf, &bp, 1, 1); /* TotalCoeff=1, T1=1 */
        write_bit(buf, &bp, 0); /* sign = 0 -> +1 */
        write_bit(buf, &bp, 1); /* total_zeros=0: code=1, len=1 */

        bs_init(&bs, buf, 4);
        memset(coeffs, 0, sizeof(coeffs));
        int ret = h264_cavlc_decode_block(&bs, coeffs, 16, 8);
        CHECK(ret == H264_OK, "nc8 TC=1 T1=1 ret");
        CHECK(coeffs[0] == 1, "nc8 TC=1 T1=1 coeff[0]=1");
    }

    /* ---- Test 3: zero block (TotalCoeff=0) for nC in [0,2) ---- */
    /* coeff_token code for TC=0: code=1, len=1 */
    {
        uint8_t buf[4] = {0x80}; /* bit 7 = 1 */
        bs_init(&bs, buf, 4);
        memset(coeffs, 0xAA, sizeof(coeffs));
        int ret = h264_cavlc_decode_block(&bs, coeffs, 16, 0);
        CHECK(ret == H264_OK, "nC=0 TC=0 ret");
        int i, all_zero = 1;
        for (i = 0; i < 16; i++) if (coeffs[i] != 0) { all_zero = 0; break; }
        CHECK(all_zero, "nC=0 TC=0 all zero");
    }

    /* ---- Test 4: TotalCoeff=1, TrailingOnes=1, nC=0
     * coeff_token table 0: TC=1,T1=1 -> code=01, len=2
     * sign: 0 (positive) -> +1
     * total_zeros for TC=1 (tzVlcIndex=1): tz=0 -> code=1, len=1
     */
    {
        uint8_t buf[4] = {0};
        int bp = 0;
        /* coeff_token: 01 (code=1, len=2) */
        write_bits(buf, &bp, 0x01, 2);
        /* sign: 0 (+1) */
        write_bit(buf, &bp, 0);
        /* total_zeros=0: code=1, len=1 */
        write_bit(buf, &bp, 1);

        bs_init(&bs, buf, 4);
        memset(coeffs, 0, sizeof(coeffs));
        int ret = h264_cavlc_decode_block(&bs, coeffs, 16, 0);
        CHECK(ret == H264_OK, "nC=0 TC=1 T1=1 ret");
        CHECK(coeffs[0] == 1, "nC=0 TC=1 T1=1 coeff[0]=1");
    }

    /* ---- Test 5: chroma DC, TotalCoeff=0 ---- */
    /* chroma DC coeff_token for TC=0: code=01, len=2 */
    {
        uint8_t buf[4] = {0};
        int bp = 0;
        write_bits(buf, &bp, 0x01, 2); /* TC=0 code */
        bs_init(&bs, buf, 4);
        memset(coeffs, 0xAA, sizeof(coeffs));
        int ret = h264_cavlc_decode_block(&bs, coeffs, 4, -1);
        CHECK(ret == H264_OK, "chroma DC TC=0 ret");
        CHECK(coeffs[0] == 0, "chroma DC TC=0 coeff[0]=0");
    }

    /* ---- Test 6: single non-trailing coefficient (TC=1, T1=0, nC=8) ---- */
    /* coeff_token:  6-bit fixed code for (TC=1, T1=0) in nC>=8 table
     * Level for coeff[0]:
     *   suffixLength=0; prefix=0 gives levelCode=0
     *   levelCode=0 (even) -> level = 1; first coeff when T1<3 adds 1 -> level = 2
     * total_zeros=0: 1-bit code "1" (tzVlcIndex=1, tz=0)
     */
    {
        uint8_t buf[8] = {0};
        int bp = 0;
        encode_coeff_token_nc8(buf, &bp, 1, 0);
        /* Level prefix: 1 bit "1" (prefix=0), suffix length=0 */
        write_bit(buf, &bp, 1);
        /* total_zeros=0: code=1, len=1 */
        write_bit(buf, &bp, 1);

        bs_init(&bs, buf, 8);
        memset(coeffs, 0, sizeof(coeffs));
        int ret = h264_cavlc_decode_block(&bs, coeffs, 16, 8);
        CHECK(ret == H264_OK, "level T1=0 ret");
        /* The level at position 0 should be 2 due to the adjustment */
        CHECK(coeffs[0] == 2, "level T1=0 coeff=2");
    }

    return 0;
}
