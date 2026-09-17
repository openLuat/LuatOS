#ifndef LUAT_VOIP_PCM_H
#define LUAT_VOIP_PCM_H

#include <stdint.h>

#define VOIP_PCM_FRAME_SAMPLES 160U
#define VOIP_PCM_MAX_INPUT_SAMPLES 960U
#define VOIP_PCM_MAX_RAW_BYTES (VOIP_PCM_MAX_INPUT_SAMPLES * 2U * 2U)

typedef void (*voip_pcm_frame_cb_t)(void *user, const int16_t *pcm,
        uint32_t render_seq, uint64_t capture_end_ms);

typedef struct {
    void *resampler;
    uint32_t input_rate;
    uint32_t latency_samples;
    uint64_t input_samples;
    uint64_t output_samples;
    uint16_t pending_samples;
    uint8_t channels;
    int16_t mono[VOIP_PCM_MAX_INPUT_SAMPLES];
    int16_t frame[VOIP_PCM_FRAME_SAMPLES];
} voip_pcm_normalizer_t;

/* Task-only streaming PCM16 normalization; no allocation in push. */
int voip_pcm_normalizer_init(voip_pcm_normalizer_t *state,
        uint32_t input_rate, uint8_t channels);
void voip_pcm_normalizer_deinit(voip_pcm_normalizer_t *state);
int voip_pcm_normalizer_push(voip_pcm_normalizer_t *state, const uint8_t *raw,
        uint32_t bytes, uint32_t render_seq, uint64_t capture_end_ms,
        voip_pcm_frame_cb_t callback, void *user);

#endif
