#include "luat_base.h"
#include "luat_common_api.h"
#include "luat_audio_core.h"
#include "luat_mem.h"
#include <stdint.h>

#define LUAT_LOG_TAG "luat_speex"
#include "luat_log.h"

#ifdef LUAT_SUPPORT_SPEEX

#include "speex/speex.h"

/* Frame sizes in samples */
#define SPEEX_NB_FRAME_SAMPLES   160
#define SPEEX_WB_FRAME_SAMPLES   320
#define SPEEX_UWB_FRAME_SAMPLES  640

/* Max encoded frame sizes (bytes) + 2-byte length header */
#define SPEEX_NB_MAX_ENCODED     202
#define SPEEX_WB_MAX_ENCODED     402
#define SPEEX_UWB_MAX_ENCODED    802

/* PCM output sizes (bytes) */
#define SPEEX_NB_PCM_BYTES       (SPEEX_NB_FRAME_SAMPLES * 2)   /* 320 */
#define SPEEX_WB_PCM_BYTES       (SPEEX_WB_FRAME_SAMPLES * 2)   /* 640 */
#define SPEEX_UWB_PCM_BYTES      (SPEEX_UWB_FRAME_SAMPLES * 2)  /* 1280 */

typedef struct {
    void *enc_state;
    void *dec_state;
    SpeexBits enc_bits;
    SpeexBits dec_bits;
    uint8_t mode;       /* 0=NB, 1=WB, 2=UWB */
    int quality;
    uint8_t enc_inited;
    uint8_t dec_inited;
} speex_v2_ctx_t;

static const SpeexMode* _speex_get_mode(uint8_t mode) {
    switch (mode) {
        case 0: return &speex_nb_mode;
        case 1: return &speex_wb_mode;
        case 2: return &speex_uwb_mode;
        default: return &speex_nb_mode;
    }
}

static uint32_t _speex_get_frame_samples(uint8_t mode) {
    switch (mode) {
        case 0: return SPEEX_NB_FRAME_SAMPLES;
        case 1: return SPEEX_WB_FRAME_SAMPLES;
        case 2: return SPEEX_UWB_FRAME_SAMPLES;
        default: return SPEEX_NB_FRAME_SAMPLES;
    }
}

static uint32_t _speex_get_sample_rate(uint8_t mode) {
    switch (mode) {
        case 0: return 8000;
        case 1: return 16000;
        case 2: return 32000;
        default: return 8000;
    }
}

/*======================== NB mode ========================*/

static int _speex_nb_init(luat_audio_data_codec_t *codec, uint8_t is_encode) {
    speex_v2_ctx_t *ctx;
    if (is_encode) {
        if (codec->encode_ctx) return LUAT_ERROR_NONE;
        ctx = (speex_v2_ctx_t*)luat_heap_malloc(sizeof(speex_v2_ctx_t));
        if (!ctx) return -LUAT_ERROR_NO_MEMORY;
        memset(ctx, 0, sizeof(speex_v2_ctx_t));
        ctx->mode = 0;
        ctx->quality = 8;
        speex_bits_init(&ctx->enc_bits);
        ctx->enc_state = speex_encoder_init(&speex_nb_mode);
        if (!ctx->enc_state) {
            speex_bits_destroy(&ctx->enc_bits);
            luat_heap_free(ctx);
            return -LUAT_ERROR_NO_MEMORY;
        }
        speex_encoder_ctl(ctx->enc_state, SPEEX_SET_QUALITY, &ctx->quality);
        int complexity = 3;
        speex_encoder_ctl(ctx->enc_state, SPEEX_SET_COMPLEXITY, &complexity);
        ctx->enc_inited = 1;
        codec->encode_ctx = ctx;
    } else {
        if (codec->decode_ctx) return LUAT_ERROR_NONE;
        ctx = (speex_v2_ctx_t*)luat_heap_malloc(sizeof(speex_v2_ctx_t));
        if (!ctx) return -LUAT_ERROR_NO_MEMORY;
        memset(ctx, 0, sizeof(speex_v2_ctx_t));
        ctx->mode = 0;
        speex_bits_init(&ctx->dec_bits);
        ctx->dec_state = speex_decoder_init(&speex_nb_mode);
        if (!ctx->dec_state) {
            speex_bits_destroy(&ctx->dec_bits);
            luat_heap_free(ctx);
            return -LUAT_ERROR_NO_MEMORY;
        }
        int enh = 1;
        speex_decoder_ctl(ctx->dec_state, SPEEX_SET_ENH, &enh);
        ctx->dec_inited = 1;
        codec->decode_ctx = ctx;
    }
    return LUAT_ERROR_NONE;
}

