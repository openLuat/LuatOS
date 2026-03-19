#include <string.h>
#include <stdlib.h>
#include "h264_common.h"

/* ---- VUI parameter parsing ------------------------------------------ */

static int h264_parse_hrd(H264BitStream *bs)
{
    int cpb_cnt = (int)bs_read_ue(bs) + 1;
    bs_skip_bits(bs, 4); /* bit_rate_scale */
    bs_skip_bits(bs, 4); /* cpb_size_scale */
    int i;
    for (i = 0; i < cpb_cnt; i++) {
        bs_read_ue(bs); /* bit_rate_value_minus1 */
        bs_read_ue(bs); /* cpb_size_value_minus1 */
        bs_skip_bits(bs, 1); /* cbr_flag */
    }
    bs_skip_bits(bs, 5); /* initial_cpb_removal_delay_length_minus1 */
    bs_skip_bits(bs, 5); /* cpb_removal_delay_length_minus1 */
    bs_skip_bits(bs, 5); /* dpb_output_delay_length_minus1 */
    bs_skip_bits(bs, 5); /* time_offset_length */
    return H264_OK;
}

static int h264_parse_vui(H264BitStream *bs, H264SPS *sps)
{
    (void)sps;

    int aspect_ratio_info_present = (int)bs_read_u1(bs);
    if (aspect_ratio_info_present) {
        int idc = (int)bs_read_bits(bs, 8);
        if (idc == 255) { /* EXTENDED_SAR */
            bs_skip_bits(bs, 16); /* sar_width */
            bs_skip_bits(bs, 16); /* sar_height */
        }
    }
    if (bs_read_u1(bs)) bs_skip_bits(bs, 1); /* overscan_appropriate_flag */

    int video_signal_type_present = (int)bs_read_u1(bs);
    if (video_signal_type_present) {
        bs_skip_bits(bs, 3); /* video_format */
        bs_skip_bits(bs, 1); /* video_full_range_flag */
        if (bs_read_u1(bs)) { /* colour_description_present_flag */
            bs_skip_bits(bs, 8); /* colour_primaries */
            bs_skip_bits(bs, 8); /* transfer_characteristics */
            bs_skip_bits(bs, 8); /* matrix_coefficients */
        }
    }
    int chroma_loc_info_present = (int)bs_read_u1(bs);
    if (chroma_loc_info_present) {
        bs_read_ue(bs); /* chroma_sample_loc_type_top_field */
        bs_read_ue(bs); /* chroma_sample_loc_type_bottom_field */
    }
    int timing_info_present = (int)bs_read_u1(bs);
    if (timing_info_present) {
        bs_skip_bits(bs, 32); /* num_units_in_tick */
        bs_skip_bits(bs, 32); /* time_scale */
        bs_skip_bits(bs, 1);  /* fixed_frame_rate_flag */
    }
    int nal_hrd = (int)bs_read_u1(bs);
    if (nal_hrd) h264_parse_hrd(bs);
    int vcl_hrd = (int)bs_read_u1(bs);
    if (vcl_hrd) h264_parse_hrd(bs);
    if (nal_hrd || vcl_hrd) bs_skip_bits(bs, 1); /* low_delay_hrd_flag */
    bs_skip_bits(bs, 1); /* pic_struct_present_flag */
    int bitstream_restriction = (int)bs_read_u1(bs);
    if (bitstream_restriction) {
        bs_skip_bits(bs, 1); /* motion_vectors_over_pic_boundaries_flag */
        bs_read_ue(bs); /* max_bytes_per_pic_denom */
        bs_read_ue(bs); /* max_bits_per_mb_denom */
        bs_read_ue(bs); /* log2_max_mv_length_horizontal */
        bs_read_ue(bs); /* log2_max_mv_length_vertical */
        bs_read_ue(bs); /* num_reorder_frames */
        bs_read_ue(bs); /* max_dec_frame_buffering */
    }
    return H264_OK;
}

/* ---- Scaling list parsing ------------------------------------------- */

static void h264_parse_scaling_list(H264BitStream *bs, int *scaling_list, int size)
{
    int last_scale = 8;
    int next_scale = 8;
    int i;
    for (i = 0; i < size; i++) {
        if (next_scale != 0) {
            int delta = (int)bs_read_se(bs);
            next_scale = (last_scale + delta + 256) % 256;
        }
        scaling_list[i] = (next_scale == 0) ? last_scale : next_scale;
        last_scale = scaling_list[i];
    }
}

/* ---- SPS parsing ----------------------------------------------------- */

