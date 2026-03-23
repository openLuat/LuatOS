#include <stdio.h>
#include <string.h>
#include <stdint.h>

#include "../src/h264_bitstream.h"

/* Emulation prevention removal - from h264_bitstream.c */
extern int h264_nalu_to_rbsp(const uint8_t *nalu_data, int nalu_size,
                              uint8_t *rbsp_data, int rbsp_size);
extern int h264_rbsp_to_nalu(const uint8_t *rbsp_data, int rbsp_size,
                              uint8_t *nalu_data, int nalu_size);

#define CHECK(cond, msg) do { \
    if (!(cond)) { fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); return 1; } \
} while(0)

int test_bitstream(void) {
    H264BitStream bs;

    /* ---- Test 1: basic bit reading ---- */
    {
        uint8_t data[] = {0xAB, 0xCD, 0xEF};
        /* 0xAB = 1010 1011 */
        bs_init(&bs, data, 3);
        CHECK(bs_bits_left(&bs) == 24, "bits_left init");

        CHECK(bs_read_u1(&bs) == 1, "bit 7 of 0xAB");
        CHECK(bs_read_u1(&bs) == 0, "bit 6 of 0xAB");
        CHECK(bs_read_u1(&bs) == 1, "bit 5 of 0xAB");
        CHECK(bs_read_u1(&bs) == 0, "bit 4 of 0xAB");
        /* remaining nibble = 1011 = 0x0B */
        CHECK(bs_read_bits(&bs, 4) == 0x0B, "lower nibble of 0xAB");

        /* 0xCD = 1100 1101 */
        CHECK(bs_read_bits(&bs, 8) == 0xCD, "byte 0xCD");
        /* 0xEF = 1110 1111 */
        CHECK(bs_read_bits(&bs, 8) == 0xEF, "byte 0xEF");
        CHECK(bs_bits_left(&bs) == 0, "bits exhausted");
    }

    /* ---- Test 2: peek does not advance ---- */
    {
        uint8_t data[] = {0xF0};
        bs_init(&bs, data, 1);
        uint32_t p = bs_peek_bits(&bs, 4);
        CHECK(p == 0x0F, "peek 4 bits of 0xF0 = 0x0F");
        /* Should still be at start */
        CHECK(bs_bits_left(&bs) == 8, "peek did not advance");
        CHECK(bs_read_bits(&bs, 4) == 0x0F, "read after peek");
    }

    /* ---- Test 3: byte alignment ---- */
    {
        uint8_t data[] = {0xFF, 0x00};
        bs_init(&bs, data, 2);
        CHECK(bs_byte_aligned(&bs), "aligned at start");
        bs_read_u1(&bs);
        CHECK(!bs_byte_aligned(&bs), "not aligned after 1 bit");
        bs_skip_bits(&bs, 7);
        CHECK(bs_byte_aligned(&bs), "aligned after 8 bits");
    }

    /* ---- Test 4: ue(v) decoding ---- */
    {
        /* Encode ue values in sequence:
         * ue=0: "1"           -> 1 bit
         * ue=1: "010"         -> 3 bits
         * ue=2: "011"         -> 3 bits
         * ue=3: "00100"       -> 5 bits
         * ue=4: "00101"       -> 5 bits
         * ue=5: "00110"       -> 5 bits
         * ue=6: "00111"       -> 5 bits
         * Total: 1+3+3+5+5+5+5 = 27 bits -> 4 bytes needed
         *
         * Bit string: 1 010 011 00100 00101 00110 00111 0
         * = 1010 0110 0100 0010 1001 1000 1110000
         * Byte 0: 1010 0110 = 0xA6
         * Byte 1: 0100 0010 = 0x42
         * Byte 2: 1001 1000 = 0x98
         * Byte 3: 1110 0000 = 0xE0 (padded)
         */
        uint8_t data[] = {0xA6, 0x42, 0x98, 0xE0};
        bs_init(&bs, data, 4);
        CHECK(bs_read_ue(&bs) == 0, "ue=0");
        CHECK(bs_read_ue(&bs) == 1, "ue=1");
        CHECK(bs_read_ue(&bs) == 2, "ue=2");
        CHECK(bs_read_ue(&bs) == 3, "ue=3");
        CHECK(bs_read_ue(&bs) == 4, "ue=4");
        CHECK(bs_read_ue(&bs) == 5, "ue=5");
        CHECK(bs_read_ue(&bs) == 6, "ue=6");
    }

    /* ---- Test 5: se(v) decoding ---- */
    {
        /* se values: se=0 (ue=0), se=1 (ue=1), se=-1 (ue=2), se=2 (ue=3), se=-2 (ue=4)
         * ue codes: 1, 010, 011, 00100, 00101
         * Bits: 1 010 011 00100 00101 (pad)
         * = 1010 0110 0100 0010 1
         * Byte 0: 0xA6, Byte 1: 0x42, Byte 2: 0x80
         */
        uint8_t data[] = {0xA6, 0x42, 0x80};
        bs_init(&bs, data, 3);
        CHECK(bs_read_se(&bs) == 0,  "se=0");
        CHECK(bs_read_se(&bs) == 1,  "se=1");
        CHECK(bs_read_se(&bs) == -1, "se=-1");
        CHECK(bs_read_se(&bs) == 2,  "se=2");
        CHECK(bs_read_se(&bs) == -2, "se=-2");
    }

    /* ---- Test 6: emulation prevention removal ---- */
    {
        /* Input with emulation prevention: 00 00 03 xx -> 00 00 xx */
        uint8_t input[]  = {0x00, 0x00, 0x03, 0x01, 0x00, 0x00, 0x03, 0x02};
        uint8_t output[16];
        int n = h264_nalu_to_rbsp(input, 8, output, 16);
        CHECK(n == 6, "rbsp size after emulation removal");
        CHECK(output[0] == 0x00, "rbsp[0]");
        CHECK(output[1] == 0x00, "rbsp[1]");
        CHECK(output[2] == 0x01, "rbsp[2] (03 removed)");
        CHECK(output[3] == 0x00, "rbsp[3]");
        CHECK(output[4] == 0x00, "rbsp[4]");
        CHECK(output[5] == 0x02, "rbsp[5] (03 removed)");
    }

    /* ---- Test 7: read_u8 ---- */
    {
        uint8_t data[] = {0xDE, 0xAD};
        bs_init(&bs, data, 2);
        CHECK(bs_read_u8(&bs) == 0xDE, "read_u8 first");
        CHECK(bs_read_u8(&bs) == 0xAD, "read_u8 second");
    }

    /* ---- Test 8: skip_bits ---- */
    {
        uint8_t data[] = {0xFF, 0x00};
        bs_init(&bs, data, 2);
        bs_skip_bits(&bs, 8);
        CHECK(bs_read_u8(&bs) == 0x00, "read after skip");
    }

    return 0;
}
