#include "luat_audio_core.h"
#define LUAT_LOG_TAG "audio_dsp"
#include "luat_log.h"

extern const luat_audio_dsp_opts_t luat_audio_dsp_speexdsp_opts;
static const luat_audio_dsp_opts_t* _table[LUAT_AUDIO_DSP_TYPE_MAX] = {
    &luat_audio_dsp_speexdsp_opts,
};

const luat_audio_dsp_opts_t *luat_audio_dsp_get_opts(uint8_t type)
{
    if (type >= LUAT_AUDIO_DSP_TYPE_MAX) {
        return NULL;
    }
    return _table[type];
}

int luat_audio_dsp_bind(luat_audio_dsp_t *dsp, const luat_audio_dsp_opts_t *opts)
{
    if (!opts) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    dsp->opts = opts;
    int ret = dsp->opts->init(dsp);
    if (ret != LUAT_ERROR_NONE) {
        LLOGE("bind %d failed, ret = %d", opts->type, ret);
        dsp->opts = NULL;
    }
    return ret;
}

void luat_audio_dsp_unbind(luat_audio_dsp_t *dsp)
{
    if (dsp->opts) {
        dsp->opts->deinit(dsp);
        dsp->opts = NULL;
    }
}
