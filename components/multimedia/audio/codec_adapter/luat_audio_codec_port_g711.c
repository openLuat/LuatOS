#include "luat_base.h"
#include "luat_audio_core.h"
#include "luat_mem.h"
#include "g711_codec/g711_codec.h"
#include "luat_multimedia_codec.h"

int _g711_codec_init(luat_audio_data_codec_t* codec, uint8_t is_encode) {
    if (!codec) return -LUAT_ERROR_PARAM_INVALID;
    if (codec->opts->type != LUAT_AUDIO_DATA_CODEC_TYPE_G711_ULAW && codec->opts->type != LUAT_AUDIO_DATA_CODEC_TYPE_G711_ALAW) {
        return -LUAT_ERROR_PARAM_INVALID;
    }

    uint8_t type = (codec->opts->type == LUAT_AUDIO_DATA_CODEC_TYPE_G711_ULAW) ? LUAT_MULTIMEDIA_DATA_TYPE_ULAW : LUAT_MULTIMEDIA_DATA_TYPE_ALAW;

    if (is_encode) {
        if (codec->encode_ctx) {
            return LUAT_ERROR_NONE;  // 已经初始化过编码器
        }
        codec->encode_ctx = g711_encoder_create(type);
    } else {
        if (codec->decode_ctx) {
            return LUAT_ERROR_NONE;  // 已经初始化过解码器
        }
        codec->decode_ctx = g711_decoder_create(type);
    }
    return LUAT_ERROR_NONE;
}

static void _g711_codec_deinit(luat_audio_data_codec_t* codec) {
    if (!codec) return;
    if (codec->encode_ctx) {
        g711_encoder_destroy(codec->encode_ctx);
        codec->encode_ctx = NULL;
    } 
    if (codec->decode_ctx) {
        g711_decoder_destroy(codec->decode_ctx);
        codec->decode_ctx = NULL;
    }
}

static int _g711_codec_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, 
                  uint32_t *decoded_output_size, uint32_t *decoded_used_size) {
    if (!codec || !codec->decode_ctx || !input || !output || !decoded_output_size || !decoded_used_size) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    int ret = g711_decoder_get_data(codec->decode_ctx, input, input_size, (int16_t*)output, decoded_output_size, decoded_used_size);
    if (ret <= 0) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    return LUAT_ERROR_NONE;
}

static int _g711_codec_encode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size) {
    if (!codec || !codec->encode_ctx || !input || !output || !encoded_used_size || !encoded_output_size) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    int ret = g711_encoder_get_data(codec->encode_ctx, input, input_size, output, encoded_output_size);
    if (ret <= 0) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    return LUAT_ERROR_NONE;
}


const luat_audio_data_codec_opts_t luat_audio_data_codec_g711_ulaw_opts = {
    .init = _g711_codec_init,
    .deinit = _g711_codec_deinit,
    .get_play_info = NULL,
    .pre_decode = NULL,
    .decode = _g711_codec_decode,
    .make_head = NULL,
    .encode = _g711_codec_encode,
    .decode_min_input_len = 160,
    .decode_max_output_len = 320,
    .encode_min_input_len = 160,
    .encode_max_output_len = 160,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_G711_ULAW,
    .is_reentrant = 1,
    .is_hardware = 0,
    .support_detect = 0,
};

const luat_audio_data_codec_opts_t luat_audio_data_codec_g711_alaw_opts = {
    .init = _g711_codec_init,
    .deinit = _g711_codec_deinit,
    .get_play_info = NULL,
    .pre_decode = NULL,
    .decode = _g711_codec_decode,
    .make_head = NULL,
    .encode = _g711_codec_encode,
    .decode_min_input_len = 160,
    .decode_max_output_len = 320,
    .encode_min_input_len = 160,
    .encode_max_output_len = 160,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_G711_ALAW,
    .is_reentrant = 1,
    .is_hardware = 0,
    .support_detect = 0,
};
