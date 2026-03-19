#include <string.h>
#include <stdint.h>

static inline int clip_u8(int v) { return v < 0 ? 0 : (v > 255 ? 255 : v); }
static inline int avg2(int a, int b) { return (a + b + 1) >> 1; }
static inline int avg4(int a, int b, int c, int d) { return (a + b + c + d + 2) >> 2; }

/* ============================================================
 * 4x4 Intra prediction
 * top[4] = samples above, left[4] = samples to the left
 * top_left = top-left corner sample
 * mode: 0=Vertical, 1=Horizontal, 2=DC,
 *       3=DiagDL, 4=DiagDR, 5=VertR, 6=HorizD, 7=VertL, 8=HorizU
 * ============================================================ */
void h264_intra4x4_predict(uint8_t *dst, int stride, int mode,
                            const uint8_t *top, const uint8_t *left,
                            uint8_t top_left)
{
    int i, j;
    switch (mode) {
    case 0: /* Vertical */
        for (i = 0; i < 4; i++)
            for (j = 0; j < 4; j++)
                dst[i*stride+j] = top[j];
        break;

    case 1: /* Horizontal */
        for (i = 0; i < 4; i++)
            for (j = 0; j < 4; j++)
                dst[i*stride+j] = left[i];
        break;

    case 2: { /* DC */
        int sum = 0, cnt = 0;
        for (i = 0; i < 4; i++) { sum += top[i];  cnt++; }
        for (i = 0; i < 4; i++) { sum += left[i]; cnt++; }
        int dc = (sum + (cnt >> 1)) / cnt;
        for (i = 0; i < 4; i++)
            for (j = 0; j < 4; j++)
                dst[i*stride+j] = (uint8_t)dc;
        break;
    }

    case 3: { /* Diagonal Down-Left */
        uint8_t p[8];
        for (i = 0; i < 8; i++) p[i] = (i < 4) ? top[i] : top[3];
        for (i = 0; i < 4; i++)
            for (j = 0; j < 4; j++) {
                int k = i + j;
                if (k == 6) dst[i*stride+j] = (uint8_t)avg4(p[6],p[7],p[7],p[7]);
                else        dst[i*stride+j] = (uint8_t)avg4(p[k],p[k+1],p[k+1],p[k+2 < 8 ? k+2 : 7]);
            }
        break;
    }

    case 4: { /* Diagonal Down-Right */
        for (i = 0; i < 4; i++)
            for (j = 0; j < 4; j++) {
                if (j > i) {
                    int k = j - i;
                    dst[i*stride+j] = (uint8_t)avg4(top[k-1], top[k], top[k], k+1<4?top[k+1]:top[3]);
                } else if (j < i) {
                    int k = i - j;
                    dst[i*stride+j] = (uint8_t)avg4(left[k-1], left[k], left[k], k+1<4?left[k+1]:left[3]);
                } else {
                    dst[i*stride+j] = (uint8_t)avg4(top_left, top[0], left[0], top[0]);
                }
            }
        break;
    }

    case 5: { /* Vertical-Right */
        for (i = 0; i < 4; i++)
            for (j = 0; j < 4; j++) {
                int zVR = 2*j - i;
                if (zVR >= 0) {
                    if (zVR % 2 == 0) {
                        int k = zVR / 2;
                        dst[i*stride+j] = (uint8_t)avg2(k == 0 ? top_left : top[k-1], top[k < 4 ? k : 3]);
                    } else {
                        int k = (zVR - 1) / 2;
                        int a = k == 0 ? top_left : top[k-1];
                        int b = top[k < 4 ? k : 3];
                        int c = top[k+1 < 4 ? k+1 : 3];
                        dst[i*stride+j] = (uint8_t)avg4(a, b, b, c);
                    }
                } else if (zVR == -1) {
                    dst[i*stride+j] = (uint8_t)avg4(left[0], top_left, top_left, top[0]);
                } else {
                    dst[i*stride+j] = (uint8_t)avg2(left[-zVR-1 < 4 ? -zVR-1 : 3], left[-zVR-2 < 4 ? -zVR-2 : 3]);
                }
            }
        break;
    }

    case 6: { /* Horizontal-Down */
        for (i = 0; i < 4; i++)
            for (j = 0; j < 4; j++) {
                int zHD = 2*i - j;
                if (zHD >= 0) {
                    if (zHD % 2 == 0) {
                        int k = zHD / 2;
                        dst[i*stride+j] = (uint8_t)avg2(k == 0 ? top_left : left[k-1], left[k < 4 ? k : 3]);
                    } else {
                        int k = (zHD - 1) / 2;
                        int a = k == 0 ? top_left : left[k-1];
                        int b = left[k < 4 ? k : 3];
                        int c = left[k+1 < 4 ? k+1 : 3];
                        dst[i*stride+j] = (uint8_t)avg4(a, b, b, c);
                    }
                } else if (zHD == -1) {
                    dst[i*stride+j] = (uint8_t)avg4(top[0], top_left, top_left, left[0]);
                } else {
                    dst[i*stride+j] = (uint8_t)avg2(top[-zHD-1 < 4 ? -zHD-1 : 3], top[-zHD-2 < 4 ? -zHD-2 : 3]);
                }
            }
        break;
    }

    case 7: { /* Vertical-Left */
        for (i = 0; i < 4; i++)
            for (j = 0; j < 4; j++) {
                int k = j + (i >> 1);
                if (i % 2 == 0) {
                    dst[i*stride+j] = (uint8_t)avg2(top[k < 4 ? k : 3], top[k+1 < 4 ? k+1 : 3]);
                } else {
                    dst[i*stride+j] = (uint8_t)avg4(top[k < 4 ? k : 3],
                                                    top[k+1 < 4 ? k+1 : 3],
                                                    top[k+1 < 4 ? k+1 : 3],
                                                    top[k+2 < 4 ? k+2 : 3]);
                }
            }
        break;
    }

    case 8: { /* Horizontal-Up */
        for (i = 0; i < 4; i++)
            for (j = 0; j < 4; j++) {
                int zHU = j + 2*i;
                if (zHU >= 6) {
                    dst[i*stride+j] = left[3];
                } else if (zHU % 2 == 0) {
                    int k = zHU / 2;
                    dst[i*stride+j] = (uint8_t)avg2(left[k < 4 ? k : 3], left[k+1 < 4 ? k+1 : 3]);
                } else {
                    int k = (zHU - 1) / 2;
                    dst[i*stride+j] = (uint8_t)avg4(left[k < 4 ? k : 3],
                                                    left[k+1 < 4 ? k+1 : 3],
                                                    left[k+1 < 4 ? k+1 : 3],
                                                    left[k+2 < 4 ? k+2 : 3]);
                }
            }
        break;
    }

    default:
        for (i = 0; i < 4; i++)
            memset(dst + i*stride, 128, 4);
        break;
    }
}

