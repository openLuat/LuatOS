#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#include "../src/luat_voip_aec_sync.h"

#define FRAME_SAMPLES 160U
#define SAMPLE_RATE 8000U
#define HISTORY_FRAMES 8U

static uint32_t source_seq(uint64_t source_sample)
{
    return (uint32_t)(source_sample / FRAME_SAMPLES) + 1U;
}

int main(void)
{
    uint64_t source = 0;
    int16_t far_end[10U * FRAME_SAMPLES];
    int16_t near_end[FRAME_SAMPLES];
    int16_t microphone[FRAME_SAMPLES];

    /* Silent startup: a delayed reference is not available yet. */
    assert(voip_aec_sync_reference_start(1, FRAME_SAMPLES, SAMPLE_RATE, 160,
            1000, 1000, &source) == VOIP_AEC_SYNC_WARMUP);

    /* Exact frame alignment and the default 20 ms acoustic delay. */
    assert(voip_aec_sync_reference_start(5, FRAME_SAMPLES, SAMPLE_RATE, 0,
            1100, 1100, &source) == VOIP_AEC_SYNC_OK);
    assert(source_seq(source) == 5);
    assert(voip_aec_sync_reference_start(5, FRAME_SAMPLES, SAMPLE_RATE, 160,
            1100, 1100, &source) == VOIP_AEC_SYNC_OK);
    assert(source_seq(source) == 4);

    /* Independent callbacks may arrive a few milliseconds apart. */
    assert(voip_aec_sync_reference_start(5, FRAME_SAMPLES, SAMPLE_RATE, 160,
            1100, 1102, &source) == VOIP_AEC_SYNC_OK);
    assert(source == 496);
    assert(voip_aec_sync_reference_start(5, FRAME_SAMPLES, SAMPLE_RATE, 0,
            1100, 1102, &source) == VOIP_AEC_SYNC_FUTURE);
    assert(voip_aec_sync_reference_start(5, FRAME_SAMPLES, SAMPLE_RATE, 0,
            1100, 1098, &source) == VOIP_AEC_SYNC_OK);
    assert(source == 624);

    /* Exercise 0-100 ms delay windows across ring wrap boundaries. */
    for (uint32_t i = 0; i < 10U * FRAME_SAMPLES; i++) {
        far_end[i] = (int16_t)(((i * 73U) % 2001U) - 1000);
    }
    for (uint32_t i = 0; i < FRAME_SAMPLES; i++) {
        near_end[i] = (int16_t)((i & 1U) ? 200 : -200);
    }
    for (uint32_t delay = 0; delay <= 800; delay += 80) {
        assert(voip_aec_sync_reference_start(10, FRAME_SAMPLES, SAMPLE_RATE,
                delay, 1200, 1200, &source) == VOIP_AEC_SYNC_OK);
        assert(source == 10U * FRAME_SAMPLES - delay - FRAME_SAMPLES);
        for (uint32_t i = 0; i < FRAME_SAMPLES; i++) {
            /* Synthetic echo plus independent near-end speech (double talk). */
            microphone[i] = (int16_t)(far_end[source + i] + near_end[i]);
            assert((int16_t)(microphone[i] - near_end[i]) ==
                    far_end[source + i]);
        }
    }

    /* Missing callbacks are underflow; overwritten ring slots are overflow. */
    assert(voip_aec_sync_history_status(0, 9, 10, HISTORY_FRAMES) ==
            VOIP_AEC_SYNC_UNDERFLOW);
    assert(voip_aec_sync_history_status(11, 3, 11, HISTORY_FRAMES) ==
            VOIP_AEC_SYNC_OVERFLOW);
    /* Once the missing slot is committed, processing can recover. */
    assert(voip_aec_sync_history_status(9, 9, 10, HISTORY_FRAMES) ==
            VOIP_AEC_SYNC_OK);
    assert(voip_aec_sync_history_status(10, 10, 10, HISTORY_FRAMES) ==
            VOIP_AEC_SYNC_OK);

    /* A restarted session starts a new sequence and must not reuse old slots. */
    assert(voip_aec_sync_history_status(0, 1, 1, HISTORY_FRAMES) ==
            VOIP_AEC_SYNC_UNDERFLOW);
    assert(voip_aec_sync_history_status(1, 1, 1, HISTORY_FRAMES) ==
            VOIP_AEC_SYNC_OK);

    puts("voip AEC synchronization tests passed");
    return 0;
}
