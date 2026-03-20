/*
 * test_stream.h — shared helpers for building a synthetic 16×16 H.264
 * Annex-B stream used across multiple test files.
 */
#ifndef TEST_STREAM_H
#define TEST_STREAM_H

#include <stdint.h>
#include <string.h>
#include "test_utils.h"

/* Provided by h264_bitstream.c */
extern int h264_rbsp_to_nalu(const uint8_t *rbsp_data, int rbsp_size,
                              uint8_t *nalu_data, int nalu_size);

/* Provided by h264_nalu.c */
extern int h264_find_next_nal(const uint8_t *data, int size,
                               int *nal_start, int *nal_size);

/*
 * Write a single NAL unit (start-code + header byte + emulation-prevention
 * protected RBSP) into *out at position *out_pos.
 * Returns 0 on success, -1 on error.
 */
static int ts_write_nalu(uint8_t *out, int out_max, int *out_pos,
                         uint8_t nal_header,
                         const uint8_t *rbsp, int rbsp_len)
{
    uint8_t nalu_body[4096];
    int body_len = h264_rbsp_to_nalu(rbsp, rbsp_len, nalu_body, (int)sizeof(nalu_body));
    if (body_len < 0) return -1;
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
 * Build a minimal valid H.264 Annex-B stream for a 16×16 video with one IDR
 * I-frame using an I_PCM macroblock.  All luma/chroma samples are 128.
 *
 * Returns 0 on success and sets *out_size to the number of bytes written.
 * Returns -1 on buffer overflow.
 */
static int build_16x16_gray_stream(uint8_t *out, int out_max, int *out_size)
{
    TestBitWriter bw;
    int pos = 0;

    /* ---- SPS (NAL 0x67) ---- */
    tbw_init(&bw);
    tbw_write_bits(&bw, 66,   8); /* profile_idc = Baseline */
    tbw_write_bits(&bw, 0xC0, 8); /* constraint flags */
    tbw_write_bits(&bw, 30,   8); /* level_idc */
    tbw_write_ue(&bw, 0);  /* sps_id */
    tbw_write_ue(&bw, 0);  /* log2_max_frame_num_minus4 */
    tbw_write_ue(&bw, 0);  /* pic_order_cnt_type */
    tbw_write_ue(&bw, 4);  /* log2_max_poc_lsb_minus4 */
    tbw_write_ue(&bw, 1);  /* max_num_ref_frames */
    tbw_write_bit(&bw, 0); /* gaps_in_frame_num */
    tbw_write_ue(&bw, 0);  /* pic_width_in_mbs_minus1  = 0 → 16 px */
    tbw_write_ue(&bw, 0);  /* pic_height_in_map_units_minus1 = 0 → 16 px */
    tbw_write_bit(&bw, 1); /* frame_mbs_only_flag */
    tbw_write_bit(&bw, 1); /* direct_8x8_inference_flag */
    tbw_write_bit(&bw, 0); /* frame_cropping_flag */
    tbw_write_bit(&bw, 0); /* vui_parameters_present_flag */
    if (ts_write_nalu(out, out_max, &pos, 0x67, bw.buf, tbw_len(&bw)) != 0) return -1;

    /* ---- PPS (NAL 0x68) ---- */
    tbw_init(&bw);
    tbw_write_ue(&bw, 0);     /* pps_id */
    tbw_write_ue(&bw, 0);     /* sps_id */
    tbw_write_bit(&bw, 0);    /* entropy_coding_mode = CAVLC */
    tbw_write_bit(&bw, 0);    /* bottom_field_pic_order */
    tbw_write_ue(&bw, 0);     /* num_slice_groups_minus1 */
    tbw_write_ue(&bw, 0);     /* num_ref_idx_l0_default */
    tbw_write_ue(&bw, 0);     /* num_ref_idx_l1_default */
    tbw_write_bit(&bw, 0);    /* weighted_pred_flag */
    tbw_write_bits(&bw, 0, 2);/* weighted_bipred_idc */
    tbw_write_se(&bw, 0);     /* pic_init_qp_minus26 */
    tbw_write_se(&bw, 0);     /* pic_init_qs_minus26 */
    tbw_write_se(&bw, 0);     /* chroma_qp_index_offset */
    tbw_write_bit(&bw, 1);    /* deblocking_filter_control_present */
    tbw_write_bit(&bw, 0);    /* constrained_intra_pred */
    tbw_write_bit(&bw, 0);    /* redundant_pic_cnt_present */
    if (ts_write_nalu(out, out_max, &pos, 0x68, bw.buf, tbw_len(&bw)) != 0) return -1;

    /* ---- IDR slice — I_PCM macroblock (NAL 0x65) ---- */
    tbw_init(&bw);
    tbw_write_ue(&bw, 0);     /* first_mb_in_slice */
    tbw_write_ue(&bw, 7);     /* slice_type = I (all-I) */
    tbw_write_ue(&bw, 0);     /* pps_id */
    tbw_write_bits(&bw, 0, 4);/* frame_num (4 bits: log2_max_frame_num=4) */
    tbw_write_ue(&bw, 0);     /* idr_pic_id */
    tbw_write_bits(&bw, 0, 8);/* pic_order_cnt_lsb (8 bits) */
    tbw_write_bit(&bw, 0);    /* no_output_of_prior_pics_flag */
    tbw_write_bit(&bw, 0);    /* long_term_reference_flag */
    tbw_write_se(&bw, 0);     /* slice_qp_delta */
    tbw_write_ue(&bw, 0);     /* disable_deblocking_filter_idc */
    tbw_write_se(&bw, 0);     /* slice_alpha_c0_offset_div2 */
    tbw_write_se(&bw, 0);     /* slice_beta_offset_div2 */
    tbw_write_ue(&bw, 25);    /* mb_type = I_PCM */
    tbw_align(&bw);
    {
        int i;
        for (i = 0; i < 256; i++) tbw_write_bits(&bw, 128, 8); /* Y */
        for (i = 0; i < 64;  i++) tbw_write_bits(&bw, 128, 8); /* Cb */
        for (i = 0; i < 64;  i++) tbw_write_bits(&bw, 128, 8); /* Cr */
    }
    if (ts_write_nalu(out, out_max, &pos, 0x65, bw.buf, tbw_len(&bw)) != 0) return -1;

    *out_size = pos;
    return 0;
}

#endif /* TEST_STREAM_H */
