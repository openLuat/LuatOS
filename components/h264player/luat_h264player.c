#undef LUAT_LOG_TAG
#define LUAT_LOG_TAG "h264player"
#include "luat_log.h"
#include "luat_h264player.h"
#include "luat_mem.h"
#include <string.h>

typedef struct luat_h264player_ctx {
    uint16_t width;
    uint16_t height;
    uint16_t mb_width;
    uint16_t mb_height;
    uint32_t frame_size;
    uint8_t format;
    uint8_t sps_received;
    uint8_t pps_received;
    uint8_t frame_ready;
    uint8_t profile_idc;
    uint8_t level_idc;
    uint8_t chroma_format_idc;
    uint8_t separate_colour_plane_flag;
    uint8_t log2_max_frame_num;
    uint8_t pic_order_cnt_type;
    uint8_t log2_max_pic_order_cnt_lsb;
    uint8_t frame_mbs_only_flag;
    uint8_t delta_pic_order_always_zero_flag;
    uint8_t pic_order_present_flag;
    uint8_t entropy_coding_mode_flag;
    uint8_t num_ref_idx_l0_active_minus1;
    uint8_t num_ref_idx_l1_active_minus1;
    uint8_t weighted_pred_flag;
    uint8_t weighted_bipred_idc;
    uint8_t deblocking_filter_control_present_flag;
    uint8_t redundant_pic_cnt_present_flag;
    uint8_t transform_8x8_mode_flag;
    uint8_t sps_id;
    uint8_t pps_id;
    uint8_t bit_depth_luma_minus8;
    uint8_t bit_depth_chroma_minus8;
    uint8_t qp;
    uint8_t pic_init_qp;
    uint32_t frame_num;
    uint8_t *sps_rbsp;
    size_t sps_rbsp_len;
    uint8_t *pps_rbsp;
    size_t pps_rbsp_len;
    uint8_t *frame;
    uint8_t *ref_frame;
    size_t ref_size;
    uint8_t *nz_luma;
    size_t nz_luma_size;
    uint8_t *nz_chroma;
    size_t nz_chroma_size;
    luat_h264player_frame_cb_t frame_cb;
    void *frame_cb_userdata;
} luat_h264player_t;

typedef struct {
    const uint8_t *data;
    size_t size;
    size_t bitpos;
} h264_bitreader_t;

static int h264player_check_resolution(uint16_t width, uint16_t height) {
    size_t pixels = (size_t)width * (size_t)height;
    if (pixels == 0 || pixels > LUAT_H264PLAYER_MAX_PIXELS) {
        return 0;
    }
    return 1;
}

static void h264player_br_init(h264_bitreader_t *br, const uint8_t *data, size_t size) {
    br->data = data;
    br->size = size;
    br->bitpos = 0;
}

static int h264player_br_read_bit(h264_bitreader_t *br, uint32_t *out) {
    if (!br || !out) {
        return 0;
    }
    if (br->bitpos >= br->size * 8) {
        return 0;
    }
    size_t byte_pos = br->bitpos >> 3;
    uint32_t bit_off = 7U - (uint32_t)(br->bitpos & 7U);
    uint8_t val = br->data[byte_pos];
    *out = (uint32_t)((val >> bit_off) & 0x01U);
    br->bitpos++;
    return 1;
}

static int h264player_br_read_bits(h264_bitreader_t *br, uint32_t num_bits, uint32_t *out) {
    if (!br || !out || num_bits == 0 || num_bits > 32) {
        return 0;
    }
    uint32_t val = 0;
    for (uint32_t i = 0; i < num_bits; i++) {
        uint32_t bit = 0;
        if (!h264player_br_read_bit(br, &bit)) {
            return 0;
        }
        val = (val << 1U) | bit;
    }
    *out = val;
    return 1;
}

static int h264player_br_peek_bits(h264_bitreader_t *br, uint32_t num_bits, uint32_t *out) {
    if (!br || !out) {
        return 0;
    }
    size_t saved = br->bitpos;
    int ok = h264player_br_read_bits(br, num_bits, out);
    br->bitpos = saved;
    return ok;
}

static int h264player_br_skip_bits(h264_bitreader_t *br, uint32_t num_bits) {
    if (!br) {
        return 0;
    }
    if (br->bitpos + num_bits > br->size * 8) {
        return 0;
    }
    br->bitpos += num_bits;
    return 1;
}

static int h264player_br_more_rbsp_data(h264_bitreader_t *br) {
    if (!br) {
        return 0;
    }
    size_t total_bits = br->size * 8;
    if (br->bitpos >= total_bits) {
        return 0;
    }
    size_t remaining = total_bits - br->bitpos;
    if (remaining == 0) {
        return 0;
    }
    size_t saved = br->bitpos;
    uint32_t bit = 0;
    if (!h264player_br_read_bit(br, &bit)) {
        br->bitpos = saved;
        return 0;
    }
    if (bit == 0) {
        br->bitpos = saved;
        return 1;
    }
    for (size_t i = 0; i + 1 < remaining; i++) {
        if (!h264player_br_read_bit(br, &bit)) {
            br->bitpos = saved;
            return 0;
        }
        if (bit) {
            br->bitpos = saved;
            return 1;
        }
    }
    br->bitpos = saved;
    return 0;
}

static int h264player_br_read_ue(h264_bitreader_t *br, uint32_t *out) {
    uint32_t zero_count = 0;
    uint32_t bit = 0;
    while (1) {
        if (!h264player_br_read_bit(br, &bit)) {
            return 0;
        }
        if (bit == 1) {
            break;
        }
        zero_count++;
        if (zero_count > 31) {
            return 0;
        }
    }
    if (zero_count == 0) {
        *out = 0;
        return 1;
    }
    uint32_t suffix = 0;
    if (!h264player_br_read_bits(br, zero_count, &suffix)) {
        return 0;
    }
    *out = ((1U << zero_count) - 1U) + suffix;
    return 1;
}

static int h264player_br_read_se(h264_bitreader_t *br, int32_t *out) {
    uint32_t ue = 0;
    if (!h264player_br_read_ue(br, &ue)) {
        return 0;
    }
    int32_t val = (int32_t)((ue + 1U) >> 1U);
    if ((ue & 1U) == 0) {
        val = -val;
    }
    *out = val;
    return 1;
}

static int h264player_find_start_code(const uint8_t *data, size_t len, size_t *sc_size) {
    if (!data || len < 3) {
        return -1;
    }
    for (size_t i = 0; i + 3 <= len; i++) {
        if (data[i] == 0x00 && data[i + 1] == 0x00) {
            if (data[i + 2] == 0x01) {
                if (sc_size) {
                    *sc_size = 3;
                }
                return (int)i;
            }
            if (i + 3 < len && data[i + 2] == 0x00 && data[i + 3] == 0x01) {
                if (sc_size) {
                    *sc_size = 4;
                }
                return (int)i;
            }
        }
    }
    return -1;
}

static int h264player_convert_to_rbsp(const uint8_t *src, size_t src_len, uint8_t **out, size_t *out_len) {
    if (!src || !out || !out_len) {
        return 0;
    }
    uint8_t *buf = (uint8_t *)luat_heap_malloc(src_len);
    if (!buf) {
        return 0;
    }
    size_t w = 0;
    size_t zero_count = 0;
    for (size_t i = 0; i < src_len; i++) {
        uint8_t b = src[i];
        if (zero_count == 2 && b == 0x03) {
            zero_count = 0;
            continue;
        }
        buf[w++] = b;
        if (b == 0x00) {
            zero_count++;
        } else {
            zero_count = 0;
        }
    }
    *out = buf;
    *out_len = w;
    return 1;
}

static int h264player_skip_scaling_list(h264_bitreader_t *br, uint32_t size_of_list) {
    int32_t last_scale = 8;
    int32_t next_scale = 8;
    for (uint32_t i = 0; i < size_of_list; i++) {
        if (next_scale != 0) {
            int32_t delta_scale = 0;
            if (!h264player_br_read_se(br, &delta_scale)) {
                return 0;
            }
            next_scale = (last_scale + delta_scale + 256) % 256;
        }
        last_scale = (next_scale == 0) ? last_scale : next_scale;
    }
    return 1;
}

