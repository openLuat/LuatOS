/* Wideband UART bridge receive queue and continuous 8/16 kHz conversion. */
#ifndef LUAT_CC_UART_MEDIA_H
#define LUAT_CC_UART_MEDIA_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LUAT_CC_UART_MEDIA_FRAME 320U
#define LUAT_CC_UART_MEDIA_QUEUE_FRAMES 6U
#define LUAT_CC_UART_MEDIA_PREBUFFER_FRAMES 3U
#define LUAT_CC_UART_MEDIA_CAPACITY (LUAT_CC_UART_MEDIA_FRAME * \
                                    LUAT_CC_UART_MEDIA_QUEUE_FRAMES)
#define LUAT_CC_UART_MEDIA_BAD_ARG (-1)
#define LUAT_CC_UART_MEDIA_STALE (-2)
#define LUAT_CC_UART_MEDIA_STOPPED (-3)

typedef struct {
    int32_t proportional_ppm; /* Default 1000 ppm / frame; validated at -1000 ppm. */
    int32_t integral_ppm;     /* Default 10 ppm / frame / second. */
    int32_t limit_ppm;        /* Default 1000 ppm. */
    int32_t slew_ppm;         /* Default 50 ppm / second. */
} luat_cc_uart_media_clock_config_t;

typedef struct {
    uint32_t pushed;
    uint32_t popped;
    uint32_t dropped_samples;
    uint32_t flushed_samples;
    uint32_t underflows;
    uint32_t prebuffer_silence;
    uint32_t lost_frames;
    uint32_t duplicate_frames;
    uint32_t late_frames;
    uint32_t rejected_session;
    uint32_t rejected_format;
    uint32_t high_water_samples;
    uint64_t session;
    uint32_t epoch;
    uint16_t queued_samples;
    int32_t clock_ppm;
    uint8_t running;
    uint8_t ready;
} luat_cc_uart_media_stats_t;

/** Internal fields must not be inspected concurrently. Every operation,
 * including init/configure/start/stop/ready/get_stats, requires the same owner
 * lock. The backend is responsible for threading and epoch ownership.
 * This core never allocates, waits, retains PCM pointers, or calls other code. */
typedef struct {
    int16_t samples[LUAT_CC_UART_MEDIA_CAPACITY];
    luat_cc_uart_media_stats_t counters;
    luat_cc_uart_media_clock_config_t clock;
    uint64_t session;
    uint32_t epoch;
    uint32_t last_sequence;
    uint32_t phase;           /* Fractional source sample in millionths. */
    uint32_t occupancy_sum;
    int32_t integral_scaled; /* ppm times 1000. */
    int32_t clock_ppm;
    uint16_t read;
    uint16_t count;
    uint8_t running;
    uint8_t ready;
    uint8_t have_sequence;
    uint8_t observation_ticks;
} luat_cc_uart_media_t;

void luat_cc_uart_media_init(luat_cc_uart_media_t *core);

/** Configure while stopped. Nonnegative gains, limit 0..5000, slew 1..5000.
 * A zero limit disables clock adaptation for deterministic diagnostics. */
int luat_cc_uart_media_configure(luat_cc_uart_media_t *core,
                                 const luat_cc_uart_media_clock_config_t *config);

/** Nonzero session/epoch. Same active pair is idempotent; a new pair resets
 * media, interpolation, sequence tracking, PI state, and call counters. */
int luat_cc_uart_media_start(luat_cc_uart_media_t *core, uint64_t session,
                             uint32_t epoch);
int luat_cc_uart_media_stop(luat_cc_uart_media_t *core, uint64_t session);
int luat_cc_uart_media_flush(luat_cc_uart_media_t *core, uint64_t session,
                             uint32_t epoch);

/** Copy exactly 320 samples. Reject old session/epoch and duplicate/late seq.
 * UART audio sequence is monotonic modulo 2^32; it is independent of control.
 * A gap adds bounded silence to preserve its missing 20 ms positions.
 * Overflow discards oldest samples and restores a three-frame fresh window.
 * Returns 1 accepted, 0 duplicate/late, or a negative error. */
int luat_cc_uart_media_push(luat_cc_uart_media_t *core, uint64_t session,
                            uint32_t epoch, uint32_t sequence,
                            const int16_t *pcm);

/** Produce 320 samples on every established CC 20 ms upload tick. Before three
 * frames or after underflow, emit silence and re-prime. Fractional interpolation
 * adjusts source consumption using a one-second PI queue observation.
 * Returns 320, or a negative error without changing out. */
int luat_cc_uart_media_pop(luat_cc_uart_media_t *core, uint64_t session,
                           uint32_t epoch, int16_t *out);

/** Three-frame prebuffer has completed since start/flush/underflow. Once
 * playback begins this stays true while the source queue remains playable.
 * Read under the owner lock; priming owners do not call pop before COMMIT. */
int luat_cc_uart_media_ready(const luat_cc_uart_media_t *core);
void luat_cc_uart_media_get_stats(const luat_cc_uart_media_t *core,
                                 luat_cc_uart_media_stats_t *out);

/** Filter history belongs to a single unidirectional conversion stream.
 * Reset on new call or source format change, not on every 20 ms frame. */
typedef struct {
    int16_t history[15];
    uint16_t input_rate;
    uint16_t output_rate;
    uint8_t at;
} luat_cc_uart_resampler_t;

void luat_cc_uart_resampler_init(luat_cc_uart_resampler_t *resampler);

/** Stateful low-pass 8<->16 kHz conversion, exactly one 20 ms frame. In/out
 * must not overlap; output holds 160 or 320 samples. Same-rate 16 kHz preserves
 * all samples. Returns output sample count or BAD_ARG, leaving out unchanged
 * for bad arguments. Rate changes reset filter history automatically. */
int luat_cc_uart_resampler_convert(luat_cc_uart_resampler_t *resampler,
                                   const int16_t *in, uint16_t input_samples,
                                   uint32_t input_rate, int16_t *out,
                                   uint16_t output_capacity,
                                   uint32_t output_rate);

#ifdef __cplusplus
}
#endif
#endif
