#include <string.h>
#include <stdio.h>
#include "h264_common.h"
#include "h264_tables.h"

/* Debug tracing for CAVLC - set to 1 from caller to dump decode details */
int h264_cavlc_trace = 0;

/* ============================================================
 * CAVLC coeff_token VLC tables (H.264 spec Table 9-5)
 *
 * Each entry: {code, len, trailing_ones, total_coeff}
 * We store all entries for each nC range and search linearly.
 * For performance in a real decoder these would be hash tables,
 * but correctness is the priority here.
 * ============================================================ */

typedef struct {
    uint16_t code;
    uint8_t  len;
    uint8_t  trailing_ones;
    uint8_t  total_coeff;
} CoeffTokenEntry;

/* ---- Table 0: nC in [0,2) ---- */
static const CoeffTokenEntry ct_table0[] = {
    /* tc= 0 */ {0x01, 1,0, 0},
    /* tc= 1 */ {0x05, 6,0, 1}, {0x01, 2,1, 1},
    /* tc= 2 */ {0x07, 8,0, 2}, {0x04, 6,1, 2}, {0x01, 3,2, 2},
    /* tc= 3 */ {0x07, 9,0, 3}, {0x06, 8,1, 3}, {0x05, 7,2, 3}, {0x03, 5,3, 3},
    /* tc= 4 */ {0x07,10,0, 4}, {0x06, 9,1, 4}, {0x05, 8,2, 4}, {0x03, 6,3, 4},
    /* tc= 5 */ {0x07,11,0, 5}, {0x06,10,1, 5}, {0x05, 9,2, 5}, {0x04, 7,3, 5},
    /* tc= 6 */ {0x0f,13,0, 6}, {0x06,11,1, 6}, {0x05,10,2, 6}, {0x04, 8,3, 6},
    /* tc= 7 */ {0x0b,13,0, 7}, {0x0e,13,1, 7}, {0x05,11,2, 7}, {0x04, 9,3, 7},
    /* tc= 8 */ {0x08,13,0, 8}, {0x0a,13,1, 8}, {0x0d,13,2, 8}, {0x04,10,3, 8},
    /* tc= 9 */ {0x0f,14,0, 9}, {0x0e,14,1, 9}, {0x09,13,2, 9}, {0x04,11,3, 9},
    /* tc=10 */ {0x0b,14,0,10}, {0x0a,14,1,10}, {0x0d,14,2,10}, {0x0c,13,3,10},
    /* tc=11 */ {0x0f,15,0,11}, {0x0e,15,1,11}, {0x09,14,2,11}, {0x0c,14,3,11},
    /* tc=12 */ {0x0b,15,0,12}, {0x0a,15,1,12}, {0x0d,15,2,12}, {0x08,14,3,12},
    /* tc=13 */ {0x0f,16,0,13}, {0x01,15,1,13}, {0x09,15,2,13}, {0x0c,15,3,13},
    /* tc=14 */ {0x0b,16,0,14}, {0x0e,16,1,14}, {0x0d,16,2,14}, {0x08,15,3,14},
    /* tc=15 */ {0x07,16,0,15}, {0x0a,16,1,15}, {0x09,16,2,15}, {0x0c,16,3,15},
    /* tc=16 */ {0x04,16,0,16}, {0x06,16,1,16}, {0x05,16,2,16}, {0x08,16,3,16},
};
#define CT_TABLE0_SIZE (int)(sizeof(ct_table0)/sizeof(ct_table0[0]))