static void _speex_nb_deinit(luat_audio_data_codec_t *codec) {
    if (codec->encode_ctx) {
        speex_v2_ctx_t *ctx = (speex_v2_ctx_t*)codec->encode_ctx;
        if (ctx->enc_state) speex_encoder_destroy(ctx->enc_state);
        if (ctx->enc_inited) speex_bits_destroy(&ctx->enc_bits);
        luat_heap_free(ctx);
        codec->encode_ctx = NULL;
    }
    if (codec->decode_ctx) {
        speex_v2_ctx_t *ctx = (speex_v2_ctx_t*)codec->decode_ctx;
        if (ctx->dec_state) speex_decoder_destroy(ctx->dec_state);
        if (ctx->dec_inited) speex_bits_destroy(&ctx->dec_bits);
        luat_heap_free(ctx);
        codec->decode_ctx = NULL;
    }
}

static int _speex_nb_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer,
    uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info) {
    (void)now_file_pos;
    /* Speex raw stream: no file header, start from offset 0 */
    if (input_buffer->pos < 2) {
        *jump_offset_bytes = 0;
        *need_bytes = 2;
        info->sample_rate = 0;
        return LUAT_ERROR_NONE;
    }
    info->channel_nums = 1;
    info->data_align = 2;
    info->is_signed = 1;
    info->sample_rate = 8000;
    info->one_frame_sample_cnt = SPEEX_NB_FRAME_SAMPLES;
    info->one_frame_bytes = SPEEX_NB_PCM_BYTES;
    *jump_offset_bytes = 0;
    *need_bytes = 0;
    return LUAT_ERROR_NONE;
}

static void _speex_nb_set_record_info(struct luat_audio_data_codec *codec, luat_audio_common_param_t *info) {
    info->sample_rate = 8000;
    info->channel_nums = 1;
    info->data_align = 2;
    info->is_signed = 1;
    codec->common_param.sample_rate = 8000;
    codec->common_param.channel_nums = 1;
    codec->common_param.data_align = 2;
    codec->common_param.is_signed = 1;
    codec->common_param.one_frame_sample_cnt = SPEEX_NB_FRAME_SAMPLES;
    codec->common_param.one_frame_bytes = SPEEX_NB_PCM_BYTES;
}

static void _speex_nb_pre_decode(luat_audio_data_codec_t* codec, const uint8_t *input, uint32_t input_size, uint32_t *frame_size_bytes) {
    (void)codec;
    if (input_size < 2) {
        *frame_size_bytes = 2;
        return;
    }
    uint16_t len = (uint16_t)((input[0] << 8) | input[1]);
    *frame_size_bytes = 2 + len;
}

static int _speex_nb_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
    const uint8_t *input, uint32_t input_size,
    uint8_t *output, uint32_t *decoded_output_size, uint32_t *decoded_used_size) {
    (void)info;
    speex_v2_ctx_t *ctx = (speex_v2_ctx_t*)codec->decode_ctx;
    if (!ctx || !ctx->dec_state) return -LUAT_ERROR_PARAM_INVALID;

    if (input_size < 2) return -LUAT_ERROR_PARAM_INVALID;
    uint16_t enc_len = (uint16_t)((input[0] << 8) | input[1]);
    if (input_size < (uint32_t)(2 + enc_len)) return -LUAT_ERROR_PARAM_INVALID;

    speex_bits_read_from(&ctx->dec_bits, (const char*)(input + 2), (int)enc_len);
    int ret = speex_decode_int(ctx->dec_state, &ctx->dec_bits, (spx_int16_t*)output);
    if (ret != 0) {
        memset(output, 0, SPEEX_NB_PCM_BYTES);
    }

    *decoded_output_size = SPEEX_NB_PCM_BYTES;
    *decoded_used_size = 2 + enc_len;
    return LUAT_ERROR_NONE;
}

