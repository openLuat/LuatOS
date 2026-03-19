#include <stdio.h>
#include <string.h>
#include <stdint.h>

#include "../include/h264_decoder.h"
#include "../src/h264_common.h"

#define CHECK(cond, msg) do { \
    if (!(cond)) { fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); return 1; } \
} while(0)

/* ---- Bit writer ---- */
typedef struct {
    uint8_t buf[4096];
    int     bit_pos;
    int     byte_count;
} BW;

static void bw_init2(BW *bw) {
    memset(bw->buf, 0, sizeof(bw->buf));
    bw->bit_pos   = 0;
    bw->byte_count = 0;
}

static void bw_write_bit2(BW *bw, int b) {
    if ((bw->bit_pos >> 3) >= (int)sizeof(bw->buf)) return;
    if (b) bw->buf[bw->bit_pos >> 3] |= (0x80 >> (bw->bit_pos & 7));
    bw->bit_pos++;
}

static void bw_write_bits2(BW *bw, uint32_t v, int n) {
    int i;
    for (i = n-1; i >= 0; i--)
        bw_write_bit2(bw, (v >> i) & 1);
}

static void bw_write_ue2(BW *bw, uint32_t v) {
    if (v == 0) { bw_write_bit2(bw, 1); return; }
    int n = 0;
    uint32_t t = v + 1;
    while (t > 1) { n++; t >>= 1; }
    int i;
    for (i = 0; i < n; i++) bw_write_bit2(bw, 0);
    bw_write_bits2(bw, v + 1, n + 1);
}

static void bw_write_se2(BW *bw, int v) {
    uint32_t k = (v <= 0) ? (uint32_t)(-2*v) : (uint32_t)(2*v - 1);
    bw_write_ue2(bw, k);
}

static void bw_align(BW *bw) {
    while (bw->bit_pos & 7) bw_write_bit2(bw, 0);
}

static int bw_len(const BW *bw) { return (bw->bit_pos + 7) >> 3; }

/* ---- Emulation prevention ---- */
extern int h264_rbsp_to_nalu(const uint8_t *rbsp_data, int rbsp_size,
                              uint8_t *nalu_data, int nalu_size);

/* Write start code + NAL header + NALU data into output buffer */
static int write_nalu(uint8_t *out, int out_max, int *out_pos,
                      uint8_t nal_header, const uint8_t *rbsp, int rbsp_len)
{
    uint8_t nalu_body[4096];
    int body_len = h264_rbsp_to_nalu(rbsp, rbsp_len, nalu_body, sizeof(nalu_body));
    if (body_len < 0) return -1;

    /* Start code 00 00 00 01 */
    if (*out_pos + 5 + body_len > out_max) return -1;
    out[(*out_pos)++] = 0x00;
    out[(*out_pos)++] = 0x00;
    out[(*out_pos)++] = 0x00;
    out[(*out_pos)++] = 0x01;
    out[(*out_pos)++] = nal_header;
    memcpy(out + *out_pos, nalu_body, (size_t)body_len);
    *out_pos += body_len;
    return 0;
}

/*
 * Build a minimal valid H.264 Annex-B stream for a 16x16 video with one IDR
 * I-frame using I_PCM macroblock.  Pixel values are Y=128, Cb=128, Cr=128.
 */
