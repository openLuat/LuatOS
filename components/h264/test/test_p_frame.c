#include <stdio.h>
#include <string.h>
#include <stdint.h>

#include "../include/h264_decoder.h"
#include "../src/h264_common.h"
#include "test_utils.h"
#include "test_stream.h"

#define CHECK(cond, msg) do { \
    if (!(cond)) { fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); return 1; } \
} while(0)

/*
 * Append a P-slice NAL (non-IDR, nal_ref_idc=1) to *buf after an IDR frame.
 * The P-slice has one P_L0_16x16 macroblock with zero MVD and zero CBP,
 * i.e. it simply copies the reference frame unchanged.
 *
 * SPS parameters assumed:
 *   log2_max_frame_num_minus4 = 0  → frame_num field is 4 bits
 *   pic_order_cnt_type = 0
 *   log2_max_pic_order_cnt_lsb_minus4 = 4  → poc_lsb field is 8 bits
 * PPS parameters assumed:
 *   entropy_coding_mode = CAVLC
 *   num_ref_idx_l0_default_active_minus1 = 0
 *   deblocking_filter_control_present = 1
 *   weighted_pred_flag = 0
 */
static void tbw_write_rbsp_trailing_bits(TestBitWriter *bw)
{
    /* rbsp_trailing_bits: rbsp_stop_one_bit (1) followed by alignment zero bits.
     * The TestBitWriter buffer is assumed to be zero-initialized, so writing the
     * stop bit is sufficient; remaining bits in the last byte are already zero. */
    tbw_write_bit(bw, 1);
}

static int append_p_frame(uint8_t *buf, int buf_max, int *pos)
{
    TestBitWriter bw;
    tbw_init(&bw);

    /* Slice header */
    tbw_write_ue(&bw, 0);      /* first_mb_in_slice = 0 */
    tbw_write_ue(&bw, 5);      /* slice_type = 5 (all-P), maps to H264_SLICE_P via %5 */
    tbw_write_ue(&bw, 0);      /* pps_id = 0 */
    tbw_write_bits(&bw, 1, 4); /* frame_num = 1  (4 bits) */
    tbw_write_bits(&bw, 2, 8); /* pic_order_cnt_lsb = 2  (8 bits) */
    /* not IDR, no idr_pic_id */
    /* poc_type=0, bottom_field_pic_order_in_frame_present=0 → no delta */
    /* redundant_pic_cnt_present=0 → no redundant_pic_cnt */
    /* slice_type != B → no direct_spatial_mv_pred_flag */
    tbw_write_bit(&bw, 0);     /* num_ref_idx_active_override_flag = 0 */
    /* ref_pic_list_modification (slice_type != I/SI) */
    tbw_write_bit(&bw, 0);     /* ref_pic_list_modification_flag_l0 = 0 */
    /* pred_weight_table: skipped (weighted_pred_flag=0) */
    /* dec_ref_pic_marking (non-IDR, nal_ref_idc != 0) */
    tbw_write_bit(&bw, 0);     /* adaptive_ref_pic_marking_mode_flag = 0 */
    tbw_write_se(&bw, 0);      /* slice_qp_delta = 0 */
    /* deblocking_filter_control_present = 1 */
    tbw_write_ue(&bw, 1);      /* disable_deblocking_filter_idc = 1 (off) */
    /* idc==1 → no alpha/beta offset fields */

    /* Macroblock data: one 16x16 macroblock */
    tbw_write_ue(&bw, 0);      /* mb_skip_run = 0 (no skipped MBs before this one) */
    tbw_write_ue(&bw, 0);      /* mb_type = 0 → P_L0_16x16 */
    /* ref_idx_l0: read_ref_idx(bs, 0) → max_val=0, no bits in bitstream */
    tbw_write_se(&bw, 0);      /* mvd_l0[0][0] = 0 */
    tbw_write_se(&bw, 0);      /* mvd_l0[0][1] = 0 */
    tbw_write_ue(&bw, 0);      /* cbp_idx = 0 → cbp = 0, no residuals */
    /* cbp==0 → no mb_qp_delta, no residual syntax */

    /* Terminate RBSP with rbsp_trailing_bits to make the slice spec-compliant. */
    tbw_write_rbsp_trailing_bits(&bw);

    /* NAL header 0x21: forbidden=0, nal_ref_idc=1, nal_unit_type=1 (non-IDR slice) */
    return ts_write_nalu(buf, buf_max, pos, 0x21, bw.buf, tbw_len(&bw));
}

