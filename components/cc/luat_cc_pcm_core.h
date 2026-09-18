/* Pure PCM queues for CC <-> SIP. No RTOS or audio device dependency. */
#ifndef LUAT_CC_PCM_CORE_H
#define LUAT_CC_PCM_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LUAT_CC_PCM_CORE_QUEUE_FRAMES 6U
#define LUAT_CC_PCM_CORE_PREBUFFER_FRAMES 3U
#define LUAT_CC_PCM_CORE_8K_SAMPLES 160U
#define LUAT_CC_PCM_CORE_16K_SAMPLES 320U

#define LUAT_CC_PCM_CORE_BAD_ARG (-1)
#define LUAT_CC_PCM_CORE_STALE (-2)
#define LUAT_CC_PCM_CORE_STOPPED (-3)

typedef struct {
    uint32_t dl_pushed;
    uint32_t dl_popped;
    uint32_t dl_dropped;       /* Queue overflow: oldest frame discarded. */
    uint32_t dl_flushed;       /* Frames discarded by stop or rate change. */
    uint32_t dl_underflows;    /* Active pop with an empty DL queue. */
    uint32_t dl_high_water;
    uint32_t ul_pushed;
    uint32_t ul_popped;        /* Real frames, excluding generated silence. */
    uint32_t ul_dropped;
    uint32_t ul_flushed;
    uint32_t ul_underflows;    /* Running playout ran out; rebuffer begins. */
    uint32_t ul_prebuffer_silence;
    uint32_t ul_high_water;
    uint32_t rejected_session;
    uint32_t rejected_stopped;
    uint32_t rejected_format;
    uint32_t rate_changes;
    uint32_t session;
    uint32_t cc_rate;
    uint8_t running;
    uint8_t dl_queued;
    uint8_t ul_queued;
    uint8_t ul_ready;
} luat_cc_pcm_core_stats_t;

/** Caller-owned storage; fields are implementation details, not live stats.
 *
 * Every operation, including init/start/stop/get_stats, MUST be serialized by
 * the SAME caller-owned lock. The platform may use a short critical section.
 * No field may be read concurrently outside that lock: get_stats copies one
 * consistent snapshot while locked, and the caller may log that copy later.
 * Counter updates additionally use compiler atomics per repository rules.
 * Atomics do not replace serialization of queues, lifecycle, and snapshots;
 * no unlocked access to individual fields is supported.
 *
 * The core never retains caller PCM pointers, allocates memory, calls another
 * subsystem, or waits. Its storage must outlive all callbacks using it.
 */
typedef struct {
    int16_t dl[LUAT_CC_PCM_CORE_QUEUE_FRAMES][LUAT_CC_PCM_CORE_16K_SAMPLES];
    int16_t ul[LUAT_CC_PCM_CORE_QUEUE_FRAMES][LUAT_CC_PCM_CORE_8K_SAMPLES];
    luat_cc_pcm_core_stats_t counters;
    uint32_t session;
    uint32_t cc_rate;
    uint8_t running;
    uint8_t dl_read;
    uint8_t dl_count;
    uint8_t ul_read;
    uint8_t ul_count;
    uint8_t ul_ready;
} luat_cc_pcm_core_t;

/** Initialize before any callback can access the core. */
void luat_cc_pcm_core_init(luat_cc_pcm_core_t *core);

/** Start an owner-selected, nonzero session at 8000 or 16000 Hz.
 * A different session (or a stopped session) starts with empty queues and new
 * counters. An active same-session/same-rate start is a no-op. A rate change
 * in the active session flushes both queues and restarts UL prebuffering.
 * Only the lifecycle owner may call start; session numbers are opaque tokens,
 * not ordered sequence numbers. Use a new token for each distinct call.
 * Returns 0 on success, BAD_ARG for invalid parameters without changing state.
 */
int luat_cc_pcm_core_start(luat_cc_pcm_core_t *core, uint32_t session,
                           uint32_t cc_rate);

/** Close a matching session and flush queued PCM; matching repeated stop is OK.
 * A stale stop cannot close a newer session. Counters remain for inspection.
 */
int luat_cc_pcm_core_stop(luat_cc_pcm_core_t *core, uint32_t session);

/** Flush both queues and restart prebuffering without closing the session or
 * resetting counters/rate. Requires an active matching session; returns 0.
 */
int luat_cc_pcm_core_flush(luat_cc_pcm_core_t *core, uint32_t session);

/** Copy exactly one 20 ms CC DL frame (160 or 320 samples at current rate).
 * Both queues discard their oldest frame on overflow. Returns 1 or an error.
 */
int luat_cc_pcm_core_push_dl(luat_cc_pcm_core_t *core, uint32_t session,
                             const int16_t *pcm, uint16_t samples);

/** Pop one DL frame, converting it to 160 samples at 8 kHz.
 * Returns 160, 0 if empty, or an error. Empty/error leaves out untouched.
 * out must have room for 160 samples and must not alias core storage.
 */
int luat_cc_pcm_core_pop_dl(luat_cc_pcm_core_t *core, uint32_t session,
                            int16_t *out);

/** Copy exactly 160 samples of SIP UL PCM at 8 kHz. Returns 1 or an error. */
int luat_cc_pcm_core_push_ul(luat_cc_pcm_core_t *core, uint32_t session,
                             const int16_t *pcm, uint16_t samples);

/** Produce one 20 ms frame at the current CC rate: returns 160 or 320.
 * Starts after three queued frames. Before startup and after a true underrun,
 * produces silence while accumulating three frames again. No timer is owned
 * here: the caller must invoke this on its established CC upload cadence.
 * Returns an error without touching out when inactive/stale/undersized.
 * out must not alias core storage; capacity_samples is in int16_t samples.
 */
int luat_cc_pcm_core_pop_ul(luat_cc_pcm_core_t *core, uint32_t session,
                            int16_t *out, uint16_t capacity_samples);

/** Copy a consistent per-session snapshot under the same serialization lock. */
void luat_cc_pcm_core_get_stats(const luat_cc_pcm_core_t *core,
                               luat_cc_pcm_core_stats_t *out);

#ifdef __cplusplus
}
#endif
#endif