/* ---- Table 1: nC in [2,4) ---- */
static const CoeffTokenEntry ct_table1[] = {
    /* tc= 0 */ {0x03, 2,0, 0},
    /* tc= 1 */ {0x0b, 6,0, 1}, {0x02, 2,1, 1},
    /* tc= 2 */ {0x07, 6,0, 2}, {0x07, 5,1, 2}, {0x03, 3,2, 2},
    /* tc= 3 */ {0x07, 7,0, 3}, {0x0a, 6,1, 3}, {0x09, 6,2, 3}, {0x05, 4,3, 3},
    /* tc= 4 */ {0x07, 8,0, 4}, {0x06, 6,1, 4}, {0x05, 6,2, 4}, {0x04, 4,3, 4},
    /* tc= 5 */ {0x04, 8,0, 5}, {0x06, 7,1, 5}, {0x05, 7,2, 5}, {0x06, 5,3, 5},
    /* tc= 6 */ {0x07, 9,0, 6}, {0x06, 8,1, 6}, {0x05, 8,2, 6}, {0x08, 6,3, 6},
    /* tc= 7 */ {0x0f,11,0, 7}, {0x06, 9,1, 7}, {0x05, 9,2, 7}, {0x04, 6,3, 7},
    /* tc= 8 */ {0x0b,11,0, 8}, {0x0e,11,1, 8}, {0x0d,11,2, 8}, {0x04, 7,3, 8},
    /* tc= 9 */ {0x0f,12,0, 9}, {0x0a,11,1, 9}, {0x09,11,2, 9}, {0x04, 9,3, 9},
    /* tc=10 */ {0x0b,12,0,10}, {0x0e,12,1,10}, {0x0d,12,2,10}, {0x0c,11,3,10},
    /* tc=11 */ {0x08,12,0,11}, {0x0a,12,1,11}, {0x09,12,2,11}, {0x08,11,3,11},
    /* tc=12 */ {0x0f,13,0,12}, {0x0e,13,1,12}, {0x0d,13,2,12}, {0x0c,12,3,12},
    /* tc=13 */ {0x0b,13,0,13}, {0x0a,13,1,13}, {0x09,13,2,13}, {0x0c,13,3,13},
    /* tc=14 */ {0x07,13,0,14}, {0x0b,14,1,14}, {0x06,13,2,14}, {0x08,13,3,14},
    /* tc=15 */ {0x09,14,0,15}, {0x08,14,1,15}, {0x0a,14,2,15}, {0x01,13,3,15},
    /* tc=16 */ {0x07,14,0,16}, {0x06,14,1,16}, {0x05,14,2,16}, {0x04,14,3,16},
};
#define CT_TABLE1_SIZE (int)(sizeof(ct_table1)/sizeof(ct_table1[0]))

/* ---- Table 2: nC in [4,8) ---- */
static const CoeffTokenEntry ct_table2[] = {
    /* tc= 0 */ {0x0f, 4,0, 0},
    /* tc= 1 */ {0x0f, 6,0, 1}, {0x0e, 4,1, 1},
    /* tc= 2 */ {0x0b, 6,0, 2}, {0x0f, 5,1, 2}, {0x0d, 4,2, 2},
    /* tc= 3 */ {0x08, 6,0, 3}, {0x0c, 5,1, 3}, {0x0e, 5,2, 3}, {0x0c, 4,3, 3},
    /* tc= 4 */ {0x0f, 7,0, 4}, {0x0a, 5,1, 4}, {0x0b, 5,2, 4}, {0x0b, 4,3, 4},
    /* tc= 5 */ {0x0b, 7,0, 5}, {0x08, 5,1, 5}, {0x09, 5,2, 5}, {0x0a, 4,3, 5},
    /* tc= 6 */ {0x09, 7,0, 6}, {0x0e, 6,1, 6}, {0x0d, 6,2, 6}, {0x09, 4,3, 6},
    /* tc= 7 */ {0x08, 7,0, 7}, {0x0a, 6,1, 7}, {0x09, 6,2, 7}, {0x08, 4,3, 7},
    /* tc= 8 */ {0x0f, 8,0, 8}, {0x0e, 7,1, 8}, {0x0d, 7,2, 8}, {0x0d, 5,3, 8},
    /* tc= 9 */ {0x0b, 8,0, 9}, {0x0e, 8,1, 9}, {0x0a, 7,2, 9}, {0x0c, 6,3, 9},
    /* tc=10 */ {0x0f, 9,0,10}, {0x0a, 8,1,10}, {0x0d, 8,2,10}, {0x0c, 7,3,10},
    /* tc=11 */ {0x0b, 9,0,11}, {0x0e, 9,1,11}, {0x09, 8,2,11}, {0x0c, 8,3,11},
    /* tc=12 */ {0x08, 9,0,12}, {0x0a, 9,1,12}, {0x0d, 9,2,12}, {0x08, 8,3,12},
    /* tc=13 */ {0x0d,10,0,13}, {0x07, 9,1,13}, {0x09, 9,2,13}, {0x0c, 9,3,13},
    /* tc=14 */ {0x09,10,0,14}, {0x0c,10,1,14}, {0x0b,10,2,14}, {0x0a,10,3,14},
    /* tc=15 */ {0x05,10,0,15}, {0x08,10,1,15}, {0x07,10,2,15}, {0x06,10,3,15},
    /* tc=16 */ {0x01,10,0,16}, {0x04,10,1,16}, {0x03,10,2,16}, {0x02,10,3,16},
};
#define CT_TABLE2_SIZE (int)(sizeof(ct_table2)/sizeof(ct_table2[0]))

