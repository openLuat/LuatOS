/* Fixed 8kHz CC PCM <-> 16kHz SIP PCM conversion, without a frame workspace. */
#ifndef LUAT_VOIP_BRIDGE_PCM_H
#define LUAT_VOIP_BRIDGE_PCM_H

#include <stdint.h>

typedef struct {
    int16_t previous;
    uint8_t previous_valid;
} voip_bridge_pcm_upsampler_t;

static inline int16_t voip_bridge_pcm_downsample(int16_t first, int16_t second)
{
    return (int16_t)(((int32_t)first + (int32_t)second) / 2);
}

/* Place the midpoint before the current sample so interpolation remains
 * continuous across frames. The first sample seeds a new stream's history. */
static inline void voip_bridge_pcm_upsample(voip_bridge_pcm_upsampler_t *state,
        int16_t sample, int16_t pair[2])
{
    pair[0] = state->previous_valid ?
            voip_bridge_pcm_downsample(state->previous, sample) : sample;
    pair[1] = sample;
    state->previous = sample;
    state->previous_valid = 1;
}

#endif
