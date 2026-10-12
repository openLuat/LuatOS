#ifndef LUAT_VOIP_PLAY_H
#define LUAT_VOIP_PLAY_H

#include <stddef.h>
#include <stdint.h>

typedef enum {
    LUAT_VOIP_PLAY_TARGET_SIP = 1,
    LUAT_VOIP_PLAY_TARGET_CC = 2,
    LUAT_VOIP_PLAY_TARGET_BOTH = 3
} luat_voip_play_target_t;

typedef enum {
    LUAT_VOIP_PLAY_REPLACE = 0,
    LUAT_VOIP_PLAY_MIX = 1
} luat_voip_play_mode_t;

typedef enum {
    LUAT_VOIP_PLAY_IDLE = 0,
    LUAT_VOIP_PLAY_LOADING = 1,
    LUAT_VOIP_PLAY_PLAYING = 2,
    LUAT_VOIP_PLAY_STOPPING = 3
} luat_voip_play_state_t;

typedef enum {
    LUAT_VOIP_PLAY_OK = 0,
    LUAT_VOIP_PLAY_E_INVALID = -1,
    LUAT_VOIP_PLAY_E_BUSY = -2,
    LUAT_VOIP_PLAY_E_NOT_RUNNING = -3,
    LUAT_VOIP_PLAY_E_UNSUPPORTED = -4,
    LUAT_VOIP_PLAY_E_CC_NOT_READY = -5,
    LUAT_VOIP_PLAY_E_NO_MEMORY = -6,
    LUAT_VOIP_PLAY_E_OPEN = -7,
    LUAT_VOIP_PLAY_E_DECODE = -8,
    LUAT_VOIP_PLAY_E_NOT_FOUND = -9
} luat_voip_play_error_t;

/* All fields identify the CC media bound at job admission. */
typedef struct {
    uint32_t session;
    uint32_t phase;
    uint32_t epoch;
} luat_voip_play_cc_media_t;

typedef struct {
    uint32_t sample_rate; /* Raw PCM16LE input rate; 0 defaults to 8000. */
    uint16_t gain_q15; /* 0..32768; 32768 is unity. */
    uint16_t speech_gain_q15;
    uint8_t channels; /* Raw input channels: 1 or 2; 0 defaults to 1. */
    uint8_t target;
    uint8_t mode;
} luat_voip_play_options_t;

typedef struct {
    uint32_t id;
    uint32_t session;
    uint8_t state;
    uint8_t target;
    uint8_t mode;
    uint32_t played_samples[2]; /* 8 kHz source samples committed to SIP/CC. */
    char reason[32];
} luat_voip_play_status_t;

/* Callback runs in the producer task; status is a snapshot valid during the call.
 * Events are "started", "done", "stopped", "error". init is repeatable. */
int luat_voip_play_init(void (*notify)(const char *, const luat_voip_play_status_t *));
int luat_voip_play_start_tts(const char *text, size_t len,
        const luat_voip_play_options_t *options, uint32_t *id);
int luat_voip_play_start_file(const char *path,
        const luat_voip_play_options_t *options, uint32_t *id);
int luat_voip_play_stop(uint32_t id);
void luat_voip_play_cancel(const char *reason);
void luat_voip_play_cancel_target(uint8_t target, const char *reason);
/* Failures finish with error; user/media cancellation finishes with stopped. */
void luat_voip_play_fail_target(uint8_t target, const char *reason);
void luat_voip_play_get_status(luat_voip_play_status_t *status);
uint32_t luat_voip_play_active(uint8_t target);

/* Task-only, bounded work. render peeks one frame and never consumes it.
 * Only 160 samples at 8 kHz or 320 samples at 16 kHz are accepted. A zero
 * token leaves pcm unchanged except an active REPLACE underrun produces silence. Commit only after successful transport upload.
 * Each target has one consumer. A repeated render before commit retries the
 * same source frame. Stop/session changes invalidate outstanding tokens.
 * SIP passes NULL. CC passes a snapshot taken while holding its media lock
 * and keeps that lock through render, submit and commit. No media snapshot
 * function may be called while holding the play queue lock. */
uint32_t luat_voip_play_render(uint8_t target, int16_t *pcm,
        uint16_t samples, uint32_t rate, const luat_voip_play_cc_media_t *media);
void luat_voip_play_commit(uint8_t target, uint32_t id);
const char *luat_voip_play_error(int error);

/* Platform/core hooks. CC playback requires the pure PCM bridge backend. */
int luat_voip_play_cc_snapshot(luat_voip_play_cc_media_t *media);
/* 0 for running G.711/8 kHz/20 ms; otherwise a play error. */
int voip_play_media_snapshot(uint32_t *session);
void voip_play_wakeup(void);

#endif