static int h264player_parse_sps(luat_h264player_t *ctx, const uint8_t *data, size_t size) {
    if (!ctx || !data || size == 0) {
        return 0;
    }
    uint8_t *rbsp = NULL;
    size_t rbsp_size = 0;
    if (!h264player_convert_to_rbsp(data, size, &rbsp, &rbsp_size)) {
        LLOGW("h264: sps rbsp convert fail len=%u", (unsigned)size);
        return 0;
    }

    h264_bitreader_t br;
    h264player_br_init(&br, rbsp, rbsp_size);

    uint32_t profile_idc = 0;
    uint32_t constraint_flags = 0;
    uint32_t level_idc = 0;
    uint32_t sps_id = 0;
    if (!h264player_br_read_bits(&br, 8, &profile_idc) ||
        !h264player_br_read_bits(&br, 8, &constraint_flags) ||
        !h264player_br_read_bits(&br, 8, &level_idc) ||
        !h264player_br_read_ue(&br, &sps_id)) {
        luat_heap_free(rbsp);
        return 0;
    }

    ctx->profile_idc = (uint8_t)profile_idc;
    ctx->level_idc = (uint8_t)level_idc;
    ctx->sps_id = (uint8_t)sps_id;

    uint32_t chroma_format_idc = 1;
    ctx->separate_colour_plane_flag = 0;
    if (profile_idc == 100 || profile_idc == 110 || profile_idc == 122 || profile_idc == 244 ||
        profile_idc == 44 || profile_idc == 83 || profile_idc == 86 || profile_idc == 118 ||
        profile_idc == 128 || profile_idc == 138 || profile_idc == 139 || profile_idc == 134) {
        if (!h264player_br_read_ue(&br, &chroma_format_idc)) {
            luat_heap_free(rbsp);
            return 0;
        }
        if (chroma_format_idc == 3) {
            uint32_t separate_colour_plane_flag = 0;
            if (!h264player_br_read_bit(&br, &separate_colour_plane_flag)) {
                luat_heap_free(rbsp);
                return 0;
            }
            ctx->separate_colour_plane_flag = (uint8_t)separate_colour_plane_flag;
        }
        uint32_t bit_depth_luma_minus8 = 0;
        uint32_t bit_depth_chroma_minus8 = 0;
        uint32_t qpprime_y_zero_transform_bypass_flag = 0;
        if (!h264player_br_read_ue(&br, &bit_depth_luma_minus8) ||
            !h264player_br_read_ue(&br, &bit_depth_chroma_minus8) ||
            !h264player_br_read_bit(&br, &qpprime_y_zero_transform_bypass_flag)) {
            luat_heap_free(rbsp);
            return 0;
        }
        ctx->bit_depth_luma_minus8 = (uint8_t)bit_depth_luma_minus8;
        ctx->bit_depth_chroma_minus8 = (uint8_t)bit_depth_chroma_minus8;
        uint32_t seq_scaling_matrix_present_flag = 0;
        if (!h264player_br_read_bit(&br, &seq_scaling_matrix_present_flag)) {
            luat_heap_free(rbsp);
            return 0;
        }
        if (seq_scaling_matrix_present_flag) {
            uint32_t scaling_lists = (chroma_format_idc != 3) ? 8U : 12U;
            for (uint32_t i = 0; i < scaling_lists; i++) {
                uint32_t seq_scaling_list_present_flag = 0;
                if (!h264player_br_read_bit(&br, &seq_scaling_list_present_flag)) {
                    luat_heap_free(rbsp);
                    return 0;
                }
                if (seq_scaling_list_present_flag) {
                    uint32_t size_of_list = (i < 6) ? 16U : 64U;
                    if (!h264player_skip_scaling_list(&br, size_of_list)) {
                        luat_heap_free(rbsp);
                        return 0;
                    }
                }
            }
        }
    }
    ctx->chroma_format_idc = (uint8_t)chroma_format_idc;

    uint32_t log2_max_frame_num_minus4 = 0;
    if (!h264player_br_read_ue(&br, &log2_max_frame_num_minus4)) {
        luat_heap_free(rbsp);
        return 0;
    }
    ctx->log2_max_frame_num = (uint8_t)(log2_max_frame_num_minus4 + 4);

    uint32_t pic_order_cnt_type = 0;
    if (!h264player_br_read_ue(&br, &pic_order_cnt_type)) {
        luat_heap_free(rbsp);
        return 0;
    }
    ctx->pic_order_cnt_type = (uint8_t)pic_order_cnt_type;

    if (pic_order_cnt_type == 0) {
        uint32_t log2_max_pic_order_cnt_lsb_minus4 = 0;
        if (!h264player_br_read_ue(&br, &log2_max_pic_order_cnt_lsb_minus4)) {
            luat_heap_free(rbsp);
            return 0;
        }
        ctx->log2_max_pic_order_cnt_lsb = (uint8_t)(log2_max_pic_order_cnt_lsb_minus4 + 4);
    } else if (pic_order_cnt_type == 1) {
        uint32_t delta_pic_order_always_zero_flag = 0;
        if (!h264player_br_read_bit(&br, &delta_pic_order_always_zero_flag)) {
            luat_heap_free(rbsp);
            return 0;
        }
        ctx->delta_pic_order_always_zero_flag = (uint8_t)delta_pic_order_always_zero_flag;
        int32_t offset_for_non_ref_pic = 0;
        int32_t offset_for_top_to_bottom_field = 0;
        uint32_t num_ref_frames_in_pic_order_cnt_cycle = 0;
        if (!h264player_br_read_se(&br, &offset_for_non_ref_pic) ||
            !h264player_br_read_se(&br, &offset_for_top_to_bottom_field) ||
            !h264player_br_read_ue(&br, &num_ref_frames_in_pic_order_cnt_cycle)) {
            luat_heap_free(rbsp);
            return 0;
        }
        for (uint32_t i = 0; i < num_ref_frames_in_pic_order_cnt_cycle; i++) {
            int32_t offset_for_ref_frame = 0;
            if (!h264player_br_read_se(&br, &offset_for_ref_frame)) {
                luat_heap_free(rbsp);
                return 0;
            }
        }
    }

    uint32_t max_num_ref_frames = 0;
    uint32_t gaps_in_frame_num_value_allowed_flag = 0;
    if (!h264player_br_read_ue(&br, &max_num_ref_frames) ||
        !h264player_br_read_bit(&br, &gaps_in_frame_num_value_allowed_flag)) {
        luat_heap_free(rbsp);
        return 0;
    }

    uint32_t pic_width_in_mbs_minus1 = 0;
    uint32_t pic_height_in_map_units_minus1 = 0;
    if (!h264player_br_read_ue(&br, &pic_width_in_mbs_minus1) ||
        !h264player_br_read_ue(&br, &pic_height_in_map_units_minus1)) {
        luat_heap_free(rbsp);
        return 0;
    }

    uint32_t frame_mbs_only_flag = 0;
    if (!h264player_br_read_bit(&br, &frame_mbs_only_flag)) {
        luat_heap_free(rbsp);
        return 0;
    }
    ctx->frame_mbs_only_flag = (uint8_t)frame_mbs_only_flag;
    if (!frame_mbs_only_flag) {
        uint32_t mb_adaptive_frame_field_flag = 0;
        if (!h264player_br_read_bit(&br, &mb_adaptive_frame_field_flag)) {
            luat_heap_free(rbsp);
            return 0;
        }
    }

    uint32_t direct_8x8_inference_flag = 0;
    if (!h264player_br_read_bit(&br, &direct_8x8_inference_flag)) {
        luat_heap_free(rbsp);
        return 0;
    }

    uint32_t frame_cropping_flag = 0;
    uint32_t crop_left = 0;
    uint32_t crop_right = 0;
    uint32_t crop_top = 0;
    uint32_t crop_bottom = 0;
    if (!h264player_br_read_bit(&br, &frame_cropping_flag)) {
        luat_heap_free(rbsp);
        return 0;
    }
    if (frame_cropping_flag) {
        if (!h264player_br_read_ue(&br, &crop_left) || !h264player_br_read_ue(&br, &crop_right) ||
            !h264player_br_read_ue(&br, &crop_top) || !h264player_br_read_ue(&br, &crop_bottom)) {
            luat_heap_free(rbsp);
            return 0;
        }
    }

    uint32_t vui_parameters_present_flag = 0;
    if (!h264player_br_read_bit(&br, &vui_parameters_present_flag)) {
        luat_heap_free(rbsp);
        return 0;
    }

    uint32_t width = (pic_width_in_mbs_minus1 + 1U) * 16U;
    uint32_t height = (pic_height_in_map_units_minus1 + 1U) * 16U;
    if (!frame_mbs_only_flag) {
        height *= 2U;
    }
    if (frame_cropping_flag) {
        uint32_t crop_unit_x = 1;
        uint32_t crop_unit_y = 2 - frame_mbs_only_flag;
        if (chroma_format_idc == 1) {
            crop_unit_x = 2;
            crop_unit_y *= 2;
        } else if (chroma_format_idc == 2) {
            crop_unit_x = 2;
        }
        width -= (crop_left + crop_right) * crop_unit_x;
        height -= (crop_top + crop_bottom) * crop_unit_y;
    }

    if (!h264player_check_resolution((uint16_t)width, (uint16_t)height)) {
        LLOGW("invalid resolution %u x %u", (unsigned)width, (unsigned)height);
        luat_heap_free(rbsp);
        return 0;
    }
    if (width != LUAT_H264PLAYER_FRAME_WIDTH || height != LUAT_H264PLAYER_FRAME_HEIGHT) {
        LLOGW("sps resolution %u x %u != compile %u x %u", width, height,
              (unsigned)LUAT_H264PLAYER_FRAME_WIDTH, (unsigned)LUAT_H264PLAYER_FRAME_HEIGHT);
        luat_heap_free(rbsp);
        return 0;
    }

    ctx->width = (uint16_t)width;
    ctx->height = (uint16_t)height;
    ctx->mb_width = (uint16_t)((width + 15U) / 16U);
    ctx->mb_height = (uint16_t)((height + 15U) / 16U);
    ctx->frame_size = (uint32_t)width * (uint32_t)height * LUAT_H264PLAYER_PIXEL_BYTES;
    ctx->ref_size = ctx->frame_size;

    if (ctx->sps_rbsp) {
        luat_heap_free(ctx->sps_rbsp);
    }
    ctx->sps_rbsp = rbsp;
    ctx->sps_rbsp_len = rbsp_size;
    ctx->sps_received = 1;
    LLOGI("h264: sps ok profile=%u level=%u %ux%u", (unsigned)ctx->profile_idc,
          (unsigned)ctx->level_idc, (unsigned)ctx->width, (unsigned)ctx->height);
    return 1;
}

static int h264player_parse_pps(luat_h264player_t *ctx, const uint8_t *data, size_t size) {
    if (!ctx || !data || size == 0) {
        return 0;
    }
    uint8_t *rbsp = NULL;
    size_t rbsp_size = 0;
    if (!h264player_convert_to_rbsp(data, size, &rbsp, &rbsp_size)) {
        LLOGW("h264: pps rbsp convert fail len=%u", (unsigned)size);
        return 0;
    }
    h264_bitreader_t br;
    h264player_br_init(&br, rbsp, rbsp_size);

    uint32_t pps_id = 0;
    uint32_t sps_id = 0;
    uint32_t entropy_coding_mode_flag = 0;
    uint32_t pic_order_present_flag = 0;
    if (!h264player_br_read_ue(&br, &pps_id) ||
        !h264player_br_read_ue(&br, &sps_id) ||
        !h264player_br_read_bit(&br, &entropy_coding_mode_flag) ||
        !h264player_br_read_bit(&br, &pic_order_present_flag)) {
        luat_heap_free(rbsp);
        return 0;
    }
    ctx->pps_id = (uint8_t)pps_id;
    ctx->entropy_coding_mode_flag = (uint8_t)entropy_coding_mode_flag;
    ctx->pic_order_present_flag = (uint8_t)pic_order_present_flag;

    uint32_t num_slice_groups_minus1 = 0;
    if (!h264player_br_read_ue(&br, &num_slice_groups_minus1)) {
        luat_heap_free(rbsp);
        return 0;
    }
    if (num_slice_groups_minus1 != 0) {
        LLOGW("slice groups not supported");
        luat_heap_free(rbsp);
        return 0;
    }

    uint32_t num_ref_idx_l0_default_active_minus1 = 0;
    uint32_t num_ref_idx_l1_default_active_minus1 = 0;
    if (!h264player_br_read_ue(&br, &num_ref_idx_l0_default_active_minus1) ||
        !h264player_br_read_ue(&br, &num_ref_idx_l1_default_active_minus1)) {
        luat_heap_free(rbsp);
        return 0;
    }
    ctx->num_ref_idx_l0_active_minus1 = (uint8_t)num_ref_idx_l0_default_active_minus1;
    ctx->num_ref_idx_l1_active_minus1 = (uint8_t)num_ref_idx_l1_default_active_minus1;

    uint32_t weighted_pred_flag = 0;
    uint32_t weighted_bipred_idc = 0;
    if (!h264player_br_read_bit(&br, &weighted_pred_flag) ||
        !h264player_br_read_bits(&br, 2, &weighted_bipred_idc)) {
        luat_heap_free(rbsp);
        return 0;
    }
    ctx->weighted_pred_flag = (uint8_t)weighted_pred_flag;
    ctx->weighted_bipred_idc = (uint8_t)weighted_bipred_idc;

    int32_t pic_init_qp_minus26 = 0;
    int32_t pic_init_qs_minus26 = 0;
    int32_t chroma_qp_index_offset = 0;
    if (!h264player_br_read_se(&br, &pic_init_qp_minus26) ||
        !h264player_br_read_se(&br, &pic_init_qs_minus26) ||
        !h264player_br_read_se(&br, &chroma_qp_index_offset)) {
        luat_heap_free(rbsp);
        return 0;
    }
    ctx->pic_init_qp = (uint8_t)(pic_init_qp_minus26 + 26);

    uint32_t deblocking_filter_control_present_flag = 0;
    uint32_t constrained_intra_pred_flag = 0;
    uint32_t redundant_pic_cnt_present_flag = 0;
    if (!h264player_br_read_bit(&br, &deblocking_filter_control_present_flag) ||
        !h264player_br_read_bit(&br, &constrained_intra_pred_flag) ||
        !h264player_br_read_bit(&br, &redundant_pic_cnt_present_flag)) {
        luat_heap_free(rbsp);
        return 0;
    }
    ctx->deblocking_filter_control_present_flag = (uint8_t)deblocking_filter_control_present_flag;
    ctx->redundant_pic_cnt_present_flag = (uint8_t)redundant_pic_cnt_present_flag;

    ctx->transform_8x8_mode_flag = 0;
    if (h264player_br_more_rbsp_data(&br)) {
        uint32_t transform_8x8_mode_flag = 0;
        if (!h264player_br_read_bit(&br, &transform_8x8_mode_flag)) {
            luat_heap_free(rbsp);
            return 0;
        }
        ctx->transform_8x8_mode_flag = (uint8_t)transform_8x8_mode_flag;

        uint32_t pic_scaling_matrix_present_flag = 0;
        if (!h264player_br_read_bit(&br, &pic_scaling_matrix_present_flag)) {
            luat_heap_free(rbsp);
            return 0;
        }
        if (pic_scaling_matrix_present_flag) {
            uint32_t scaling_lists = ctx->transform_8x8_mode_flag ? 8U : 6U;
            for (uint32_t i = 0; i < scaling_lists; i++) {
                uint32_t pic_scaling_list_present_flag = 0;
                if (!h264player_br_read_bit(&br, &pic_scaling_list_present_flag)) {
                    luat_heap_free(rbsp);
                    return 0;
                }
                if (pic_scaling_list_present_flag) {
                    uint32_t size_of_list = (i < 6) ? 16U : 64U;
                    if (!h264player_skip_scaling_list(&br, size_of_list)) {
                        luat_heap_free(rbsp);
                        return 0;
                    }
                }
            }
        }

        int32_t second_chroma_qp_index_offset = 0;
        if (!h264player_br_read_se(&br, &second_chroma_qp_index_offset)) {
            luat_heap_free(rbsp);
            return 0;
        }
    }

    if (ctx->pps_rbsp) {
        luat_heap_free(ctx->pps_rbsp);
    }
    ctx->pps_rbsp = rbsp;
    ctx->pps_rbsp_len = rbsp_size;
    ctx->pps_received = 1;
    LLOGI("h264: pps ok pps_id=%u sps_id=%u cabac=%u", (unsigned)ctx->pps_id,
          (unsigned)ctx->sps_id, (unsigned)ctx->entropy_coding_mode_flag);
    return 1;
}

