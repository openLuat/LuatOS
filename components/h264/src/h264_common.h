#ifndef H264_COMMON_H
#define H264_COMMON_H

#include <stdint.h>
#include <stddef.h>
#include "h264_bitstream.h"

/* ---- NAL unit types ---- */
#define H264_NAL_SLICE      1
#define H264_NAL_IDR_SLICE  5
#define H264_NAL_SEI        6
#define H264_NAL_SPS        7
#define H264_NAL_PPS        8
#define H264_NAL_AUD        9

/* ---- Slice types ---- */
#define H264_SLICE_P   0
#define H264_SLICE_B   1
#define H264_SLICE_I   2
#define H264_SLICE_SP  3
#define H264_SLICE_SI  4

/* ---- MB types (I-slice) ---- */
#define H264_MB_I_4x4    0
/* I_16x16 variants encoded as 1..24 */
#define H264_MB_I_PCM    25

/* ---- Error codes ---- */
#define H264_OK               0
#define H264_ERR_NOMEM       -1
#define H264_ERR_BITSTREAM   -2
#define H264_ERR_UNSUPPORTED -3
#define H264_ERR_PARAM       -4

/* ---- Maximum sizes ---- */
#define H264_MAX_SPS      32
#define H264_MAX_PPS     256
#define H264_MAX_REF      16

/* ---- Structures ---- */

typedef struct {
    int profile_idc;
    int constraint_set0_flag;
    int constraint_set1_flag;
    int constraint_set2_flag;
    int constraint_set3_flag;
    int level_idc;

    int seq_parameter_set_id;
    int chroma_format_idc;
    int separate_colour_plane_flag;
    int bit_depth_luma_minus8;
    int bit_depth_chroma_minus8;
    int qpprime_y_zero_transform_bypass_flag;
    int seq_scaling_matrix_present_flag;
    int seq_scaling_list_present_flag[8];
    int ScalingList4x4[6][16];
    int ScalingList8x8[2][64];

    int log2_max_frame_num_minus4;
    int pic_order_cnt_type;
    int log2_max_pic_order_cnt_lsb_minus4;
    int delta_pic_order_always_zero_flag;
    int offset_for_non_ref_pic;
    int offset_for_top_to_bottom_field;
    int num_ref_frames_in_pic_order_cnt_cycle;
    int offset_for_ref_frame[256];

    int max_num_ref_frames;
    int gaps_in_frame_num_value_allowed_flag;
    int pic_width_in_mbs_minus1;
    int pic_height_in_map_units_minus1;
    int frame_mbs_only_flag;
    int mb_adaptive_frame_field_flag;
    int direct_8x8_inference_flag;

    int frame_cropping_flag;
    int frame_crop_left_offset;
    int frame_crop_right_offset;
    int frame_crop_top_offset;
    int frame_crop_bottom_offset;

    int vui_parameters_present_flag;

    /* Derived */
    int width;
    int height;
    int is_valid;
} H264SPS;

typedef struct {
    int pic_parameter_set_id;
    int seq_parameter_set_id;
    int entropy_coding_mode_flag;
    int bottom_field_pic_order_in_frame_present_flag;
    int num_slice_groups_minus1;
    int slice_group_map_type;
    int num_ref_idx_l0_default_active_minus1;
    int num_ref_idx_l1_default_active_minus1;
    int weighted_pred_flag;
    int weighted_bipred_idc;
    int pic_init_qp_minus26;
    int pic_init_qs_minus26;
    int chroma_qp_index_offset;
    int deblocking_filter_control_present_flag;
    int constrained_intra_pred_flag;
    int redundant_pic_cnt_present_flag;
    int transform_8x8_mode_flag;
    int pic_scaling_matrix_present_flag;
    int second_chroma_qp_index_offset;
    int is_valid;
} H264PPS;

typedef struct {
    int first_mb_in_slice;
    int slice_type;
    int slice_type_raw;
    int pic_parameter_set_id;
    int frame_num;
    int idr_pic_id;
    int pic_order_cnt_lsb;
    int delta_pic_order_cnt_bottom;
    int delta_pic_order_cnt[2];
    int redundant_pic_cnt;
    int direct_spatial_mv_pred_flag;
    int num_ref_idx_active_override_flag;
    int num_ref_idx_l0_active_minus1;
    int num_ref_idx_l1_active_minus1;
    int ref_pic_list_modification_flag_l0;
    int ref_pic_list_modification_flag_l1;
    int no_output_of_prior_pics_flag;
    int long_term_reference_flag;
    int adaptive_ref_pic_marking_mode_flag;
    int cabac_init_idc;
    int slice_qp_delta;
    int sp_for_switch_flag;
    int slice_qs_delta;
    int disable_deblocking_filter_idc;
    int slice_alpha_c0_offset_div2;
    int slice_beta_offset_div2;
    int slice_group_change_cycle;
    int is_idr;
    int qp;
    int nal_ref_idc;
} H264SliceHeader;

typedef struct {
    int mb_type;
    int mb_type_raw;

    /* Intra prediction */
    int intra4x4_pred_mode[16];
    int intra16x16_pred_mode;
    int intra_chroma_pred_mode;

    /* Coded block pattern */
    int cbp_luma;
    int cbp_chroma;
    int cbp;

    /* Quantization */
    int qp;
    int qp_delta;

    /* Transform coefficients [block_index][coeff_index] */
    int16_t luma_dc[16];
    int16_t luma_ac[16][16];
    int16_t chroma_dc[2][4];
    int16_t chroma_ac[2][4][16];

    /* PCM samples */
    uint8_t pcm_luma[256];
    uint8_t pcm_cb[64];
    uint8_t pcm_cr[64];

    /* Motion vectors (for P/B slices) [partition][list] */
    int16_t mv_l0[4][2];
    int16_t mv_l1[4][2];
    int ref_idx_l0[4];
    int ref_idx_l1[4];

    /* State flags */
    int is_intra;
    int is_skipped;
    int is_pcm;
    int decoded;

    /* Non-zero coefficient counts per 4x4 block (Z-scan order) for nC */
    int nz_count[16];     /* 16 luma 4x4 blocks */
    int nz_count_cb[4];   /* 4 Cb 4x4 blocks */
    int nz_count_cr[4];   /* 4 Cr 4x4 blocks */
} H264MacroBlock;

typedef struct {
    uint8_t *y;
    uint8_t *cb;
    uint8_t *cr;
    int width;
    int height;
    int stride;
    int c_stride;
    int is_valid;
    int frame_num;
} H264RefPic;

struct H264Decoder {
    H264SPS  sps[H264_MAX_SPS];
    H264PPS  pps[H264_MAX_PPS];
    int      active_sps_id;
    int      active_pps_id;

    /* Frame buffer (current output) */
    uint8_t *frame_y;
    uint8_t *frame_cb;
    uint8_t *frame_cr;
    int      frame_width;
    int      frame_height;
    int      frame_stride;
    int      frame_c_stride;

    /* Reference frames */
    H264RefPic ref[H264_MAX_REF];
    int        num_ref;

    /* Current slice state */
    H264SliceHeader current_sh;

    /* Macroblock array */
    H264MacroBlock *mbs;
    int             mb_width;
    int             mb_height;
    int             mb_count;

    /* Current MB QP */
    int prev_qp;

    /* Frame counter */
    int frame_num;
};

#endif /* H264_COMMON_H */
