/*
 * luat_voip_record.h - non-blocking VoIP PCM recorder
 */

#ifndef LUAT_VOIP_RECORD_H
#define LUAT_VOIP_RECORD_H

#include "luat_base.h"

#define VOIP_RECORD_PATH_MAX       256
#define VOIP_RECORD_FRAME_SAMPLES  160

typedef enum {
    VOIP_RECORD_IDLE = 0,
    VOIP_RECORD_ARMED,
    VOIP_RECORD_RECORDING,
    VOIP_RECORD_STOPPING,
    VOIP_RECORD_ERROR,
} voip_record_state_t;

typedef enum {
    VOIP_RECORD_EVENT_STARTED = 1,
    VOIP_RECORD_EVENT_STOPPED,
    VOIP_RECORD_EVENT_ERROR,
} voip_record_event_t;

typedef struct {
    voip_record_state_t state;
    char path[VOIP_RECORD_PATH_MAX];
    char reason[24];
    uint32_t bytes;
    uint32_t duration_ms;
    uint32_t queued_frames;
    uint32_t dropped_frames;
} voip_record_status_t;

typedef void (*voip_record_notify_cb_t)(voip_record_event_t event);

#ifdef LUAT_USE_VOIP_RECORD
int luat_voip_record_init(voip_record_notify_cb_t notify_cb);
int luat_voip_record_start(const char *path, uint32_t max_seconds, int media_running);
int luat_voip_record_media_started(void);
int luat_voip_record_stop(const char *reason);
void luat_voip_record_tap_tx(const int16_t *pcm, uint16_t samples);
void luat_voip_record_tap_rx(const int16_t *pcm, uint16_t samples);
void luat_voip_record_get_status(voip_record_status_t *status);
const char *luat_voip_record_state_name(voip_record_state_t state);
#endif

#endif
