#include <string.h>
#include <stdlib.h>
#include "h264_common.h"
#include "h264_tables.h"
#include "../include/h264_decoder.h"

/* Forward declarations */
int h264_cavlc_decode_block(H264BitStream *bs, int16_t *coeffs, int max_coeff, int nC);
void h264_idct4x4(int16_t block[16], int qp, int is_luma);
void h264_hadamard4x4_inverse(int16_t block[16]);
void h264_hadamard2x2_inverse(int16_t block[4]);
void h264_add_residual4x4(uint8_t *dst, int stride, int16_t residual[16]);
void h264_dequantize4x4(int16_t block[16], int qp, int is_intra);
void h264_intra4x4_predict(uint8_t *dst, int stride, int mode,
                            const uint8_t *top, const uint8_t *left,
                            uint8_t top_left);
void h264_intra16x16_predict(uint8_t *dst, int stride, int mode,
                              const uint8_t *top, const uint8_t *left);
void h264_intra_chroma_predict(uint8_t *dst, int stride, int mode,
                                const uint8_t *top, const uint8_t *left,
                                int size);
void h264_mc_luma(uint8_t *dst, int dst_stride,
                  const uint8_t *src, int src_stride,
                  int src_w, int src_h,
                  int x, int y, int mv_x, int mv_y, int bw, int bh);
void h264_mc_chroma(uint8_t *dst, int dst_stride,
                    const uint8_t *src, int src_stride,
                    int src_w, int src_h,
                    int x, int y, int mv_x, int mv_y, int bw, int bh);

/* ---- Helper: get neighbours ---- */
static void get_neighbours(H264Decoder *dec, int mb_x, int mb_y,
                            uint8_t *top_y,  uint8_t *left_y,
                            uint8_t *top_cb, uint8_t *left_cb,
                            uint8_t *top_cr, uint8_t *left_cr,
                            uint8_t *tl_y,   uint8_t *tl_cb, uint8_t *tl_cr)
{
    int stride   = dec->frame_stride;
    int c_stride = dec->frame_c_stride;
    int x0 = mb_x * 16;
    int y0 = mb_y * 16;

    /* Top row */
    if (mb_y > 0 && top_y) {
        memcpy(top_y,  dec->frame_y  + (y0-1)*stride   + x0, 16);
        memcpy(top_cb, dec->frame_cb + ((y0/2-1))*c_stride + x0/2, 8);
        memcpy(top_cr, dec->frame_cr + ((y0/2-1))*c_stride + x0/2, 8);
        if (tl_y)  *tl_y  = dec->frame_y [(y0-1)*stride   + (x0 > 0 ? x0-1 : 0)];
        if (tl_cb) *tl_cb = dec->frame_cb[((y0/2)-1)*c_stride + (x0/2 > 0 ? x0/2-1 : 0)];
        if (tl_cr) *tl_cr = dec->frame_cr[((y0/2)-1)*c_stride + (x0/2 > 0 ? x0/2-1 : 0)];
    } else {
        if (top_y)  memset(top_y,  128, 16);
        if (top_cb) memset(top_cb, 128, 8);
        if (top_cr) memset(top_cr, 128, 8);
        if (tl_y)   *tl_y  = 128;
        if (tl_cb)  *tl_cb = 128;
        if (tl_cr)  *tl_cr = 128;
    }

    /* Left column */
    if (mb_x > 0 && left_y) {
        int i;
        for (i = 0; i < 16; i++)
            left_y[i] = dec->frame_y[(y0+i)*stride + x0-1];
        for (i = 0; i < 8; i++) {
            left_cb[i] = dec->frame_cb[(y0/2+i)*c_stride + x0/2-1];
            left_cr[i] = dec->frame_cr[(y0/2+i)*c_stride + x0/2-1];
        }
    } else {
        if (left_y)  memset(left_y,  128, 16);
        if (left_cb) memset(left_cb, 128, 8);
        if (left_cr) memset(left_cr, 128, 8);
    }
}

/* ---- CBP tables for I_16x16 mb_type encoding ---- */
/* mb_type = 1..24 encodes intra16x16 mode, cbp, and transform */
static void decode_i16x16_mb_type(int mb_type_raw, int *pred_mode,
                                   int *cbp_luma, int *cbp_chroma)
{
    int t = mb_type_raw - 1; /* 0..23 */
    *pred_mode  = t % 4;         /* 0..3 */
    *cbp_chroma = (t / 4) % 3;  /* 0..2 */
    *cbp_luma   = (t / 12) ? 15 : 0; /* 0 or 15 (all or none) */
}

/* ---- CBP mapping tables for P/B macroblocks ---- */
static const int cbp_inter_table[48] = {
    0,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,
    31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,
    47, 8, 9,10,11,12,13,14,15, 1, 2, 3, 4, 5, 6, 7
};
static const int cbp_intra_table[48] = {
    47,31,15, 0,23, 27,29,30, 7,11,13,14,39,43,45,46,
    16, 3, 5, 10,12,19,21,26,28,35,37,42,44, 1, 2, 4,
    8, 17,18,20,24,6, 9,22,25,32,33,34,36,40,38,41
};

/* ---- Slice header parsing ---- */

