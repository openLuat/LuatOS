#include "luat_base.h"
#ifdef LUAT_CSDK_CONFIG_FILE
#include LUAT_CSDK_CONFIG_FILE
#endif

#ifdef LUAT_USE_AUDIO_TTS_PCM
#include "luat_audio_tts_pcm.h"
#include "luat_audio_data_codec.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include <stdint.h>
#include <string.h>

#define TTS_PCM_FIFO_SIZE (16 * 1024)

typedef struct tts_pcm_job tts_pcm_job_t;

struct luat_audio_tts_pcm_session {
    tts_pcm_job_t *job;
    luat_audio_tts_pcm_state_t state;
    luat_audio_tts_pcm_reason_t reason;
    uint8_t owned;
};

struct tts_pcm_job {
    luat_audio_tts_pcm_session_t *session;
    luat_audio_data_codec_t codec;
    const luat_audio_data_codec_opts_t *opts;
    char *text;
    size_t text_length;
    uint8_t *fifo;
    size_t read_pos;
    size_t used;
    luat_rtos_semaphore_t space;
    luat_rtos_task_handle task;
    uint8_t cancel;
    uint8_t format_seen;
    uint8_t decoder_done;
};

/* Control APIs have one owner (the Lua thread); only the worker is concurrent.
 * This service mutex is shared by all sessions, including terminal handles.
 * No per-session RTOS object remains after publication of a terminal state. */
static luat_rtos_mutex_t tts_pcm_mutex;
static luat_audio_tts_pcm_session_t *tts_pcm_active;

static int tts_pcm_valid_utf8(const char *text, size_t length)
{
    size_t pos = 0;
    if (!text || !length || length > UINT32_MAX || length == SIZE_MAX) return 0;
    while (pos < length) {
        uint32_t value;
        uint32_t minimum;
        unsigned remaining;
        uint8_t c = (uint8_t)text[pos++];
        if (c < 0x80) continue;
        if (c >= 0xc2 && c <= 0xdf) {
            value = c & 0x1f; minimum = 0x80; remaining = 1;
        } else if (c >= 0xe0 && c <= 0xef) {
            value = c & 0x0f; minimum = 0x800; remaining = 2;
        } else if (c >= 0xf0 && c <= 0xf4) {
            value = c & 0x07; minimum = 0x10000; remaining = 3;
        } else return 0;
        if (remaining > length - pos) return 0;
        while (remaining--) {
            c = (uint8_t)text[pos++];
            if ((c & 0xc0) != 0x80) return 0;
            value = (value << 6) | (c & 0x3f);
        }
        if (value < minimum || value > 0x10ffff ||
            (value >= 0xd800 && value <= 0xdfff)) return 0;
    }
    return 1;
}

static void tts_pcm_free_job(tts_pcm_job_t *job)
{
    if (job->space) luat_rtos_semaphore_delete(job->space);
    luat_heap_free(job->text);
    luat_heap_free(job->fifo);
    luat_heap_free(job);
}

/* Caller holds the service mutex. The synthesis call and codec cleanup have
 * already finished; the worker must not access job/session after this call. */
static void tts_pcm_finish_locked(luat_audio_tts_pcm_session_t *session,
                                  luat_audio_tts_pcm_state_t state)
{
    tts_pcm_free_job(session->job);
    session->job = NULL;
    if (tts_pcm_active == session) tts_pcm_active = NULL;
    session->state = state;
    if (!session->owned) luat_heap_free(session);
}