/* ---- Chroma DC coeff_token (4x4 chroma, max TotalCoeff=4) ---- */
static const CoeffTokenEntry ct_chroma_dc[] = {
    {0x01, 2, 0, 0},
    {0x07, 6, 0, 1}, {0x01, 1, 1, 1},
    {0x04, 6, 0, 2}, {0x06, 6, 1, 2}, {0x01, 3, 2, 2},
    {0x03, 6, 0, 3}, {0x03, 7, 1, 3}, {0x02, 7, 2, 3}, {0x05, 6, 3, 3},
    {0x02, 6, 0, 4}, {0x01, 7, 1, 4}, {0x00, 7, 2, 4}, {0x01, 6, 3, 4},
};
#define CT_CHROMA_DC_SIZE (int)(sizeof(ct_chroma_dc)/sizeof(ct_chroma_dc[0]))

/* ============================================================
 * total_zeros VLC tables (H.264 spec Table 9-7)
 *
 * total_zeros_tab[tzVlcIndex-1][i] = {code, len, value}
 * tzVlcIndex = TotalCoeff (1..15 for 4x4 luma)
 * ============================================================ */
typedef struct { uint8_t code; uint8_t len; uint8_t value; } TZEntry;

/* tzVlcIndex=1 */
static const TZEntry tz1[] = {
    {1,1,0},{3,3,1},{2,3,2},{3,4,3},{2,4,4},{3,5,5},{2,5,6},{3,6,7},
    {2,6,8},{3,7,9},{2,7,10},{3,8,11},{2,8,12},{3,9,13},{2,9,14},{1,9,15}
};
/* tzVlcIndex=2 */
static const TZEntry tz2[] = {
    {7,3,0},{6,3,1},{5,3,2},{4,3,3},{3,3,4},{5,4,5},{4,4,6},{3,4,7},
    {2,4,8},{3,5,9},{2,5,10},{3,6,11},{2,6,12},{1,6,13},{0,6,14}
};
/* tzVlcIndex=3 (H.264 Table 9-7, 14 entries, max total_zeros=13) */
static const TZEntry tz3[] = {
    {5,4,0},{7,3,1},{6,3,2},{5,3,3},{4,4,4},{3,4,5},{4,3,6},{3,3,7},
    {2,4,8},{3,5,9},{2,5,10},{1,6,11},{1,5,12},{0,6,13}
};
/* tzVlcIndex=4 (13 entries, max total_zeros=12) */
static const TZEntry tz4[] = {
    {3,5,0},{7,3,1},{5,4,2},{4,4,3},{6,3,4},{5,3,5},{4,3,6},{3,4,7},
    {3,3,8},{2,4,9},{2,5,10},{1,5,11},{0,5,12}
};
/* tzVlcIndex=5 (12 entries, max total_zeros=11) */
static const TZEntry tz5[] = {
    {5,4,0},{4,4,1},{3,4,2},{7,3,3},{6,3,4},{5,3,5},{4,3,6},{3,3,7},
    {2,4,8},{1,5,9},{1,4,10},{0,5,11}
};
/* tzVlcIndex=6 (11 entries, max total_zeros=10) */
static const TZEntry tz6[] = {
    {1,6,0},{1,5,1},{7,3,2},{6,3,3},{5,3,4},{4,3,5},{3,3,6},{2,3,7},
    {1,4,8},{1,3,9},{0,6,10}
};
/* tzVlcIndex=7 (10 entries, max total_zeros=9) */
static const TZEntry tz7[] = {
    {1,6,0},{1,5,1},{5,3,2},{4,3,3},{3,3,4},{3,2,5},{2,3,6},{1,4,7},
    {1,3,8},{0,6,9}
};
/* tzVlcIndex=8 (9 entries, max total_zeros=8) */
static const TZEntry tz8[] = {
    {1,6,0},{1,4,1},{1,5,2},{3,3,3},{3,2,4},{2,2,5},{2,3,6},{1,3,7},
    {0,6,8}
};
/* tzVlcIndex=9 (8 entries, max total_zeros=7) */
static const TZEntry tz9[] = {
    {1,6,0},{0,6,1},{1,4,2},{3,2,3},{2,2,4},{1,3,5},{1,2,6},{1,5,7}
};
/* tzVlcIndex=10 (7 entries, max total_zeros=6) */
static const TZEntry tz10[] = {
    {1,5,0},{0,5,1},{1,3,2},{3,2,3},{2,2,4},{1,2,5},{1,4,6}
};
/* tzVlcIndex=11 (6 entries, max total_zeros=5) */
static const TZEntry tz11[] = {
    {0,4,0},{1,4,1},{1,3,2},{2,3,3},{1,1,4},{3,3,5}
};
/* tzVlcIndex=12 (5 entries, max total_zeros=4) */
static const TZEntry tz12[] = {
    {0,4,0},{1,4,1},{1,2,2},{1,1,3},{1,3,4}
};
/* tzVlcIndex=13 (4 entries, max total_zeros=3) */
static const TZEntry tz13[] = {
    {0,3,0},{1,3,1},{1,1,2},{1,2,3}
};
/* tzVlcIndex=14 (3 entries, max total_zeros=2) */
static const TZEntry tz14[] = {
    {0,2,0},{1,2,1},{1,1,2}
};
/* tzVlcIndex=15 (2 entries, max total_zeros=1) */
static const TZEntry tz15[] = {
    {0,1,0},{1,1,1}
};