/* ============================================================
 * 16x16 Intra prediction
 * mode: 0=Vertical, 1=Horizontal, 2=DC, 3=Plane
 * ============================================================ */
void h264_intra16x16_predict(uint8_t *dst, int stride, int mode,
                              const uint8_t *top, const uint8_t *left)
{
    int i, j;
    switch (mode) {
    case 0: /* Vertical */
        for (i = 0; i < 16; i++)
            for (j = 0; j < 16; j++)
                dst[i*stride+j] = top[j];
        break;

    case 1: /* Horizontal */
        for (i = 0; i < 16; i++)
            for (j = 0; j < 16; j++)
                dst[i*stride+j] = left[i];
        break;

    case 2: { /* DC */
        int sum = 0;
        for (i = 0; i < 16; i++) sum += top[i] + left[i];
        int dc = (sum + 16) >> 5;
        for (i = 0; i < 16; i++)
            for (j = 0; j < 16; j++)
                dst[i*stride+j] = (uint8_t)dc;
        break;
    }

    case 3: { /* Plane */
        int H = 0, V = 0;
        /* p[-1,-1] (top-left corner) is not passed as a separate parameter to this
         * function; approximate using the average of the first top and left samples.
         * This matches the common case where the true top-left is not available at
         * the slice boundary, and the approximation is exact when top[0]==left[0]. */
        int top_left = ((int)top[0] + (int)left[0] + 1) >> 1;
        for (i = 1; i <= 8; i++) {
            int t_plus  = top[7 + i];              /* top[8..15] */
            int t_minus = (7 - i >= 0) ? top[7 - i] : top_left; /* top[6..0] then top-left */
            H += i * (t_plus - t_minus);

            int l_plus  = left[7 + i];
            int l_minus = (7 - i >= 0) ? left[7 - i] : top_left;
            V += i * (l_plus - l_minus);
        }
        /* Use a simple approximation: a = 16*(left[15]+top[15]), without accessing p[-1,-1] */
        int a = 16 * (left[15] + top[15]);
        int b = (5 * H + 32) >> 6;
        int c = (5 * V + 32) >> 6;
        for (i = 0; i < 16; i++) {
            for (j = 0; j < 16; j++) {
                int val = (a + b*(j-7) + c*(i-7) + 16) >> 5;
                dst[i*stride+j] = (uint8_t)clip_u8(val);
            }
        }
        break;
    }

    default:
        break;
    }
}

