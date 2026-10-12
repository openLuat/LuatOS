/* PCM16LE conversion matching audio_7014.lua, with per-instance history. */
#ifndef LUAT_VOIP_PCM_RESAMPLER_H
#define LUAT_VOIP_PCM_RESAMPLER_H

#include <stddef.h>
#include <stdint.h>

#define VOIP_PCM_RESAMPLER_MAX_OUTPUT_BYTES 640U
#define VOIP_PCM_RESAMPLER_DOWN 1U
#define VOIP_PCM_RESAMPLER_UP 2U

typedef struct {
    int32_t h1, h2, h3, h4, h5, previous;
    uint8_t direction, gain;
} voip_pcm_resampler_t;

/* Clear only signal history; keep the selected rates and gain. */
static inline void voip_pcm_resampler_reset(voip_pcm_resampler_t *state)
{
    if (!state) return;
    state->h1 = state->h2 = state->h3 = state->h4 = state->h5 = 0;
    state->previous = 0;
}

/* Invalid configuration leaves an existing instance unchanged. */
static inline int voip_pcm_resampler_init(voip_pcm_resampler_t *state,
        uint32_t in_rate, uint32_t out_rate, unsigned gain)
{
    uint8_t direction;
    if (!state || gain < 1U || gain > 8U) return -1;
    if (in_rate == 16000U && out_rate == 8000U) {
        direction = VOIP_PCM_RESAMPLER_DOWN;
    } else if (in_rate == 8000U && out_rate == 16000U && gain == 1U) {
        direction = VOIP_PCM_RESAMPLER_UP;
    } else {
        return -1;
    }
    state->direction = direction;
    state->gain = (uint8_t)gain;
    voip_pcm_resampler_reset(state);
    return 0;
}

static inline int32_t voip_pcm_resampler_read(const uint8_t *input)
{
    uint32_t bits = (uint32_t)input[0] | ((uint32_t)input[1] << 8);
    return bits < 32768U ? (int32_t)bits : (int32_t)bits - 65536;
}

static inline void voip_pcm_resampler_write(uint8_t *output, int32_t value)
{
    uint16_t bits = (uint16_t)value;
    output[0] = (uint8_t)bits;
    output[1] = (uint8_t)(bits >> 8);
}

/* Lua // rounds toward negative infinity. C division truncates toward zero;
 * avoid implementation-defined right shifts of negative signed values. */
static inline int32_t voip_pcm_resampler_floor(int32_t value, int32_t divisor)
{
    int32_t result = value / divisor;
    if (value < 0 && value % divisor) result--;
    return result;
}

/* Input/output are separate PCM16LE byte buffers; no aligned access is used.
 * Down: 0..512 input bytes, divisible by four. Up: 0..320, divisible by two.
 * Success returns output bytes and writes this call's clip count when supplied.
 * Invalid input (-1) or insufficient capacity (-2) changes neither history,
 * output nor clip count. Empty input accepts NULL input/output buffers. */
static inline int voip_pcm_resampler_process(voip_pcm_resampler_t *state,
        const uint8_t *input, size_t bytes, uint8_t *output, size_t capacity,
        uint32_t *clipped)
{
    size_t needed;
    size_t i, made = 0;
    uint32_t clips = 0;
    voip_pcm_resampler_t next;
    if (!state) return -1;
    if (state->direction == VOIP_PCM_RESAMPLER_DOWN) {
        if (state->gain < 1U || state->gain > 8U || bytes > 512U || bytes % 4U) return -1;
        needed = bytes / 2U;
    } else if (state->direction == VOIP_PCM_RESAMPLER_UP) {
        if (state->gain != 1U || bytes > 320U || bytes % 2U) return -1;
        needed = bytes * 2U;
    } else {
        return -1;
    }
    if (bytes && (!input || !output)) return -1;
    if (capacity < needed) return -2;
    next = *state;
    if (next.direction == VOIP_PCM_RESAMPLER_DOWN) {
        for (i = 0; i < bytes; i += 4U) {
            int32_t a = voip_pcm_resampler_read(input + i);
            int32_t b = voip_pcm_resampler_read(input + i + 2U);
            int32_t value = voip_pcm_resampler_floor(b + next.h5 +
                    6 * (a + next.h4) + 15 * (next.h1 + next.h3) +
                    20 * next.h2 + 32, 64) * next.gain;
            if (value > 32767) {
                value = 32767;
                clips++;
            } else if (value < -32768) {
                value = -32768;
                clips++;
            }
            voip_pcm_resampler_write(output + made, value);
            made += 2U;
            next.h5 = next.h3;
            next.h4 = next.h2;
            next.h3 = next.h1;
            next.h2 = a;
            next.h1 = b;
        }
    } else {
        for (i = 0; i < bytes; i += 2U) {
            int32_t value = voip_pcm_resampler_read(input + i);
            int32_t midpoint = voip_pcm_resampler_floor(next.previous + value + 1, 2);
            voip_pcm_resampler_write(output + made, midpoint);
            voip_pcm_resampler_write(output + made + 2U, value);
            made += 4U;
            next.previous = value;
        }
    }
    *state = next;
    if (clipped) *clipped = clips;
    return (int)made;
}

#endif
