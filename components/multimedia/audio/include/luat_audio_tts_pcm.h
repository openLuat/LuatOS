#ifndef LUAT_AUDIO_TTS_PCM_H
#define LUAT_AUDIO_TTS_PCM_H

#include <stddef.h>

/** Opaque handle owned by one caller; control APIs run on the Lua thread. */
typedef struct luat_audio_tts_pcm_session luat_audio_tts_pcm_session_t;

typedef enum {
    LUAT_AUDIO_TTS_PCM_RUNNING,
    LUAT_AUDIO_TTS_PCM_DONE,
    LUAT_AUDIO_TTS_PCM_STOPPING,
    LUAT_AUDIO_TTS_PCM_STOPPED,
    LUAT_AUDIO_TTS_PCM_ERROR
} luat_audio_tts_pcm_state_t;

typedef enum {
    LUAT_AUDIO_TTS_PCM_OK,
    LUAT_AUDIO_TTS_PCM_UNSUPPORTED,
    LUAT_AUDIO_TTS_PCM_BUSY,
    LUAT_AUDIO_TTS_PCM_INVALID_TEXT,
    LUAT_AUDIO_TTS_PCM_NO_MEMORY,
    LUAT_AUDIO_TTS_PCM_INIT_FAILED,
    LUAT_AUDIO_TTS_PCM_FORMAT_ERROR,
    LUAT_AUDIO_TTS_PCM_DECODE_FAILED
} luat_audio_tts_pcm_reason_t;

/** Copy a nonempty UTF-8 text and start the sole PCM synthesis session. */
luat_audio_tts_pcm_reason_t luat_audio_tts_pcm_start(const char *text, size_t length,
                                                  luat_audio_tts_pcm_session_t **session);
/**
 * Read currently available 16 kHz signed little-endian mono PCM without waiting
 * for synthesis. The final bytes may accompany DONE. Terminal states guarantee
 * engine/FIFO/synchronization resources and the service slot have been released.
 */
size_t luat_audio_tts_pcm_read(luat_audio_tts_pcm_session_t *session, void *buffer,
                             size_t capacity, luat_audio_tts_pcm_state_t *state,
                             luat_audio_tts_pcm_reason_t *reason);
/** Request cancellation; idempotent and never destroys a running codec. */
void luat_audio_tts_pcm_stop(luat_audio_tts_pcm_session_t *session);
/** Request stop and relinquish the caller reference; do not reuse the handle. */
void luat_audio_tts_pcm_release(luat_audio_tts_pcm_session_t *session);
const char *luat_audio_tts_pcm_state_name(luat_audio_tts_pcm_state_t state);
const char *luat_audio_tts_pcm_reason_name(luat_audio_tts_pcm_reason_t reason);

#endif
