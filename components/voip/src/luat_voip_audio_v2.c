/* audio_v2 adapter for VoIP's private PCM transport codec. */
#include "luat_voip_core.h"

#ifdef LUAT_USE_VOIP_AUDIO_V2
#include "luat_audio_core.h"
#include <string.h>

static int voip_pcm_encode(luat_audio_data_codec_t *codec, const uint8_t *input, uint32_t input_size,
    uint8_t *output, uint32_t *used, uint32_t *out_size)
{
    (void)codec;
    memcpy(output, input, input_size);
    *used = input_size;
    *out_size = input_size;
    return LUAT_ERROR_NONE;
}

static int voip_pcm_decode(luat_audio_data_codec_t *codec, luat_audio_common_param_t *info,
    const uint8_t *input, uint32_t input_size, uint8_t *output, uint32_t *out_size, uint32_t *used)
{
    (void)codec;
    (void)info;
    memcpy(output, input, input_size);
    *out_size = input_size;
    *used = input_size;
    return LUAT_ERROR_NONE;
}

static int voip_pcm_init(luat_audio_data_codec_t *codec, uint8_t is_encode)
{
    (void)codec;
    (void)is_encode;
    return LUAT_ERROR_NONE;
}

static void voip_pcm_deinit(luat_audio_data_codec_t *codec)
{
    (void)codec;
}

static const luat_audio_data_codec_opts_t s_voip_pcm_codec_opts = {
    .init = voip_pcm_init,
    .deinit = voip_pcm_deinit,
    .set_record_info = luat_audio_codec_wav_set_record_info,
    .decode = voip_pcm_decode,
    .encode = voip_pcm_encode,
    .decode_min_input_len = 320,
    .decode_max_output_len = 320,
    .encode_min_input_len = 320,
    .encode_max_output_len = 320,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_VOIP_PCM,
    .decode_raw_mode = 1,
};
#endif

void luat_voip_audio_codec_register(void)
{
#ifdef LUAT_USE_VOIP_AUDIO_V2
    static uint8_t registered;
    if (!registered && luat_audio_data_codec_register(&s_voip_pcm_codec_opts) == LUAT_ERROR_NONE) {
        registered = 1;
    }
#endif
}