int h264_parse_slice_header(H264BitStream *bs, H264Decoder *dec,
                             H264SliceHeader *sh)
{
    int is_idr = sh->is_idr; /* preserve before memset */
    memset(sh, 0, sizeof(*sh));
    sh->is_idr = is_idr;

    sh->first_mb_in_slice  = (int)bs_read_ue(bs);
    sh->slice_type_raw     = (int)bs_read_ue(bs);
    sh->slice_type         = sh->slice_type_raw % 5;
    sh->pic_parameter_set_id = (int)bs_read_ue(bs);

    if (sh->pic_parameter_set_id >= H264_MAX_PPS)     return H264_ERR_PARAM;
    if (!dec->pps[sh->pic_parameter_set_id].is_valid) return H264_ERR_PARAM;

    H264PPS *pps = &dec->pps[sh->pic_parameter_set_id];
    int sps_id   = pps->seq_parameter_set_id;
    if (sps_id >= H264_MAX_SPS || !dec->sps[sps_id].is_valid) return H264_ERR_PARAM;
    H264SPS *sps = &dec->sps[sps_id];

    dec->active_pps_id = sh->pic_parameter_set_id;
    dec->active_sps_id = sps_id;

    int log2_max_fn = sps->log2_max_frame_num_minus4 + 4;
    sh->frame_num = (int)bs_read_bits(bs, log2_max_fn);

    if (sh->is_idr) {
        sh->idr_pic_id = (int)bs_read_ue(bs);
    }

    if (sps->pic_order_cnt_type == 0) {
        int log2_max_poc = sps->log2_max_pic_order_cnt_lsb_minus4 + 4;
        sh->pic_order_cnt_lsb = (int)bs_read_bits(bs, log2_max_poc);
        if (pps->bottom_field_pic_order_in_frame_present_flag)
            sh->delta_pic_order_cnt_bottom = (int)bs_read_se(bs);
    } else if (sps->pic_order_cnt_type == 1) {
        if (!sps->delta_pic_order_always_zero_flag) {
            sh->delta_pic_order_cnt[0] = (int)bs_read_se(bs);
            if (pps->bottom_field_pic_order_in_frame_present_flag)
                sh->delta_pic_order_cnt[1] = (int)bs_read_se(bs);
        }
    }

    if (pps->redundant_pic_cnt_present_flag)
        sh->redundant_pic_cnt = (int)bs_read_ue(bs);

    if (sh->slice_type == H264_SLICE_B)
        sh->direct_spatial_mv_pred_flag = (int)bs_read_u1(bs);

    if (sh->slice_type == H264_SLICE_P || sh->slice_type == H264_SLICE_SP ||
        sh->slice_type == H264_SLICE_B) {
        sh->num_ref_idx_active_override_flag = (int)bs_read_u1(bs);
        if (sh->num_ref_idx_active_override_flag) {
            sh->num_ref_idx_l0_active_minus1 = (int)bs_read_ue(bs);
            if (sh->slice_type == H264_SLICE_B)
                sh->num_ref_idx_l1_active_minus1 = (int)bs_read_ue(bs);
        } else {
            sh->num_ref_idx_l0_active_minus1 = pps->num_ref_idx_l0_default_active_minus1;
            sh->num_ref_idx_l1_active_minus1 = pps->num_ref_idx_l1_default_active_minus1;
        }
    }

    /* ref_pic_list_modification */
    if (sh->slice_type != H264_SLICE_I && sh->slice_type != H264_SLICE_SI) {
        sh->ref_pic_list_modification_flag_l0 = (int)bs_read_u1(bs);
        if (sh->ref_pic_list_modification_flag_l0) {
            int op;
            do {
                op = (int)bs_read_ue(bs);
                if (op != 3) bs_read_ue(bs);
            } while (op != 3);
        }
    }
    if (sh->slice_type == H264_SLICE_B) {
        sh->ref_pic_list_modification_flag_l1 = (int)bs_read_u1(bs);
        if (sh->ref_pic_list_modification_flag_l1) {
            int op;
            do {
                op = (int)bs_read_ue(bs);
                if (op != 3) bs_read_ue(bs);
            } while (op != 3);
        }
    }

    /* pred_weight_table skipped */

    /* dec_ref_pic_marking */
    if (sh->is_idr) {
        sh->no_output_of_prior_pics_flag = (int)bs_read_u1(bs);
        sh->long_term_reference_flag     = (int)bs_read_u1(bs);
    } else if (sh->nal_ref_idc != 0) {
        sh->adaptive_ref_pic_marking_mode_flag = (int)bs_read_u1(bs);
        if (sh->adaptive_ref_pic_marking_mode_flag) {
            int op;
            do {
                op = (int)bs_read_ue(bs);
                if (op != 0) {
                    if (op == 1 || op == 3 || op == 5 || op == 6)
                        bs_read_ue(bs);
                    if (op == 2 || op == 4)
                        bs_read_ue(bs);
                }
            } while (op != 0);
        }
    }

    sh->slice_qp_delta = (int)bs_read_se(bs);
    sh->qp = 26 + pps->pic_init_qp_minus26 + sh->slice_qp_delta;

    if (pps->deblocking_filter_control_present_flag) {
        sh->disable_deblocking_filter_idc = (int)bs_read_ue(bs);
        if (sh->disable_deblocking_filter_idc != 1) {
            sh->slice_alpha_c0_offset_div2 = (int)bs_read_se(bs);
            sh->slice_beta_offset_div2     = (int)bs_read_se(bs);
        }
    }

    return H264_OK;
}

/* ---- Macroblock decoding helpers ---- */

static int decode_intra4x4_pred_mode(H264BitStream *bs, int prev_mode,
                                      int *mode_out)
{
    int use_prev = (int)bs_read_u1(bs);
    if (use_prev) {
        *mode_out = prev_mode;
    } else {
        int rem = (int)bs_read_bits(bs, 3);
        *mode_out = rem < prev_mode ? rem : rem + 1;
    }
    return H264_OK;
}

/* Get intra 4x4 predicted mode from neighbours (simplified: return 2=DC) */
static int get_intra4x4_pred_mode_from_neighbour(H264Decoder *dec,
                                                   int mb_x, int mb_y,
                                                   int blk_x, int blk_y)
{
    (void)dec; (void)mb_x; (void)mb_y; (void)blk_x; (void)blk_y;
    return 2; /* DC is the safest fallback */
}

/* CBP parsing for non-I_16x16 macroblocks */
static int parse_cbp(H264BitStream *bs, int is_intra)
{
    int idx = (int)bs_read_ue(bs);
    if (idx < 0 || idx >= 48) return H264_ERR_BITSTREAM;
    return is_intra ? cbp_intra_table[idx] : cbp_inter_table[idx];
}

