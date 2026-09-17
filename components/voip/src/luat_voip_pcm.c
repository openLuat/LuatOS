#include "luat_conf_bsp.h"

#ifdef LUAT_USE_VOIP_AUDIO_PORT
#include "luat_voip_pcm.h"
#include "luat_voip_audio_port.h"
#include <string.h>

int voip_pcm_normalizer_init(voip_pcm_normalizer_t *state,
        uint32_t input_rate, uint8_t channels)
{
    if (!state || (input_rate != 8000 && input_rate != 16000 && input_rate != 48000) ||
            (channels != 1 && channels != 2)) return -1;
    memset(state, 0, sizeof(*state));
    state->input_rate = input_rate;
    state->channels = channels;
    if (input_rate != 8000) {
        state->resampler = luat_voip_audio_resampler_create(input_rate, 8000);
        if (!state->resampler) return -1;
        state->latency_samples = luat_voip_audio_resampler_latency(state->resampler);
    }
    return 0;
}

void voip_pcm_normalizer_deinit(voip_pcm_normalizer_t *state)
{
    if (!state) return;
    if (state->resampler) luat_voip_audio_resampler_destroy(state->resampler);
    memset(state, 0, sizeof(*state));
}

int voip_pcm_normalizer_push(voip_pcm_normalizer_t *state, const uint8_t *raw,
        uint32_t bytes, uint32_t render_seq, uint64_t capture_end_ms,
        voip_pcm_frame_cb_t callback, void *user)
{
    uint32_t samples, offset = 0;
    int frames = 0;
    if (!state || !raw || !callback || !state->input_rate || !state->channels ||
            !bytes || bytes % (2U * state->channels)) return -1;
    samples = bytes / (2U * state->channels);
    if (samples > state->input_rate / 50U || samples > VOIP_PCM_MAX_INPUT_SAMPLES) return -1;
    for (uint32_t i = 0; i < samples; i++) {
        const uint8_t *p = raw + i * 2U * state->channels;
        state->mono[i] = (int16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
    }
    state->input_samples += samples;
    while (offset < samples) {
        uint32_t consumed = samples - offset;
        uint32_t produced = VOIP_PCM_FRAME_SAMPLES - state->pending_samples;
        if (state->resampler) {
            if (luat_voip_audio_resampler_process(state->resampler,
                    state->mono + offset, &consumed,
                    state->frame + state->pending_samples, &produced) != 0 ||
                    consumed > samples - offset ||
                    produced > VOIP_PCM_FRAME_SAMPLES - state->pending_samples ||
                    (!consumed && !produced)) return -1;
        } else {
            if (consumed > produced) consumed = produced;
            produced = consumed;
            memcpy(state->frame + state->pending_samples, state->mono + offset,
                    produced * sizeof(int16_t));
        }
        offset += consumed;
        state->pending_samples += (uint16_t)produced;
        state->output_samples += produced;
        if (state->pending_samples == VOIP_PCM_FRAME_SAMPLES) {
            /* Re-anchor the independent output sample counter to the hardware
             * block end, never the task's processing time. Remove DSP latency
             * to identify when the filtered microphone samples were acquired. */
            int64_t end_samples = (int64_t)(capture_end_ms * 8U) -
                    (int64_t)(state->input_samples * 8000U / state->input_rate) +
                    (int64_t)state->output_samples - state->latency_samples;
            callback(user, state->frame, render_seq,
                    end_samples > 0 ? (uint64_t)end_samples / 8U : 0);
            state->pending_samples = 0;
            frames++;
        }
    }
    return frames;
}

#endif /* LUAT_USE_VOIP_AUDIO_PORT */
