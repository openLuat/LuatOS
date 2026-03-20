/*
 * test_utils.h - Shared bit-writer utility for H264 test cases
 */
#ifndef TEST_UTILS_H
#define TEST_UTILS_H

#include <stdint.h>
#include <string.h>

/* Simple bit-writer for constructing synthetic H264 RBSP in tests */
typedef struct {
    uint8_t buf[4096];
    int     bit_pos;
} TestBitWriter;

static inline void tbw_init(TestBitWriter *bw) {
    memset(bw->buf, 0, sizeof(bw->buf));
    bw->bit_pos = 0;
}

static inline void tbw_write_bit(TestBitWriter *bw, int b) {
    if ((bw->bit_pos >> 3) >= (int)sizeof(bw->buf)) return;
    if (b) bw->buf[bw->bit_pos >> 3] |= (uint8_t)(0x80 >> (bw->bit_pos & 7));
    bw->bit_pos++;
}

static inline void tbw_write_bits(TestBitWriter *bw, uint32_t v, int n) {
    int i;
    for (i = n - 1; i >= 0; i--)
        tbw_write_bit(bw, (v >> i) & 1);
}

static inline void tbw_write_ue(TestBitWriter *bw, uint32_t v) {
    if (v == 0) { tbw_write_bit(bw, 1); return; }
    int n = 0;
    uint32_t t = v + 1;
    while (t > 1) { n++; t >>= 1; }
    int i;
    for (i = 0; i < n; i++) tbw_write_bit(bw, 0);
    tbw_write_bits(bw, v + 1, n + 1);
}

static inline void tbw_write_se(TestBitWriter *bw, int v) {
    uint32_t k = (v <= 0) ? (uint32_t)(-2 * v) : (uint32_t)(2 * v - 1);
    tbw_write_ue(bw, k);
}

static inline void tbw_align(TestBitWriter *bw) {
    while (bw->bit_pos & 7) tbw_write_bit(bw, 0);
}

static inline int tbw_len(const TestBitWriter *bw) {
    return (bw->bit_pos + 7) >> 3;
}

#endif /* TEST_UTILS_H */