int h264_parse_sps(H264BitStream *bs, H264SPS *sps)
{
    memset(sps, 0, sizeof(*sps));

    sps->profile_idc = (int)bs_read_bits(bs, 8);
    sps->constraint_set0_flag = (int)bs_read_u1(bs);
    sps->constraint_set1_flag = (int)bs_read_u1(bs);
    sps->constraint_set2_flag = (int)bs_read_u1(bs);
    sps->constraint_set3_flag = (int)bs_read_u1(bs);
    bs_skip_bits(bs, 4); /* reserved_zero_4bits */
    sps->level_idc = (int)bs_read_bits(bs, 8);
    sps->seq_parameter_set_id = (int)bs_read_ue(bs);
    if (sps->seq_parameter_set_id >= H264_MAX_SPS) return H264_ERR_PARAM;

    /* High-profile specific fields */
    if (sps->profile_idc == 100 || sps->profile_idc == 110 ||
        sps->profile_idc == 122 || sps->profile_idc == 244 ||
        sps->profile_idc == 44  || sps->profile_idc == 83  ||
        sps->profile_idc == 86  || sps->profile_idc == 118 ||
        sps->profile_idc == 128)
    {
        sps->chroma_format_idc = (int)bs_read_ue(bs);
        if (sps->chroma_format_idc == 3) {
            sps->separate_colour_plane_flag = (int)bs_read_u1(bs);
        }
        sps->bit_depth_luma_minus8   = (int)bs_read_ue(bs);
        sps->bit_depth_chroma_minus8 = (int)bs_read_ue(bs);
        sps->qpprime_y_zero_transform_bypass_flag = (int)bs_read_u1(bs);
        sps->seq_scaling_matrix_present_flag = (int)bs_read_u1(bs);
        if (sps->seq_scaling_matrix_present_flag) {
            int n = (sps->chroma_format_idc != 3) ? 8 : 12;
            int i;
            for (i = 0; i < n; i++) {
                sps->seq_scaling_list_present_flag[i] = (int)bs_read_u1(bs);
                if (sps->seq_scaling_list_present_flag[i]) {
                    if (i < 6)
                        h264_parse_scaling_list(bs, sps->ScalingList4x4[i], 16);
                    else
                        h264_parse_scaling_list(bs, sps->ScalingList8x8[i-6], 64);
                }
            }
        }
    } else {
        sps->chroma_format_idc = 1; /* default: 4:2:0 */
    }

    sps->log2_max_frame_num_minus4 = (int)bs_read_ue(bs);
    sps->pic_order_cnt_type = (int)bs_read_ue(bs);

    if (sps->pic_order_cnt_type == 0) {
        sps->log2_max_pic_order_cnt_lsb_minus4 = (int)bs_read_ue(bs);
    } else if (sps->pic_order_cnt_type == 1) {
        sps->delta_pic_order_always_zero_flag = (int)bs_read_u1(bs);
        sps->offset_for_non_ref_pic           = (int)bs_read_se(bs);
        sps->offset_for_top_to_bottom_field   = (int)bs_read_se(bs);
        sps->num_ref_frames_in_pic_order_cnt_cycle = (int)bs_read_ue(bs);
        int i;
        for (i = 0; i < sps->num_ref_frames_in_pic_order_cnt_cycle; i++) {
            if (i < 256)
                sps->offset_for_ref_frame[i] = (int)bs_read_se(bs);
            else
                bs_read_se(bs);
        }
    }

    sps->max_num_ref_frames = (int)bs_read_ue(bs);
    sps->gaps_in_frame_num_value_allowed_flag = (int)bs_read_u1(bs);
    sps->pic_width_in_mbs_minus1              = (int)bs_read_ue(bs);
    sps->pic_height_in_map_units_minus1       = (int)bs_read_ue(bs);
    sps->frame_mbs_only_flag                  = (int)bs_read_u1(bs);
    if (!sps->frame_mbs_only_flag) {
        sps->mb_adaptive_frame_field_flag = (int)bs_read_u1(bs);
    }
    sps->direct_8x8_inference_flag = (int)bs_read_u1(bs);
    sps->frame_cropping_flag       = (int)bs_read_u1(bs);
    if (sps->frame_cropping_flag) {
        sps->frame_crop_left_offset   = (int)bs_read_ue(bs);
        sps->frame_crop_right_offset  = (int)bs_read_ue(bs);
        sps->frame_crop_top_offset    = (int)bs_read_ue(bs);
        sps->frame_crop_bottom_offset = (int)bs_read_ue(bs);
    }
    sps->vui_parameters_present_flag = (int)bs_read_u1(bs);
    if (sps->vui_parameters_present_flag) {
        h264_parse_vui(bs, sps);
    }

    /* Derive picture dimensions */
    int crop_x = sps->frame_crop_left_offset  + sps->frame_crop_right_offset;
    int crop_y = sps->frame_crop_top_offset    + sps->frame_crop_bottom_offset;
    int mux    = (sps->chroma_format_idc == 0) ? 0 : 2;
    sps->width  = (sps->pic_width_in_mbs_minus1 + 1) * 16 - crop_x * mux;
    sps->height = (sps->pic_height_in_map_units_minus1 + 1) *
                  (sps->frame_mbs_only_flag ? 16 : 32) - crop_y * mux;
    /* Fallback: ensure non-zero */
    if (sps->width  <= 0) sps->width  = (sps->pic_width_in_mbs_minus1 + 1) * 16;
    if (sps->height <= 0) sps->height = (sps->pic_height_in_map_units_minus1 + 1) * 16;

    sps->is_valid = 1;
    return H264_OK;
}

