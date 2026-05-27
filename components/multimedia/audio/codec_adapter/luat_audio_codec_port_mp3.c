#include "luat_audio_define.h"
#include "luat_base.h"
#include "luat_common_api.h"
#include "luat_malloc.h"
#include "luat_mem.h"
#include "luat_audio_core.h"

#define LUAT_LOG_TAG "luat_mp3"
#include "luat_log.h"

#include "mp3_decode/minimp3.h"

#define MP3_FRAME_AFTER_ENCODE_SIZE 1792
#define MP3_FRAME_BEFORE_ENCODE_SIZE (4 * 1152)

int luat_audio_mp3_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info)
{
    // LLOGC(luat_audio_debug_flag, "get mp3 file info pos %d, len %d", now_file_pos, input_buffer->pos);
    if (input_buffer->pos < MP3_FRAME_AFTER_ENCODE_SIZE) {
        *jump_offset_bytes = 0;
        *need_bytes = MP3_FRAME_AFTER_ENCODE_SIZE;
        info->sample_rate = 0;
        return LUAT_ERROR_NONE;
    }
    mp3dec_t *mp3_decoder;
    if (input_buffer->data[0] == 0xff || (now_file_pos > 12)) {  //mp3数据帧，尝试解码  
        mp3_decoder = luat_heap_malloc(sizeof(mp3dec_t));
        if (!mp3_decoder) {
            return -LUAT_ERROR_NO_MEMORY;
        }
        memset(mp3_decoder, 0, sizeof(mp3dec_t));
        mp3dec_init(mp3_decoder);
        mp3dec_frame_info_t mp3_frame_info;
        int ret = mp3dec_decode_frame(mp3_decoder, input_buffer->data, input_buffer->pos, NULL, &mp3_frame_info);
        luat_heap_free(mp3_decoder);
        if (ret > 0) {
            info->sample_rate = mp3_frame_info.hz;
            info->channel_nums = mp3_frame_info.channels;
            info->data_align = 2;
            info->is_signed = 1;
            *jump_offset_bytes = now_file_pos;
            *need_bytes = 0;
            return LUAT_ERROR_NONE;
        } else {
            return -LUAT_ERROR_PARAM_INVALID;
        }

    }
    if (!memcmp(input_buffer->data, "ID3", 3)) {
        uint32_t jump = 0;
        for(uint32_t i = 0; i < 4; i++) {
            jump <<= 7;
            jump |= input_buffer->data[6 + i] & 0x7f;
        }
        *jump_offset_bytes = jump + 12;
        *need_bytes = MP3_FRAME_AFTER_ENCODE_SIZE;
        info->sample_rate = 0;
        return LUAT_ERROR_NONE;
    }
    return -LUAT_ERROR_PARAM_INVALID;
}

static int _mp3_codec_init(luat_audio_data_codec_t* codec, uint8_t is_encode) {
    if (is_encode) {
        return -LUAT_ERROR_PERMISSION_DENIED;
    } else {
        if (codec->decode_ctx) {
            mp3dec_init((mp3dec_t*)codec->decode_ctx);
            return LUAT_ERROR_NONE;
        }
        codec->decode_ctx = luat_heap_malloc(sizeof(mp3dec_t));
        if (!codec->decode_ctx) {
            return -LUAT_ERROR_NO_MEMORY;
        }
        memset(codec->decode_ctx, 0, sizeof(mp3dec_t));
        mp3dec_init((mp3dec_t*)codec->decode_ctx);
        return LUAT_ERROR_NONE;
    }
    return LUAT_ERROR_NONE;
}

static void _mp3_codec_deinit(luat_audio_data_codec_t* codec) {
    if (codec->encode_ctx) {
        
    } 
    if (codec->decode_ctx) {
        luat_heap_free(codec->decode_ctx);
        codec->decode_ctx = NULL;
    }
}

static int _mp3_codec_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, 
                  uint32_t *decoded_output_size, uint32_t *decoded_used_size)
{
    mp3dec_frame_info_t mp3_frame_info;
    int ret = mp3dec_decode_frame((mp3dec_t*)codec->decode_ctx, input, input_size, (int16_t *)output, &mp3_frame_info);
    if (ret > 0) {
        *decoded_output_size = (ret * mp3_frame_info.channels * 2);;
        *decoded_used_size = mp3_frame_info.frame_bytes;
    } else {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    return LUAT_ERROR_NONE;
}     

static int _mp3_codec_encode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size)
{
    return -LUAT_ERROR_PERMISSION_DENIED;
}

const luat_audio_data_codec_opts_t luat_audio_data_codec_mp3_opts = {
    .init = _mp3_codec_init,
    .deinit = _mp3_codec_deinit,
    .get_play_info = luat_audio_mp3_get_play_info,
    .pre_decode = NULL,
    .decode = _mp3_codec_decode,
    .make_head = NULL,
    .encode = _mp3_codec_encode,
    .decode_min_input_len = MP3_FRAME_AFTER_ENCODE_SIZE,
    .decode_max_output_len = MP3_FRAME_BEFORE_ENCODE_SIZE,
    .encode_min_input_len = MP3_FRAME_BEFORE_ENCODE_SIZE,
    .encode_max_output_len = MP3_FRAME_AFTER_ENCODE_SIZE,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_MP3,
    .is_reentrant = 1,
    .is_hardware = 0,
    .support_detect = 1,
};