static int tts_pcm_output(void *data, uint32_t length, void *user_data)
{
    tts_pcm_job_t *job = user_data;
    const uint8_t *input = data;
    size_t offset = 0;
    luat_rtos_mutex_lock(tts_pcm_mutex, LUAT_WAIT_FOREVER);
    if (job->cancel) {
        luat_rtos_mutex_unlock(tts_pcm_mutex);
        return -1;
    }
    if (!data) {
        const luat_audio_common_param_t *format = &job->codec.common_param;
        if (format->sample_rate != 16000 || format->data_align != 2 ||
            format->channel_nums != 1 || !format->is_signed) {
            job->session->reason = LUAT_AUDIO_TTS_PCM_FORMAT_ERROR;
        } else job->format_seen = 1;
        int result = job->session->reason == LUAT_AUDIO_TTS_PCM_OK ? 0 : -1;
        luat_rtos_mutex_unlock(tts_pcm_mutex);
        return result;
    }
    if (!job->format_seen || (length & 1)) {
        job->session->reason = LUAT_AUDIO_TTS_PCM_FORMAT_ERROR;
        luat_rtos_mutex_unlock(tts_pcm_mutex);
        return -1;
    }
    while (offset < length) {
        if (job->cancel) {
            luat_rtos_mutex_unlock(tts_pcm_mutex);
            return -1;
        }
        if (job->used == TTS_PCM_FIFO_SIZE) {
            luat_rtos_mutex_unlock(tts_pcm_mutex);
            luat_rtos_semaphore_take(job->space, LUAT_WAIT_FOREVER);
            luat_rtos_mutex_lock(tts_pcm_mutex, LUAT_WAIT_FOREVER);
            continue;
        }
        size_t write_pos = (job->read_pos + job->used) % TTS_PCM_FIFO_SIZE;
        size_t count = TTS_PCM_FIFO_SIZE - job->used;
        if (count > length - offset) count = length - offset;
        if (count > TTS_PCM_FIFO_SIZE - write_pos) count = TTS_PCM_FIFO_SIZE - write_pos;
        memcpy(job->fifo + write_pos, input + offset, count);
        job->used += count;
        offset += count;
    }
    luat_rtos_mutex_unlock(tts_pcm_mutex);
    return 0;
}

static void tts_pcm_worker(void *user_data)
{
    tts_pcm_job_t *job = user_data;
    int result = 0;
    int bound = 0;
    int cancel;
    luat_audio_tts_pcm_reason_t failure = LUAT_AUDIO_TTS_PCM_OK;
    /* start holds this mutex through task creation, so task is initialized
     * before the worker can capture it, even on a preemptive RTOS. */
    luat_rtos_mutex_lock(tts_pcm_mutex, LUAT_WAIT_FOREVER);
    luat_rtos_task_handle task = job->task;
    cancel = job->cancel;
    luat_rtos_mutex_unlock(tts_pcm_mutex);
    if (!cancel) {
        result = luat_audio_data_codec_bind(&job->codec, job->opts, job);
        if (result) failure = LUAT_AUDIO_TTS_PCM_NO_MEMORY;
        else {
            bound = 1;
            result = job->opts->init(&job->codec, 0);
            if (result) failure = LUAT_AUDIO_TTS_PCM_INIT_FAILED;
            else {
                luat_rtos_mutex_lock(tts_pcm_mutex, LUAT_WAIT_FOREVER);
                cancel = job->cancel;
                luat_rtos_mutex_unlock(tts_pcm_mutex);
                if (!cancel) {
                    job->codec.param.tts_output_callback = tts_pcm_output;
                    result = job->opts->tts_decode_sync(&job->codec, job->text,
                                                       (uint32_t)job->text_length, job);
                    if (result) failure = LUAT_AUDIO_TTS_PCM_DECODE_FAILED;
                }
            }
        }
    }
    if (bound) luat_audio_data_codec_unbind(&job->codec);
    luat_heap_free(job->text);
    job->text = NULL;
    luat_rtos_mutex_lock(tts_pcm_mutex, LUAT_WAIT_FOREVER);
    luat_audio_tts_pcm_session_t *session = job->session;
    job->decoder_done = 1;
    /* No callback can wait for space after tts_decode_sync has returned. */
    luat_rtos_semaphore_delete(job->space);
    job->space = NULL;
    if (job->cancel) {
        session->reason = LUAT_AUDIO_TTS_PCM_OK;
        tts_pcm_finish_locked(session, LUAT_AUDIO_TTS_PCM_STOPPED);
    } else {
        if (session->reason == LUAT_AUDIO_TTS_PCM_OK) session->reason = failure;
        if (session->reason != LUAT_AUDIO_TTS_PCM_OK)
            tts_pcm_finish_locked(session, LUAT_AUDIO_TTS_PCM_ERROR);
        else if (!job->used)
            tts_pcm_finish_locked(session, LUAT_AUDIO_TTS_PCM_DONE);
    }
    luat_rtos_mutex_unlock(tts_pcm_mutex);
    /* The owner may already release a terminal handle. Use only the saved
     * task handle here; job and session may both have been freed. */
    luat_rtos_task_delete(task);
}

