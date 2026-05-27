#include "luat_base.h"
#include "luat_audio_core.h"
#include "luat_common_api.h"
#include "luat_mem.h"
#include <string.h>
#define LUAT_LOG_TAG "luat_raw"
#include "luat_log.h"

static int _raw_codec_init(luat_audio_data_codec_t* codec, uint8_t is_encode) {
    return LUAT_ERROR_NONE;
}

static void _raw_codec_deinit(luat_audio_data_codec_t* codec) {
}

static int _raw_codec_decode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output,
                  uint32_t *decoded_output_size, uint32_t *decoded_used_size)
{
    memcpy(output, input, input_size);
    *decoded_output_size = input_size;
    *decoded_used_size = input_size;
    return LUAT_ERROR_NONE;
}

static int _raw_codec_encode(luat_audio_data_codec_t* codec, luat_audio_common_param_t *info,
                  const uint8_t *input, uint32_t input_size,
                  uint8_t *output, uint32_t *encoded_used_size, uint32_t *encoded_output_size)
{
    memcpy(output, input, input_size);
    *encoded_output_size = input_size;
    *encoded_used_size = input_size;
    return LUAT_ERROR_NONE;
}

const luat_audio_data_codec_opts_t luat_audio_data_codec_raw_opts = {
    .init = _raw_codec_init,
    .deinit = _raw_codec_deinit,
    .get_play_info = NULL,
    .pre_decode = NULL,
    .decode = _raw_codec_decode,
    .make_head = NULL,
    .encode = _raw_codec_encode,
    .decode_min_input_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .decode_max_output_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .encode_min_input_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .encode_max_output_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_RAW,
    .is_reentrant = 1,
    .is_hardware = 0,
    .support_detect = 0,
};