/* ============================================================
 * 8x8 Chroma Intra prediction (size=8, 4 modes)
 * mode: 0=DC, 1=Horizontal, 2=Vertical, 3=Plane
 * ============================================================ */
void h264_intra_chroma_predict(uint8_t *dst, int stride, int mode,
                                const uint8_t *top, const uint8_t *left,
                                int size)
{
    int i, j, half = size / 2;
    (void)half;

    switch (mode) {
    case 0: { /* DC */
        /* Split into 4 quadrants, each has its own DC */
        int sz = size;
        int sumT0 = 0, sumT1 = 0, sumL0 = 0, sumL1 = 0;
        for (i = 0; i < sz/2; i++) { sumT0 += top[i];        sumT1 += top[sz/2+i]; }
        for (i = 0; i < sz/2; i++) { sumL0 += left[i];       sumL1 += left[sz/2+i]; }
        int dc00 = (sumT0 + sumL0 + sz/2) >> (sz == 8 ? 3 : 2);
        int dc01 = (sumT1 + sz/4) >> (sz == 8 ? 2 : 1);
        int dc10 = (sumL1 + sz/4) >> (sz == 8 ? 2 : 1);
        int dc11 = (sumT1 + sumL1 + sz/2) >> (sz == 8 ? 3 : 2);
        for (i = 0; i < sz/2; i++)
            for (j = 0; j < sz/2; j++) dst[i*stride+j]            = (uint8_t)dc00;
        for (i = 0; i < sz/2; i++)
            for (j = sz/2; j < sz; j++) dst[i*stride+j]           = (uint8_t)dc01;
        for (i = sz/2; i < sz; i++)
            for (j = 0; j < sz/2; j++) dst[i*stride+j]            = (uint8_t)dc10;
        for (i = sz/2; i < sz; i++)
            for (j = sz/2; j < sz; j++) dst[i*stride+j]           = (uint8_t)dc11;
        break;
    }

    case 1: /* Horizontal */
        for (i = 0; i < size; i++)
            for (j = 0; j < size; j++)
                dst[i*stride+j] = left[i];
        break;

    case 2: /* Vertical */
        for (i = 0; i < size; i++)
            for (j = 0; j < size; j++)
                dst[i*stride+j] = top[j];
        break;

    case 3: { /* Plane */
        int H = 0, V = 0, sz = size;
        for (i = 1; i <= sz/2; i++) {
            H += i * (top[sz/2-1+i] - top[sz/2-1-i]);
            V += i * (left[sz/2-1+i] - left[sz/2-1-i]);
        }
        int a = 16 * (top[sz-1] + left[sz-1]);
        int b = (17 * H + 16 * sz) >> (sz == 8 ? 5 : 4);
        int c = (17 * V + 16 * sz) >> (sz == 8 ? 5 : 4);
        for (i = 0; i < sz; i++) {
            for (j = 0; j < sz; j++) {
                int val = (a + b*(j - sz/2 + 1) + c*(i - sz/2 + 1) + 16) >> 5;
                dst[i*stride+j] = (uint8_t)clip_u8(val);
            }
        }
        break;
    }

    default:
        break;
    }
}