luat_audio_tts_pcm_reason_t luat_audio_tts_pcm_start(const char *text, size_t length,
                                                  luat_audio_tts_pcm_session_t **out)
{
    luat_audio_tts_pcm_session_t *session = NULL;
    tts_pcm_job_t *job = NULL;
    const luat_audio_data_codec_opts_t *opts;
    if (!out) return LUAT_AUDIO_TTS_PCM_INVALID_TEXT;
    *out = NULL;
    if (!tts_pcm_valid_utf8(text, length)) return LUAT_AUDIO_TTS_PCM_INVALID_TEXT;
    opts = luat_audio_data_codec_find(LUAT_AUDIO_DATA_CODEC_TYPE_TTS);
    if (!opts || !opts->init || !opts->deinit || !opts->tts_decode_sync ||
        opts->is_tts_asynchronous) return LUAT_AUDIO_TTS_PCM_UNSUPPORTED;
    if (!tts_pcm_mutex && luat_rtos_mutex_create(&tts_pcm_mutex))
        return LUAT_AUDIO_TTS_PCM_NO_MEMORY;
    luat_rtos_mutex_lock(tts_pcm_mutex, LUAT_WAIT_FOREVER);
    if (tts_pcm_active) {
        luat_rtos_mutex_unlock(tts_pcm_mutex);
        return LUAT_AUDIO_TTS_PCM_BUSY;
    }
    session = luat_heap_malloc(sizeof(*session));
    if (!session) goto no_memory;
    memset(session, 0, sizeof(*session));
    job = luat_heap_malloc(sizeof(*job));
    if (!job) goto no_memory;
    memset(job, 0, sizeof(*job));
    job->text = luat_heap_malloc(length + 1);
    job->fifo = luat_heap_malloc(TTS_PCM_FIFO_SIZE);
    if (!job->text || !job->fifo || luat_rtos_semaphore_create(&job->space, 0))
        goto no_memory;
    memcpy(job->text, text, length);
    job->text[length] = 0;
    job->text_length = length;
    job->opts = opts;
    job->session = session;
    session->job = job;
    session->owned = 1;
    session->state = LUAT_AUDIO_TTS_PCM_RUNNING;
    tts_pcm_active = session;
    if (luat_rtos_task_create(&job->task, LUAT_AUDIO_TASK_STACK,
                              LUAT_AUDIO_TTS_TASK_PRIORITY, "tts_pcm",
                              tts_pcm_worker, job, 0)) {
        tts_pcm_active = NULL;
        goto no_memory;
    }
    *out = session;
    luat_rtos_mutex_unlock(tts_pcm_mutex);
    return LUAT_AUDIO_TTS_PCM_OK;
no_memory:
    if (job) tts_pcm_free_job(job);
    luat_heap_free(session);
    luat_rtos_mutex_unlock(tts_pcm_mutex);
    return LUAT_AUDIO_TTS_PCM_NO_MEMORY;
}

