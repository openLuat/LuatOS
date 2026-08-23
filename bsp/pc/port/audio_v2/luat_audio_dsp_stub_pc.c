/*
 * PC simulator stub for audio DSP (speexdsp).
 * Provides a no-op implementation when the external audio_dsp component is absent.
 */
#include "luat_base.h"

#ifndef LUAT_USE_AUDIO_DSP

#include "luat_audio_core.h"

static int stub_init(luat_audio_dsp_t *dsp) {
    (void)dsp;
    return -1; // not supported
}

static void stub_deinit(luat_audio_dsp_t *dsp) {
    (void)dsp;
}

static int stub_process(luat_audio_dsp_t *dsp, int16_t *in, int16_t *out, size_t frames) {
    (void)dsp;
    (void)in;
    (void)out;
    (void)frames;
    return -1; // not supported
}

const luat_audio_dsp_opts_t luat_audio_dsp_speexdsp_opts = {
    .type = 0,
    .init = stub_init,
    .deinit = stub_deinit,
    .process = stub_process,
};

#endif /* !LUAT_USE_AUDIO_DSP */