/* ---- Motion vector prediction ---- */

/* Return a stored MV component from a neighbouring macroblock, or 0. */
static int16_t mb_mv(const H264Decoder *dec, int mb_x, int mb_y,
                     int part, int comp)
{
    if (mb_x < 0 || mb_y < 0 ||
        mb_x >= dec->mb_width || mb_y >= dec->mb_height)
        return 0;
    return dec->mbs[mb_y * dec->mb_width + mb_x].mv_l0[part][comp];
}

static int16_t median3_mv(int16_t a, int16_t b, int16_t c)
{
    int16_t mn = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
    int16_t mx = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
    return (int16_t)(a + b + c - mn - mx);
}

/*
 * Compute the H.264 median motion vector predictor for a 16x16 partition.
 * Uses neighbours A (left), B (top), C (top-right, or top-left if unavailable).
 */
static void compute_mvp(const H264Decoder *dec, int mb_x, int mb_y,
                        int16_t mvp[2])
{
    int16_t ax = mb_mv(dec, mb_x - 1, mb_y,     0, 0);
    int16_t ay = mb_mv(dec, mb_x - 1, mb_y,     0, 1);
    int16_t bx = mb_mv(dec, mb_x,     mb_y - 1, 0, 0);
    int16_t by = mb_mv(dec, mb_x,     mb_y - 1, 0, 1);
    int16_t cx, cy;
    if (mb_x + 1 < dec->mb_width && mb_y > 0) {
        cx = mb_mv(dec, mb_x + 1, mb_y - 1, 0, 0);
        cy = mb_mv(dec, mb_x + 1, mb_y - 1, 0, 1);
    } else {
        cx = mb_mv(dec, mb_x - 1, mb_y - 1, 0, 0);
        cy = mb_mv(dec, mb_x - 1, mb_y - 1, 0, 1);
    }
    mvp[0] = median3_mv(ax, bx, cx);
    mvp[1] = median3_mv(ay, by, cy);
}

/* Read truncated exp-Golomb code te(max_val) for a reference frame index. */
static int read_ref_idx(H264BitStream *bs, int max_val)
{
    if (max_val <= 0) return 0;   /* single reference: no bits written */
    if (max_val == 1) return (int)bs_read_u1(bs);
    return (int)bs_read_ue(bs);
}

/* ---- Motion compensation and P-frame helpers ---- */

/* Fill a 16x16 macroblock with grey (128) on all three planes. */
static void mb_fill_gray(H264Decoder *dec, int mb_x, int mb_y)
{
    int stride   = dec->frame_stride;
    int c_stride = dec->frame_c_stride;
    int x0 = mb_x * 16;
    int y0 = mb_y * 16;
    int i;
    for (i = 0; i < 16; i++)
        memset(dec->frame_y  + (y0 + i) * stride   + x0,     128, 16);
    for (i = 0; i < 8; i++) {
        memset(dec->frame_cb + (y0/2 + i) * c_stride + x0/2, 128, 8);
        memset(dec->frame_cr + (y0/2 + i) * c_stride + x0/2, 128, 8);
    }
}

/*
 * Luma + chroma (4:2:0) motion compensation for a block of bw x bh luma
 * pixels at position (x0, y0).  mv_x and mv_y are in quarter-luma-pixel
 * units.  For 4:2:0, one quarter-luma-pixel equals one eighth-chroma-pixel
 * numerically, so the same integer MV values are passed to h264_mc_chroma.
 */
static void do_mc(H264Decoder *dec, const H264RefPic *ref,
                  int x0, int y0, int bw, int bh,
                  int16_t mv_x, int16_t mv_y)
{
    int stride   = dec->frame_stride;
    int c_stride = dec->frame_c_stride;
    h264_mc_luma(dec->frame_y + y0 * stride + x0, stride,
                 ref->y, ref->stride, ref->width, ref->height,
                 x0, y0, (int)mv_x, (int)mv_y, bw, bh);
    h264_mc_chroma(dec->frame_cb + (y0/2) * c_stride + x0/2, c_stride,
                   ref->cb, ref->c_stride, ref->width/2, ref->height/2,
                   x0/2, y0/2, (int)mv_x, (int)mv_y, bw/2, bh/2);
    h264_mc_chroma(dec->frame_cr + (y0/2) * c_stride + x0/2, c_stride,
                   ref->cr, ref->c_stride, ref->width/2, ref->height/2,
                   x0/2, y0/2, (int)mv_x, (int)mv_y, bw/2, bh/2);
}

/*
 * Handle a P-skip macroblock: perform MC with the median-predictor MV
 * (as specified by H.264 for P-skip), or fill grey if no reference available.
 */
static void p_skip_mb(H264Decoder *dec, int mb_x, int mb_y)
{
    H264MacroBlock *mb = &dec->mbs[mb_y * dec->mb_width + mb_x];
    int i;
    memset(mb, 0, sizeof(*mb));
    mb->is_skipped = 1;

    int16_t mvp[2] = {0, 0};
    compute_mvp(dec, mb_x, mb_y, mvp);
    for (i = 0; i < 4; i++) {
        mb->mv_l0[i][0] = mvp[0];
        mb->mv_l0[i][1] = mvp[1];
    }

    if (dec->num_ref > 0 && dec->ref[0].is_valid)
        do_mc(dec, &dec->ref[0], mb_x * 16, mb_y * 16, 16, 16,
              mvp[0], mvp[1]);
    else
        mb_fill_gray(dec, mb_x, mb_y);

    mb->decoded = 1;
}

/*
 * Decode inter (P-frame) residuals: luma 4x4 CAVLC blocks (no DC Hadamard)
 * and chroma DC (2x2 Hadamard) + optional AC for a macroblock.
 */
