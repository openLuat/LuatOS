#include <string.h>
#include <stdint.h>

static inline int clamp(int v, int lo, int hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

/* 6-tap half-pixel filter coefficients: {1, -5, 20, 20, -5, 1} / 32 */
static int filter6(int a, int b, int c, int d, int e, int f)
{
    return (a - 5*b + 20*c + 20*d - 5*e + f + 16) >> 5;
}

/*
 * Get a sample from the reference plane with boundary clamping.
 */
static inline uint8_t ref_sample(const uint8_t *src, int src_stride,
                                  int src_w, int src_h, int x, int y)
{
    x = clamp(x, 0, src_w - 1);
    y = clamp(y, 0, src_h - 1);
    return src[y * src_stride + x];
}

/*
 * Luma motion compensation with 1/4-pixel precision.
 * mv_x, mv_y are in 1/4-pixel units.
 */
void h264_mc_luma(uint8_t *dst, int dst_stride,
                  const uint8_t *src, int src_stride,
                  int src_w, int src_h,
                  int x, int y, int mv_x, int mv_y,
                  int bw, int bh)
{
    int hpel_x = mv_x & 3;
    int hpel_y = mv_y & 3;
    int base_x = x + (mv_x >> 2);
    int base_y = y + (mv_y >> 2);

    int i, j;

    if (hpel_x == 0 && hpel_y == 0) {
        /* Full-pixel */
        for (i = 0; i < bh; i++)
            for (j = 0; j < bw; j++)
                dst[i*dst_stride+j] = ref_sample(src, src_stride, src_w, src_h,
                                                  base_x+j, base_y+i);
        return;
    }

    if (hpel_y == 0) {
        /* Horizontal filtering only */
        for (i = 0; i < bh; i++) {
            for (j = 0; j < bw; j++) {
                int px = base_x + j;
                int py = base_y + i;
                int a = ref_sample(src,src_stride,src_w,src_h, px-2, py);
                int b = ref_sample(src,src_stride,src_w,src_h, px-1, py);
                int c = ref_sample(src,src_stride,src_w,src_h, px,   py);
                int d = ref_sample(src,src_stride,src_w,src_h, px+1, py);
                int e = ref_sample(src,src_stride,src_w,src_h, px+2, py);
                int f = ref_sample(src,src_stride,src_w,src_h, px+3, py);
                int hp = filter6(a,b,c,d,e,f);
                hp = clamp(hp, 0, 255);

                if (hpel_x == 2) {
                    dst[i*dst_stride+j] = (uint8_t)hp;
                } else {
                    int fp = (hpel_x == 1) ?
                        ref_sample(src,src_stride,src_w,src_h, px, py) :
                        ref_sample(src,src_stride,src_w,src_h, px+1, py);
                    dst[i*dst_stride+j] = (uint8_t)((hp + fp + 1) >> 1);
                }
            }
        }
        return;
    }

    if (hpel_x == 0) {
        /* Vertical filtering only */
        for (i = 0; i < bh; i++) {
            for (j = 0; j < bw; j++) {
                int px = base_x + j;
                int py = base_y + i;
                int a = ref_sample(src,src_stride,src_w,src_h, px, py-2);
                int b = ref_sample(src,src_stride,src_w,src_h, px, py-1);
                int c = ref_sample(src,src_stride,src_w,src_h, px, py);
                int d = ref_sample(src,src_stride,src_w,src_h, px, py+1);
                int e = ref_sample(src,src_stride,src_w,src_h, px, py+2);
                int f = ref_sample(src,src_stride,src_w,src_h, px, py+3);
                int hp = filter6(a,b,c,d,e,f);
                hp = clamp(hp, 0, 255);

                if (hpel_y == 2) {
                    dst[i*dst_stride+j] = (uint8_t)hp;
                } else {
                    int fp = (hpel_y == 1) ?
                        ref_sample(src,src_stride,src_w,src_h, px, py) :
                        ref_sample(src,src_stride,src_w,src_h, px, py+1);
                    dst[i*dst_stride+j] = (uint8_t)((hp + fp + 1) >> 1);
                }
            }
        }
        return;
    }

    /* Both horizontal and vertical sub-pixel: use bilinear between half-pel positions */
    for (i = 0; i < bh; i++) {
        for (j = 0; j < bw; j++) {
            int px = base_x + j;
            int py = base_y + i;
            /* Get h-filtered row at py and at py+1 (for vertical quarter-pel) */
            int iy = (hpel_y == 1) ? py : py + 1;
            int rows[2];
            rows[0] = py; rows[1] = iy;
            int k;
            int hvals[2];
            for (k = 0; k < 2; k++) {
                int a = ref_sample(src,src_stride,src_w,src_h, px-2, rows[k]);
                int b = ref_sample(src,src_stride,src_w,src_h, px-1, rows[k]);
                int c = ref_sample(src,src_stride,src_w,src_h, px,   rows[k]);
                int d = ref_sample(src,src_stride,src_w,src_h, px+1, rows[k]);
                int e = ref_sample(src,src_stride,src_w,src_h, px+2, rows[k]);
                int f = ref_sample(src,src_stride,src_w,src_h, px+3, rows[k]);
                hvals[k] = clamp(filter6(a,b,c,d,e,f), 0, 255);
            }
            dst[i*dst_stride+j] = (uint8_t)((hvals[0] + hvals[1] + 1) >> 1);
        }
    }
}

/*
 * Chroma motion compensation (bilinear, 1/8-pixel precision).
 */
void h264_mc_chroma(uint8_t *dst, int dst_stride,
                    const uint8_t *src, int src_stride,
                    int src_w, int src_h,
                    int x, int y, int mv_x, int mv_y,
                    int bw, int bh)
{
    int base_x = x + (mv_x >> 3);
    int base_y = y + (mv_y >> 3);
    int frac_x = mv_x & 7;
    int frac_y = mv_y & 7;
    int i, j;

    for (i = 0; i < bh; i++) {
        for (j = 0; j < bw; j++) {
            int px = base_x + j;
            int py = base_y + i;
            int a = ref_sample(src, src_stride, src_w, src_h, px,   py);
            int b = ref_sample(src, src_stride, src_w, src_h, px+1, py);
            int c = ref_sample(src, src_stride, src_w, src_h, px,   py+1);
            int d = ref_sample(src, src_stride, src_w, src_h, px+1, py+1);

            int val = ((8-frac_x)*(8-frac_y)*a + frac_x*(8-frac_y)*b +
                       (8-frac_x)*frac_y*c     + frac_x*frac_y*d + 32) >> 6;
            dst[i*dst_stride+j] = (uint8_t)clamp(val, 0, 255);
        }
    }
}

/*
 * General motion compensation dispatcher.
 */
void h264_motion_compensate(uint8_t *dst, int dst_stride,
                             const uint8_t *ref, int ref_stride,
                             int ref_width, int ref_height,
                             int x, int y, int mv_x, int mv_y,
                             int block_w, int block_h)
{
    h264_mc_luma(dst, dst_stride, ref, ref_stride,
                 ref_width, ref_height,
                 x, y, mv_x, mv_y, block_w, block_h);
}