static const TZEntry * const tz_tables[15] = {
    tz1,tz2,tz3,tz4,tz5,tz6,tz7,tz8,tz9,tz10,tz11,tz12,tz13,tz14,tz15
};
static const int tz_sizes[15] = {16,15,14,13,12,11,10,9,8,7,6,5,4,3,2};

/* ============================================================
 * run_before VLC tables (H.264 spec Table 9-10)
 * ============================================================ */
typedef struct { uint8_t code; uint8_t len; uint8_t value; } RBEntry;

static const RBEntry rb1[] = {{1,1,0},{0,1,1}};
static const RBEntry rb2[] = {{1,1,0},{1,2,1},{0,2,2}};
static const RBEntry rb3[] = {{3,2,0},{2,2,1},{1,2,2},{0,2,3}};
static const RBEntry rb4[] = {{3,2,0},{2,2,1},{1,2,2},{1,3,3},{0,3,4}};
static const RBEntry rb5[] = {{3,2,0},{2,2,1},{3,3,2},{2,3,3},{1,3,4},{0,3,5}};
static const RBEntry rb6[] = {{3,2,0},{0,3,1},{1,3,2},{3,3,3},{2,3,4},{5,3,5},{4,3,6}};

static const RBEntry * const rb_tables[6] = {rb1,rb2,rb3,rb4,rb5,rb6};
static const int rb_sizes[6] = {2,3,4,5,6,7};