static int _speex_nb_encode(luat_audio_data_codec_t* codec,
    const uint8_t *input, uint32_t input_size,
    uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size) {
    speex_v2_ctx_t *ctx = (speex_v2_ctx_t*)codec->encode_ctx;
    if (!ctx || !ctx->enc_state) return -LUAT_ERROR_PARAM_INVALID;
    if (input_size < SPEEX_NB_PCM_BYTES) return -LUAT_ERROR_PARAM_INVALID;

    speex_bits_reset(&ctx->enc_bits);
    int ret = speex_encode_int(ctx->enc_state, (spx_int16_t*)input, &ctx->enc_bits);
    if (ret < 0) return -LUAT_ERROR_OPERATION_FAILED;

    int nb_bytes = speex_bits_write(&ctx->enc_bits, (char*)(output + 2), SPEEX_NB_MAX_ENCODED - 2);
    if (nb_bytes <= 0) return -LUAT_ERROR_OPERATION_FAILED;

    output[0] = (uint8_t)((nb_bytes >> 8) & 0xFF);
    output[1] = (uint8_t)(nb_bytes & 0xFF);

    *encoded_used_size = SPEEX_NB_PCM_BYTES;
    *encoded_output_size = 2 + (uint32_t)nb_bytes;
    return LUAT_ERROR_NONE;
}

static int _speex_nb_make_head(luat_audio_data_codec_t* codec, uint32_t total_len, luat_buffer_t *out_buffer) {
    (void)codec; (void)total_len; (void)out_buffer;
    /* Speex raw stream has no file header */
    return LUAT_ERROR_NONE;
}

const luat_audio_data_codec_opts_t luat_audio_data_codec_speex_nb_opts = {
    .init = _speex_nb_init,
    .deinit = _speex_nb_deinit,
    .get_play_info = _speex_nb_get_play_info,
    .set_record_info = _speex_nb_set_record_info,
    .pre_decode = _speex_nb_pre_decode,
    .decode = _speex_nb_decode,
    .make_head = _speex_nb_make_head,
    .encode = _speex_nb_encode,
    .decode_min_input_len = 0,
    .decode_max_output_len = SPEEX_NB_PCM_BYTES,
    .encode_min_input_len = SPEEX_NB_PCM_BYTES,
    .encode_max_output_len = SPEEX_NB_MAX_ENCODED,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_SPEEX_NB,
    .is_hardware = 0,
    .support_detect = 0,
    .encode_raw_mode = 0,
};

/*======================== WB mode ========================*/

static int _speex_wb_init(luat_audio_data_codec_t *codec, uint8_t is_encode) {
    speex_v2_ctx_t *ctx;
    if (is_encode) {
        if (codec->encode_ctx) return LUAT_ERROR_NONE;
        ctx = (speex_v2_ctx_t*)luat_heap_malloc(sizeof(speex_v2_ctx_t));
        if (!ctx) return -LUAT_ERROR_NO_MEMORY;
        memset(ctx, 0, sizeof(speex_v2_ctx_t));
        ctx->mode = 1;
        ctx->quality = 8;
        speex_bits_init(&ctx->enc_bits);
        ctx->enc_state = speex_encoder_init(&speex_wb_mode);
        if (!ctx->enc_state) {
            speex_bits_destroy(&ctx->enc_bits);
            luat_heap_free(ctx);
            return -LUAT_ERROR_NO_MEMORY;
        }
        speex_encoder_ctl(ctx->enc_state, SPEEX_SET_QUALITY, &ctx->quality);
        int complexity = 3;
        speex_encoder_ctl(ctx->enc_state, SPEEX_SET_COMPLEXITY, &complexity);
        ctx->enc_inited = 1;
        codec->encode_ctx = ctx;
    } else {
        if (codec->decode_ctx) return LUAT_ERROR_NONE;
        ctx = (speex_v2_ctx_t*)luat_heap_malloc(sizeof(speex_v2_ctx_t));
        if (!ctx) return -LUAT_ERROR_NO_MEMORY;
        memset(ctx, 0, sizeof(speex_v2_ctx_t));
        ctx->mode = 1;
        speex_bits_init(&ctx->dec_bits);
        ctx->dec_state = speex_decoder_init(&speex_wb_mode);
        if (!ctx->dec_state) {
            speex_bits_destroy(&ctx->dec_bits);
            luat_heap_free(ctx);
            return -LUAT_ERROR_NO_MEMORY;
        }
        int enh = 1;
        speex_decoder_ctl(ctx->dec_state, SPEEX_SET_ENH, &enh);
        ctx->dec_inited = 1;
        codec->decode_ctx = ctx;
    }
    return LUAT_ERROR_NONE;
}