static int h264player_skip_ref_pic_list_reordering(h264_bitreader_t *br, uint8_t slice_type) {
    if (!br) {
        return 0;
    }
    if (slice_type != 0 && slice_type != 5 && slice_type != 1 && slice_type != 6) {
        return 1;
    }
    uint32_t ref_pic_list_reordering_flag_l0 = 0;
    if (!h264player_br_read_bit(br, &ref_pic_list_reordering_flag_l0)) {
        return 0;
    }
    if (ref_pic_list_reordering_flag_l0) {
        while (1) {
            uint32_t reordering_of_pic_nums_idc = 0;
            if (!h264player_br_read_ue(br, &reordering_of_pic_nums_idc)) {
                return 0;
            }
            if (reordering_of_pic_nums_idc == 3) {
                break;
            }
            if (reordering_of_pic_nums_idc == 0 || reordering_of_pic_nums_idc == 1) {
                uint32_t abs_diff_pic_num_minus1 = 0;
                if (!h264player_br_read_ue(br, &abs_diff_pic_num_minus1)) {
                    return 0;
                }
            } else if (reordering_of_pic_nums_idc == 2) {
                uint32_t long_term_pic_num = 0;
                if (!h264player_br_read_ue(br, &long_term_pic_num)) {
                    return 0;
                }
            }
        }
    }
    if (slice_type == 1 || slice_type == 6) {
        uint32_t ref_pic_list_reordering_flag_l1 = 0;
        if (!h264player_br_read_bit(br, &ref_pic_list_reordering_flag_l1)) {
            return 0;
        }
        if (ref_pic_list_reordering_flag_l1) {
            while (1) {
                uint32_t reordering_of_pic_nums_idc = 0;
                if (!h264player_br_read_ue(br, &reordering_of_pic_nums_idc)) {
                    return 0;
                }
                if (reordering_of_pic_nums_idc == 3) {
                    break;
                }
                if (reordering_of_pic_nums_idc == 0 || reordering_of_pic_nums_idc == 1) {
                    uint32_t abs_diff_pic_num_minus1 = 0;
                    if (!h264player_br_read_ue(br, &abs_diff_pic_num_minus1)) {
                        return 0;
                    }
                } else if (reordering_of_pic_nums_idc == 2) {
                    uint32_t long_term_pic_num = 0;
                    if (!h264player_br_read_ue(br, &long_term_pic_num)) {
                        return 0;
                    }
                }
            }
        }
    }
    return 1;
}

static int h264player_skip_pred_weight_table(h264_bitreader_t *br, uint8_t slice_type,
                                             uint8_t num_ref_idx_l0_active_minus1,
                                             uint8_t num_ref_idx_l1_active_minus1) {
    if (!br) {
        return 0;
    }
    if (slice_type != 0 && slice_type != 5 && slice_type != 3 && slice_type != 8 && slice_type != 1 && slice_type != 6) {
        return 1;
    }
    uint32_t luma_log2_weight_denom = 0;
    uint32_t chroma_log2_weight_denom = 0;
    if (!h264player_br_read_ue(br, &luma_log2_weight_denom)) {
        return 0;
    }
    if (!h264player_br_read_ue(br, &chroma_log2_weight_denom)) {
        return 0;
    }
    for (uint32_t i = 0; i <= num_ref_idx_l0_active_minus1; i++) {
        uint32_t luma_weight_flag = 0;
        if (!h264player_br_read_bit(br, &luma_weight_flag)) {
            return 0;
        }
        if (luma_weight_flag) {
            int32_t weight = 0;
            int32_t offset = 0;
            if (!h264player_br_read_se(br, &weight) || !h264player_br_read_se(br, &offset)) {
                return 0;
            }
        }
        uint32_t chroma_weight_flag = 0;
        if (!h264player_br_read_bit(br, &chroma_weight_flag)) {
            return 0;
        }
        if (chroma_weight_flag) {
            for (uint32_t j = 0; j < 2; j++) {
                int32_t weight = 0;
                int32_t offset = 0;
                if (!h264player_br_read_se(br, &weight) || !h264player_br_read_se(br, &offset)) {
                    return 0;
                }
            }
        }
    }
    if (slice_type == 1 || slice_type == 6) {
        for (uint32_t i = 0; i <= num_ref_idx_l1_active_minus1; i++) {
            uint32_t luma_weight_flag = 0;
            if (!h264player_br_read_bit(br, &luma_weight_flag)) {
                return 0;
            }
            if (luma_weight_flag) {
                int32_t weight = 0;
                int32_t offset = 0;
                if (!h264player_br_read_se(br, &weight) || !h264player_br_read_se(br, &offset)) {
                    return 0;
                }
            }
            uint32_t chroma_weight_flag = 0;
            if (!h264player_br_read_bit(br, &chroma_weight_flag)) {
                return 0;
            }
            if (chroma_weight_flag) {
                for (uint32_t j = 0; j < 2; j++) {
                    int32_t weight = 0;
                    int32_t offset = 0;
                    if (!h264player_br_read_se(br, &weight) || !h264player_br_read_se(br, &offset)) {
                        return 0;
                    }
                }
            }
        }
    }
    return 1;
}

static int h264player_skip_dec_ref_pic_marking(h264_bitreader_t *br, uint8_t nal_ref_idc, uint8_t nal_type) {
    if (!br) {
        return 0;
    }
    if (nal_ref_idc == 0) {
        return 1;
    }
    if (nal_type == 5) {
        uint32_t no_output_of_prior_pics_flag = 0;
        uint32_t long_term_reference_flag = 0;
        if (!h264player_br_read_bit(br, &no_output_of_prior_pics_flag) ||
            !h264player_br_read_bit(br, &long_term_reference_flag)) {
            return 0;
        }
    } else {
        uint32_t adaptive_ref_pic_marking_mode_flag = 0;
        if (!h264player_br_read_bit(br, &adaptive_ref_pic_marking_mode_flag)) {
            return 0;
        }
        if (adaptive_ref_pic_marking_mode_flag) {
            while (1) {
                uint32_t memory_management_control_operation = 0;
                if (!h264player_br_read_ue(br, &memory_management_control_operation)) {
                    return 0;
                }
                if (memory_management_control_operation == 0) {
                    break;
                }
                if (memory_management_control_operation == 1 || memory_management_control_operation == 3) {
                    uint32_t diff_pic_num_minus1 = 0;
                    if (!h264player_br_read_ue(br, &diff_pic_num_minus1)) {
                        return 0;
                    }
                }
                if (memory_management_control_operation == 2) {
                    uint32_t long_term_pic_num = 0;
                    if (!h264player_br_read_ue(br, &long_term_pic_num)) {
                        return 0;
                    }
                }
                if (memory_management_control_operation == 3 || memory_management_control_operation == 6) {
                    uint32_t long_term_frame_idx = 0;
                    if (!h264player_br_read_ue(br, &long_term_frame_idx)) {
                        return 0;
                    }
                }
                if (memory_management_control_operation == 4) {
                    uint32_t max_long_term_frame_idx_plus1 = 0;
                    if (!h264player_br_read_ue(br, &max_long_term_frame_idx_plus1)) {
                        return 0;
                    }
                }
            }
        }
    }
    return 1;
}

static void h264player_mb_index_to_xy(luat_h264player_t *ctx, uint32_t mb_index, uint32_t *mb_x, uint32_t *mb_y) {
    if (!ctx || !mb_x || !mb_y || ctx->mb_width == 0) {
        if (mb_x) {
            *mb_x = 0;
        }
        if (mb_y) {
            *mb_y = 0;
        }
        return;
    }
    *mb_x = mb_index % ctx->mb_width;
    *mb_y = mb_index / ctx->mb_width;
}

static int h264player_skip_pcm(luat_h264player_t *ctx, h264_bitreader_t *br) {
    if (!ctx || !br) {
        return 0;
    }
    uint32_t align = (uint32_t)(br->bitpos & 7U);
    if (align) {
        if (!h264player_br_skip_bits(br, 8U - align)) {
            return 0;
        }
    }
    uint32_t luma_bits = (uint32_t)ctx->bit_depth_luma_minus8 + 8U;
    uint32_t chroma_bits = (uint32_t)ctx->bit_depth_chroma_minus8 + 8U;
    uint32_t luma_bytes = (luma_bits + 7U) / 8U;
    uint32_t chroma_bytes = (chroma_bits + 7U) / 8U;
    uint32_t bytes = 16U * 16U * luma_bytes + 2U * 8U * 8U * chroma_bytes;
    return h264player_br_skip_bits(br, bytes * 8U);
}

static void h264player_fill_mb_gray(luat_h264player_t *ctx, uint32_t mb_x, uint32_t mb_y) {
    if (!ctx || !ctx->frame || ctx->frame_size == 0) {
        return;
    }
    uint32_t start_x = mb_x * 16U;
    uint32_t start_y = mb_y * 16U;
    if (start_x >= ctx->width || start_y >= ctx->height) {
        return;
    }
    if (ctx->format == 0) {
        uint16_t gray565 = (uint16_t)(((0x10U & 0x1FU) << 11) | ((0x20U & 0x3FU) << 5) | (0x10U & 0x1FU));
        uint16_t *dst = (uint16_t *)ctx->frame;
        uint32_t stride = ctx->width;
        for (uint32_t y = 0; y < 16 && (start_y + y) < ctx->height; y++) {
            uint32_t line = (start_y + y) * stride + start_x;
            for (uint32_t x = 0; x < 16 && (start_x + x) < ctx->width; x++) {
                dst[line + x] = gray565;
            }
        }
    } else {
        uint32_t gray8888 = 0xFF808080U;
        uint32_t *dst = (uint32_t *)ctx->frame;
        uint32_t stride = ctx->width;
        for (uint32_t y = 0; y < 16 && (start_y + y) < ctx->height; y++) {
            uint32_t line = (start_y + y) * stride + start_x;
            for (uint32_t x = 0; x < 16 && (start_x + x) < ctx->width; x++) {
                dst[line + x] = gray8888;
            }
        }
    }
}

static void h264player_copy_mb_from_ref(luat_h264player_t *ctx, uint32_t mb_x, uint32_t mb_y) {
    if (!ctx || !ctx->frame || !ctx->ref_frame || ctx->frame_size == 0 || ctx->ref_size != ctx->frame_size) {
        return;
    }
    uint32_t start_x = mb_x * 16U;
    uint32_t start_y = mb_y * 16U;
    if (start_x >= ctx->width || start_y >= ctx->height) {
        return;
    }
    uint32_t bytes_per_pixel = LUAT_H264PLAYER_PIXEL_BYTES;
    uint32_t stride_bytes = ctx->width * bytes_per_pixel;
    uint8_t *dst = ctx->frame + start_y * stride_bytes + start_x * bytes_per_pixel;
    uint8_t *src = ctx->ref_frame + start_y * stride_bytes + start_x * bytes_per_pixel;
    uint32_t copy_width = (start_x + 16U <= ctx->width) ? 16U : (ctx->width - start_x);
    uint32_t copy_height = (start_y + 16U <= ctx->height) ? 16U : (ctx->height - start_y);
    size_t row_bytes = copy_width * bytes_per_pixel;
    for (uint32_t y = 0; y < copy_height; y++) {
        memcpy(dst + y * stride_bytes, src + y * stride_bytes, row_bytes);
    }
}

static const uint8_t h264_golomb_to_intra4x4_cbp[48] = {
    47, 31, 15, 0,  23, 27, 29, 30, 7,  11, 13, 14, 39, 43, 45, 46,
    16, 3,  5,  10, 12, 19, 21, 26, 28, 35, 37, 42, 44, 1,  2,  4,
    8,  17, 18, 20, 24, 6,  9,  22, 25, 32, 33, 34, 36, 40, 38, 41
};

static const uint8_t h264_golomb_to_inter_cbp[48] = {
    0,  16, 1,  2,  4,  8,  32, 3,  5,  10, 12, 15, 47, 7,  11, 13,
    14, 6,  9,  31, 35, 37, 42, 44, 33, 34, 36, 40, 39, 43, 45, 46,
    17, 18, 20, 24, 19, 21, 26, 28, 23, 27, 29, 30, 22, 25, 38, 41
};

static const uint8_t h264_code_coeff_token_table[4][4][17] = {
    {
        {1, 5, 7, 7, 7, 7, 15, 11, 8, 15, 11, 15, 11, 15, 11, 7, 4},
        {0, 1, 4, 6, 6, 6, 6, 14, 10, 14, 10, 14, 10, 1, 14, 10, 6},
        {0, 0, 1, 5, 5, 5, 5, 5, 13, 9, 13, 9, 13, 9, 13, 9, 5},
        {0, 0, 0, 3, 3, 4, 4, 4, 4, 4, 12, 12, 8, 12, 8, 12, 8},
    },
    {
        {3, 11, 7, 7, 7, 4, 7, 15, 11, 15, 11, 8, 15, 11, 7, 9, 7},
        {0, 2, 7, 10, 6, 6, 6, 6, 14, 10, 14, 10, 14, 10, 11, 8, 6},
        {0, 0, 3, 9, 5, 5, 5, 5, 13, 9, 13, 9, 13, 9, 6, 10, 5},
        {0, 0, 0, 5, 4, 6, 8, 4, 4, 4, 12, 8, 12, 12, 8, 1, 4},
    },
    {
        {15, 15, 11, 8, 15, 11, 9, 8, 15, 11, 15, 11, 8, 13, 9, 5, 1},
        {0, 14, 15, 12, 10, 8, 14, 10, 14, 14, 10, 14, 10, 7, 12, 8, 4},
        {0, 0, 13, 14, 11, 9, 13, 9, 13, 10, 13, 9, 13, 9, 11, 7, 3},
        {0, 0, 0, 12, 11, 10, 9, 8, 13, 12, 12, 12, 8, 12, 10, 6, 2},
    },
    {
        {3, 0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60},
        {0, 1, 5, 9, 13, 17, 21, 25, 29, 33, 37, 41, 45, 49, 53, 57, 61},
        {0, 0, 6, 10, 14, 18, 22, 26, 30, 34, 38, 42, 46, 50, 54, 58, 62},
        {0, 0, 0, 11, 15, 19, 23, 27, 31, 35, 39, 43, 47, 51, 55, 59, 63},
    },
};