static int decode_inter_residuals(H264Decoder *dec, H264BitStream *bs,
                                   int mb_x, int mb_y, int cbp, int qp)
{
    int stride   = dec->frame_stride;
    int c_stride = dec->frame_c_stride;
    int x0 = mb_x * 16;
    int y0 = mb_y * 16;
    int cbp_luma   = cbp & 0x0F;
    int cbp_chroma = (cbp >> 4) & 0x03;
    int i, j;

    /* Luma: 4 8x8 groups, each containing 4 4x4 CAVLC blocks (no DC Hadamard) */
    for (i = 0; i < 4; i++) {
        if (!(cbp_luma & (1 << i))) continue;
        int bx8 = (i % 2) * 8;
        int by8 = (i / 2) * 8;
        for (j = 0; j < 4; j++) {
            int bx = bx8 + (j % 2) * 4;
            int by = by8 + (j / 2) * 4;
            uint8_t *dst = dec->frame_y + (y0 + by) * stride + x0 + bx;
            int16_t coeffs[16];
            memset(coeffs, 0, sizeof(coeffs));
            if (h264_cavlc_decode_block(bs, coeffs, 16, 0) != H264_OK)
                return H264_ERR_BITSTREAM;
            h264_idct4x4(coeffs, qp, 1);
            h264_add_residual4x4(dst, stride, coeffs);
        }
    }

    /* Chroma DC + (optionally) AC */
    if (cbp_chroma > 0) {
        int16_t dc_cb[4], dc_cr[4];
        memset(dc_cb, 0, sizeof(dc_cb));
        memset(dc_cr, 0, sizeof(dc_cr));
        if (h264_cavlc_decode_block(bs, dc_cb, 4, -1) != H264_OK)
            return H264_ERR_BITSTREAM;
        if (h264_cavlc_decode_block(bs, dc_cr, 4, -1) != H264_OK)
            return H264_ERR_BITSTREAM;
        h264_hadamard2x2_inverse(dc_cb);
        h264_hadamard2x2_inverse(dc_cr);

        for (i = 0; i < 4; i++) {
            int bx = (i % 2) * 4;
            int by = (i / 2) * 4;
            uint8_t *dst_cb = dec->frame_cb + (y0/2 + by) * c_stride + x0/2 + bx;
            uint8_t *dst_cr = dec->frame_cr + (y0/2 + by) * c_stride + x0/2 + bx;
            if (cbp_chroma == 2) {
                int16_t ac_cb[16], ac_cr[16];
                memset(ac_cb, 0, sizeof(ac_cb));
                memset(ac_cr, 0, sizeof(ac_cr));
                if (h264_cavlc_decode_block(bs, ac_cb + 1, 15, 0) != H264_OK)
                    return H264_ERR_BITSTREAM;
                if (h264_cavlc_decode_block(bs, ac_cr + 1, 15, 0) != H264_OK)
                    return H264_ERR_BITSTREAM;
                ac_cb[0] = dc_cb[i];
                ac_cr[0] = dc_cr[i];
                h264_idct4x4(ac_cb, qp, 0);
                h264_idct4x4(ac_cr, qp, 0);
                h264_add_residual4x4(dst_cb, c_stride, ac_cb);
                h264_add_residual4x4(dst_cr, c_stride, ac_cr);
            } else {
                /* cbp_chroma == 1: DC only */
                int16_t ac[16];
                memset(ac, 0, sizeof(ac));
                ac[0] = dc_cb[i];
                h264_idct4x4(ac, qp, 0);
                h264_add_residual4x4(dst_cb, c_stride, ac);
                memset(ac, 0, sizeof(ac));
                ac[0] = dc_cr[i];
                h264_idct4x4(ac, qp, 0);
                h264_add_residual4x4(dst_cr, c_stride, ac);
            }
        }
    }
    return H264_OK;
}

/* ---- Decode macroblock ---- */

