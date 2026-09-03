#ifndef LUAT_VOIP_AEC_SYNC_H
#define LUAT_VOIP_AEC_SYNC_H

#include <stdint.h>

enum {
    VOIP_AEC_SYNC_OK = 0,
    VOIP_AEC_SYNC_UNDERFLOW = -1,
    VOIP_AEC_SYNC_OVERFLOW = -2,
    VOIP_AEC_SYNC_FUTURE = -3,
    VOIP_AEC_SYNC_WARMUP = -4,
};

/*
 * Map the microphone frame end time onto the completed render sample
 * timeline. source_sample is the first render sample corresponding to the
 * microphone frame after the configured acoustic delay is removed.
 */
static inline int voip_aec_sync_reference_start(uint32_t render_seq,
        uint32_t frame_samples, uint32_t sample_rate, uint32_t delay_samples,
        uint64_t render_tick_ms, uint64_t capture_tick_ms,
        uint64_t *source_sample)
{
    int64_t delta_ms = 0;
    int64_t committed_end;
    int64_t target_end;

    if (!render_seq || !frame_samples || !sample_rate || !source_sample) {
        return VOIP_AEC_SYNC_UNDERFLOW;
    }
    if (render_tick_ms && capture_tick_ms) {
        if (capture_tick_ms >= render_tick_ms) {
            delta_ms = (int64_t)(capture_tick_ms - render_tick_ms);
        } else {
            delta_ms = -(int64_t)(render_tick_ms - capture_tick_ms);
        }
    }

    committed_end = (int64_t)render_seq * frame_samples;
    target_end = committed_end + delta_ms * sample_rate / 1000 - delay_samples;
    if (target_end > committed_end) {
        return VOIP_AEC_SYNC_FUTURE;
    }
    if (target_end < (int64_t)frame_samples) {
        return VOIP_AEC_SYNC_WARMUP;
    }
    *source_sample = (uint64_t)(target_end - frame_samples);
    return VOIP_AEC_SYNC_OK;
}

static inline int voip_aec_sync_history_status(uint32_t committed_seq,
        uint32_t expected_seq, uint32_t latest_seq, uint32_t history_frames)
{
    if (committed_seq == expected_seq) {
        return VOIP_AEC_SYNC_OK;
    }
    if (latest_seq >= history_frames &&
        expected_seq <= latest_seq - history_frames) {
        return VOIP_AEC_SYNC_OVERFLOW;
    }
    return VOIP_AEC_SYNC_UNDERFLOW;
}

#endif
