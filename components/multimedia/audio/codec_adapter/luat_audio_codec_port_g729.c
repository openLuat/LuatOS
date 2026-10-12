/*
 * G.729A audio_v2 codec adapter: fixed 8kHz/mono/16bit, 80 samples (160 bytes)
 * PCM per 10 ms frame, 10 bytes of bitstream per frame. The library is
 * malloc-free and fully reentrant, so each direction simply owns one state.
 *
 * Annex B (VAD/DTX) is intentionally NOT enabled here: the audio_v2 record /
 * play pipeline treats the bitstream as a continuous byte stream without
 * frame-length tagging, which cannot carry variable-length (10/2/0 byte)
 * frames. Use the legacy codec module (codec.G729 with encode_level=1) for
 * Annex B; its file decode accepts the length-prefixed container.
 */
#include "luat_conf_bsp.h"
#ifdef LUAT_SUPPORT_G729
#include "luat_base.h"
#include "luat_audio_core.h"
#include "luat_mem.h"
#include "g729a_interface.h"

#define G729_PCM_FRAME_BYTES    160 /* 80 samples * 2 bytes */
#define G729_BITSTREAM_BYTES    10

static int _g729_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info)
{
    info->channel_nums = 1;
    info->data_align = 2;
    info->is_signed = 1;
    info->sample_rate = 8000;
    *jump_offset_bytes = 0;
    *need_bytes = 0;
    return LUAT_ERROR_NONE;
}

static void _g729_set_record_info(struct luat_audio_data_codec *codec, luat_audio_common_param_t *info)
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
    codec->common_param.one_frame_sample_cnt = 80;
    codec->common_param.one_frame_bytes = G729_PCM_FRAME_BYTES;
}

static int _g729_codec_init(luat_audio_data_codec_t* codec, uint8_t is_encode) {
    if (!codec) return -LUAT_ERROR_PARAM_INVALID;

    if (is_encode) {
        if (codec->encode_ctx) {
            return LUAT_ERROR_NONE;
        }
        codec->encode_ctx = luat_heap_malloc(G729A_Encoder_Get_Size());
        if (!codec->encode_ctx) {
            return -LUAT_ERROR_NO_MEMORY;
        }
        if (G729A_Encoder_Init(codec->encode_ctx) != G729A_NO_ERROR) {
            luat_heap_free(codec->encode_ctx);
            codec->encode_ctx = NULL;
            return -LUAT_ERROR_OPERATION_FAILED;
        }
    } else {
        if (codec->decode_ctx) {
            return LUAT_ERROR_NONE;
        }
        codec->decode_ctx = luat_heap_malloc(G729A_Decoder_Get_Size());
        if (!codec->decode_ctx) {
            return -LUAT_ERROR_NO_MEMORY;
        }
        if (G729A_Decoder_Init(codec->decode_ctx) != G729A_NO_ERROR) {
            luat_heap_free(codec->decode_ctx);
            codec->decode_ctx = NULL;
            return -LUAT_ERROR_OPERATION_FAILED;
        }
    }
    return LUAT_ERROR_NONE;
}

static void _g729_codec_deinit(luat_audio_data_codec_t* codec) {
    if (!codec) return;
    if (codec->encode_ctx) {
        luat_heap_free(codec->encode_ctx);
        codec->encode_ctx = NULL;
    }
    if (codec->decode_ctx) {
        luat_heap_free(codec->decode_ctx);
        codec->decode_ctx = NULL;
    }
}

static int _g729_codec_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output,
                  uint32_t *decoded_output_size, uint32_t *decoded_used_size) {
    uint32_t used = 0, produced = 0;

    if (!codec || !codec->decode_ctx || !input || !output || !decoded_output_size || !decoded_used_size) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    while (input_size - used >= G729_BITSTREAM_BYTES) {
        if (G729A_Decoder_Process(codec->decode_ctx, input + used, G729_BITSTREAM_BYTES,
                                  (G729_Word16*)(output + produced)) != G729A_NO_ERROR) {
            break;
        }
        used += G729_BITSTREAM_BYTES;
        produced += G729_PCM_FRAME_BYTES;
    }
    if (!used) {
        /* Truncated tail (e.g. last frame of a file): consume and drop it
           instead of failing, otherwise the core reports a fatal decode
           error at end of stream. */
        *decoded_used_size = input_size;
        *decoded_output_size = 0;
        return LUAT_ERROR_NONE;
    }
    *decoded_used_size = used;
    *decoded_output_size = produced;
    return LUAT_ERROR_NONE;
}

static int _g729_codec_encode(luat_audio_data_codec_t* codec,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size) {
    /* One frame per call (speex-style): the core output buffer is only
       2*encode_min_input_len bytes, and every caller delivers exactly one
       160-byte frame. The record path never hands us a partial frame, so
       unlike the legacy codec port we do not zero-pad a tail. */
    if (!codec || !codec->encode_ctx || !input || !output || !encoded_used_size || !encoded_output_size) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    if (input_size < G729_PCM_FRAME_BYTES) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    G729_UWord32 out_len = 0;
    if (G729A_Encoder_Process(codec->encode_ctx, (const G729_Word16*)input, output, &out_len) != G729A_NO_ERROR) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    *encoded_used_size = G729_PCM_FRAME_BYTES;
    *encoded_output_size = out_len;     /* VAD off: always G729_BITSTREAM_BYTES */
    return LUAT_ERROR_NONE;
}

const luat_audio_data_codec_opts_t luat_audio_data_codec_g729_opts = {
    .init = _g729_codec_init,
    .deinit = _g729_codec_deinit,
    .get_play_info = _g729_get_play_info,
    .set_record_info = _g729_set_record_info,
    .pre_decode = NULL,
    .decode = _g729_codec_decode,
    .make_head = NULL,
    .encode = _g729_codec_encode,
    .decode_min_input_len = G729_BITSTREAM_BYTES,
    .decode_max_output_len = G729_PCM_FRAME_BYTES,
    .encode_min_input_len = G729_PCM_FRAME_BYTES,
    .encode_max_output_len = G729_BITSTREAM_BYTES,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_G729,
    .is_hardware = 0,
    .support_detect = 0,
    .encode_raw_mode = 0,
};
#endif