static const uint8_t h264_size_coeff_token_table[4][4][17] = {
    {
        {1, 6, 8, 9, 10, 11, 13, 13, 13, 14, 14, 15, 15, 16, 16, 16, 16},
        {0, 2, 6, 8, 9, 10, 11, 13, 13, 14, 14, 15, 15, 15, 16, 16, 16},
        {0, 0, 3, 7, 8, 9, 10, 11, 13, 13, 14, 14, 15, 15, 16, 16, 16},
        {0, 0, 0, 5, 6, 7, 8, 9, 10, 11, 13, 14, 14, 15, 15, 16, 16},
    },
    {
        {2, 6, 6, 7, 8, 8, 9, 11, 11, 12, 12, 12, 13, 13, 13, 14, 14},
        {0, 2, 5, 6, 6, 7, 8, 9, 11, 11, 12, 12, 13, 13, 14, 14, 14},
        {0, 0, 3, 6, 6, 7, 8, 9, 11, 11, 12, 12, 13, 13, 13, 14, 14},
        {0, 0, 0, 4, 4, 5, 6, 6, 7, 9, 11, 11, 12, 13, 13, 13, 14},
    },
    {
        {4, 6, 6, 6, 7, 7, 7, 7, 8, 8, 9, 9, 9, 10, 10, 10, 10},
        {0, 4, 5, 5, 5, 5, 6, 6, 7, 8, 8, 9, 9, 9, 10, 10, 10},
        {0, 0, 4, 5, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 10},
        {0, 0, 0, 4, 4, 4, 4, 4, 5, 6, 7, 8, 8, 9, 10, 10, 10},
    },
    {
        {6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6},
        {0, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6},
        {0, 0, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6},
        {0, 0, 0, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6},
    },
};

static const uint8_t h264_code_coeff_token_table_chroma[4][5] = {
    {1, 7, 4, 3, 2},
    {0, 1, 6, 3, 3},
    {0, 0, 1, 2, 2},
    {0, 0, 0, 5, 0},
};

static const uint8_t h264_size_coeff_token_table_chroma[4][5] = {
    {2, 6, 6, 6, 6},
    {0, 1, 6, 7, 8},
    {0, 0, 3, 7, 8},
    {0, 0, 0, 6, 7},
};

static const uint8_t h264_threshold_vlc_level[6] = {0, 3, 6, 12, 24, 48};

static const uint8_t h264_size_zero_table[135] = {
    1, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 9,
    3, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 6, 6, 6, 6,
    4, 3, 3, 3, 4, 4, 3, 3, 4, 5, 5, 6, 5, 6,
    5, 3, 4, 4, 3, 3, 3, 4, 3, 4, 5, 5, 5,
    4, 4, 4, 3, 3, 3, 3, 3, 4, 5, 4, 5,
    6, 5, 3, 3, 3, 3, 3, 3, 4, 3, 6,
    6, 5, 3, 3, 3, 2, 3, 4, 3, 6,
    6, 4, 5, 3, 2, 2, 3, 3, 6,
    6, 6, 4, 2, 2, 3, 2, 5,
    5, 5, 3, 2, 2, 2, 4,
    4, 4, 3, 3, 1, 3,
    4, 4, 2, 1, 3,
    3, 3, 1, 2,
    2, 2, 1,
    1, 1,
};

static const uint8_t h264_code_zero_table[135] = {
    1, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 3, 2, 1,
    7, 6, 5, 4, 3, 5, 4, 3, 2, 3, 2, 3, 2, 1, 0,
    5, 7, 6, 5, 4, 3, 4, 3, 2, 3, 2, 1, 1, 0,
    3, 7, 5, 4, 6, 5, 4, 3, 3, 2, 2, 1, 0,
    5, 4, 3, 7, 6, 5, 4, 3, 2, 1, 1, 0,
    1, 1, 7, 6, 5, 4, 3, 2, 1, 1, 0,
    1, 1, 5, 4, 3, 3, 2, 1, 1, 0,
    1, 1, 1, 3, 3, 2, 2, 1, 0,
    1, 0, 1, 3, 2, 1, 1, 1,
    1, 0, 1, 3, 2, 1, 1,
    0, 1, 1, 2, 1, 3,
    0, 1, 1, 1, 1,
    0, 1, 1, 1,
    0, 1, 1,
    0, 1,
};

static const uint8_t h264_size_zero_table_chroma[9] = {
    1, 2, 3, 3,
    1, 2, 2,
    1, 1,
};

static const uint8_t h264_code_zero_table_chroma[9] = {
    1, 1, 1, 0,
    1, 1, 0,
    1, 0,
};

static const uint8_t h264_index_zero_table[15] = {
    0, 16, 31, 45, 58, 70, 81, 91, 100, 108, 115, 121, 126, 130, 133,
};

static const uint8_t h264_size_run_table[42] = {
    1, 1,
    1, 2, 2,
    2, 2, 2, 2,
    2, 2, 2, 3, 3,
    2, 2, 3, 3, 3, 3,
    2, 3, 3, 3, 3, 3, 3,
    3, 3, 3, 3, 3, 3, 3, 4, 5, 6, 7, 8, 9, 10, 11,
};

static const uint8_t h264_code_run_table[42] = {
    1, 0,
    1, 1, 0,
    3, 2, 1, 0,
    3, 2, 1, 1, 0,
    3, 2, 3, 2, 1, 0,
    3, 0, 1, 3, 2, 5, 4,
    7, 6, 5, 4, 3, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1,
};

static const uint8_t h264_index_run_table[7] = {0, 2, 5, 9, 14, 20, 27};

static uint8_t h264player_get_luma_nz(luat_h264player_t *ctx, uint32_t mb_x, uint32_t mb_y, uint32_t blk) {
    if (!ctx || !ctx->nz_luma || ctx->mb_width == 0 || ctx->mb_height == 0) {
        return 0;
    }
    uint32_t mb_index = mb_y * ctx->mb_width + mb_x;
    size_t idx = (size_t)mb_index * 16U + blk;
    if (idx >= ctx->nz_luma_size) {
        return 0;
    }
    return ctx->nz_luma[idx];
}

static void h264player_set_luma_nz(luat_h264player_t *ctx, uint32_t mb_x, uint32_t mb_y, uint32_t blk, uint8_t val) {
    if (!ctx || !ctx->nz_luma || ctx->mb_width == 0 || ctx->mb_height == 0) {
        return;
    }
    uint32_t mb_index = mb_y * ctx->mb_width + mb_x;
    size_t idx = (size_t)mb_index * 16U + blk;
    if (idx >= ctx->nz_luma_size) {
        return;
    }
    ctx->nz_luma[idx] = val;
}

static uint8_t h264player_get_chroma_nz(luat_h264player_t *ctx, uint32_t mb_x, uint32_t mb_y, uint32_t plane,
                                        uint32_t blk) {
    if (!ctx || !ctx->nz_chroma || ctx->mb_width == 0 || ctx->mb_height == 0 || plane > 1) {
        return 0;
    }
    uint32_t mb_index = mb_y * ctx->mb_width + mb_x;
    size_t idx = (size_t)mb_index * 8U + plane * 4U + blk;
    if (idx >= ctx->nz_chroma_size) {
        return 0;
    }
    return ctx->nz_chroma[idx];
}

static void h264player_set_chroma_nz(luat_h264player_t *ctx, uint32_t mb_x, uint32_t mb_y, uint32_t plane,
                                     uint32_t blk, uint8_t val) {
    if (!ctx || !ctx->nz_chroma || ctx->mb_width == 0 || ctx->mb_height == 0 || plane > 1) {
        return;
    }
    uint32_t mb_index = mb_y * ctx->mb_width + mb_x;
    size_t idx = (size_t)mb_index * 8U + plane * 4U + blk;
    if (idx >= ctx->nz_chroma_size) {
        return;
    }
    ctx->nz_chroma[idx] = val;
}

static uint8_t h264player_get_luma_nC(luat_h264player_t *ctx, uint32_t mb_x, uint32_t mb_y, uint32_t blk) {
    uint32_t blk_x = blk & 3U;
    uint32_t blk_y = blk >> 2;
    uint8_t nA = 0;
    uint8_t nB = 0;
    uint8_t availA = 0;
    uint8_t availB = 0;

    if (blk_x > 0) {
        availA = 1;
        nA = h264player_get_luma_nz(ctx, mb_x, mb_y, blk - 1U);
    } else if (mb_x > 0) {
        availA = 1;
        nA = h264player_get_luma_nz(ctx, mb_x - 1U, mb_y, blk + 3U);
    }

    if (blk_y > 0) {
        availB = 1;
        nB = h264player_get_luma_nz(ctx, mb_x, mb_y, blk - 4U);
    } else if (mb_y > 0) {
        availB = 1;
        nB = h264player_get_luma_nz(ctx, mb_x, mb_y - 1U, blk + 12U);
    }

    if (availA && availB) {
        return (uint8_t)((nA + nB + 1U) / 2U);
    }
    if (availA) {
        return nA;
    }
    if (availB) {
        return nB;
    }
    return 0;
}

static uint8_t h264player_get_chroma_nC(luat_h264player_t *ctx, uint32_t mb_x, uint32_t mb_y, uint32_t plane,
                                        uint32_t blk) {
    uint32_t blk_x = blk & 1U;
    uint32_t blk_y = blk >> 1;
    uint8_t nA = 0;
    uint8_t nB = 0;
    uint8_t availA = 0;
    uint8_t availB = 0;

    if (blk_x > 0) {
        availA = 1;
        nA = h264player_get_chroma_nz(ctx, mb_x, mb_y, plane, blk - 1U);
    } else if (mb_x > 0) {
        availA = 1;
        nA = h264player_get_chroma_nz(ctx, mb_x - 1U, mb_y, plane, blk + 1U);
    }

    if (blk_y > 0) {
        availB = 1;
        nB = h264player_get_chroma_nz(ctx, mb_x, mb_y, plane, blk - 2U);
    } else if (mb_y > 0) {
        availB = 1;
        nB = h264player_get_chroma_nz(ctx, mb_x, mb_y - 1U, plane, blk + 2U);
    }

    if (availA && availB) {
        return (uint8_t)((nA + nB + 1U) / 2U);
    }
    if (availA) {
        return nA;
    }
    if (availB) {
        return nB;
    }
    return 0;
}

static int h264player_cavlc_decode_coeff_token(h264_bitreader_t *br, uint8_t nC,
                                               uint8_t *total_coeff, uint8_t *trailing_ones) {
    if (!br || !total_coeff || !trailing_ones) {
        return 0;
    }
    if (nC == 0xFF) {
        for (uint32_t t1 = 0; t1 < 4; t1++) {
            for (uint32_t tc = 0; tc < 5; tc++) {
                uint8_t size = h264_size_coeff_token_table_chroma[t1][tc];
                if (size == 0) {
                    continue;
                }
                uint32_t bits = 0;
                if (!h264player_br_peek_bits(br, size, &bits)) {
                    return 0;
                }
                if (bits == h264_code_coeff_token_table_chroma[t1][tc]) {
                    if (!h264player_br_skip_bits(br, size)) {
                        return 0;
                    }
                    *total_coeff = (uint8_t)tc;
                    *trailing_ones = (uint8_t)t1;
                    return 1;
                }
            }
        }
          uint32_t peek = 0;
          h264player_br_peek_bits(br, 16, &peek);
          LLOGW("h264: cavlc coeff_token fail chroma_dc nC=0xFF bit=%u next=0x%04X",
              (unsigned)br->bitpos, (unsigned)peek);
          return 0;
    }

    uint32_t table_idx = 0;
    if (nC < 2) {
        table_idx = 0;
    } else if (nC < 4) {
        table_idx = 1;
    } else if (nC < 8) {
        table_idx = 2;
    } else {
        table_idx = 3;
    }
    for (uint32_t t1 = 0; t1 < 4; t1++) {
        for (uint32_t tc = 0; tc < 17; tc++) {
            uint8_t size = h264_size_coeff_token_table[table_idx][t1][tc];
            if (size == 0) {
                continue;
            }
            uint32_t bits = 0;
            if (!h264player_br_peek_bits(br, size, &bits)) {
                return 0;
            }
            if (bits == h264_code_coeff_token_table[table_idx][t1][tc]) {
                if (!h264player_br_skip_bits(br, size)) {
                    return 0;
                }
                *total_coeff = (uint8_t)tc;
                *trailing_ones = (uint8_t)t1;
                return 1;
            }
        }
    }
    uint32_t peek = 0;
    h264player_br_peek_bits(br, 16, &peek);
    LLOGW("h264: cavlc coeff_token fail table=%u nC=%u bit=%u next=0x%04X",
          (unsigned)table_idx, (unsigned)nC, (unsigned)br->bitpos, (unsigned)peek);
    return 0;
}

