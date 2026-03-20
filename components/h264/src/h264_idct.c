#include <string.h>
#include "h264_common.h"

/* H.264 dequantization multiplier table: dequant_coeff[qp%6][pos_type]
 * pos_type: 0 = (0,0), 1 = (0,1)/(1,0), 2 = (1,1)
 * Matches H.264 spec Table 8-15. */
static const int dequant_coeff[6][3] = {
    {10, 13, 16},
    {11, 14, 18},
    {13, 16, 20},
    {14, 18, 23},
    {16, 20, 25},
    {18, 23, 29}
};

/* Position type for each index in a 4x4 block:
 * 0=(0,0) -> type 0, off-diagonal -> type 1, (1,1) -> type 2 */
static const uint8_t pos_type[16] = {
    0, 1, 1, 2,
    1, 1, 1, 1,
    1, 1, 2, 1,
    2, 1, 1, 1
};

/* ---- Dequantize 4x4 block in-place ---- */
void h264_dequantize4x4(int16_t block[16], int qp, int is_intra)
{
    int qp_mod6 = qp % 6;
    int qp_div6 = qp / 6;
    int i;
    (void)is_intra;

    if (qp_div6 >= 6) {
        int shift = qp_div6 - 6;
        for (i = 0; i < 16; i++) {
            int v = dequant_coeff[qp_mod6][pos_type[i]];
            block[i] = (int16_t)(block[i] * v * (1 << shift));
        }
    } else {
        int shift = 6 - qp_div6;
        int add   = 1 << (shift - 1);
        for (i = 0; i < 16; i++) {
            int v = dequant_coeff[qp_mod6][pos_type[i]];
            block[i] = (int16_t)((block[i] * v + add) >> shift);
        }
    }
}

/* ---- H.264 4x4 integer inverse DCT ---- */
void h264_idct4x4(int16_t block[16], int qp, int is_luma)
{
    int tmp[16];
    int i;

    /* Dequantize first */
    h264_dequantize4x4(block, qp, is_luma);

    /* Horizontal pass */
    for (i = 0; i < 4; i++) {
        int a = block[i*4+0];
        int b = block[i*4+1];
        int c = block[i*4+2];
        int d = block[i*4+3];

        int e0 = a + c;
        int e1 = a - c;
        int e2 = (b >> 1) - d;
        int e3 = b + (d >> 1);

        tmp[i*4+0] = e0 + e3;
        tmp[i*4+1] = e1 + e2;
        tmp[i*4+2] = e1 - e2;
        tmp[i*4+3] = e0 - e3;
    }

    /* Vertical pass */
    for (i = 0; i < 4; i++) {
        int a = tmp[0*4+i];
        int b = tmp[1*4+i];
        int c = tmp[2*4+i];
        int d = tmp[3*4+i];

        int e0 = a + c;
        int e1 = a - c;
        int e2 = (b >> 1) - d;
        int e3 = b + (d >> 1);

        block[0*4+i] = (int16_t)((e0 + e3 + 32) >> 6);
        block[1*4+i] = (int16_t)((e1 + e2 + 32) >> 6);
        block[2*4+i] = (int16_t)((e1 - e2 + 32) >> 6);
        block[3*4+i] = (int16_t)((e0 - e3 + 32) >> 6);
    }
}

/* ---- Hadamard 4x4 inverse transform (for luma DC in 16x16 mode) ---- */
void h264_hadamard4x4_inverse(int16_t block[16])
{
    int tmp[16];
    int i;

    /* Horizontal */
    for (i = 0; i < 4; i++) {
        int a = block[i*4+0];
        int b = block[i*4+1];
        int c = block[i*4+2];
        int d = block[i*4+3];
        tmp[i*4+0] = a + b + c + d;
        tmp[i*4+1] = a - b + c - d;
        tmp[i*4+2] = a + b - c - d;
        tmp[i*4+3] = a - b - c + d;
    }

    /* Vertical */
    for (i = 0; i < 4; i++) {
        int a = tmp[0*4+i];
        int b = tmp[1*4+i];
        int c = tmp[2*4+i];
        int d = tmp[3*4+i];
        block[0*4+i] = (int16_t)((a + b + c + d) >> 1);
        block[1*4+i] = (int16_t)((a - b + c - d) >> 1);
        block[2*4+i] = (int16_t)((a + b - c - d) >> 1);
        block[3*4+i] = (int16_t)((a - b - c + d) >> 1);
    }
}

/* ---- Hadamard 2x2 for chroma DC ---- */
void h264_hadamard2x2_inverse(int16_t block[4])
{
    int a = block[0];
    int b = block[1];
    int c = block[2];
    int d = block[3];

    block[0] = (int16_t)((a + b + c + d) >> 1);
    block[1] = (int16_t)((a - b + c - d) >> 1);
    block[2] = (int16_t)((a + b - c - d) >> 1);
    block[3] = (int16_t)((a - b - c + d) >> 1);
}

/* ---- Add residuals to prediction block (clamp 0-255) ---- */
void h264_add_residual4x4(uint8_t *dst, int stride, int16_t residual[16])
{
    int i, j;
    for (i = 0; i < 4; i++) {
        for (j = 0; j < 4; j++) {
            int val = (int)dst[i*stride + j] + (int)residual[i*4 + j];
            if (val < 0)   val = 0;
            if (val > 255) val = 255;
            dst[i*stride + j] = (uint8_t)val;
        }
    }
}