int test_p_frame(void)
{
    /* ---- Build the stream: IDR I-frame + P-frame ---- */
    static uint8_t stream[16384];
    int stream_size = 0;
    int ret;

    /* IDR frame with I_PCM mb, Y=200 so we can verify the P-frame copied it */
    {
        TestBitWriter bw;
        int pos = 0;

        /* SPS */
        tbw_init(&bw);
        tbw_write_bits(&bw, 66,   8);
        tbw_write_bits(&bw, 0xC0, 8);
        tbw_write_bits(&bw, 30,   8);
        tbw_write_ue(&bw, 0);
        tbw_write_ue(&bw, 0);
        tbw_write_ue(&bw, 0);
        tbw_write_ue(&bw, 4);
        tbw_write_ue(&bw, 1);
        tbw_write_bit(&bw, 0);
        tbw_write_ue(&bw, 0);
        tbw_write_ue(&bw, 0);
        tbw_write_bit(&bw, 1);
        tbw_write_bit(&bw, 1);
        tbw_write_bit(&bw, 0);
        tbw_write_bit(&bw, 0);
        CHECK(ts_write_nalu(stream, (int)sizeof(stream), &pos, 0x67,
                            bw.buf, tbw_len(&bw)) == 0, "SPS write");

        /* PPS */
        tbw_init(&bw);
        tbw_write_ue(&bw, 0);
        tbw_write_ue(&bw, 0);
        tbw_write_bit(&bw, 0);
        tbw_write_bit(&bw, 0);
        tbw_write_ue(&bw, 0);
        tbw_write_ue(&bw, 0);
        tbw_write_ue(&bw, 0);
        tbw_write_bit(&bw, 0);
        tbw_write_bits(&bw, 0, 2);
        tbw_write_se(&bw, 0);
        tbw_write_se(&bw, 0);
        tbw_write_se(&bw, 0);
        tbw_write_bit(&bw, 1);
        tbw_write_bit(&bw, 0);
        tbw_write_bit(&bw, 0);
        CHECK(ts_write_nalu(stream, (int)sizeof(stream), &pos, 0x68,
                            bw.buf, tbw_len(&bw)) == 0, "PPS write");

        /* IDR slice with I_PCM, Y=200, Cb=Cr=128 */
        tbw_init(&bw);
        tbw_write_ue(&bw, 0);
        tbw_write_ue(&bw, 7);
        tbw_write_ue(&bw, 0);
        tbw_write_bits(&bw, 0, 4);
        tbw_write_ue(&bw, 0);
        tbw_write_bits(&bw, 0, 8);
        tbw_write_bit(&bw, 0);
        tbw_write_bit(&bw, 0);
        tbw_write_se(&bw, 0);
        tbw_write_ue(&bw, 1); /* disable_deblocking_filter_idc=1 */
        tbw_write_ue(&bw, 25); /* mb_type = I_PCM */
        tbw_align(&bw);
        {
            int i;
            for (i = 0; i < 256; i++) tbw_write_bits(&bw, 200, 8); /* Y=200 */
            for (i = 0; i < 64;  i++) tbw_write_bits(&bw, 100, 8); /* Cb=100 */
            for (i = 0; i < 64;  i++) tbw_write_bits(&bw, 150, 8); /* Cr=150 */
        }
        CHECK(ts_write_nalu(stream, (int)sizeof(stream), &pos, 0x65,
                            bw.buf, tbw_len(&bw)) == 0, "IDR slice write");

        stream_size = pos;
    }

    /* ---- Decode the IDR frame ---- */
    H264Decoder *dec = h264_decoder_create();
    CHECK(dec != NULL, "decoder create");

    H264Frame idr_frame;
    memset(&idr_frame, 0, sizeof(idr_frame));
    ret = h264_decode_stream(dec, stream, stream_size, &idr_frame);
    CHECK(ret == H264_OK || ret == H264_ERR_BITSTREAM, "IDR decode ok");
    CHECK(idr_frame.is_valid, "IDR frame valid");
    CHECK(idr_frame.y[0] == 200, "IDR Y=200");
    CHECK(idr_frame.cb[0] == 100, "IDR Cb=100");
    CHECK(idr_frame.cr[0] == 150, "IDR Cr=150");

    /* ---- Append P-frame NAL and decode ---- */
    ret = append_p_frame(stream, (int)sizeof(stream), &stream_size);
    CHECK(ret == 0, "P-frame NAL build");

    /* Decode the P NAL directly via h264_decode_stream over the whole buffer;
     * it will re-process SPS/PPS (no-op) then decode the P slice. */
    H264Frame p_frame;
    memset(&p_frame, 0, sizeof(p_frame));
    ret = h264_decode_stream(dec, stream, stream_size, &p_frame);
    CHECK(ret == H264_OK || ret == H264_ERR_BITSTREAM, "P decode ok");
    CHECK(p_frame.is_valid, "P frame valid");
    CHECK(p_frame.width  == 16, "P frame width == 16");
    CHECK(p_frame.height == 16, "P frame height == 16");

    /* The P-frame has zero MV and zero residuals — it should copy the reference.
     * Reference was saved from the IDR frame (Y=200, Cb=100, Cr=150). */
    CHECK(p_frame.y[0]  == 200, "P frame Y copied from ref");
    CHECK(p_frame.cb[0] == 100, "P frame Cb copied from ref");
    CHECK(p_frame.cr[0] == 150, "P frame Cr copied from ref");

    h264_decoder_destroy(dec);
    return 0;
}