static int h264player_cavlc_decode_levels(h264_bitreader_t *br, uint8_t total_coeff, uint8_t trailing_ones) {
    if (!br) {
        return 0;
    }
    for (uint32_t i = 0; i < trailing_ones; i++) {
        uint32_t sign = 0;
        if (!h264player_br_read_bit(br, &sign)) {
            return 0;
        }
    }

    uint32_t suffix_length = 0;
    if (total_coeff > 10 && trailing_ones < 3) {
        suffix_length = 1;
    }

    uint32_t remaining = (uint32_t)total_coeff - (uint32_t)trailing_ones;
    for (uint32_t i = 0; i < remaining; i++) {
        uint32_t level_prefix = 0;
        uint32_t bit = 0;
        while (1) {
            if (!h264player_br_read_bit(br, &bit)) {
                return 0;
            }
            if (bit) {
                break;
            }
            level_prefix++;
        }

        uint32_t level_suffix_size = 0;
        if (level_prefix == 14 && suffix_length == 0) {
            level_suffix_size = 4;
        } else if (level_prefix >= 15) {
            level_suffix_size = level_prefix - 3;
        } else {
            level_suffix_size = suffix_length;
        }

        uint32_t level_suffix = 0;
        if (level_suffix_size > 0) {
            if (!h264player_br_read_bits(br, level_suffix_size, &level_suffix)) {
                return 0;
            }
        }

        uint32_t level_code = 0;
        if (level_prefix >= 15) {
            level_code = (15U << suffix_length) + level_suffix + (1U << (level_prefix - 3U)) - 4096U;
        } else {
            level_code = (level_prefix << suffix_length) + level_suffix;
        }
        if (i == 0 && trailing_ones < 3) {
            level_code += 2U;
        }

        int32_t level_val = (int32_t)((level_code + 2U) >> 1U);
        if ((level_code & 1U) == 0) {
            level_val = -level_val;
        }

        if (suffix_length == 0) {
            suffix_length = 1;
        }
        if ((uint32_t)(level_val < 0 ? -level_val : level_val) > (3U << (suffix_length - 1U)) && suffix_length < 6) {
            suffix_length++;
        }
    }
    return 1;
}

static int h264player_cavlc_decode_total_zeros(h264_bitreader_t *br, uint8_t total_coeff, uint8_t max_coeff,
                                               uint8_t nC, uint8_t *total_zeros) {
    if (!br || !total_zeros) {
        return 0;
    }
    if (total_coeff == 0 || total_coeff >= max_coeff) {
        *total_zeros = 0;
        return 1;
    }
    if (nC == 0xFF) {
        uint32_t base = 0;
        uint32_t count = 0;
        if (total_coeff == 1) {
            base = 0;
            count = 4;
        } else if (total_coeff == 2) {
            base = 4;
            count = 3;
        } else if (total_coeff == 3) {
            base = 7;
            count = 2;
        } else {
            *total_zeros = 0;
            return 1;
        }
        for (uint32_t z = 0; z < count; z++) {
            uint8_t size = h264_size_zero_table_chroma[base + z];
            uint8_t code = h264_code_zero_table_chroma[base + z];
            uint32_t bits = 0;
            if (!h264player_br_peek_bits(br, size, &bits)) {
                return 0;
            }
            if (bits == code) {
                if (!h264player_br_skip_bits(br, size)) {
                    return 0;
                }
                *total_zeros = (uint8_t)z;
                return 1;
            }
        }
        return 0;
    }

    uint32_t base = h264_index_zero_table[total_coeff - 1U];
    uint32_t max_zeros = (uint32_t)max_coeff - total_coeff;
    for (uint32_t z = 0; z <= max_zeros; z++) {
        uint8_t size = h264_size_zero_table[base + z];
        uint8_t code = h264_code_zero_table[base + z];
        uint32_t bits = 0;
        if (!h264player_br_peek_bits(br, size, &bits)) {
            return 0;
        }
        if (bits == code) {
            if (!h264player_br_skip_bits(br, size)) {
                return 0;
            }
            *total_zeros = (uint8_t)z;
            return 1;
        }
    }
    return 0;
}

static int h264player_cavlc_decode_run_before(h264_bitreader_t *br, uint8_t zeros_left) {
    if (!br || zeros_left == 0) {
        return 0;
    }
    uint32_t table_zeros = (zeros_left > 6) ? 7 : zeros_left;
    uint32_t base = h264_index_run_table[table_zeros - 1U];
    uint32_t max_run = (zeros_left > 6) ? 14 : table_zeros;
    for (uint32_t run = 0; run <= max_run; run++) {
        uint8_t size = h264_size_run_table[base + run];
        uint8_t code = h264_code_run_table[base + run];
        uint32_t bits = 0;
        if (!h264player_br_peek_bits(br, size, &bits)) {
            return -1;
        }
        if (bits == code) {
            if (!h264player_br_skip_bits(br, size)) {
                return -1;
            }
            return (int)run;
        }
    }
    return -1;
}

static int h264player_cavlc_parse_residual_block(h264_bitreader_t *br, uint8_t nC, uint8_t max_coeff,
                                                 uint8_t *total_coeff_out) {
    uint8_t total_coeff = 0;
    uint8_t trailing_ones = 0;
    if (!h264player_cavlc_decode_coeff_token(br, nC, &total_coeff, &trailing_ones)) {
        LLOGW("h264: cavlc coeff_token fail nC=%u max=%u bit=%u", (unsigned)nC,
              (unsigned)max_coeff, (unsigned)br->bitpos);
        uint32_t align = (uint32_t)(br->bitpos & 7U);
        uint32_t skip_bits = align ? (8U - align) : 8U;
        if (h264player_br_skip_bits(br, skip_bits) || h264player_br_skip_bits(br, 1)) {
            LLOGW("h264: cavlc coeff_token soft skip %ubit bit=%u", (unsigned)skip_bits,
                  (unsigned)br->bitpos);
            if (total_coeff_out) {
                *total_coeff_out = 0;
            }
            return 1;
        }
        return 0;
    }
    if (total_coeff_out) {
        *total_coeff_out = total_coeff;
    }
    if (total_coeff == 0) {
        return 1;
    }
    if (!h264player_cavlc_decode_levels(br, total_coeff, trailing_ones)) {
        LLOGW("h264: cavlc levels fail tc=%u t1=%u bit=%u", (unsigned)total_coeff,
              (unsigned)trailing_ones, (unsigned)br->bitpos);
        if (total_coeff_out) {
            *total_coeff_out = 0;
        }
        return 1;
    }
    uint8_t total_zeros = 0;
    if (!h264player_cavlc_decode_total_zeros(br, total_coeff, max_coeff, nC, &total_zeros)) {
        LLOGW("h264: cavlc total_zeros fail tc=%u max=%u nC=%u bit=%u", (unsigned)total_coeff,
              (unsigned)max_coeff, (unsigned)nC, (unsigned)br->bitpos);
        if (total_coeff_out) {
            *total_coeff_out = 0;
        }
        return 1;
    }
    uint8_t zeros_left = total_zeros;
    for (uint32_t i = 0; i + 1 < total_coeff; i++) {
        if (zeros_left == 0) {
            break;
        }
        int run = h264player_cavlc_decode_run_before(br, zeros_left);
        if (run < 0) {
            uint32_t peek = 0;
            h264player_br_peek_bits(br, 16, &peek);
            LLOGW("h264: cavlc run_before fail tc=%u zl=%u i=%u bit=%u next=0x%04X",
                  (unsigned)total_coeff, (unsigned)zeros_left, (unsigned)i, (unsigned)br->bitpos,
                  (unsigned)peek);
            uint32_t align = (uint32_t)(br->bitpos & 7U);
            uint32_t skip_bits = align ? (8U - align) : 8U;
            if (h264player_br_skip_bits(br, skip_bits) || h264player_br_skip_bits(br, 1)) {
                LLOGW("h264: cavlc run_before soft skip %ubit bit=%u", (unsigned)skip_bits,
                      (unsigned)br->bitpos);
            }
            if (total_coeff_out) {
                *total_coeff_out = 0;
            }
            return 1;
        }
        zeros_left = (uint8_t)(zeros_left - (uint8_t)run);
    }
    return 1;
}

static int h264player_parse_luma_residual(luat_h264player_t *ctx, h264_bitreader_t *br, uint32_t mb_x,
                                          uint32_t mb_y, uint8_t cbp_luma) {
    if (!ctx || !br) {
        return 0;
    }
    for (uint32_t block = 0; block < 16; block++) {
        uint8_t present = (cbp_luma >> (block >> 2)) & 1U;
        if (!present) {
            h264player_set_luma_nz(ctx, mb_x, mb_y, block, 0);
            continue;
        }
        uint8_t nC = h264player_get_luma_nC(ctx, mb_x, mb_y, block);
        uint8_t total_coeff = 0;
        if (!h264player_cavlc_parse_residual_block(br, nC, 16, &total_coeff)) {
            LLOGW("h264: luma residual fail mb=(%u,%u) blk=%u nC=%u bit=%u", (unsigned)mb_x,
                  (unsigned)mb_y, (unsigned)block, (unsigned)nC, (unsigned)br->bitpos);
            if (nC != 0) {
                if (h264player_cavlc_parse_residual_block(br, 0, 16, &total_coeff)) {
                    LLOGW("h264: luma residual fallback nC=0 ok mb=(%u,%u) blk=%u", (unsigned)mb_x,
                          (unsigned)mb_y, (unsigned)block);
                } else {
                    LLOGW("h264: luma residual soft skip mb=(%u,%u) blk=%u", (unsigned)mb_x,
                          (unsigned)mb_y, (unsigned)block);
                    total_coeff = 0;
                }
            } else {
                LLOGW("h264: luma residual soft skip mb=(%u,%u) blk=%u", (unsigned)mb_x,
                      (unsigned)mb_y, (unsigned)block);
                total_coeff = 0;
            }
        }
        h264player_set_luma_nz(ctx, mb_x, mb_y, block, total_coeff);
    }
    return 1;
}

static int h264player_parse_chroma_residual(luat_h264player_t *ctx, h264_bitreader_t *br, uint32_t mb_x,
                                            uint32_t mb_y, uint8_t cbp_chroma) {
    if (!ctx || !br) {
        return 0;
    }
    if (cbp_chroma == 0) {
        for (uint32_t plane = 0; plane < 2; plane++) {
            for (uint32_t blk = 0; blk < 4; blk++) {
                h264player_set_chroma_nz(ctx, mb_x, mb_y, plane, blk, 0);
            }
        }
        return 1;
    }

    for (uint32_t plane = 0; plane < 2; plane++) {
        uint8_t total_coeff = 0;
        if (!h264player_cavlc_parse_residual_block(br, 0xFF, 4, &total_coeff)) {
            LLOGW("h264: chroma dc fail mb=(%u,%u) plane=%u bit=%u", (unsigned)mb_x,
                  (unsigned)mb_y, (unsigned)plane, (unsigned)br->bitpos);
            LLOGW("h264: chroma dc soft skip mb=(%u,%u) plane=%u", (unsigned)mb_x,
                  (unsigned)mb_y, (unsigned)plane);
        }
    }

    if (cbp_chroma == 2) {
        for (uint32_t plane = 0; plane < 2; plane++) {
            for (uint32_t blk = 0; blk < 4; blk++) {
                uint8_t nC = h264player_get_chroma_nC(ctx, mb_x, mb_y, plane, blk);
                uint8_t total_coeff = 0;
                if (!h264player_cavlc_parse_residual_block(br, nC, 15, &total_coeff)) {
                    LLOGW("h264: chroma ac fail mb=(%u,%u) plane=%u blk=%u bit=%u", (unsigned)mb_x,
                          (unsigned)mb_y, (unsigned)plane, (unsigned)blk, (unsigned)br->bitpos);
                    LLOGW("h264: chroma ac soft skip mb=(%u,%u) plane=%u blk=%u", (unsigned)mb_x,
                          (unsigned)mb_y, (unsigned)plane, (unsigned)blk);
                    total_coeff = 0;
                }
                h264player_set_chroma_nz(ctx, mb_x, mb_y, plane, blk, total_coeff);
            }
        }
    } else {
        for (uint32_t plane = 0; plane < 2; plane++) {
            for (uint32_t blk = 0; blk < 4; blk++) {
                h264player_set_chroma_nz(ctx, mb_x, mb_y, plane, blk, 0);
            }
        }
    }
    return 1;
}

