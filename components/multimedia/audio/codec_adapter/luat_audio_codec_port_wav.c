#include "luat_base.h"
#include "luat_audio_core.h"
#include "luat_common_api.h"
#include "luat_mem.h"
#include <string.h>
#define LUAT_LOG_TAG "luat_wav"
#include "luat_log.h"

int luat_audio_wav_get_play_info(struct luat_audio_data_codec *codec, luat_buffer_t *input_buffer, uint32_t now_file_pos, uint32_t *jump_offset_bytes, uint32_t *need_bytes, luat_audio_common_param_t *info) {
    uint8_t *temp = input_buffer->data;
    uint32_t pos = 0;
    uint32_t len = 0;
    uint8_t find_data = 0;
    if (input_buffer->pos < 44) {
        *jump_offset_bytes = 0;
        *need_bytes = 44;
        info->sample_rate = 0;
        return LUAT_ERROR_NONE;
    }
        
    if (!memcmp(temp, "RIFF", 4) && !memcmp(temp + 8, "WAVE", 4) && !memcmp(temp + 12, "fmt ", 4)) {
        memcpy(&len, temp + 16, 4);
        pos = 16 + len;
        while((pos + 8) < input_buffer->pos && !find_data) {
            if (memcmp(temp + pos, "data", 4) == 0) {
                find_data = 1;
            } else {
                memcpy(&len, temp + pos + 4, 4);
                pos += len + 8;
            }
        }
        LLOGC(luat_audio_debug_flag, "head pos %d/%d data block %d", pos, input_buffer->pos, find_data);
        if (!find_data) {
            *jump_offset_bytes = 0;
            *need_bytes = now_file_pos + 1024;
            info->sample_rate = 0;
            return LUAT_ERROR_NONE;
        }
        info->is_signed = 1;
        info->channel_nums = temp[22];
        memcpy(&info->sample_rate, temp + 24, 4);
        if (16 == temp[34]) {
            info->data_align = 2;
        } else {
            info->sample_rate = 0;
            LLOGE("wav file only suppor 16bit audio");
            return -LUAT_ERROR_PARAM_INVALID;
        }
        *jump_offset_bytes = 0;
        *need_bytes = pos + 8;
        return LUAT_ERROR_NONE;
    }
    return -LUAT_ERROR_PARAM_INVALID;
}

static int _wav_codec_init(luat_audio_data_codec_t* codec, uint8_t is_encode) {
    return LUAT_ERROR_NONE;
}
static void _wav_codec_deinit(luat_audio_data_codec_t* codec) {
}   

static int _wav_codec_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, 
                  uint32_t *decoded_output_size, uint32_t *decoded_used_size) 
{
    memcpy(output, input, input_size);
    *decoded_output_size = input_size;
    *decoded_used_size = input_size;
    return LUAT_ERROR_NONE;
}
static int _wav_codec_make_head(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info, uint32_t total_len, luat_buffer_t *out_buffer)
{
    uint8_t header[44] = {0};
    uint32_t data_size = total_len;
    uint32_t file_size = data_size + 36;
    uint16_t block_align = info->data_align * info->channel_nums;
    uint32_t byte_rate = info->sample_rate * block_align;
    uint16_t bits_per_sample = info->data_align * 8;

    memcpy(header, "RIFF", 4);
    header[4] = file_size & 0xff;
    header[5] = (file_size >> 8) & 0xff;
    header[6] = (file_size >> 16) & 0xff;
    header[7] = (file_size >> 24) & 0xff;
    memcpy(header + 8, "WAVE", 4);
    memcpy(header + 12, "fmt ", 4);
    header[16] = 16;
    header[20] = 1;
    header[22] = info->channel_nums;
    memcpy(header + 24, &info->sample_rate, 4);
    memcpy(header + 28, &byte_rate, 4);
    header[32] = block_align & 0xff;
    header[33] = (block_align >> 8) & 0xff;
    header[34] = bits_per_sample & 0xff;
    header[35] = (bits_per_sample >> 8) & 0xff;
    memcpy(header + 36, "data", 4);
    memcpy(header + 40, &data_size, 4);

    luat_buffer_write(out_buffer, header, 44);
    return LUAT_ERROR_NONE;
}

static int _wav_codec_encode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size)
{
    memcpy(output, input, input_size);
    *encoded_output_size = input_size;
    *encoded_used_size = input_size;
    return LUAT_ERROR_NONE;
}

const luat_audio_data_codec_opts_t luat_audio_data_codec_wav_opts = {
    .init = _wav_codec_init,
    .deinit = _wav_codec_deinit,
    .get_play_info = luat_audio_wav_get_play_info,
    .pre_decode = NULL,
    .decode = _wav_codec_decode,
    .make_head = _wav_codec_make_head,
    .encode = _wav_codec_encode,
    .decode_min_input_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .decode_max_output_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .encode_min_input_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .encode_max_output_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_WAV,
    .is_reentrant = 1,
    .is_hardware = 0,
    .support_detect = 1,
};