static int build_16x16_gray_stream(uint8_t *out, int out_max, int *out_size)
{
    BW bw;
    int pos = 0;

    /* ---- SPS ---- */
    bw_init2(&bw);
    bw_write_bits2(&bw, 66, 8);   /* profile_idc = Baseline */
    bw_write_bits2(&bw, 0xC0, 8); /* constraint flags */
    bw_write_bits2(&bw, 30, 8);   /* level_idc */
    bw_write_ue2(&bw, 0);  /* sps_id */
    bw_write_ue2(&bw, 0);  /* log2_max_frame_num_minus4 */
    bw_write_ue2(&bw, 0);  /* pic_order_cnt_type */
    bw_write_ue2(&bw, 4);  /* log2_max_poc_lsb_minus4 */
    bw_write_ue2(&bw, 1);  /* max_num_ref_frames */
    bw_write_bit2(&bw, 0); /* gaps_in_frame_num */
    bw_write_ue2(&bw, 0);  /* pic_width_in_mbs_minus1 = 0 -> 16px */
    bw_write_ue2(&bw, 0);  /* pic_height_in_map_units_minus1 = 0 -> 16px */
    bw_write_bit2(&bw, 1); /* frame_mbs_only_flag */
    bw_write_bit2(&bw, 1); /* direct_8x8_inference_flag */
    bw_write_bit2(&bw, 0); /* frame_cropping_flag */
    bw_write_bit2(&bw, 0); /* vui_parameters_present_flag */

    if (write_nalu(out, out_max, &pos, 0x67, bw.buf, bw_len(&bw)) != 0) return -1;

    /* ---- PPS ---- */
    bw_init2(&bw);
    bw_write_ue2(&bw, 0);  /* pps_id */
    bw_write_ue2(&bw, 0);  /* sps_id */
    bw_write_bit2(&bw, 0); /* entropy_coding_mode = CAVLC */
    bw_write_bit2(&bw, 0); /* bottom_field_pic_order */
    bw_write_ue2(&bw, 0);  /* num_slice_groups_minus1 */
    bw_write_ue2(&bw, 0);  /* num_ref_idx_l0_default */
    bw_write_ue2(&bw, 0);  /* num_ref_idx_l1_default */
    bw_write_bit2(&bw, 0); /* weighted_pred_flag */
    bw_write_bits2(&bw, 0, 2); /* weighted_bipred_idc */
    bw_write_se2(&bw, 0);  /* pic_init_qp_minus26 */
    bw_write_se2(&bw, 0);  /* pic_init_qs_minus26 */
    bw_write_se2(&bw, 0);  /* chroma_qp_index_offset */
    bw_write_bit2(&bw, 1); /* deblocking_filter_control_present */
    bw_write_bit2(&bw, 0); /* constrained_intra_pred */
    bw_write_bit2(&bw, 0); /* redundant_pic_cnt_present */

    if (write_nalu(out, out_max, &pos, 0x68, bw.buf, bw_len(&bw)) != 0) return -1;

    /* ---- IDR Slice with I_PCM macroblock ---- */
    bw_init2(&bw);
    /* Slice header */
    bw_write_ue2(&bw, 0);  /* first_mb_in_slice */
    bw_write_ue2(&bw, 7);  /* slice_type = I (7 = I only) */
    bw_write_ue2(&bw, 0);  /* pps_id */
    /* frame_num (log2_max_frame_num_minus4+4 = 4 bits) */
    bw_write_bits2(&bw, 0, 4);
    /* idr_pic_id */
    bw_write_ue2(&bw, 0);
    /* pic_order_cnt_lsb (log2_max_poc_lsb_minus4+4 = 8 bits) */
    bw_write_bits2(&bw, 0, 8);
    /* IDR dec_ref_pic_marking: no_output_of_prior_pics_flag, long_term_reference_flag */
    bw_write_bit2(&bw, 0);
    bw_write_bit2(&bw, 0);
    /* slice_qp_delta = 0 -> qp = 26 */
    bw_write_se2(&bw, 0);
    /* disable_deblocking_filter_idc = 0 */
    bw_write_ue2(&bw, 0);
    /* slice_alpha_c0_offset_div2 = 0 */
    bw_write_se2(&bw, 0);
    /* slice_beta_offset_div2 = 0 */
    bw_write_se2(&bw, 0);

    /* Macroblock type = I_PCM: ue(25) */
    bw_write_ue2(&bw, 25);

    /* Byte-align */
    bw_align(&bw);

    /* Write 256 luma samples (Y=128) */
    int i;
    for (i = 0; i < 256; i++) bw_write_bits2(&bw, 128, 8);
    /* Write 64 Cb samples (128) */
    for (i = 0; i < 64;  i++) bw_write_bits2(&bw, 128, 8);
    /* Write 64 Cr samples (128) */
    for (i = 0; i < 64;  i++) bw_write_bits2(&bw, 128, 8);

    /* NAL header 0x65 = IDR slice, nal_ref_idc=3 */
    if (write_nalu(out, out_max, &pos, 0x65, bw.buf, bw_len(&bw)) != 0) return -1;

    *out_size = pos;
    return 0;
}

int test_integration(void) {
    /* ---- Build the stream ---- */
    static uint8_t stream[8192];
    int stream_size = 0;
    int ret = build_16x16_gray_stream(stream, sizeof(stream), &stream_size);
    CHECK(ret == 0, "stream build");
    CHECK(stream_size > 10, "stream has data");

    /* ---- Create decoder ---- */
    H264Decoder *dec = h264_decoder_create();
    CHECK(dec != NULL, "decoder create");

    /* ---- Decode stream ---- */
    H264Frame frame;
    memset(&frame, 0, sizeof(frame));

    ret = h264_decode_stream(dec, stream, stream_size, &frame);

    if (ret != H264_OK && ret != H264_ERR_BITSTREAM) {
        fprintf(stderr, "decode_stream returned %d\n", ret);
        h264_decoder_destroy(dec);
        return 1;
    }

    CHECK(frame.is_valid, "frame is valid");
    CHECK(frame.width  == 16, "frame width == 16");
    CHECK(frame.height == 16, "frame height == 16");
    CHECK(frame.y  != NULL, "luma plane not null");
    CHECK(frame.cb != NULL, "Cb plane not null");
    CHECK(frame.cr != NULL, "Cr plane not null");

    /* Verify I_PCM content (Y=128, Cb=128, Cr=128) */
    int all_y_ok = 1, all_c_ok = 1;
    int i;
    for (i = 0; i < 16; i++) {
        int j;
        for (j = 0; j < 16; j++) {
            if (frame.y[i * frame.y_stride + j] != 128) { all_y_ok = 0; }
        }
    }
    for (i = 0; i < 8; i++) {
        int j;
        for (j = 0; j < 8; j++) {
            if (frame.cb[i * frame.c_stride + j] != 128) { all_c_ok = 0; }
            if (frame.cr[i * frame.c_stride + j] != 128) { all_c_ok = 0; }
        }
    }
    CHECK(all_y_ok, "I_PCM luma = 128");
    CHECK(all_c_ok, "I_PCM chroma = 128");

    h264_decoder_destroy(dec);
    return 0;
}
