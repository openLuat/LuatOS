#include "luat_base.h"
#include "luat_audio_core.h"
#include "luat_common_api.h"
#include "luat_mem.h"
#include <string.h>

static int _raw_codec_init(luat_audio_data_codec_t* codec, uint8_t is_encode) {
    return LUAT_ERROR_NONE;
}

static void _raw_codec_deinit(luat_audio_data_codec_t* codec) {
}



const luat_audio_data_codec_opts_t luat_audio_data_codec_no_op_opts = {
    .init = _raw_codec_init,
    .deinit = _raw_codec_deinit,
    .get_play_info = NULL,
    .set_record_info = NULL,
    .pre_decode = NULL,
    .decode = NULL,
    .make_head = NULL,
    .encode = NULL,
    .decode_min_input_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .decode_max_output_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .encode_min_input_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .encode_max_output_len = LUAT_AUDIO_DATA_CACHE_LEN,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_NO_OP,
    .is_hardware = 0,
    .support_detect = 0,
    .encode_raw_mode = 1,
};