static void _speex_wb_deinit(luat_audio_data_codec_t *codec) {
    _speex_nb_deinit(codec);  /* same logic */
}

static int _speex_wb_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer,
    uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info) {
    (void)now_file_pos;
    if (input_buffer->pos < 2) {
        *jump_offset_bytes = 0;
        *need_bytes = 2;
        info->sample_rate = 0;
        return LUAT_ERROR_NONE;
    }
    info->channel_nums = 1;
    info->data_align = 2;
    info->is_signed = 1;
    info->sample_rate = 16000;
    info->one_frame_sample_cnt = SPEEX_WB_FRAME_SAMPLES;
    info->one_frame_bytes = SPEEX_WB_PCM_BYTES;
    *jump_offset_bytes = 0;
    *need_bytes = 0;
    return LUAT_ERROR_NONE;
}

static void _speex_wb_set_record_info(struct luat_audio_data_codec *codec, luat_audio_common_param_t *info) {
    info->sample_rate = 16000;
    info->channel_nums = 1;
    info->data_align = 2;
    info->is_signed = 1;
    codec->common_param.sample_rate = 16000;
    codec->common_param.channel_nums = 1;
    codec->common_param.data_align = 2;
    codec->common_param.is_signed = 1;
    codec->common_param.one_frame_sample_cnt = SPEEX_WB_FRAME_SAMPLES;
    codec->common_param.one_frame_bytes = SPEEX_WB_PCM_BYTES;
}

static void _speex_wb_pre_decode(luat_audio_data_codec_t* codec, const uint8_t *input, uint32_t input_size, uint32_t *frame_size_bytes) {
    (void)codec;
    if (input_size < 2) {
        *frame_size_bytes = 2;
        return;
    }
    uint16_t len = (uint16_t)((input[0] << 8) | input[1]);
    *frame_size_bytes = 2 + len;
}

static int _speex_wb_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
    const uint8_t *input, uint32_t input_size,
    uint8_t *output, uint32_t *decoded_output_size, uint32_t *decoded_used_size) {
    (void)info;
    speex_v2_ctx_t *ctx = (speex_v2_ctx_t*)codec->decode_ctx;
    if (!ctx || !ctx->dec_state) return -LUAT_ERROR_PARAM_INVALID;

    if (input_size < 2) return -LUAT_ERROR_PARAM_INVALID;
    uint16_t enc_len = (uint16_t)((input[0] << 8) | input[1]);
    if (input_size < (uint32_t)(2 + enc_len)) return -LUAT_ERROR_PARAM_INVALID;

    speex_bits_read_from(&ctx->dec_bits, (const char*)(input + 2), (int)enc_len);
    int ret = speex_decode_int(ctx->dec_state, &ctx->dec_bits, (spx_int16_t*)output);
    if (ret != 0) {
        memset(output, 0, SPEEX_WB_PCM_BYTES);
    }

    *decoded_output_size = SPEEX_WB_PCM_BYTES;
    *decoded_used_size = 2 + enc_len;
    return LUAT_ERROR_NONE;
}

static int _speex_wb_encode(luat_audio_data_codec_t* codec,
    const uint8_t *input, uint32_t input_size,
    uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size) {
    speex_v2_ctx_t *ctx = (speex_v2_ctx_t*)codec->encode_ctx;
    if (!ctx || !ctx->enc_state) return -LUAT_ERROR_PARAM_INVALID;
    if (input_size < SPEEX_WB_PCM_BYTES) return -LUAT_ERROR_PARAM_INVALID;

    speex_bits_reset(&ctx->enc_bits);
    int ret = speex_encode_int(ctx->enc_state, (spx_int16_t*)input, &ctx->enc_bits);
    if (ret < 0) return -LUAT_ERROR_OPERATION_FAILED;

    int nb_bytes = speex_bits_write(&ctx->enc_bits, (char*)(output + 2), SPEEX_WB_MAX_ENCODED - 2);
    if (nb_bytes <= 0) return -LUAT_ERROR_OPERATION_FAILED;

    output[0] = (uint8_t)((nb_bytes >> 8) & 0xFF);
    output[1] = (uint8_t)(nb_bytes & 0xFF);

    *encoded_used_size = SPEEX_WB_PCM_BYTES;
    *encoded_output_size = 2 + (uint32_t)nb_bytes;
    return LUAT_ERROR_NONE;
}