int h264_decode_macroblock(H264Decoder *dec, H264BitStream *bs,
                            int mb_x, int mb_y)
{
    H264SPS *sps = &dec->sps[dec->active_sps_id];
    H264PPS *pps = &dec->pps[dec->active_pps_id];
    H264SliceHeader *sh = &dec->current_sh;
    int mb_idx = mb_y * dec->mb_width + mb_x;
    H264MacroBlock *mb = &dec->mbs[mb_idx];
    int i, j;

    memset(mb, 0, sizeof(*mb));

    int x0 = mb_x * 16;
    int y0 = mb_y * 16;
    int stride   = dec->frame_stride;
    int c_stride = dec->frame_c_stride;

    /* Neighbour samples */
    uint8_t top_y[16], left_y[16];
    uint8_t top_cb[8], left_cb[8];
    uint8_t top_cr[8], left_cr[8];
    uint8_t tl_y = 128, tl_cb = 128, tl_cr = 128;
    get_neighbours(dec, mb_x, mb_y,
                   top_y, left_y, top_cb, left_cb, top_cr, left_cr,
                   &tl_y, &tl_cb, &tl_cr);

    /* P-skip handling */
    if (sh->slice_type == H264_SLICE_P) {
        /* Skip run is handled by h264_decode_slice; here we only see coded MBs */
    }

    /* Read mb_type */
    int mb_type_raw = (int)bs_read_ue(bs);
    mb->mb_type_raw = mb_type_raw;

    /*
     * In a P-slice, mb_type >= 5 signals an intra macroblock:
     *   5  -> I_4x4  (raw type 0 in I-slice)
     *   6..29 -> I_16x16 variants (raw types 1..24, i.e. mb_type-5 = 1..24)
     *   30 -> I_PCM  (raw type 25, i.e. mb_type-5 = 25)
     * Remap and treat as an I-slice macroblock.
     */
    int effective_slice_type = sh->slice_type;
    if (sh->slice_type == H264_SLICE_P && mb_type_raw >= 5) {
        mb_type_raw -= 5;
        effective_slice_type = H264_SLICE_I;
    }

    if (effective_slice_type == H264_SLICE_I) {
        mb->is_intra = 1;

        if (mb_type_raw == H264_MB_I_PCM) {
            /* I_PCM: byte-align, then read raw samples */
            mb->is_pcm = 1;
            while (!bs_byte_aligned(bs)) bs_read_u1(bs);

            for (i = 0; i < 256; i++)
                mb->pcm_luma[i] = bs_read_u8(bs);
            for (i = 0; i < 64; i++)
                mb->pcm_cb[i] = bs_read_u8(bs);
            for (i = 0; i < 64; i++)
                mb->pcm_cr[i] = bs_read_u8(bs);

            /* Copy PCM samples to frame */
            for (i = 0; i < 16; i++)
                memcpy(dec->frame_y + (y0+i)*stride + x0, mb->pcm_luma + i*16, 16);
            for (i = 0; i < 8; i++) {
                memcpy(dec->frame_cb + (y0/2+i)*c_stride + x0/2, mb->pcm_cb + i*8, 8);
                memcpy(dec->frame_cr + (y0/2+i)*c_stride + x0/2, mb->pcm_cr + i*8, 8);
            }
            mb->decoded = 1;
            dec->prev_qp = sh->qp;
            return H264_OK;
        }

        if (mb_type_raw >= 1 && mb_type_raw <= 24) {
            /* I_16x16 */
            mb->mb_type = 1; /* I_16x16 */
            int pred_mode, cbp_luma, cbp_chroma;
            decode_i16x16_mb_type(mb_type_raw, &pred_mode, &cbp_luma, &cbp_chroma);
            mb->intra16x16_pred_mode = pred_mode;
            mb->cbp_luma   = cbp_luma;
            mb->cbp_chroma = cbp_chroma;

            mb->intra_chroma_pred_mode = (int)bs_read_ue(bs);
            int qp_delta = (int)bs_read_se(bs);
            mb->qp = dec->prev_qp + qp_delta;
            if (mb->qp < 0) mb->qp = 0;
            if (mb->qp > 51) mb->qp = 51;
            dec->prev_qp = mb->qp;

            /* Luma DC (Hadamard 4x4) */
            int16_t dc_block[16];
            memset(dc_block, 0, sizeof(dc_block));
            if (h264_cavlc_decode_block(bs, dc_block, 16, 0) != H264_OK)
                return H264_ERR_BITSTREAM;

            /* Dequantize DC */
            {
                int qp = mb->qp;
                int qp_mod = qp % 6;
                int qp_div = qp / 6;
                int v = (qp_div >= 2) ? (10 << (qp_div - 2)) :
                        ((qp_div == 1) ? 5 : 2);
                (void)qp_mod;
                for (i = 0; i < 16; i++)
                    dc_block[i] = (int16_t)(dc_block[i] * v);
            }
            h264_hadamard4x4_inverse(dc_block);

            /* Do 16x16 luma prediction */
            h264_intra16x16_predict(dec->frame_y + y0*stride + x0, stride,
                                    pred_mode, top_y, left_y);

            /* Luma AC blocks */
            for (i = 0; i < 16; i++) {
                int bx = (i % 4) * 4;
                int by = (i / 4) * 4;
                uint8_t *dst = dec->frame_y + (y0+by)*stride + x0+bx;

                if (cbp_luma & (1 << (i/4))) {
                    int16_t ac[16];
                    memset(ac, 0, sizeof(ac));
                    if (h264_cavlc_decode_block(bs, ac+1, 15, 0) != H264_OK)
                        return H264_ERR_BITSTREAM;
                    ac[0] = dc_block[i];
                    h264_idct4x4(ac, mb->qp, 1);
                    h264_add_residual4x4(dst, stride, ac);
                } else {
                    /* DC only */
                    int16_t ac[16];
                    memset(ac, 0, sizeof(ac));
                    ac[0] = dc_block[i];
                    h264_idct4x4(ac, mb->qp, 1);
                    h264_add_residual4x4(dst, stride, ac);
                }
            }

            /* Chroma */
            h264_intra_chroma_predict(dec->frame_cb + (y0/2)*c_stride + x0/2,
                                      c_stride, mb->intra_chroma_pred_mode,
                                      top_cb, left_cb, 8);
            h264_intra_chroma_predict(dec->frame_cr + (y0/2)*c_stride + x0/2,
                                      c_stride, mb->intra_chroma_pred_mode,
                                      top_cr, left_cr, 8);

            if (cbp_chroma) {
                /* Cb/Cr DC + AC */
                int16_t dc_cb[4], dc_cr[4];
                memset(dc_cb, 0, sizeof(dc_cb)); memset(dc_cr, 0, sizeof(dc_cr));
                if (h264_cavlc_decode_block(bs, dc_cb, 4, -1) != H264_OK)
                    return H264_ERR_BITSTREAM;
                if (h264_cavlc_decode_block(bs, dc_cr, 4, -1) != H264_OK)
                    return H264_ERR_BITSTREAM;

                h264_hadamard2x2_inverse(dc_cb);
                h264_hadamard2x2_inverse(dc_cr);

                for (i = 0; i < 4; i++) {
                    int bx = (i % 2) * 4;
                    int by = (i / 2) * 4;

                    uint8_t *dst_cb = dec->frame_cb + (y0/2+by)*c_stride + x0/2+bx;
                    uint8_t *dst_cr = dec->frame_cr + (y0/2+by)*c_stride + x0/2+bx;

                    if (cbp_chroma == 2) {
                        int16_t ac_cb[16], ac_cr[16];
                        memset(ac_cb, 0, sizeof(ac_cb));
                        memset(ac_cr, 0, sizeof(ac_cr));
                        if (h264_cavlc_decode_block(bs, ac_cb+1, 15, 0) != H264_OK)
                            return H264_ERR_BITSTREAM;
                        if (h264_cavlc_decode_block(bs, ac_cr+1, 15, 0) != H264_OK)
                            return H264_ERR_BITSTREAM;
                        ac_cb[0] = dc_cb[i];
                        ac_cr[0] = dc_cr[i];
                        h264_idct4x4(ac_cb, mb->qp, 0);
                        h264_idct4x4(ac_cr, mb->qp, 0);
                        h264_add_residual4x4(dst_cb, c_stride, ac_cb);
                        h264_add_residual4x4(dst_cr, c_stride, ac_cr);
                    } else {
                        int16_t ac[16];
                        memset(ac, 0, sizeof(ac));
                        ac[0] = dc_cb[i];
                        h264_idct4x4(ac, mb->qp, 0);
                        h264_add_residual4x4(dst_cb, c_stride, ac);
                        memset(ac, 0, sizeof(ac));
                        ac[0] = dc_cr[i];
                        h264_idct4x4(ac, mb->qp, 0);
                        h264_add_residual4x4(dst_cr, c_stride, ac);
                    }
                }
            }

        } else if (mb_type_raw == 0) {
            /* I_4x4 */
            mb->mb_type = H264_MB_I_4x4;
            mb->intra_chroma_pred_mode = 0;

            /* Parse intra 4x4 prediction modes */
            for (i = 0; i < 16; i++) {
                int prev = get_intra4x4_pred_mode_from_neighbour(dec, mb_x, mb_y,
                                                                   i%4, i/4);
                decode_intra4x4_pred_mode(bs, prev, &mb->intra4x4_pred_mode[i]);
            }
            mb->intra_chroma_pred_mode = (int)bs_read_ue(bs);

            /* CBP */
            int cbp = parse_cbp(bs, 1);
            if (cbp < 0) return H264_ERR_BITSTREAM;
            mb->cbp = cbp;
            mb->cbp_luma   = cbp & 0x0F;
            mb->cbp_chroma = (cbp >> 4) & 0x03;

            /* QP delta */
            if (mb->cbp) {
                int qp_delta = (int)bs_read_se(bs);
                mb->qp = dec->prev_qp + qp_delta;
                if (mb->qp < 0) mb->qp = 0;
                if (mb->qp > 51) mb->qp = 51;
                dec->prev_qp = mb->qp;
            } else {
                mb->qp = dec->prev_qp;
            }

            /* Process each 4x4 block */
            for (i = 0; i < 16; i++) {
                int blk_x = (i % 4);
                int blk_y = (i / 4);
                int bx = blk_x * 4;
                int by = blk_y * 4;
                uint8_t *dst = dec->frame_y + (y0+by)*stride + x0+bx;

                /* Build neighbours for 4x4 block */
                uint8_t blk_top[4], blk_left[4];
                uint8_t blk_tl;
                for (j = 0; j < 4; j++) {
                    if (by == 0) {
                        blk_top[j] = (mb_y > 0) ? dec->frame_y[(y0-1)*stride + x0+bx+j] : 128;
                    } else {
                        blk_top[j] = dec->frame_y[(y0+by-1)*stride + x0+bx+j];
                    }
                    if (bx == 0) {
                        blk_left[j] = (mb_x > 0) ? dec->frame_y[(y0+by+j)*stride + x0-1] : 128;
                    } else {
                        blk_left[j] = dec->frame_y[(y0+by+j)*stride + x0+bx-1];
                    }
                }
                if (bx == 0 && by == 0)
                    blk_tl = tl_y;
                else if (bx == 0)
                    blk_tl = (mb_x > 0) ? dec->frame_y[(y0+by-1)*stride + x0-1] : 128;
                else
                    blk_tl = dec->frame_y[(y0+by-1)*stride + x0+bx-1];

                h264_intra4x4_predict(dst, stride,
                                      mb->intra4x4_pred_mode[i],
                                      blk_top, blk_left, blk_tl);

                /* CAVLC residuals */
                if (mb->cbp_luma & (1 << blk_y)) {
                    int16_t coeffs[16];
                    memset(coeffs, 0, sizeof(coeffs));
                    if (h264_cavlc_decode_block(bs, coeffs, 16, 0) != H264_OK)
                        return H264_ERR_BITSTREAM;
                    h264_idct4x4(coeffs, mb->qp, 1);
                    h264_add_residual4x4(dst, stride, coeffs);
                }
            }

            /* Chroma */
            h264_intra_chroma_predict(dec->frame_cb + (y0/2)*c_stride + x0/2,
                                      c_stride, mb->intra_chroma_pred_mode,
                                      top_cb, left_cb, 8);
            h264_intra_chroma_predict(dec->frame_cr + (y0/2)*c_stride + x0/2,
                                      c_stride, mb->intra_chroma_pred_mode,
                                      top_cr, left_cr, 8);

            if (mb->cbp_chroma) {
                int16_t dc_cb[4], dc_cr[4];
                memset(dc_cb, 0, sizeof(dc_cb)); memset(dc_cr, 0, sizeof(dc_cr));
                if (h264_cavlc_decode_block(bs, dc_cb, 4, -1) != H264_OK)
                    return H264_ERR_BITSTREAM;
                if (h264_cavlc_decode_block(bs, dc_cr, 4, -1) != H264_OK)
                    return H264_ERR_BITSTREAM;
                h264_hadamard2x2_inverse(dc_cb);
                h264_hadamard2x2_inverse(dc_cr);

                for (i = 0; i < 4; i++) {
                    int bx = (i%2)*4, by = (i/2)*4;
                    uint8_t *dst_cb = dec->frame_cb + (y0/2+by)*c_stride + x0/2+bx;
                    uint8_t *dst_cr = dec->frame_cr + (y0/2+by)*c_stride + x0/2+bx;
                    if (mb->cbp_chroma == 2) {
                        int16_t ac_cb[16], ac_cr[16];
                        memset(ac_cb, 0, sizeof(ac_cb)); memset(ac_cr, 0, sizeof(ac_cr));
                        if (h264_cavlc_decode_block(bs, ac_cb+1, 15, 0) != H264_OK)
                            return H264_ERR_BITSTREAM;
                        if (h264_cavlc_decode_block(bs, ac_cr+1, 15, 0) != H264_OK)
                            return H264_ERR_BITSTREAM;
                        ac_cb[0] = dc_cb[i]; ac_cr[0] = dc_cr[i];
                        h264_idct4x4(ac_cb, mb->qp, 0);
                        h264_idct4x4(ac_cr, mb->qp, 0);
                        h264_add_residual4x4(dst_cb, c_stride, ac_cb);
                        h264_add_residual4x4(dst_cr, c_stride, ac_cr);
                    } else {
                        /* cbp_chroma == 1: DC only */
                        int16_t ac[16];
                        memset(ac, 0, sizeof(ac));
                        ac[0] = dc_cb[i];
                        h264_idct4x4(ac, mb->qp, 0);
                        h264_add_residual4x4(dst_cb, c_stride, ac);
                        memset(ac, 0, sizeof(ac));
                        ac[0] = dc_cr[i];
                        h264_idct4x4(ac, mb->qp, 0);
                        h264_add_residual4x4(dst_cr, c_stride, ac);
                    }
                }
            }
        } else {
            return H264_ERR_UNSUPPORTED;
        }
    } else if (sh->slice_type == H264_SLICE_P) {
        /*
         * P-slice inter macroblock.  mb_type_raw values (intra-in-P is
         * already remapped to effective_slice_type == I above):
         *   0  P_L0_16x16        single 16x16 partition
         *   1  P_L0_L0_16x8      top-16x8 + bottom-16x8 partitions
         *   2  P_L0_L0_8x16      left-8x16 + right-8x16 partitions
         *   3  P_8x8             four 8x8 sub-macroblocks
         *   4  P_8x8ref0         four 8x8 sub-MBs, ref_idx always 0
         */
        int n_ref = pps->num_ref_idx_l0_default_active_minus1;
        if (sh->num_ref_idx_active_override_flag)
            n_ref = sh->num_ref_idx_l0_active_minus1;
        H264RefPic *ref = (dec->num_ref > 0 && dec->ref[0].is_valid) ?
                           &dec->ref[0] : NULL;

        /* Number of top-level partitions */
        int npart = (mb_type_raw == 0) ? 1 :
                    (mb_type_raw <= 2) ? 2 : 4;

        /* sub_mb_type for P_8x8 / P_8x8ref0 */
        int sub_type[4] = {0, 0, 0, 0};
        if (mb_type_raw == 3 || mb_type_raw == 4) {
            for (i = 0; i < 4; i++)
                sub_type[i] = (int)bs_read_ue(bs);
        }

        /* ref_idx_l0 per partition (te(v); no bits when n_ref == 0).
         * For P_8x8ref0 (mb_type_raw == 4), the spec does not code ref_idx_l0;
         * it is implicitly 0, so we must not consume any bits here.
         */
        if (mb_type_raw != 4) {
            for (i = 0; i < npart; i++)
                (void)read_ref_idx(bs, n_ref);
        }

        /* mvd_l0: read per partition / sub-partition.
         * For P_8x8/P_8x8ref0 each 8x8 block can contain up to 4 sub-partitions
         * (P_L0_8x8=1, P_L0_8x4=2, P_L0_4x8=2, P_L0_4x4=4), each with its own MV.
         * sub_mv[block][sub_partition][x/y]                                      */
        int16_t mv[4][2];
        int16_t sub_mv[4][4][2];  /* used only for P_8x8 / P_8x8ref0 */
        if (mb_type_raw == 3 || mb_type_raw == 4) {
            memset(sub_mv, 0, sizeof(sub_mv));
            /* P_8x8 / P_8x8ref0: read MVDs for each sub-MB, per sub-partition */
            for (i = 0; i < 4; i++) {
                /* Number of sub-partitions inside this 8x8 block */
                int nsub = (sub_type[i] == 3) ? 4 :
                           (sub_type[i] >= 1) ? 2 : 1;
                int16_t mvp[2] = {0, 0};
                compute_mvp(dec, mb_x, mb_y, mvp);
                int k;
                for (k = 0; k < nsub; k++) {
                    int16_t dx = (int16_t)bs_read_se(bs);
                    int16_t dy = (int16_t)bs_read_se(bs);
                    sub_mv[i][k][0] = (int16_t)(mvp[0] + dx);
                    sub_mv[i][k][1] = (int16_t)(mvp[1] + dy);
                }
                /* Store first sub-partition MV in mb->mv_l0[i] for neighbour prediction */
                mv[i][0] = sub_mv[i][0][0];
                mv[i][1] = sub_mv[i][0][1];
                mb->mv_l0[i][0] = mv[i][0];
                mb->mv_l0[i][1] = mv[i][1];
            }
        } else {
            /* P_L0_16x16, P_L0_L0_16x8, P_L0_L0_8x16 */
            for (i = 0; i < npart; i++) {
                int16_t mvp[2] = {0, 0};
                compute_mvp(dec, mb_x, mb_y, mvp);
                int16_t dx = (int16_t)bs_read_se(bs);
                int16_t dy = (int16_t)bs_read_se(bs);
                mv[i][0] = (int16_t)(mvp[0] + dx);
                mv[i][1] = (int16_t)(mvp[1] + dy);
                mb->mv_l0[i][0] = mv[i][0];
                mb->mv_l0[i][1] = mv[i][1];
            }
            /* Replicate last partition MV for neighbour predictor */
            for (i = npart; i < 4; i++) {
                mb->mv_l0[i][0] = mv[npart - 1][0];
                mb->mv_l0[i][1] = mv[npart - 1][1];
            }
        }

        /* CBP */
        {
            int cbp_idx = (int)bs_read_ue(bs);
            if (cbp_idx >= 48) {
                return H264_ERR_BITSTREAM;
            }
            int cbp = cbp_inter_table[cbp_idx];
            mb->cbp       = cbp;
            mb->cbp_luma   = cbp & 0x0F;
            mb->cbp_chroma = (cbp >> 4) & 0x03;

            /* QP delta (present only when CBP != 0) */
            if (cbp != 0) {
                int qp_delta = (int)bs_read_se(bs);
                mb->qp = dec->prev_qp + qp_delta;
                if (mb->qp < 0) mb->qp = 0;
                if (mb->qp > 51) mb->qp = 51;
                dec->prev_qp = mb->qp;
            } else {
                mb->qp = dec->prev_qp;
            }

            /* Motion compensation */
            if (ref) {
                switch (mb_type_raw) {
                case 0: /* P_L0_16x16 */
                    do_mc(dec, ref, x0, y0, 16, 16, mv[0][0], mv[0][1]);
                    break;
                case 1: /* P_L0_L0_16x8 */
                    do_mc(dec, ref, x0, y0,   16, 8, mv[0][0], mv[0][1]);
                    do_mc(dec, ref, x0, y0+8, 16, 8, mv[1][0], mv[1][1]);
                    break;
                case 2: /* P_L0_L0_8x16 */
                    do_mc(dec, ref, x0,   y0, 8, 16, mv[0][0], mv[0][1]);
                    do_mc(dec, ref, x0+8, y0, 8, 16, mv[1][0], mv[1][1]);
                    break;
                default: /* P_8x8 / P_8x8ref0: per sub-macroblock partition */
                {
                    int i;
                    for (i = 0; i < 4; i++) {
                        int sx = x0 + (i & 1) * 8;
                        int sy = y0 + (i >> 1) * 8;
                        switch (sub_type[i]) {
                        case 0: /* P_L0_8x8 — one 8x8 block */
                            do_mc(dec, ref, sx,     sy,     8, 8, sub_mv[i][0][0], sub_mv[i][0][1]);
                            break;
                        case 1: /* P_L0_8x4 — two 8x4 sub-partitions (top/bottom) */
                            do_mc(dec, ref, sx,     sy,     8, 4, sub_mv[i][0][0], sub_mv[i][0][1]);
                            do_mc(dec, ref, sx,     sy + 4, 8, 4, sub_mv[i][1][0], sub_mv[i][1][1]);
                            break;
                        case 2: /* P_L0_4x8 — two 4x8 sub-partitions (left/right) */
                            do_mc(dec, ref, sx,     sy,     4, 8, sub_mv[i][0][0], sub_mv[i][0][1]);
                            do_mc(dec, ref, sx + 4, sy,     4, 8, sub_mv[i][1][0], sub_mv[i][1][1]);
                            break;
                        case 3: /* P_L0_4x4 — four 4x4 sub-partitions (Z-scan) */
                            do_mc(dec, ref, sx,     sy,     4, 4, sub_mv[i][0][0], sub_mv[i][0][1]);
                            do_mc(dec, ref, sx + 4, sy,     4, 4, sub_mv[i][1][0], sub_mv[i][1][1]);
                            do_mc(dec, ref, sx,     sy + 4, 4, 4, sub_mv[i][2][0], sub_mv[i][2][1]);
                            do_mc(dec, ref, sx + 4, sy + 4, 4, 4, sub_mv[i][3][0], sub_mv[i][3][1]);
                            break;
                        default:
                            /* Fallback: treat as a single 8x8 block */
                            do_mc(dec, ref, sx,     sy,     8, 8, sub_mv[i][0][0], sub_mv[i][0][1]);
                            break;
                        }
                    }
                    break;
                }
                }
            } else {
                mb_fill_gray(dec, mb_x, mb_y);
            }

            /* Residuals */
            if (cbp != 0) {
                int residual_status = decode_inter_residuals(dec, bs, mb_x, mb_y, cbp, mb->qp);
                if (residual_status != H264_OK)
                    return residual_status;
            }
        }
    } else {
        /* Unsupported slice type: fill gray */
        for (i = 0; i < 16; i++)
            memset(dec->frame_y + (y0+i)*stride + x0, 128, 16);
        for (i = 0; i < 8; i++) {
            memset(dec->frame_cb + (y0/2+i)*c_stride + x0/2, 128, 8);
            memset(dec->frame_cr + (y0/2+i)*c_stride + x0/2, 128, 8);
        }
    }

    mb->decoded = 1;
    (void)sps; (void)pps;
    return H264_OK;
}

