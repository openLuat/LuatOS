/*
 * G.722 audio_v2 codec adapter: fixed 16kHz/mono/16bit wideband, 20 ms frame
 * convention: 320 samples (640 bytes) PCM <-> 160 bytes bitstream at 64kbps.
 * The library is fully reentrant, so each direction simply owns one state.
 *
 * Only the 64kbps mode is wired here: it is the RTP/mandatory mode and the
 * stream carries no rate tag. Use the legacy codec module (codec.G722 with
 * encode_level 1/2) for 56/48kbps.
 */
#include "luat_conf_bsp.h"
#ifdef LUAT_SUPPORT_G722
#include "luat_base.h"
#include "luat_audio_core.h"
#include "luat_mem.h"
#include "g722_codec.h"

#define G722_PCM_FRAME_BYTES    640 /* 320 samples * 2 bytes, 20ms @16kHz */
#define G722_BITSTREAM_BYTES    160 /* 64kbps: 8000字节/秒 * 20ms */

static int _g722_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info)
{
    info->channel_nums = 1;
    info->data_align = 2;
    info->is_signed = 1;
    info->sample_rate = 16000;
    *jump_offset_bytes = 0;
    *need_bytes = 0;
    return LUAT_ERROR_NONE;
}

static void _g722_set_record_info(struct luat_audio_data_codec *codec, luat_audio_common_param_t *info)
{
    if (info->sample_rate != 16000) {
        info->sample_rate = 16000;
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
    codec->common_param.one_frame_sample_cnt = 320;
    codec->common_param.one_frame_bytes = G722_PCM_FRAME_BYTES;
}

static int _g722_codec_init(luat_audio_data_codec_t* codec, uint8_t is_encode) {
    if (!codec) return -LUAT_ERROR_PARAM_INVALID;

    if (is_encode) {
        if (codec->encode_ctx) {
            return LUAT_ERROR_NONE;
        }
        codec->encode_ctx = g722_encoder_new(64000, 0);
        if (!codec->encode_ctx) {
            return -LUAT_ERROR_NO_MEMORY;
        }
    } else {
        if (codec->decode_ctx) {
            return LUAT_ERROR_NONE;
        }
        codec->decode_ctx = g722_decoder_new(64000, 0);
        if (!codec->decode_ctx) {
            return -LUAT_ERROR_NO_MEMORY;
        }
    }
    return LUAT_ERROR_NONE;
}

static void _g722_codec_deinit(luat_audio_data_codec_t* codec) {
    if (!codec) return;
    if (codec->encode_ctx) {
        g722_encoder_destroy((G722_ENC_CTX*)codec->encode_ctx);
        codec->encode_ctx = NULL;
    }
    if (codec->decode_ctx) {
        g722_decoder_destroy((G722_DEC_CTX*)codec->decode_ctx);
        codec->decode_ctx = NULL;
    }
}

static int _g722_codec_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output,
                  uint32_t *decoded_output_size, uint32_t *decoded_used_size) {
    if (!codec || !codec->decode_ctx || !input || !output || !decoded_output_size || !decoded_used_size) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    /* 核心每次固定喂 decode_min_input_len(160) 字节; 文件末尾不足一帧的尾巴
       照常解码(流式codec任意字节数都合法), 不报错, 与g729适配器的尾帧处理一致 */
    uint32_t n = input_size;
    if (n > G722_BITSTREAM_BYTES) n = G722_BITSTREAM_BYTES;
    int samples = g722_decode((G722_DEC_CTX*)codec->decode_ctx, input, n, (int16_t*)output);
    if (samples < 0) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    *decoded_used_size = n;
    *decoded_output_size = samples * 2;
    return LUAT_ERROR_NONE;
}

static int _g722_codec_encode(luat_audio_data_codec_t* codec,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size) {
    /* One frame per call (g729-style): every caller delivers exactly one
       640-byte frame. The record path never hands us a partial frame. */
    if (!codec || !codec->encode_ctx || !input || !output || !encoded_used_size || !encoded_output_size) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (input_size < G722_PCM_FRAME_BYTES) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    int produced = g722_encode((G722_ENC_CTX*)codec->encode_ctx, (const int16_t*)input, 320, output);
    if (produced < 0) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    *encoded_used_size = G722_PCM_FRAME_BYTES;
    *encoded_output_size = produced;    /* 64kbps: always G722_BITSTREAM_BYTES */
    return LUAT_ERROR_NONE;
}

const luat_audio_data_codec_opts_t luat_audio_data_codec_g722_opts = {
    .init = _g722_codec_init,
    .deinit = _g722_codec_deinit,
    .get_play_info = _g722_get_play_info,
    .set_record_info = _g722_set_record_info,
    .pre_decode = NULL,
    .decode = _g722_codec_decode,
    .make_head = NULL,
    .encode = _g722_codec_encode,
    .decode_min_input_len = G722_BITSTREAM_BYTES,
    .decode_max_output_len = G722_PCM_FRAME_BYTES,
    .encode_min_input_len = G722_PCM_FRAME_BYTES,
    .encode_max_output_len = G722_BITSTREAM_BYTES,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_G722,
    .is_hardware = 0,
    .support_detect = 0,
    .encode_raw_mode = 0,
};
#endif