static int _speex_wb_make_head(luat_audio_data_codec_t* codec, uint32_t total_len, luat_buffer_t *out_buffer) {
    (void)codec; (void)total_len; (void)out_buffer;
    return LUAT_ERROR_NONE;
}

const luat_audio_data_codec_opts_t luat_audio_data_codec_speex_wb_opts = {
    .init = _speex_wb_init,
    .deinit = _speex_wb_deinit,
    .get_play_info = _speex_wb_get_play_info,
    .set_record_info = _speex_wb_set_record_info,
    .pre_decode = _speex_wb_pre_decode,
    .decode = _speex_wb_decode,
    .make_head = _speex_wb_make_head,
    .encode = _speex_wb_encode,
    .decode_min_input_len = 0,
    .decode_max_output_len = SPEEX_WB_PCM_BYTES,
    .encode_min_input_len = SPEEX_WB_PCM_BYTES,
    .encode_max_output_len = SPEEX_WB_MAX_ENCODED,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_SPEEX_WB,
    .is_hardware = 0,
    .support_detect = 0,
    .encode_raw_mode = 0,
};

/*======================== UWB mode ========================*/

static int _speex_uwb_init(luat_audio_data_codec_t *codec, uint8_t is_encode) {
    speex_v2_ctx_t *ctx;
    if (is_encode) {
        if (codec->encode_ctx) return LUAT_ERROR_NONE;
        ctx = (speex_v2_ctx_t*)luat_heap_malloc(sizeof(speex_v2_ctx_t));
        if (!ctx) return -LUAT_ERROR_NO_MEMORY;
        memset(ctx, 0, sizeof(speex_v2_ctx_t));
        ctx->mode = 2;
        ctx->quality = 8;
        speex_bits_init(&ctx->enc_bits);
        ctx->enc_state = speex_encoder_init(&speex_uwb_mode);
        if (!ctx->enc_state) {
            speex_bits_destroy(&ctx->enc_bits);
            luat_heap_free(ctx);
            return -LUAT_ERROR_NO_MEMORY;
        }
        speex_encoder_ctl(ctx->enc_state, SPEEX_SET_QUALITY, &ctx->quality);
        int complexity = 3;
        speex_encoder_ctl(ctx->enc_state, SPEEX_SET_COMPLEXITY, &complexity);
        ctx->enc_inited = 1;
        codec->encode_ctx = ctx;
    } else {
        if (codec->decode_ctx) return LUAT_ERROR_NONE;
        ctx = (speex_v2_ctx_t*)luat_heap_malloc(sizeof(speex_v2_ctx_t));
        if (!ctx) return -LUAT_ERROR_NO_MEMORY;
        memset(ctx, 0, sizeof(speex_v2_ctx_t));
        ctx->mode = 2;
        speex_bits_init(&ctx->dec_bits);
        ctx->dec_state = speex_decoder_init(&speex_uwb_mode);
        if (!ctx->dec_state) {
            speex_bits_destroy(&ctx->dec_bits);
            luat_heap_free(ctx);
            return -LUAT_ERROR_NO_MEMORY;
        }
        int enh = 1;
        speex_decoder_ctl(ctx->dec_state, SPEEX_SET_ENH, &enh);
        ctx->dec_inited = 1;
        codec->decode_ctx = ctx;
    }
    return LUAT_ERROR_NONE;
}

static void _speex_uwb_deinit(luat_audio_data_codec_t *codec) {
    _speex_nb_deinit(codec);  /* same logic */
}

static int _speex_uwb_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer,
    uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info) {
    (void)now_file_pos;
    if (input_buffer->pos < 2) {
        *jump_offset_bytes = 0;
        *need_bytes = 2;
        info->sample_rate = 0;
        return LUAT_ERROR_NONE;
    }
    info->channel_nums = 1;
    info->data_align = 2;
    info->is_signed = 1;
    info->sample_rate = 32000;
    info->one_frame_sample_cnt = SPEEX_UWB_FRAME_SAMPLES;
    info->one_frame_bytes = SPEEX_UWB_PCM_BYTES;
    *jump_offset_bytes = 0;
    *need_bytes = 0;
    return LUAT_ERROR_NONE;
}

static void _speex_uwb_set_record_info(struct luat_audio_data_codec *codec, luat_audio_common_param_t *info) {
    info->sample_rate = 32000;
    info->channel_nums = 1;
    info->data_align = 2;
    info->is_signed = 1;
    codec->common_param.sample_rate = 32000;
    codec->common_param.channel_nums = 1;
    codec->common_param.data_align = 2;
    codec->common_param.is_signed = 1;
    codec->common_param.one_frame_sample_cnt = SPEEX_UWB_FRAME_SAMPLES;
    codec->common_param.one_frame_bytes = SPEEX_UWB_PCM_BYTES;
}