/* ---- PPS parsing ----------------------------------------------------- */

int h264_parse_pps(H264BitStream *bs, H264PPS *pps, H264SPS sps_array[32])
{
    (void)sps_array;
    memset(pps, 0, sizeof(*pps));

    pps->pic_parameter_set_id = (int)bs_read_ue(bs);
    pps->seq_parameter_set_id = (int)bs_read_ue(bs);
    if (pps->pic_parameter_set_id >= H264_MAX_PPS) return H264_ERR_PARAM;
    if (pps->seq_parameter_set_id >= H264_MAX_SPS) return H264_ERR_PARAM;

    pps->entropy_coding_mode_flag = (int)bs_read_u1(bs);
    pps->bottom_field_pic_order_in_frame_present_flag = (int)bs_read_u1(bs);
    pps->num_slice_groups_minus1 = (int)bs_read_ue(bs);

    if (pps->num_slice_groups_minus1 > 0) {
        pps->slice_group_map_type = (int)bs_read_ue(bs);
        if (pps->slice_group_map_type == 0) {
            int i;
            for (i = 0; i <= pps->num_slice_groups_minus1; i++)
                bs_read_ue(bs); /* run_length_minus1 */
        } else if (pps->slice_group_map_type == 2) {
            int i;
            for (i = 0; i < pps->num_slice_groups_minus1; i++) {
                bs_read_ue(bs); /* top_left */
                bs_read_ue(bs); /* bottom_right */
            }
        } else if (pps->slice_group_map_type == 3 ||
                   pps->slice_group_map_type == 4 ||
                   pps->slice_group_map_type == 5) {
            bs_skip_bits(bs, 1); /* slice_group_change_direction_flag */
            bs_read_ue(bs);      /* slice_group_change_rate_minus1 */
        } else if (pps->slice_group_map_type == 6) {
            int n = (int)bs_read_ue(bs) + 1; /* pic_size_in_map_units_minus1 */
            int i, bits = 1;
            int t = pps->num_slice_groups_minus1;
            while (t >>= 1) bits++;
            for (i = 0; i < n; i++)
                bs_skip_bits(bs, bits);
        }
    }

    pps->num_ref_idx_l0_default_active_minus1 = (int)bs_read_ue(bs);
    pps->num_ref_idx_l1_default_active_minus1 = (int)bs_read_ue(bs);
    pps->weighted_pred_flag                   = (int)bs_read_u1(bs);
    pps->weighted_bipred_idc                  = (int)bs_read_bits(bs, 2);
    pps->pic_init_qp_minus26                  = (int)bs_read_se(bs);
    pps->pic_init_qs_minus26                  = (int)bs_read_se(bs);
    pps->chroma_qp_index_offset               = (int)bs_read_se(bs);
    pps->deblocking_filter_control_present_flag = (int)bs_read_u1(bs);
    pps->constrained_intra_pred_flag            = (int)bs_read_u1(bs);
    pps->redundant_pic_cnt_present_flag         = (int)bs_read_u1(bs);

    /* Optional extension */
    if (bs_bits_left(bs) > 0) {
        pps->transform_8x8_mode_flag = (int)bs_read_u1(bs);
        pps->pic_scaling_matrix_present_flag = (int)bs_read_u1(bs);
        if (pps->pic_scaling_matrix_present_flag) {
            /* skip scaling lists */
            int i, n = 6 + 2 * pps->transform_8x8_mode_flag;
            for (i = 0; i < n; i++) {
                if (bs_read_u1(bs)) {
                    int sz = (i < 6) ? 16 : 64;
                    int j, ls = 8, ns = 8;
                    for (j = 0; j < sz; j++) {
                        if (ns != 0) {
                            int d = (int)bs_read_se(bs);
                            ns = (ls + d + 256) % 256;
                        }
                        ls = (ns == 0) ? ls : ns;
                    }
                }
            }
        }
        if (bs_bits_left(bs) > 0)
            pps->second_chroma_qp_index_offset = (int)bs_read_se(bs);
        else
            pps->second_chroma_qp_index_offset = pps->chroma_qp_index_offset;
    } else {
        pps->second_chroma_qp_index_offset = pps->chroma_qp_index_offset;
    }

    pps->is_valid = 1;
    return H264_OK;
}