/* ============================================================
 * Chroma DC total_zeros (max TotalCoeff=3 for 2x2 chroma DC)
 * Table 9-9
 * ============================================================ */
/* ============================================================
 * Chroma DC total_zeros (H.264 Table 9-9(a), 4:2:0)
 *
 * total_coeff=1: total_zeros 0-3
 * total_coeff=2: total_zeros 0-2
 * total_coeff=3: total_zeros 0-1
 * ============================================================ */
static const TZEntry tz_chroma_dc1[] = {
    {1,1,0}, {1,2,1}, {1,3,2}, {0,3,3}
};
static const TZEntry tz_chroma_dc2[] = {
    {1,1,0}, {1,2,1}, {0,2,2}
};
static const TZEntry tz_chroma_dc3[] = {
    {1,1,0}, {0,1,1}
};
static const TZEntry * const tz_chroma_dc[3] = {tz_chroma_dc1,tz_chroma_dc2,tz_chroma_dc3};
static const int tz_chroma_dc_sizes[3] = {4,3,2};

/* ============================================================
 * Helpers
 * ============================================================ */

static int decode_coeff_token(H264BitStream *bs, int nC,
                               int *total_coeff, int *trailing_ones)
{
    const CoeffTokenEntry *table;
    int tsize;

    if (nC < 0) {
        /* Chroma DC */
        table  = ct_chroma_dc;
        tsize  = CT_CHROMA_DC_SIZE;
    } else if (nC >= 8) {
        /* Fixed 6-bit code (H.264 Table 9-5(d)):
         * code=3 → tc=0,t1=0
         * code=0,1 → tc=1,t1=code
         * code=4..6 → tc=2,t1=code-4
         * code=8..63 → tc=(code>>2)+1, t1=code&3
         * codes 2,7 are unused */
        uint32_t code = bs_read_bits(bs, 6);
        if (code == 3) {
            *total_coeff = 0;
            *trailing_ones = 0;
        } else if (code == 2 || code == 7) {
            return H264_ERR_BITSTREAM;
        } else {
            *total_coeff   = (int)((code >> 2) + 1);
            *trailing_ones = (int)(code & 3);
            if (*trailing_ones > *total_coeff) return H264_ERR_BITSTREAM;
        }
        return H264_OK;
    } else if (nC >= 4) {
        table  = ct_table2;
        tsize  = CT_TABLE2_SIZE;
    } else if (nC >= 2) {
        table  = ct_table1;
        tsize  = CT_TABLE1_SIZE;
    } else {
        table  = ct_table0;
        tsize  = CT_TABLE0_SIZE;
    }

    /* Find the matching entry by peeking bits */
    int i;
    for (i = 0; i < tsize; i++) {
        int len = table[i].len;
        if (bs_bits_left(bs) < len) continue;
        uint32_t peeked = bs_peek_bits(bs, len);
        if (peeked == table[i].code) {
            bs_skip_bits(bs, len);
            *total_coeff   = table[i].total_coeff;
            *trailing_ones = table[i].trailing_ones;
            return H264_OK;
        }
    }
    return H264_ERR_BITSTREAM;
}