static void _speex_uwb_pre_decode(luat_audio_data_codec_t* codec, const uint8_t *input, uint32_t input_size, uint32_t *frame_size_bytes) {
    (void)codec;
    if (input_size < 2) {
        *frame_size_bytes = 2;
        return;
    }
    uint16_t len = (uint16_t)((input[0] << 8) | input[1]);
    *frame_size_bytes = 2 + len;
}

static int _speex_uwb_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
    const uint8_t *input, uint32_t input_size,
    uint8_t *output, uint32_t *decoded_output_size, uint32_t *decoded_used_size) {
    (void)info;
    speex_v2_ctx_t *ctx = (speex_v2_ctx_t*)codec->decode_ctx;
    if (!ctx || !ctx->dec_state) return -LUAT_ERROR_PARAM_INVALID;

    if (input_size < 2) return -LUAT_ERROR_PARAM_INVALID;
    uint16_t enc_len = (uint16_t)((input[0] << 8) | input[1]);
    if (input_size < (uint32_t)(2 + enc_len)) return -LUAT_ERROR_PARAM_INVALID;

    speex_bits_read_from(&ctx->dec_bits, (const char*)(input + 2), (int)enc_len);
    int ret = speex_decode_int(ctx->dec_state, &ctx->dec_bits, (spx_int16_t*)output);
    if (ret != 0) {
        memset(output, 0, SPEEX_UWB_PCM_BYTES);
    }

    *decoded_output_size = SPEEX_UWB_PCM_BYTES;
    *decoded_used_size = 2 + enc_len;
    return LUAT_ERROR_NONE;
}

static int _speex_uwb_encode(luat_audio_data_codec_t* codec,
    const uint8_t *input, uint32_t input_size,
    uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size) {
    speex_v2_ctx_t *ctx = (speex_v2_ctx_t*)codec->encode_ctx;
    if (!ctx || !ctx->enc_state) return -LUAT_ERROR_PARAM_INVALID;
    if (input_size < SPEEX_UWB_PCM_BYTES) return -LUAT_ERROR_PARAM_INVALID;

    speex_bits_reset(&ctx->enc_bits);
    int ret = speex_encode_int(ctx->enc_state, (spx_int16_t*)input, &ctx->enc_bits);
    if (ret < 0) return -LUAT_ERROR_OPERATION_FAILED;

    int nb_bytes = speex_bits_write(&ctx->enc_bits, (char*)(output + 2), SPEEX_UWB_MAX_ENCODED - 2);
    if (nb_bytes <= 0) return -LUAT_ERROR_OPERATION_FAILED;

    output[0] = (uint8_t)((nb_bytes >> 8) & 0xFF);
    output[1] = (uint8_t)(nb_bytes & 0xFF);

    *encoded_used_size = SPEEX_UWB_PCM_BYTES;
    *encoded_output_size = 2 + (uint32_t)nb_bytes;
    return LUAT_ERROR_NONE;
}

static int _speex_uwb_make_head(luat_audio_data_codec_t* codec, uint32_t total_len, luat_buffer_t *out_buffer) {
    (void)codec; (void)total_len; (void)out_buffer;
    return LUAT_ERROR_NONE;
}

const luat_audio_data_codec_opts_t luat_audio_data_codec_speex_uwb_opts = {
    .init = _speex_uwb_init,
    .deinit = _speex_uwb_deinit,
    .get_play_info = _speex_uwb_get_play_info,
    .set_record_info = _speex_uwb_set_record_info,
    .pre_decode = _speex_uwb_pre_decode,
    .decode = _speex_uwb_decode,
    .make_head = _speex_uwb_make_head,
    .encode = _speex_uwb_encode,
    .decode_min_input_len = 0,
    .decode_max_output_len = SPEEX_UWB_PCM_BYTES,
    .encode_min_input_len = SPEEX_UWB_PCM_BYTES,
    .encode_max_output_len = SPEEX_UWB_MAX_ENCODED,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_SPEEX_UWB,
    .is_hardware = 0,
    .support_detect = 0,
    .encode_raw_mode = 0,
};

#endif /* LUAT_SUPPORT_SPEEX */