static int h264player_read_mvd_pair(h264_bitreader_t *br) {
    int32_t mvd = 0;
    if (!h264player_br_read_se(br, &mvd)) {
        return 0;
    }
    if (!h264player_br_read_se(br, &mvd)) {
        return 0;
    }
    return 1;
}

static int h264player_parse_p_inter_pred(luat_h264player_t *ctx, h264_bitreader_t *br, uint32_t mb_index,
                                         uint32_t mb_type) {
    uint32_t ref_idx = 0;
    if (mb_type == 0) {
        if (ctx->num_ref_idx_l0_active_minus1 > 0) {
            if (!h264player_br_read_ue(br, &ref_idx)) {
                return 0;
            }
        }
        return h264player_read_mvd_pair(br);
    }
    if (mb_type == 1 || mb_type == 2) {
        for (uint32_t part = 0; part < 2; part++) {
            if (ctx->num_ref_idx_l0_active_minus1 > 0) {
                if (!h264player_br_read_ue(br, &ref_idx)) {
                    return 0;
                }
            }
            if (!h264player_read_mvd_pair(br)) {
                return 0;
            }
        }
        return 1;
    }
    if (mb_type == 3 || mb_type == 4) {
        for (uint32_t sub = 0; sub < 4; sub++) {
            uint32_t sub_mb_type = 0;
            if (!h264player_br_read_ue(br, &sub_mb_type)) {
                return 0;
            }
            uint32_t mvd_pairs = 0;
            uint8_t need_ref_idx = 0;
            switch (sub_mb_type) {
                case 0: mvd_pairs = 1; break; /* 8x8 */
                case 1: mvd_pairs = 2; break; /* 8x4 */
                case 2: mvd_pairs = 2; break; /* 4x8 */
                case 3: mvd_pairs = 4; break; /* 4x4 */
                case 4: mvd_pairs = 1; break; /* 8x8 ref0 */
                case 5: mvd_pairs = 2; break; /* 8x4 ref0 */
                case 6: mvd_pairs = 2; break; /* 4x8 ref0 */
                case 7: mvd_pairs = 4; break; /* 4x4 ref0 */
                default:
                    LLOGW("h264: mb%u unsupported P sub_mb_type=%u", (unsigned)mb_index,
                          (unsigned)sub_mb_type);
                    mvd_pairs = 1;
                    need_ref_idx = 1;
                    break;
            }
            if (ctx->num_ref_idx_l0_active_minus1 > 0 &&
                ((mb_type == 3 && (sub_mb_type <= 3 || need_ref_idx)) ||
                 (mb_type == 4 && need_ref_idx))) {
                if (!h264player_br_read_ue(br, &ref_idx)) {
                    return 0;
                }
            }
            for (uint32_t mv = 0; mv < mvd_pairs; mv++) {
                if (!h264player_read_mvd_pair(br)) {
                    return 0;
                }
            }
        }
        return 1;
    }
    return 1;
}

static int h264player_parse_macroblock(luat_h264player_t *ctx, h264_bitreader_t *br, uint32_t mb_index,
                                       uint8_t slice_type) {
    uint32_t mb_x = 0;
    uint32_t mb_y = 0;
    h264player_mb_index_to_xy(ctx, mb_index, &mb_x, &mb_y);

    uint32_t mb_type_ue = 0;
    if (!h264player_br_read_ue(br, &mb_type_ue)) {
        LLOGW("h264: mb%u read mb_type fail bit=%u", (unsigned)mb_index, (unsigned)br->bitpos);
        return 0;
    }
    LLOGI("h264: mb%u type=%u slice=%u bit=%u", (unsigned)mb_index, (unsigned)mb_type_ue,
          (unsigned)slice_type, (unsigned)br->bitpos);

    uint8_t cbp_luma = 0;
    uint8_t cbp_chroma = 0;
    uint32_t coded_block_pattern = 0;
    uint8_t mb_is_intra = 0;
    uint32_t intra_mb_type = 0;

    if (slice_type == 2 || slice_type == 7) {
        if (mb_type_ue > 25) {
            LLOGW("h264: mb%u invalid I mb_type=%u", (unsigned)mb_index, (unsigned)mb_type_ue);
            h264player_fill_mb_gray(ctx, mb_x, mb_y);
            return 1;
        }
        if (mb_type_ue == 0) {
            if (ctx->transform_8x8_mode_flag) {
                uint32_t transform_size_8x8_flag = 0;
                if (!h264player_br_read_bit(br, &transform_size_8x8_flag)) {
                    LLOGW("h264: mb%u transform8x8 flag fail bit=%u", (unsigned)mb_index,
                          (unsigned)br->bitpos);
                    return 0;
                }
                if (transform_size_8x8_flag) {
                    LLOGW("h264: mb%u transform8x8 unsupported", (unsigned)mb_index);
                    return 0;
                }
            }
            for (uint32_t blk = 0; blk < 16; blk++) {
                uint32_t prev_intra4x4_pred_mode_flag = 0;
                if (!h264player_br_read_bit(br, &prev_intra4x4_pred_mode_flag)) {
                    LLOGW("h264: mb%u intra4x4 pred_flag fail blk=%u bit=%u", (unsigned)mb_index,
                          (unsigned)blk, (unsigned)br->bitpos);
                    return 0;
                }
                if (!prev_intra4x4_pred_mode_flag) {
                    uint32_t rem_intra4x4_pred_mode = 0;
                    if (!h264player_br_read_bits(br, 3, &rem_intra4x4_pred_mode)) {
                        LLOGW("h264: mb%u intra4x4 pred_mode fail blk=%u bit=%u", (unsigned)mb_index,
                              (unsigned)blk, (unsigned)br->bitpos);
                        return 0;
                    }
                }
            }
            uint32_t intra_chroma_pred_mode = 0;
            if (!h264player_br_read_ue(br, &intra_chroma_pred_mode)) {
                LLOGW("h264: mb%u intra_chroma_pred_mode fail bit=%u", (unsigned)mb_index,
                      (unsigned)br->bitpos);
                return 0;
            }
            if (!h264player_br_read_ue(br, &coded_block_pattern)) {
                LLOGW("h264: mb%u read cbp fail", (unsigned)mb_index);
                coded_block_pattern = 0;
            }
            if (coded_block_pattern >= 48) {
                LLOGW("h264: mb%u cbp out of range=%u", (unsigned)mb_index, (unsigned)coded_block_pattern);
                coded_block_pattern = 0;
            }
            uint8_t cbp = h264_golomb_to_intra4x4_cbp[coded_block_pattern];
            cbp_luma = cbp & 0x0F;
            cbp_chroma = (cbp >> 4) & 0x03;
            LLOGI("h264: mb%u cbp=%u luma=0x%X chroma=%u bit=%u", (unsigned)mb_index,
                  (unsigned)cbp, (unsigned)cbp_luma, (unsigned)cbp_chroma, (unsigned)br->bitpos);
        } else if (mb_type_ue <= 24) {
            uint32_t intra_chroma_pred_mode = 0;
            if (!h264player_br_read_ue(br, &intra_chroma_pred_mode)) {
                LLOGW("h264: mb%u intra_chroma_pred_mode fail bit=%u", (unsigned)mb_index,
                      (unsigned)br->bitpos);
                return 0;
            }
            uint32_t type_minus1 = mb_type_ue - 1U;
            uint32_t cbp_chroma_code = (type_minus1 / 4U) % 3U;
            uint32_t cbp_luma_code = type_minus1 / 12U;
            cbp_chroma = (uint8_t)cbp_chroma_code;
            cbp_luma = cbp_luma_code ? 0x0F : 0x00;
            LLOGI("h264: mb%u I16x16 cbp_luma_code=%u cbp_chroma=%u", (unsigned)mb_index,
                  (unsigned)cbp_luma_code, (unsigned)cbp_chroma);
        } else if (mb_type_ue == 25) {
            if (!h264player_skip_pcm(ctx, br)) {
                LLOGW("h264: mb%u pcm skip fail bit=%u", (unsigned)mb_index, (unsigned)br->bitpos);
                return 0;
            }
            h264player_fill_mb_gray(ctx, mb_x, mb_y);
            return 1;
        } else {
            LLOGW("h264: unsupported I-slice mb_type=%u", (unsigned)mb_type_ue);
            return 0;
        }
    } else if (slice_type == 0 || slice_type == 5) {
        if (mb_type_ue > 30) {
            LLOGW("h264: mb%u invalid P mb_type=%u", (unsigned)mb_index, (unsigned)mb_type_ue);
            h264player_copy_mb_from_ref(ctx, mb_x, mb_y);
            for (uint32_t block = 0; block < 16; block++) {
                h264player_set_luma_nz(ctx, mb_x, mb_y, block, 0);
            }
            for (uint32_t plane = 0; plane < 2; plane++) {
                for (uint32_t blk = 0; blk < 4; blk++) {
                    h264player_set_chroma_nz(ctx, mb_x, mb_y, plane, blk, 0);
                }
            }
            return 1;
        }
        if (mb_type_ue >= 5) {
            mb_is_intra = 1;
            intra_mb_type = mb_type_ue - 5U;
            if (intra_mb_type == 0) {
                if (ctx->transform_8x8_mode_flag) {
                    uint32_t transform_size_8x8_flag = 0;
                    if (!h264player_br_read_bit(br, &transform_size_8x8_flag)) {
                        LLOGW("h264: mb%u transform8x8 flag fail bit=%u", (unsigned)mb_index,
                              (unsigned)br->bitpos);
                        return 0;
                    }
                    if (transform_size_8x8_flag) {
                        LLOGW("h264: mb%u transform8x8 unsupported", (unsigned)mb_index);
                        return 0;
                    }
                }
                for (uint32_t blk = 0; blk < 16; blk++) {
                    uint32_t prev_intra4x4_pred_mode_flag = 0;
                    if (!h264player_br_read_bit(br, &prev_intra4x4_pred_mode_flag)) {
                        LLOGW("h264: mb%u intra4x4 pred_flag fail blk=%u bit=%u", (unsigned)mb_index,
                              (unsigned)blk, (unsigned)br->bitpos);
                        return 0;
                    }
                    if (!prev_intra4x4_pred_mode_flag) {
                        uint32_t rem_intra4x4_pred_mode = 0;
                        if (!h264player_br_read_bits(br, 3, &rem_intra4x4_pred_mode)) {
                            LLOGW("h264: mb%u intra4x4 pred_mode fail blk=%u bit=%u", (unsigned)mb_index,
                                  (unsigned)blk, (unsigned)br->bitpos);
                            return 0;
                        }
                    }
                }
                uint32_t intra_chroma_pred_mode = 0;
                if (!h264player_br_read_ue(br, &intra_chroma_pred_mode)) {
                    LLOGW("h264: mb%u intra_chroma_pred_mode fail bit=%u", (unsigned)mb_index,
                          (unsigned)br->bitpos);
                    return 0;
                }
                if (!h264player_br_read_ue(br, &coded_block_pattern)) {
                    LLOGW("h264: mb%u read cbp fail", (unsigned)mb_index);
                    coded_block_pattern = 0;
                }
                if (coded_block_pattern >= 48) {
                    LLOGW("h264: mb%u cbp out of range=%u", (unsigned)mb_index, (unsigned)coded_block_pattern);
                    coded_block_pattern = 0;
                }
                uint8_t cbp = h264_golomb_to_intra4x4_cbp[coded_block_pattern];
                cbp_luma = cbp & 0x0F;
                cbp_chroma = (cbp >> 4) & 0x03;
                LLOGI("h264: mb%u cbp=%u luma=0x%X chroma=%u bit=%u", (unsigned)mb_index,
                      (unsigned)cbp, (unsigned)cbp_luma, (unsigned)cbp_chroma, (unsigned)br->bitpos);
            } else if (intra_mb_type <= 24) {
                uint32_t intra_chroma_pred_mode = 0;
                if (!h264player_br_read_ue(br, &intra_chroma_pred_mode)) {
                    LLOGW("h264: mb%u intra_chroma_pred_mode fail bit=%u", (unsigned)mb_index,
                          (unsigned)br->bitpos);
                    return 0;
                }
                uint32_t type_minus1 = intra_mb_type - 1U;
                uint32_t cbp_chroma_code = (type_minus1 / 4U) % 3U;
                uint32_t cbp_luma_code = type_minus1 / 12U;
                cbp_chroma = (uint8_t)cbp_chroma_code;
                cbp_luma = cbp_luma_code ? 0x0F : 0x00;
                LLOGI("h264: mb%u I16x16 cbp_luma_code=%u cbp_chroma=%u", (unsigned)mb_index,
                      (unsigned)cbp_luma_code, (unsigned)cbp_chroma);
            } else if (intra_mb_type == 25) {
                if (!h264player_skip_pcm(ctx, br)) {
                    LLOGW("h264: mb%u pcm skip fail bit=%u", (unsigned)mb_index, (unsigned)br->bitpos);
                    return 0;
                }
                h264player_fill_mb_gray(ctx, mb_x, mb_y);
                return 1;
            } else {
                LLOGW("h264: unsupported P-intra mb_type=%u", (unsigned)mb_type_ue);
                return 0;
            }
        } else if (mb_type_ue == 0 || mb_type_ue == 1 || mb_type_ue == 2 || mb_type_ue == 3 || mb_type_ue == 4) {
            if (!h264player_parse_p_inter_pred(ctx, br, mb_index, mb_type_ue)) {
                LLOGW("h264: mb%u inter pred fail type=%u bit=%u", (unsigned)mb_index,
                      (unsigned)mb_type_ue, (unsigned)br->bitpos);
                h264player_copy_mb_from_ref(ctx, mb_x, mb_y);
                for (uint32_t block = 0; block < 16; block++) {
                    h264player_set_luma_nz(ctx, mb_x, mb_y, block, 0);
                }
                for (uint32_t plane = 0; plane < 2; plane++) {
                    for (uint32_t blk = 0; blk < 4; blk++) {
                        h264player_set_chroma_nz(ctx, mb_x, mb_y, plane, blk, 0);
                    }
                }
                return 1;
            }
        }
        if (!mb_is_intra) {
            if (!h264player_br_read_ue(br, &coded_block_pattern)) {
                LLOGW("h264: mb%u read cbp fail", (unsigned)mb_index);
                coded_block_pattern = 0;
            }
            if (coded_block_pattern >= 48) {
                LLOGW("h264: mb%u cbp out of range=%u", (unsigned)mb_index, (unsigned)coded_block_pattern);
                coded_block_pattern = 0;
            }
            uint8_t cbp = h264_golomb_to_inter_cbp[coded_block_pattern];
            cbp_luma = cbp & 0x0F;
            cbp_chroma = (cbp >> 4) & 0x03;
            LLOGI("h264: mb%u cbp=%u luma=0x%X chroma=%u bit=%u", (unsigned)mb_index,
                  (unsigned)cbp, (unsigned)cbp_luma, (unsigned)cbp_chroma, (unsigned)br->bitpos);
        }
    } else {
        LLOGW("h264: unsupported slice_type=%u", (unsigned)slice_type);
        return 0;
    }

    uint8_t is_i16x16 = 0;
    if (slice_type == 2 || slice_type == 7) {
        if (mb_type_ue >= 1 && mb_type_ue <= 24) {
            is_i16x16 = 1;
        }
    } else if (mb_is_intra) {
        if (intra_mb_type >= 1 && intra_mb_type <= 24) {
            is_i16x16 = 1;
        }
    }

    if ((cbp_luma | cbp_chroma) != 0 || is_i16x16) {
        uint32_t mb_qp_delta = 0;
        if (!h264player_br_read_se(br, (int32_t *)&mb_qp_delta)) {
            LLOGW("h264: mb%u qp_delta fail bit=%u", (unsigned)mb_index, (unsigned)br->bitpos);
            return 0;
        }
        ctx->qp = (uint8_t)((int32_t)ctx->qp + (int32_t)mb_qp_delta);
    }

    if (slice_type == 2 || slice_type == 7 || mb_is_intra) {
        uint32_t intra_type = mb_is_intra ? intra_mb_type : mb_type_ue;
        if (intra_type >= 1 && intra_type <= 24) {
            if (!h264player_cavlc_parse_residual_block(br, 0, 16, NULL)) {
                LLOGW("h264: mb%u luma dc fail bit=%u", (unsigned)mb_index, (unsigned)br->bitpos);
                LLOGW("h264: mb%u luma dc soft skip", (unsigned)mb_index);
            }
            if (cbp_luma) {
                for (uint32_t block = 0; block < 16; block++) {
                    uint8_t nC = h264player_get_luma_nC(ctx, mb_x, mb_y, block);
                    uint8_t total_coeff = 0;
                    if (!h264player_cavlc_parse_residual_block(br, nC, 15, &total_coeff)) {
                        LLOGW("h264: luma ac fail mb=(%u,%u) blk=%u bit=%u", (unsigned)mb_x,
                              (unsigned)mb_y, (unsigned)block, (unsigned)br->bitpos);
                        LLOGW("h264: luma ac soft skip mb=(%u,%u) blk=%u", (unsigned)mb_x,
                              (unsigned)mb_y, (unsigned)block);
                        total_coeff = 0;
                    }
                    h264player_set_luma_nz(ctx, mb_x, mb_y, block, total_coeff);
                }
            } else {
                for (uint32_t block = 0; block < 16; block++) {
                    h264player_set_luma_nz(ctx, mb_x, mb_y, block, 0);
                }
            }
        } else {
            if (!h264player_parse_luma_residual(ctx, br, mb_x, mb_y, cbp_luma)) {
                return 0;
            }
        }
    } else {
        if (!h264player_parse_luma_residual(ctx, br, mb_x, mb_y, cbp_luma)) {
            return 0;
        }
    }

    if (!h264player_parse_chroma_residual(ctx, br, mb_x, mb_y, cbp_chroma)) {
        return 0;
    }

    if (slice_type == 2 || slice_type == 7 || mb_is_intra) {
        h264player_fill_mb_gray(ctx, mb_x, mb_y);
    } else {
        if (mb_type_ue <= 4) {
            h264player_copy_mb_from_ref(ctx, mb_x, mb_y);
        } else {
            h264player_fill_mb_gray(ctx, mb_x, mb_y);
        }
    }
    return 1;
}