/* ---- Slice decoding ---- */

int h264_decode_slice(H264Decoder *dec, H264BitStream *bs,
                      H264SliceHeader *sh)
{
    H264SPS *sps = &dec->sps[dec->active_sps_id];
    int mb_width  = dec->mb_width;
    int mb_height = dec->mb_height;
    int mb_x, mb_y;
    int mb_idx = sh->first_mb_in_slice;
    int skip_run = 0;
    int slice_status = H264_OK;

    dec->prev_qp = sh->qp;

    for (mb_y = mb_idx / mb_width; mb_y < mb_height; mb_y++) {
        for (mb_x = (mb_y == mb_idx / mb_width ? mb_idx % mb_width : 0);
             mb_x < mb_width; mb_x++)
        {
            if (bs_bits_left(bs) <= 0) goto done;

            /* Handle P-skip macroblocks.
             * In a P-slice the bitstream reads:
             *   mb_skip_run  (ue) — number of skipped MBs before the next coded MB
             * We read it fresh whenever the previous run has been consumed. */
            if (sh->slice_type == H264_SLICE_P) {
                if (skip_run == 0) {
                    if (bs_bits_left(bs) <= 0) goto done;
                    skip_run = (int)bs_read_ue(bs);
                }
                if (skip_run > 0) {
                    p_skip_mb(dec, mb_x, mb_y);
                    dec->mbs[mb_y * mb_width + mb_x].decoded = 1;
                    skip_run--;
                    continue;
                }
            }

            int ret = h264_decode_macroblock(dec, bs, mb_x, mb_y);
            if (ret != H264_OK) {
                /* On error, continue with next MB, but remember the first failure
                 * so that callers can detect that this slice encountered issues. */
                if (slice_status == H264_OK) {
                    slice_status = ret;
                }
            }
        }
    }
done:
    (void)sps;
    return slice_status;
}
