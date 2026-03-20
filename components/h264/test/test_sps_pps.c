#include <stdio.h>
#include <string.h>
#include <stdint.h>

#include "../src/h264_bitstream.h"
#include "../src/h264_common.h"
#include "test_utils.h"

extern int h264_parse_sps(H264BitStream *bs, H264SPS *sps);
extern int h264_parse_pps(H264BitStream *bs, H264PPS *pps, H264SPS sps_array[32]);

#define CHECK(cond, msg) do { \
    if (!(cond)) { fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); return 1; } \
} while(0)

/* Use TestBitWriter from test_utils.h */
typedef TestBitWriter BitWriter;
#define bw_init(bw)           tbw_init(bw)
#define bw_write_bit(bw,b)    tbw_write_bit(bw,b)
#define bw_write_bits(bw,v,n) tbw_write_bits(bw,v,n)
#define bw_write_ue(bw,v)     tbw_write_ue(bw,v)
#define bw_write_se(bw,v)     tbw_write_se(bw,v)
#define bw_byte_count(bw)     tbw_len(bw)

/* Build a minimal SPS for 640x480 Baseline Profile, level 3.0 */
static int build_sps_640x480(uint8_t *out, int max_size)
{
    BitWriter bw;
    bw_init(&bw);

    /* profile_idc = 66 (Baseline) */
    bw_write_bits(&bw, 66, 8);
    /* constraint flags: set0=1, set1=1, set2=0, set3=0, reserved=0000 */
    bw_write_bits(&bw, 0xC0, 8);
    /* level_idc = 30 */
    bw_write_bits(&bw, 30, 8);
    /* seq_parameter_set_id = 0 */
    bw_write_ue(&bw, 0);
    /* log2_max_frame_num_minus4 = 0 */
    bw_write_ue(&bw, 0);
    /* pic_order_cnt_type = 0 */
    bw_write_ue(&bw, 0);
    /* log2_max_pic_order_cnt_lsb_minus4 = 0 */
    bw_write_ue(&bw, 0);
    /* max_num_ref_frames = 1 */
    bw_write_ue(&bw, 1);
    /* gaps_in_frame_num_value_allowed_flag = 0 */
    bw_write_bit(&bw, 0);
    /* pic_width_in_mbs_minus1 = 39  (40*16=640) */
    bw_write_ue(&bw, 39);
    /* pic_height_in_map_units_minus1 = 29  (30*16=480) */
    bw_write_ue(&bw, 29);
    /* frame_mbs_only_flag = 1 */
    bw_write_bit(&bw, 1);
    /* direct_8x8_inference_flag = 0 */
    bw_write_bit(&bw, 0);
    /* frame_cropping_flag = 0 */
    bw_write_bit(&bw, 0);
    /* vui_parameters_present_flag = 0 */
    bw_write_bit(&bw, 0);

    int n = bw_byte_count(&bw);
    if (n > max_size) return -1;
    memcpy(out, bw.buf, (size_t)n);
    return n;
}

/* Build a minimal PPS */
static int build_pps_baseline(uint8_t *out, int max_size)
{
    BitWriter bw;
    bw_init(&bw);

    bw_write_ue(&bw, 0); /* pic_parameter_set_id = 0 */
    bw_write_ue(&bw, 0); /* seq_parameter_set_id = 0 */
    bw_write_bit(&bw, 0); /* entropy_coding_mode_flag = 0 (CAVLC) */
    bw_write_bit(&bw, 0); /* bottom_field_pic_order_in_frame_present_flag = 0 */
    bw_write_ue(&bw, 0); /* num_slice_groups_minus1 = 0 */
    bw_write_ue(&bw, 0); /* num_ref_idx_l0_default_active_minus1 = 0 */
    bw_write_ue(&bw, 0); /* num_ref_idx_l1_default_active_minus1 = 0 */
    bw_write_bit(&bw, 0); /* weighted_pred_flag = 0 */
    bw_write_bits(&bw, 0, 2); /* weighted_bipred_idc = 0 */
    bw_write_se(&bw, 0);  /* pic_init_qp_minus26 = 0 */
    bw_write_se(&bw, 0);  /* pic_init_qs_minus26 = 0 */
    bw_write_se(&bw, 0);  /* chroma_qp_index_offset = 0 */
    bw_write_bit(&bw, 1); /* deblocking_filter_control_present_flag = 1 */
    bw_write_bit(&bw, 0); /* constrained_intra_pred_flag = 0 */
    bw_write_bit(&bw, 0); /* redundant_pic_cnt_present_flag = 0 */

    int n = bw_byte_count(&bw);
    if (n > max_size) return -1;
    memcpy(out, bw.buf, (size_t)n);
    return n;
}