size_t luat_audio_tts_pcm_read(luat_audio_tts_pcm_session_t *session, void *buffer,
                             size_t capacity, luat_audio_tts_pcm_state_t *state,
                             luat_audio_tts_pcm_reason_t *reason)
{
    size_t count = 0;
    if (!session) {
        if (state) *state = LUAT_AUDIO_TTS_PCM_ERROR;
        if (reason) *reason = LUAT_AUDIO_TTS_PCM_UNSUPPORTED;
        return 0;
    }
    luat_rtos_mutex_lock(tts_pcm_mutex, LUAT_WAIT_FOREVER);
    tts_pcm_job_t *job = session->job;
    if (job && !job->cancel) {
        count = buffer ? capacity : 0;
        if (count > job->used) count = job->used;
        if (count) {
            size_t first = count;
            if (first > TTS_PCM_FIFO_SIZE - job->read_pos) first = TTS_PCM_FIFO_SIZE - job->read_pos;
            memcpy(buffer, job->fifo + job->read_pos, first);
            if (count > first) memcpy((uint8_t *)buffer + first, job->fifo, count - first);
            job->read_pos = (job->read_pos + count) % TTS_PCM_FIFO_SIZE;
            job->used -= count;
            if (job->space) luat_rtos_semaphore_release(job->space);
        }
        if (job->decoder_done && !job->used)
            tts_pcm_finish_locked(session, LUAT_AUDIO_TTS_PCM_DONE);
    }
    if (state) *state = session->state;
    if (reason) *reason = session->reason;
    luat_rtos_mutex_unlock(tts_pcm_mutex);
    return count;
}

static void tts_pcm_stop_locked(luat_audio_tts_pcm_session_t *session)
{
    tts_pcm_job_t *job = session->job;
    if (!job) return;
    job->cancel = 1;
    session->state = LUAT_AUDIO_TTS_PCM_STOPPING;
    if (job->decoder_done) {
        session->reason = LUAT_AUDIO_TTS_PCM_OK;
        tts_pcm_finish_locked(session, LUAT_AUDIO_TTS_PCM_STOPPED);
    } else luat_rtos_semaphore_release(job->space);
}

void luat_audio_tts_pcm_stop(luat_audio_tts_pcm_session_t *session)
{
    if (!session) return;
    luat_rtos_mutex_lock(tts_pcm_mutex, LUAT_WAIT_FOREVER);
    tts_pcm_stop_locked(session);
    luat_rtos_mutex_unlock(tts_pcm_mutex);
}

void luat_audio_tts_pcm_release(luat_audio_tts_pcm_session_t *session)
{
    if (!session) return;
    luat_rtos_mutex_lock(tts_pcm_mutex, LUAT_WAIT_FOREVER);
    session->owned = 0;
    if (session->job) tts_pcm_stop_locked(session);
    else luat_heap_free(session);
    luat_rtos_mutex_unlock(tts_pcm_mutex);
}

const char *luat_audio_tts_pcm_state_name(luat_audio_tts_pcm_state_t state)
{
    switch (state) {
    case LUAT_AUDIO_TTS_PCM_RUNNING: return "running";
    case LUAT_AUDIO_TTS_PCM_DONE: return "done";
    case LUAT_AUDIO_TTS_PCM_STOPPING: return "stopping";
    case LUAT_AUDIO_TTS_PCM_STOPPED: return "stopped";
    default: return "error";
    }
}

const char *luat_audio_tts_pcm_reason_name(luat_audio_tts_pcm_reason_t reason)
{
    switch (reason) {
    case LUAT_AUDIO_TTS_PCM_OK: return NULL;
    case LUAT_AUDIO_TTS_PCM_UNSUPPORTED: return "unsupported";
    case LUAT_AUDIO_TTS_PCM_BUSY: return "busy";
    case LUAT_AUDIO_TTS_PCM_INVALID_TEXT: return "invalid_text";
    case LUAT_AUDIO_TTS_PCM_NO_MEMORY: return "no_memory";
    case LUAT_AUDIO_TTS_PCM_INIT_FAILED: return "init_failed";
    case LUAT_AUDIO_TTS_PCM_FORMAT_ERROR: return "format_error";
    default: return "decode_failed";
    }
}
#endif