static int decode_total_zeros(H264BitStream *bs, int total_coeff,
                               int max_coeff, int is_chroma_dc)
{
    const TZEntry *table;
    int tsize;

    if (is_chroma_dc) {
        int idx = total_coeff - 1;
        if (idx < 0 || idx >= 3) return 0;
        table = tz_chroma_dc[idx];
        tsize = tz_chroma_dc_sizes[idx];
    } else {
        int tzVlcIndex = total_coeff;
        if (tzVlcIndex < 1) return 0;
        if (tzVlcIndex > 15) tzVlcIndex = 15;
        table = tz_tables[tzVlcIndex - 1];
        tsize = tz_sizes[tzVlcIndex - 1];
        (void)max_coeff;
    }

    int i;
    for (i = 0; i < tsize; i++) {
        int len = table[i].len;
        if (bs_bits_left(bs) < len) continue;
        uint32_t peeked = bs_peek_bits(bs, len);
        if (peeked == table[i].code) {
            bs_skip_bits(bs, len);
            return table[i].value;
        }
    }
    return H264_ERR_BITSTREAM;
}

static int decode_run_before(H264BitStream *bs, int zeros_left)
{
    if (zeros_left == 0) return 0;

    int idx = zeros_left - 1;
    if (idx > 5) idx = 5;

    const RBEntry *table = rb_tables[idx];
    int tsize = rb_sizes[idx];

    /* Special: if zeros_left > 6, prefix with 3-bit code for values 0-6 or 3-bit 0 for >= 7 */
    if (zeros_left > 6) {
        /* The table for zeros_left >= 7 uses run_before 0..6 with codes 3..0 (len 3)
         * and run_before >= 7 with leading 0 bits */
        uint32_t b3 = bs_peek_bits(bs, 3);
        if (b3 != 0) {
            /* 3 bits, value = 7 - b3 */
            bs_skip_bits(bs, 3);
            return (int)(7 - b3);
        } else {
            /* More zeros: count leading zeros then read */
            bs_skip_bits(bs, 3); /* the 3-bit prefix is 0 */
            int extra = 0;
            while (bs_bits_left(bs) > 0 && bs_read_u1(bs) == 0)
                extra++;
            return 7 + extra;
        }
    }

    int i;
    for (i = 0; i < tsize; i++) {
        int len = table[i].len;
        if (bs_bits_left(bs) < len) continue;
        uint32_t peeked = bs_peek_bits(bs, len);
        if (peeked == table[i].code) {
            bs_skip_bits(bs, len);
            return table[i].value;
        }
    }
    return H264_ERR_BITSTREAM; /* no matching VLC entry */
}

/* ============================================================
 * Main CAVLC block decoder
 * H.264 spec section 9.2
 * ============================================================ */
