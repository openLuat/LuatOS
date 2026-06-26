#include "luat_base.h"
#include "luat_common_api.h"
#include "luat_audio_core.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "luat_amr"
#include "luat_log.h"

#define AMRNB_WRAPPER_INTERNAL
#include <sp_dec.h>
#include <amrdecode.h>
#include <amrencode.h>
#include "interf_dec.h"
#include "interf_enc.h"
#include <stdlib.h>

struct encoder_state {
	void* encCtx;
	void* pidSyncCtx;
};

static const uint8_t amr_nb_byte_len[16] = {12, 13, 15, 17, 19, 20, 26, 31, 5, 0, 0, 0, 0, 0, 0, 0};

int luat_audio_amr_nb_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info)
{
    if (input_buffer->pos < 6) {
        *jump_offset_bytes = 0;
        *need_bytes = 6;
        info->sample_rate = 0;
        return LUAT_ERROR_NONE;
    }
    if (!memcmp(input_buffer->data, "#!AMR\n", 6)) {
        info->channel_nums = 1;
        info->data_align = 2;
        info->is_signed = 1;
        info->sample_rate = 8000;
        *jump_offset_bytes = 6;
        *need_bytes = 0;
    } else {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    return LUAT_ERROR_NONE;
}

void luat_audio_codec_amr_nb_set_record_info(struct luat_audio_data_codec *codec, luat_audio_common_param_t *info)
{
    if (info->sample_rate != 8000) {
        info->sample_rate = 8000;
    }
    if (info->channel_nums != 1) {
        info->channel_nums = 1;
    }
    if (info->data_align != 2) {
        info->data_align = 2;
    }
    if (info->is_signed != 1) {
        info->is_signed = 1;
    }
    codec->common_param.sample_rate = info->sample_rate;
    codec->common_param.channel_nums = info->channel_nums;
    codec->common_param.data_align = info->data_align;
    codec->common_param.is_signed = info->is_signed;
    codec->common_param.one_frame_sample_cnt = 160;
    codec->common_param.one_frame_bytes = 320;
}

int luat_audio_codec_amr_nb_make_head(luat_audio_data_codec_t* codec, uint32_t total_len, luat_buffer_t *out_buffer)
{
    luat_buffer_write(out_buffer, "#!AMR\n", 6);
    return LUAT_ERROR_NONE;
}

void luat_audio_codec_amr_nb_pre_decode(luat_audio_data_codec_t* codec, const uint8_t *input, uint32_t input_size, uint32_t *frame_size_bytes)
{
    *frame_size_bytes = amr_nb_byte_len[(input[0] >> 3) & 0x0f] + 1;
}

static int _amr_codec_init(luat_audio_data_codec_t* codec, uint8_t is_encode) {
    if (is_encode) {
        if (codec->encode_ctx) {
            return LUAT_ERROR_NONE;
        }
	    struct encoder_state* state = (struct encoder_state*) luat_heap_malloc(sizeof(struct encoder_state));
	    AMREncodeInit(&state->encCtx, &state->pidSyncCtx, 1);
        codec->encode_ctx = state;
        if (!codec->encode_ctx) {
            return -LUAT_ERROR_NO_MEMORY;
        }
        codec->param.amr_encode_speed = 7;
        codec->param.dtx_enable = 1;
    } else {
        if (codec->decode_ctx) {
            return LUAT_ERROR_NONE;
        }
        GSMInitDecode(&codec->decode_ctx, (int8*)"Decoder");
        if (!codec->decode_ctx) {
            return -LUAT_ERROR_NO_MEMORY;
        }
    }
    return LUAT_ERROR_NONE;
}

static void _amr_codec_deinit(luat_audio_data_codec_t* codec) {
    if (codec->encode_ctx) {
        struct encoder_state* state = (struct encoder_state*)codec->encode_ctx;
        AMREncodeExit(&state->encCtx, &state->pidSyncCtx);
        luat_heap_free(codec->encode_ctx);
        codec->encode_ctx = NULL;
    } 
    if (codec->decode_ctx) {
        GSMDecodeFrameExit(&codec->decode_ctx);
        codec->decode_ctx = NULL;
    }
}



static int _amr_codec_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, 
                  uint32_t *decoded_output_size, uint32_t *decoded_used_size)
{
    memset(output, 0, 320);
    *decoded_used_size = amr_nb_byte_len[(input[0] >> 3) & 0x0f] + 1;
	unsigned char type = (input[0] >> 3) & 0x0f;
	AMRDecode(codec->decode_ctx, (enum Frame_Type_3GPP) type, (UWord8*)&input[1], (Word16*)output, MIME_IETF);
    *decoded_output_size = 320;
    return LUAT_ERROR_NONE;
}


static int _amr_codec_encode(luat_audio_data_codec_t* codec,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size)
{
    uint32_t out_len = 0;
	struct encoder_state* state = (struct encoder_state*) codec->encode_ctx;
	enum Frame_Type_3GPP frame_type = (enum Frame_Type_3GPP) codec->param.amr_encode_speed;
    out_len = AMREncode(state->encCtx, state->pidSyncCtx, codec->param.amr_encode_speed, (Word16*) input, output, &frame_type, AMR_TX_IETF);
	output[0] |= 0x04;
    *encoded_output_size = out_len;
    *encoded_used_size = 320;
    return LUAT_ERROR_NONE;
}


const luat_audio_data_codec_opts_t luat_audio_data_codec_amr_nb_opts = {
    .init = _amr_codec_init,
    .deinit = _amr_codec_deinit,
    .get_play_info = luat_audio_amr_nb_get_play_info,
    .set_record_info = luat_audio_codec_amr_nb_set_record_info,
    .pre_decode = luat_audio_codec_amr_nb_pre_decode,
    .decode = _amr_codec_decode,
    .make_head = luat_audio_codec_amr_nb_make_head,
    .encode = _amr_codec_encode,
    .decode_min_input_len = 1,
    .decode_max_output_len = 320,
    .encode_min_input_len = 320,
    .encode_max_output_len = 32,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_AMR_NB,
    .is_hardware = 0,
    .support_detect = 1,
    .encode_raw_mode = 0,
};