static void h264player_fill_remaining_mbs(luat_h264player_t *ctx, uint32_t start_mb, uint8_t slice_type) {
    if (!ctx) {
        return;
    }
    uint32_t mb_count = ctx->mb_width * ctx->mb_height;
    for (uint32_t mb = start_mb; mb < mb_count; mb++) {
        uint32_t mb_x = 0;
        uint32_t mb_y = 0;
        h264player_mb_index_to_xy(ctx, mb, &mb_x, &mb_y);
        for (uint32_t block = 0; block < 16; block++) {
            h264player_set_luma_nz(ctx, mb_x, mb_y, block, 0);
        }
        for (uint32_t plane = 0; plane < 2; plane++) {
            for (uint32_t blk = 0; blk < 4; blk++) {
                h264player_set_chroma_nz(ctx, mb_x, mb_y, plane, blk, 0);
            }
        }
        if (slice_type == 0 || slice_type == 5) {
            h264player_copy_mb_from_ref(ctx, mb_x, mb_y);
        } else {
            h264player_fill_mb_gray(ctx, mb_x, mb_y);
        }
    }
}

static int h264player_parse_slice(luat_h264player_t *ctx, const uint8_t *data, size_t size, uint8_t nal_ref_idc,
                                  uint8_t nal_type) {
    if (!ctx || !data || size == 0) {
        return 0;
    }
    uint8_t *rbsp = NULL;
    size_t rbsp_size = 0;
    if (!h264player_convert_to_rbsp(data, size, &rbsp, &rbsp_size)) {
        LLOGW("h264: slice rbsp convert fail len=%u", (unsigned)size);
        return 0;
    }
    h264_bitreader_t br;
    h264player_br_init(&br, rbsp, rbsp_size);

    uint32_t first_mb_in_slice = 0;
    uint32_t slice_type = 0;
    uint32_t pic_parameter_set_id = 0;
    if (!h264player_br_read_ue(&br, &first_mb_in_slice) ||
        !h264player_br_read_ue(&br, &slice_type) ||
        !h264player_br_read_ue(&br, &pic_parameter_set_id)) {
        LLOGW("h264: slice header ue fail bit=%u", (unsigned)br.bitpos);
        luat_heap_free(rbsp);
        return 0;
    }
    slice_type = slice_type % 5;

    uint32_t frame_num = 0;
    if (!h264player_br_read_bits(&br, ctx->log2_max_frame_num, &frame_num)) {
        LLOGW("h264: frame_num fail bit=%u", (unsigned)br.bitpos);
        luat_heap_free(rbsp);
        return 0;
    }
    ctx->frame_num = frame_num;

    if (ctx->frame_mbs_only_flag == 0) {
        uint32_t field_pic_flag = 0;
        if (!h264player_br_read_bit(&br, &field_pic_flag)) {
            LLOGW("h264: field_pic_flag fail bit=%u", (unsigned)br.bitpos);
            luat_heap_free(rbsp);
            return 0;
        }
        if (field_pic_flag) {
            uint32_t bottom_field_flag = 0;
            if (!h264player_br_read_bit(&br, &bottom_field_flag)) {
                LLOGW("h264: bottom_field_flag fail bit=%u", (unsigned)br.bitpos);
                luat_heap_free(rbsp);
                return 0;
            }
        }
    }

    if (nal_type == 5) {
        uint32_t idr_pic_id = 0;
        if (!h264player_br_read_ue(&br, &idr_pic_id)) {
            LLOGW("h264: idr_pic_id fail bit=%u", (unsigned)br.bitpos);
            luat_heap_free(rbsp);
            return 0;
        }
    }

    if (ctx->pic_order_cnt_type == 0) {
        uint32_t pic_order_cnt_lsb = 0;
        if (!h264player_br_read_bits(&br, ctx->log2_max_pic_order_cnt_lsb, &pic_order_cnt_lsb)) {
            LLOGW("h264: poc_lsb fail bit=%u", (unsigned)br.bitpos);
            luat_heap_free(rbsp);
            return 0;
        }
        if (ctx->pic_order_present_flag) {
            int32_t delta_pic_order_cnt_bottom = 0;
            if (!h264player_br_read_se(&br, &delta_pic_order_cnt_bottom)) {
                LLOGW("h264: delta_poc_bottom fail bit=%u", (unsigned)br.bitpos);
                luat_heap_free(rbsp);
                return 0;
            }
        }
    } else if (ctx->pic_order_cnt_type == 1) {
        if (!ctx->delta_pic_order_always_zero_flag) {
            int32_t delta_pic_order_cnt = 0;
            if (!h264player_br_read_se(&br, &delta_pic_order_cnt)) {
                LLOGW("h264: delta_poc0 fail bit=%u", (unsigned)br.bitpos);
                luat_heap_free(rbsp);
                return 0;
            }
            if (ctx->pic_order_present_flag) {
                if (!h264player_br_read_se(&br, &delta_pic_order_cnt)) {
                    LLOGW("h264: delta_poc1 fail bit=%u", (unsigned)br.bitpos);
                    luat_heap_free(rbsp);
                    return 0;
                }
            }
        }
    }

    if (ctx->redundant_pic_cnt_present_flag) {
        uint32_t redundant_pic_cnt = 0;
        if (!h264player_br_read_ue(&br, &redundant_pic_cnt)) {
            LLOGW("h264: redundant_pic_cnt fail bit=%u", (unsigned)br.bitpos);
            luat_heap_free(rbsp);
            return 0;
        }
    }

    if (slice_type == 1 || slice_type == 6) {
        uint32_t direct_spatial_mv_pred_flag = 0;
        if (!h264player_br_read_bit(&br, &direct_spatial_mv_pred_flag)) {
            LLOGW("h264: direct_mv_pred_flag fail bit=%u", (unsigned)br.bitpos);
            luat_heap_free(rbsp);
            return 0;
        }
    }

    if (slice_type == 0 || slice_type == 5) {
        uint32_t num_ref_idx_active_override_flag = 0;
        if (!h264player_br_read_bit(&br, &num_ref_idx_active_override_flag)) {
            LLOGW("h264: num_ref_idx_override_flag fail bit=%u", (unsigned)br.bitpos);
            luat_heap_free(rbsp);
            return 0;
        }
        if (num_ref_idx_active_override_flag) {
            uint32_t num_ref_idx_l0_active_minus1 = 0;
            if (!h264player_br_read_ue(&br, &num_ref_idx_l0_active_minus1)) {
                LLOGW("h264: num_ref_idx_l0 fail bit=%u", (unsigned)br.bitpos);
                luat_heap_free(rbsp);
                return 0;
            }
            ctx->num_ref_idx_l0_active_minus1 = (uint8_t)num_ref_idx_l0_active_minus1;
        }
    }

    if (!h264player_skip_ref_pic_list_reordering(&br, (uint8_t)slice_type)) {
        LLOGW("h264: ref_pic_list_reordering fail bit=%u", (unsigned)br.bitpos);
        luat_heap_free(rbsp);
        return 0;
    }

    if (((slice_type == 0 || slice_type == 5) && ctx->weighted_pred_flag) ||
        ((slice_type == 1 || slice_type == 6) && ctx->weighted_bipred_idc == 1)) {
        if (!h264player_skip_pred_weight_table(&br, (uint8_t)slice_type, ctx->num_ref_idx_l0_active_minus1,
                                               ctx->num_ref_idx_l1_active_minus1)) {
            LLOGW("h264: pred_weight_table fail bit=%u", (unsigned)br.bitpos);
            luat_heap_free(rbsp);
            return 0;
        }
    }

    if (!h264player_skip_dec_ref_pic_marking(&br, nal_ref_idc, nal_type)) {
        LLOGW("h264: dec_ref_pic_marking fail bit=%u", (unsigned)br.bitpos);
        luat_heap_free(rbsp);
        return 0;
    }

    uint32_t slice_qp_delta = 0;
    if (!h264player_br_read_se(&br, (int32_t *)&slice_qp_delta)) {
        LLOGW("h264: slice_qp_delta fail bit=%u", (unsigned)br.bitpos);
        luat_heap_free(rbsp);
        return 0;
    }
    ctx->qp = (uint8_t)((int32_t)ctx->pic_init_qp + (int32_t)slice_qp_delta);
    if (first_mb_in_slice == 0) {
        if (ctx->nz_luma && ctx->nz_luma_size) {
            memset(ctx->nz_luma, 0, ctx->nz_luma_size);
        }
        if (ctx->nz_chroma && ctx->nz_chroma_size) {
            memset(ctx->nz_chroma, 0, ctx->nz_chroma_size);
        }
    }

    if (ctx->deblocking_filter_control_present_flag) {
        uint32_t disable_deblocking_filter_idc = 0;
        if (!h264player_br_read_ue(&br, &disable_deblocking_filter_idc)) {
            LLOGW("h264: deblock_idc fail bit=%u", (unsigned)br.bitpos);
            luat_heap_free(rbsp);
            return 0;
        }
        if (disable_deblocking_filter_idc != 1) {
            int32_t alpha = 0;
            int32_t beta = 0;
            if (!h264player_br_read_se(&br, &alpha) || !h264player_br_read_se(&br, &beta)) {
                LLOGW("h264: deblock alpha/beta fail bit=%u", (unsigned)br.bitpos);
                luat_heap_free(rbsp);
                return 0;
            }
        }
    }

    if (ctx->entropy_coding_mode_flag) {
        LLOGW("h264: CABAC not supported");
        luat_heap_free(rbsp);
        return 0;
    }

    uint32_t mb_count = ctx->mb_width * ctx->mb_height;
    uint32_t mb_index = first_mb_in_slice;
    while (mb_index < mb_count) {
        if (!h264player_br_more_rbsp_data(&br)) {
            break;
        }
        if (slice_type == 0 || slice_type == 5) {
            uint32_t mb_skip_run = 0;
            if (!h264player_br_read_ue(&br, &mb_skip_run)) {
                LLOGW("h264: mb_skip_run fail bit=%u", (unsigned)br.bitpos);
                luat_heap_free(rbsp);
                return 0;
            }
            if (mb_skip_run > 0) {
                if (mb_index + mb_skip_run > mb_count) {
                    mb_skip_run = mb_count - mb_index;
                }
                for (uint32_t s = 0; s < mb_skip_run; s++) {
                    uint32_t sx = 0;
                    uint32_t sy = 0;
                    h264player_mb_index_to_xy(ctx, mb_index + s, &sx, &sy);
                    for (uint32_t block = 0; block < 16; block++) {
                        h264player_set_luma_nz(ctx, sx, sy, block, 0);
                    }
                    for (uint32_t plane = 0; plane < 2; plane++) {
                        for (uint32_t blk = 0; blk < 4; blk++) {
                            h264player_set_chroma_nz(ctx, sx, sy, plane, blk, 0);
                        }
                    }
                    h264player_copy_mb_from_ref(ctx, sx, sy);
                }
                mb_index += mb_skip_run;
                continue;
            }
        }
        size_t mb_bitpos_before = br.bitpos;
        if (!h264player_parse_macroblock(ctx, &br, mb_index, (uint8_t)slice_type)) {
            if (!h264player_br_more_rbsp_data(&br)) {
                break;
            }
            LLOGW("h264: mb parse fail idx=%u bit=%u", (unsigned)mb_index, (unsigned)br.bitpos);
            h264player_fill_remaining_mbs(ctx, mb_index, (uint8_t)slice_type);
            break;
        }
        if (br.bitpos <= mb_bitpos_before) {
            LLOGW("h264: mb%u bitpos stalled %u->%u, end slice", (unsigned)mb_index,
                  (unsigned)mb_bitpos_before, (unsigned)br.bitpos);
            h264player_fill_remaining_mbs(ctx, mb_index, (uint8_t)slice_type);
            break;
        }
        mb_index++;
    }

    luat_heap_free(rbsp);
    return 1;
}