int h264_cavlc_decode_block(H264BitStream *bs, int16_t *coeffs,
                             int max_coeff, int nC)
{
    int total_coeff, trailing_ones;
    int i;
    int trace = h264_cavlc_trace;

    memset(coeffs, 0, max_coeff * sizeof(int16_t));

    /* Step 1: decode coeff_token */
    int ct_start = bs->bit_pos;
    if (decode_coeff_token(bs, nC, &total_coeff, &trailing_ones) != H264_OK)
        return H264_ERR_BITSTREAM;

    if (trace) printf("[cavlc_trace] bit=%d nC=%d max=%d => tc=%d t1=%d (ct_bits=%d)\n",
                      ct_start, nC, max_coeff, total_coeff, trailing_ones, bs->bit_pos - ct_start);

    if (total_coeff == 0) return H264_OK;
    if (total_coeff > max_coeff) return H264_ERR_BITSTREAM;
    if (trailing_ones > total_coeff || trailing_ones > 3)
        return H264_ERR_BITSTREAM;

    /* levels array in reverse order (last coeff first) */
    int16_t levels[16];
    memset(levels, 0, sizeof(levels));

    /* Step 2: trailing ones sign bits */
    for (i = 0; i < trailing_ones; i++) {
        int sign = (int)bs_read_u1(bs);
        levels[total_coeff - 1 - i] = sign ? -1 : 1;
    }

    /* Step 3: level suffix length */
    int suffixLength = 0;
    if (total_coeff > 10 && trailing_ones < 3) suffixLength = 1;

    /* Step 4: read remaining levels */
    for (i = total_coeff - trailing_ones - 1; i >= 0; i--) {
        int level_prefix = 0;
        int lev_start = bs->bit_pos;
        while (bs_bits_left(bs) > 0 && bs_read_u1(bs) == 0) {
            level_prefix++;
            if (level_prefix > 15) break;
        }

        int levelSuffixSize = suffixLength;
        if (level_prefix == 14 && suffixLength == 0) levelSuffixSize = 4;
        if (level_prefix == 15) levelSuffixSize = 12;

        int level_suffix = 0;
        if (levelSuffixSize > 0)
            level_suffix = (int)bs_read_bits(bs, levelSuffixSize);

        int levelCode = (level_prefix << suffixLength) + level_suffix;
        if (level_prefix == 15 && suffixLength == 0) levelCode += 15;
        if (level_prefix == 16) levelCode += 15;

        int level;
        if (levelCode % 2 == 0)
            level = (levelCode >> 1) + 1;
        else
            level = -((levelCode + 1) >> 1);

        /* First non-trailing level with magnitude 1 triggers extra increment */
        if (i == total_coeff - trailing_ones - 1 && trailing_ones < 3)
            level += (level > 0) ? 1 : -1;

        levels[i] = (int16_t)level;

        if (trace) printf("[cavlc_trace]   level[%d]: prefix=%d sufLen=%d sufSize=%d suf=%d code=%d => %d (bits=%d)\n",
                          i, level_prefix, suffixLength, levelSuffixSize, level_suffix, levelCode, level, bs->bit_pos - lev_start);

        /* Update suffixLength */
        int abs_level = level < 0 ? -level : level;
        if (suffixLength == 0) suffixLength = 1;
        if (abs_level > (3 << (suffixLength - 1)) && suffixLength < 6)
            suffixLength++;
    }

    /* Step 5: total_zeros */
    int total_zeros;
    if (total_coeff < max_coeff) {
        int is_chroma_dc = (nC < 0 && max_coeff == 4);
        int tz_start = bs->bit_pos;
        total_zeros = decode_total_zeros(bs, total_coeff, max_coeff, is_chroma_dc);
        if (total_zeros < 0) {
            /* Dump diagnostic for total_zeros failure */
            uint32_t peek16 = bs_peek_bits(bs, 16);
            printf("[CAVLC_TZ_FAIL] nC=%d max=%d tc=%d t1=%d chroma_dc=%d bit=%d peek=0x%04X\n",
                   nC, max_coeff, total_coeff, trailing_ones, is_chroma_dc, tz_start, peek16);
            return H264_ERR_BITSTREAM;
        }
        if (trace) printf("[cavlc_trace]   total_zeros=%d (bits=%d)\n", total_zeros, bs->bit_pos - tz_start);
    } else {
        total_zeros = 0;
    }

    /* Step 6: run_before and place coefficients */
    int run[16];
    int zeros_left = total_zeros;
    for (i = total_coeff - 1; i > 0; i--) {
        if (zeros_left > 0) {
            int rb_start = bs->bit_pos;
            run[i] = decode_run_before(bs, zeros_left);
            if (run[i] < 0) return H264_ERR_BITSTREAM;
            if (trace) printf("[cavlc_trace]   run[%d]: zl=%d => %d (bits=%d)\n", i, zeros_left, run[i], bs->bit_pos - rb_start);
        } else {
            run[i] = 0;
        }
        zeros_left -= run[i];
    }
    run[0] = zeros_left;
    if (trace) printf("[cavlc_trace]   run[0]=%d (remaining zeros)\n", run[0]);

    /* Place coefficients in zigzag order */
    int pos = 0;
    for (i = total_coeff - 1; i >= 0; i--) {
        pos += run[i];
        if (pos >= max_coeff) return H264_ERR_BITSTREAM;
        coeffs[pos] = levels[i];
        pos++;
    }

    return H264_OK;
}