int test_sps_pps(void) {
    /* ---- Test 1: SPS 640x480 ---- */
    {
        uint8_t sps_rbsp[256];
        int n = build_sps_640x480(sps_rbsp, 256);
        CHECK(n > 0, "SPS build");

        H264BitStream bs;
        bs_init(&bs, sps_rbsp, n);

        H264SPS sps;
        int ret = h264_parse_sps(&bs, &sps);
        CHECK(ret == H264_OK, "SPS parse OK");
        CHECK(sps.is_valid, "SPS valid flag");
        CHECK(sps.profile_idc == 66, "profile_idc == 66");
        CHECK(sps.level_idc  == 30,  "level_idc == 30");
        CHECK(sps.seq_parameter_set_id == 0, "sps_id == 0");
        CHECK(sps.pic_width_in_mbs_minus1  == 39, "pic_width_mbs == 39");
        CHECK(sps.pic_height_in_map_units_minus1 == 29, "pic_height_mbs == 29");
        CHECK(sps.frame_mbs_only_flag == 1, "frame_mbs_only");
        CHECK(sps.max_num_ref_frames == 1, "max_ref_frames == 1");
        CHECK(sps.width  == 640, "derived width == 640");
        CHECK(sps.height == 480, "derived height == 480");
        CHECK(sps.frame_cropping_flag == 0, "no cropping");
        CHECK(sps.vui_parameters_present_flag == 0, "no VUI");
    }

    /* ---- Test 2: PPS ---- */
    {
        uint8_t pps_rbsp[256];
        int n = build_pps_baseline(pps_rbsp, 256);
        CHECK(n > 0, "PPS build");

        H264BitStream bs;
        bs_init(&bs, pps_rbsp, n);

        H264SPS sps_arr[32];
        memset(sps_arr, 0, sizeof(sps_arr));
        /* Mark sps[0] as valid for reference */
        sps_arr[0].is_valid = 1;

        H264PPS pps;
        int ret = h264_parse_pps(&bs, &pps, sps_arr);
        CHECK(ret == H264_OK, "PPS parse OK");
        CHECK(pps.is_valid, "PPS valid flag");
        CHECK(pps.pic_parameter_set_id == 0, "pps_id == 0");
        CHECK(pps.seq_parameter_set_id == 0, "sps_ref == 0");
        CHECK(pps.entropy_coding_mode_flag == 0, "CAVLC mode");
        CHECK(pps.num_slice_groups_minus1 == 0, "single slice group");
        CHECK(pps.deblocking_filter_control_present_flag == 1, "deblock present");
    }

    /* ---- Test 3: SPS 16x16 (1 MB) ---- */
    {
        BitWriter bw;
        bw_init(&bw);
        bw_write_bits(&bw, 66, 8);  /* profile */
        bw_write_bits(&bw, 0xE0, 8); /* constraints: set0=1,set1=1,set2=1,set3=0 */
        bw_write_bits(&bw, 30, 8);  /* level */
        bw_write_ue(&bw, 0);  /* sps_id */
        bw_write_ue(&bw, 0);  /* log2_max_frame_num_minus4 */
        bw_write_ue(&bw, 0);  /* poc_type */
        bw_write_ue(&bw, 4);  /* log2_max_poc_lsb_minus4 = 4 */
        bw_write_ue(&bw, 1);  /* max_ref_frames */
        bw_write_bit(&bw, 0); /* gaps */
        bw_write_ue(&bw, 0);  /* pic_width_mbs_minus1 = 0 (1 MB = 16px) */
        bw_write_ue(&bw, 0);  /* pic_height_mbs_minus1 = 0 */
        bw_write_bit(&bw, 1); /* frame_mbs_only */
        bw_write_bit(&bw, 1); /* direct_8x8_inference */
        bw_write_bit(&bw, 0); /* no crop */
        bw_write_bit(&bw, 0); /* no vui */

        int n = bw_byte_count(&bw);
        H264BitStream bs;
        bs_init(&bs, bw.buf, n);
        H264SPS sps;
        int ret = h264_parse_sps(&bs, &sps);
        CHECK(ret == H264_OK, "SPS 16x16 parse");
        CHECK(sps.width  == 16, "16x16 width");
        CHECK(sps.height == 16, "16x16 height");
    }

    return 0;
}
