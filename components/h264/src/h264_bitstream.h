#ifndef H264_BITSTREAM_H
#define H264_BITSTREAM_H

#include <stdint.h>
#include <string.h>
#include <stdlib.h>

typedef struct {
    const uint8_t *data;
    int size;       /* size in bytes */
    int bit_pos;    /* current bit position */
} H264BitStream;

static inline void bs_init(H264BitStream *bs, const uint8_t *data, int size) {
    bs->data    = data;
    bs->size    = size;
    bs->bit_pos = 0;
}

static inline int bs_bits_left(const H264BitStream *bs) {
    return bs->size * 8 - bs->bit_pos;
}

static inline uint32_t bs_read_bits(H264BitStream *bs, int n) {
    uint32_t result = 0;
    int i;
    for (i = 0; i < n; i++) {
        int byte_idx = bs->bit_pos >> 3;
        int bit_idx  = 7 - (bs->bit_pos & 7);
        if (byte_idx < bs->size) {
            result = (result << 1) | ((bs->data[byte_idx] >> bit_idx) & 1);
        } else {
            result = (result << 1);
        }
        bs->bit_pos++;
    }
    return result;
}

static inline uint32_t bs_read_u1(H264BitStream *bs) {
    return bs_read_bits(bs, 1);
}

static inline uint32_t bs_peek_bits(const H264BitStream *bs, int n) {
    H264BitStream tmp = *bs;
    return bs_read_bits(&tmp, n);
}

static inline uint32_t bs_read_ue(H264BitStream *bs) {
    int leading_zeros = 0;
    while (bs_bits_left(bs) > 0 && bs_read_u1(bs) == 0) {
        leading_zeros++;
        if (leading_zeros > 31) break;
    }
    if (leading_zeros == 0) return 0;
    return (1u << leading_zeros) - 1 + bs_read_bits(bs, leading_zeros);
}

static inline int32_t bs_read_se(H264BitStream *bs) {
    uint32_t k = bs_read_ue(bs);
    if (k == 0) return 0;
    if (k & 1) {
        return (int32_t)((k + 1) >> 1);
    } else {
        return -(int32_t)(k >> 1);
    }
}

static inline void bs_skip_bits(H264BitStream *bs, int n) {
    bs->bit_pos += n;
    if (bs->bit_pos > bs->size * 8) {
        bs->bit_pos = bs->size * 8;
    }
}

static inline int bs_byte_aligned(const H264BitStream *bs) {
    return (bs->bit_pos & 7) == 0;
}

static inline uint8_t bs_read_u8(H264BitStream *bs) {
    return (uint8_t)bs_read_bits(bs, 8);
}

#endif /* H264_BITSTREAM_H */
