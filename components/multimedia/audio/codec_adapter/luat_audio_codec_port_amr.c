#if 0
#include "luat_base.h"
#include "luat_common_api.h"
#include "luat_audio_core.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "luat_amr"
#include "luat_log.h"

#include "interf_dec.h"
#include "interf_enc.h"
#include "dec_if.h"

static const uint8_t amr_nb_byte_len[16] = {12, 13, 15, 17, 19, 20, 26, 31, 5, 0, 0, 0, 0, 0, 0, 0};
static const uint8_t amr_wb_byte_len[16] = {17, 23, 32, 36, 40, 46, 50, 58, 60, 5, 0, 0, 0, 0, 0, 0};

typedef void (*amr_decode_fun_t)(void* state, const unsigned char* in, short* out, int bfi);
typedef int (*amr_encode_fun_t)(void* state, uint8_t mode, const short* speech, unsigned char* out, int forceSpeech);

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

int luat_audio_amr_wb_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info)
{
    if (input_buffer->pos < 9) {
        *jump_offset_bytes = 0;
        *need_bytes = 9;
        info->sample_rate = 0;
        return LUAT_ERROR_NONE;
    }

    if (!memcmp(input_buffer->data, "#!AMR-WB\n", 9)) {
        info->channel_nums = 1;
        info->data_align = 2;
        info->is_signed = 1;
        *jump_offset_bytes = 9;
        *need_bytes = 0;
        info->sample_rate = 16000;
    } else {
        return -LUAT_ERROR_PARAM_INVALID;
    }

    return LUAT_ERROR_NONE;
}


static int _amr_codec_init(luat_audio_data_codec_t* codec, uint8_t is_encode) {
    if (is_encode) {
        if (codec->encode_ctx) {
            return LUAT_ERROR_NONE;
        }
        if (16000 == codec->common_param.sample_rate) {
            
        } else {
            codec->encode_ctx = Encoder_Interface_init(0);
        }
        if (!codec->encode_ctx) {
            return -LUAT_ERROR_NO_MEMORY;
        }
    } else {
        if (codec->decode_ctx) {
            return LUAT_ERROR_NONE;
        }
        if (16000 == codec->common_param.sample_rate) {
            codec->decode_ctx = D_IF_init();
        } else {
            codec->decode_ctx = Decoder_Interface_init();
        }
        if (!codec->decode_ctx) {
            return -LUAT_ERROR_NO_MEMORY;
        }
    }
    return LUAT_ERROR_NONE;
}

static void _amr_codec_deinit(luat_audio_data_codec_t* codec) {
    if (codec->encode_ctx) {
        if (16000 == codec->common_param.sample_rate) {
            
        } else {
            Encoder_Interface_exit(codec->encode_ctx);
        }
        codec->encode_ctx = NULL;
    } 
    if (codec->decode_ctx) {
        if (16000 == codec->common_param.sample_rate) {
            D_IF_exit(codec->decode_ctx);
        } else {
            Decoder_Interface_exit(codec->decode_ctx); 
        }
        codec->decode_ctx = NULL;
    }
}

static void _amr_codec_pre_decode(luat_audio_data_codec_t* codec, const uint8_t *input, uint32_t input_size, uint32_t *frame_size_bytes)
{
    const uint8_t *table = NULL;
    if (16000 == codec->common_param.sample_rate) {
        table = amr_wb_byte_len;   
    } else {
        table = amr_nb_byte_len;
    }
    *frame_size_bytes = table[(input[0] >> 3) & 0x0f] + 1;
}

static int _amr_codec_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, 
                  uint32_t *decoded_output_size, uint32_t *decoded_used_size)
{
    amr_decode_fun_t decode_if = NULL;
    const uint8_t *table = NULL;
    uint32_t frame_byte;
    if (16000 == codec->common_param.sample_rate) {
        decode_if = D_IF_decode;
        table = amr_wb_byte_len;
        frame_byte = 640;
        
    } else {
        decode_if = Decoder_Interface_Decode;
        table = amr_nb_byte_len;
        frame_byte = 320;
    }
    memset(output, 0, frame_byte);
    *decoded_used_size = table[(input[0] >> 3) & 0x0f] + 1;
    decode_if(codec->decode_ctx, input, (short*)output, 0);
    *decoded_output_size = frame_byte;
    return LUAT_ERROR_NONE;
}

static int _amr_codec_make_head(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info, uint32_t total_len, luat_buffer_t *out_buffer)
{
    if (16000 == info->sample_rate) {
        luat_buffer_write(out_buffer, "#!AMR-WB\n", 9);
        
    } else {
        luat_buffer_write(out_buffer, "#!AMR\n", 6);
    }
    return LUAT_ERROR_NONE;
}

static int _amr_codec_encode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size)
{
    uint32_t out_len = 0;
    if (16000 == codec->common_param.sample_rate) {
        *encoded_used_size = 640;    
    } else {
        out_len = Encoder_Interface_Encode(codec->encode_ctx, codec->param.amr_param.encode_speed, (int16_t*)input, output, 0);
        *encoded_used_size = 320;
    }
    *encoded_output_size = out_len;
    return LUAT_ERROR_NONE;
}


const luat_audio_data_codec_opts_t luat_audio_data_codec_amr_nb_opts = {
    .init = _amr_codec_init,
    .deinit = _amr_codec_deinit,
    .get_play_info = luat_audio_amr_nb_get_play_info,
    .pre_decode = _amr_codec_pre_decode,
    .decode = _amr_codec_decode,
    .make_head = _amr_codec_make_head,
    .encode = _amr_codec_encode,
    .decode_min_input_len = 0,
    .decode_max_output_len = 320,
    .encode_min_input_len = 320,
    .encode_max_output_len = 32,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_AMR_NB,
    .is_reentrant = 1,
    .is_hardware = 0,
    .support_detect = 1,
};

const luat_audio_data_codec_opts_t luat_audio_data_codec_amr_wb_opts = {
    .init = _amr_codec_init,
    .deinit = _amr_codec_deinit,
    .get_play_info = luat_audio_amr_wb_get_play_info,
    .pre_decode = _amr_codec_pre_decode,
    .decode = _amr_codec_decode,
    .make_head = _amr_codec_make_head,
    .encode = _amr_codec_encode,
    .tts_decode = NULL,
    .tts_set_param = NULL,
    .decode_min_input_len = 0,
    .decode_max_output_len = 640,
    .encode_min_input_len = 640,
    .encode_max_output_len = 61,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_AMR_WB,
    .is_reentrant = 1,
    .is_hardware = 0,
    .support_detect = 1,
};
#endif