static int h264player_prepare_frame(luat_h264player_t *ctx) {
    if (!ctx) {
        return 0;
    }
    if (ctx->frame_size == 0 || ctx->mb_width == 0 || ctx->mb_height == 0) {
        LLOGW("h264: invalid frame_size=%u mb=%ux%u", (unsigned)ctx->frame_size,
              (unsigned)ctx->mb_width, (unsigned)ctx->mb_height);
        return 0;
    }
    if (!ctx->frame) {
        ctx->frame = (uint8_t *)luat_heap_malloc(ctx->frame_size);
        if (!ctx->frame) {
            LLOGW("h264: frame alloc fail size=%u", (unsigned)ctx->frame_size);
            return 0;
        }
    }
    if (!ctx->ref_frame) {
        ctx->ref_frame = (uint8_t *)luat_heap_malloc(ctx->frame_size);
        if (!ctx->ref_frame) {
            LLOGW("h264: ref alloc fail size=%u", (unsigned)ctx->frame_size);
            return 0;
        }
        memset(ctx->ref_frame, 0x00, ctx->frame_size);
    }
    if (!ctx->nz_luma) {
        ctx->nz_luma_size = (size_t)ctx->mb_width * ctx->mb_height * 16U;
        ctx->nz_luma = (uint8_t *)luat_heap_malloc(ctx->nz_luma_size);
        if (!ctx->nz_luma) {
            LLOGW("h264: nz_luma alloc fail size=%u", (unsigned)ctx->nz_luma_size);
            return 0;
        }
        memset(ctx->nz_luma, 0, ctx->nz_luma_size);
    }
    if (!ctx->nz_chroma) {
        ctx->nz_chroma_size = (size_t)ctx->mb_width * ctx->mb_height * 8U;
        ctx->nz_chroma = (uint8_t *)luat_heap_malloc(ctx->nz_chroma_size);
        if (!ctx->nz_chroma) {
            LLOGW("h264: nz_chroma alloc fail size=%u", (unsigned)ctx->nz_chroma_size);
            return 0;
        }
        memset(ctx->nz_chroma, 0, ctx->nz_chroma_size);
    }
    return 1;
}

luat_h264player_t *luat_h264player_create(luat_h264player_frame_cb_t cb, void *userdata) {
    luat_h264player_t *ctx = (luat_h264player_t *)luat_heap_malloc(sizeof(luat_h264player_t));
    if (!ctx) {
        return NULL;
    }
    memset(ctx, 0, sizeof(luat_h264player_t));
    ctx->width = LUAT_H264PLAYER_FRAME_WIDTH;
    ctx->height = LUAT_H264PLAYER_FRAME_HEIGHT;
    if (!h264player_check_resolution(ctx->width, ctx->height)) {
        LLOGW("invalid resolution %u x %u", (unsigned)ctx->width, (unsigned)ctx->height);
        luat_heap_free(ctx);
        return NULL;
    }
    ctx->mb_width = (ctx->width + 15U) / 16U;
    ctx->mb_height = (ctx->height + 15U) / 16U;
    ctx->frame_size = (size_t)ctx->width * ctx->height * LUAT_H264PLAYER_PIXEL_BYTES;
    ctx->ref_size = ctx->frame_size;
    ctx->format = LUAT_H264PLAYER_OUTPUT_FORMAT;
    ctx->log2_max_frame_num = 4;
    ctx->log2_max_pic_order_cnt_lsb = 4;
    ctx->pic_init_qp = 26;
    ctx->qp = 26;
    ctx->frame_cb = cb;
    ctx->frame_cb_userdata = userdata;

    return ctx;
}

void luat_h264player_set_callback(luat_h264player_t *ctx, luat_h264player_frame_cb_t cb, void *userdata) {
    if (!ctx) {
        return;
    }
    ctx->frame_cb = cb;
    ctx->frame_cb_userdata = userdata;
}

void luat_h264player_destroy(luat_h264player_t *ctx) {
    if (!ctx) {
        return;
    }
    if (ctx->sps_rbsp) {
        luat_heap_free(ctx->sps_rbsp);
    }
    if (ctx->pps_rbsp) {
        luat_heap_free(ctx->pps_rbsp);
    }
    if (ctx->frame) {
        luat_heap_free(ctx->frame);
    }
    if (ctx->ref_frame) {
        luat_heap_free(ctx->ref_frame);
    }
    if (ctx->nz_luma) {
        luat_heap_free(ctx->nz_luma);
    }
    if (ctx->nz_chroma) {
        luat_heap_free(ctx->nz_chroma);
    }
    luat_heap_free(ctx);
}

LUAT_RET luat_h264player_feed(luat_h264player_t *ctx, const uint8_t *data, size_t len) {
    if (!ctx || !data || len < 4) {
        return LUAT_ERR_FAIL;
    }
    LLOGI("h264: feed len=%u", (unsigned)len);
    int had_frame = 0;
    size_t offset = 0;
    while (offset + 4 <= len) {
        size_t sc_size = 0;
        int sc_pos = h264player_find_start_code(data + offset, len - offset, &sc_size);
        if (sc_pos < 0) {
            LLOGW("h264: start code not found at offset=%u", (unsigned)offset);
            break;
        }
        offset += (size_t)sc_pos + sc_size;
        if (offset >= len) {
            break;
        }
        size_t next_sc_size = 0;
        int next_pos = h264player_find_start_code(data + offset, len - offset, &next_sc_size);
        size_t nal_end = (next_pos < 0) ? len : (offset + (size_t)next_pos);
        if (nal_end > offset) {
            const uint8_t *nal = data + offset;
            size_t nal_len = nal_end - offset;
            if (nal_len >= 1) {
                uint8_t nal_ref_idc = (nal[0] >> 5) & 0x03;
                uint8_t nal_type = nal[0] & 0x1F;
                const uint8_t *payload = nal + 1;
                size_t payload_len = nal_len - 1;
                LLOGI("h264: nal type=%u len=%u", (unsigned)nal_type, (unsigned)payload_len);
                if (nal_type == 7) {
                    if (!h264player_parse_sps(ctx, payload, payload_len)) {
                        LLOGW("h264: parse sps fail len=%u", (unsigned)payload_len);
                        return LUAT_ERR_FAIL;
                    }
                } else if (nal_type == 8) {
                    if (!h264player_parse_pps(ctx, payload, payload_len)) {
                        LLOGW("h264: parse pps fail len=%u", (unsigned)payload_len);
                        return LUAT_ERR_FAIL;
                    }
                } else if (nal_type == 1 || nal_type == 5) {
                    if (!ctx->sps_received || !ctx->pps_received) {
                        LLOGW("h264: slice before SPS/PPS");
                        return LUAT_ERR_FAIL;
                    }
                    if (!h264player_prepare_frame(ctx)) {
                        LLOGW("h264: prepare frame fail");
                        return LUAT_ERR_FAIL;
                    }
                    if (!h264player_parse_slice(ctx, payload, payload_len, nal_ref_idc, nal_type)) {
                        LLOGW("h264: parse slice fail type=%u len=%u", (unsigned)nal_type,
                              (unsigned)payload_len);
                        if (nal_type == 5) {
                            if (had_frame) {
                                break;
                            }
                            return LUAT_ERR_FAIL;
                        }
                        continue;
                    }
                    memcpy(ctx->ref_frame, ctx->frame, ctx->frame_size);
                    ctx->frame_ready = 1;
                    if (ctx->frame_cb) {
                        ctx->frame_cb(ctx->frame_cb_userdata, ctx->frame, ctx->frame_size,
                                      ctx->width, ctx->height, ctx->format);
                    }
                    had_frame = 1;
                }
            }
        }
        offset = nal_end;
    }
    return LUAT_ERR_OK;
}

int luat_h264player_get_frame(luat_h264player_t *ctx, const uint8_t **out, size_t *out_len) {
    if (!ctx || !out || !out_len) {
        return 0;
    }
    if (!ctx->frame_ready) {
        return 0;
    }
    *out = ctx->frame;
    *out_len = ctx->frame_size;
    ctx->frame_ready = 0;
    return 1;
}

uint16_t luat_h264player_get_width(luat_h264player_t *ctx) {
    return ctx ? ctx->width : 0;
}

uint16_t luat_h264player_get_height(luat_h264player_t *ctx) {
    return ctx ? ctx->height : 0;
}

uint8_t luat_h264player_get_format(luat_h264player_t *ctx) {
    return ctx ? ctx->format : 0;
}
