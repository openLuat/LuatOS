#include "luat_conf_bsp.h"

#ifdef LUAT_USE_VOIP_RECORD

#include "luat_voip_record.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_fs.h"

#include <stdio.h>
#include <string.h>
#ifdef _MSC_VER
#include <intrin.h>
#endif

#define LUAT_LOG_TAG "voip.record"
#include "luat_log.h"

#define VOIP_RECORD_QUEUE_FRAMES  100
#define VOIP_RECORD_FRAME_BYTES   (VOIP_RECORD_FRAME_SAMPLES * 2 * sizeof(int16_t))
#define VOIP_RECORD_DEFAULT_MAX_S 7200
#define VOIP_RECORD_WRITER_BATCH  7

typedef enum {
    VOIP_RECORD_MSG_START = 1,
    VOIP_RECORD_MSG_FRAME,
} voip_record_msg_type_t;

typedef struct {
    uint8_t type;
    uint8_t reserved[3];
    int16_t pcm[VOIP_RECORD_FRAME_SAMPLES * 2];
} voip_record_msg_t;

typedef struct {
    luat_rtos_task_handle task;
    luat_rtos_queue_t queue;
    luat_rtos_mutex_t mutex;
    voip_record_notify_cb_t notify_cb;
    volatile uint8_t stop_requested;
    volatile uint8_t runtime_ready;
    voip_record_status_t status;
    uint32_t max_frames;
    uint32_t accepted_frames;
    int16_t tx_pcm[VOIP_RECORD_FRAME_SAMPLES];
    int16_t rx_pcm[VOIP_RECORD_FRAME_SAMPLES];
    uint8_t tx_valid;
    uint8_t rx_valid;
} voip_record_ctx_t;

static voip_record_ctx_t g_record;

static void record_increment_drop(void)
{
#ifdef _MSC_VER
    _InterlockedIncrement((volatile long *)&g_record.status.dropped_frames);
#else
    __sync_add_and_fetch(&g_record.status.dropped_frames, 1);
#endif
}

static void record_copy_text(char *dst, size_t dst_size, const char *src)
{
    size_t len = src ? strlen(src) : 0;
    if (len >= dst_size) len = dst_size - 1;
    if (len) memcpy(dst, src, len);
    dst[len] = '\0';
}

static void record_put_u16(uint8_t *p, uint16_t value)
{
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
}

static void record_put_u32(uint8_t *p, uint32_t value)
{
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
    p[2] = (uint8_t)(value >> 16);
    p[3] = (uint8_t)(value >> 24);
}

static void record_make_wav_header(uint8_t header[44], uint32_t data_bytes)
{
    memset(header, 0, 44);
    memcpy(header, "RIFF", 4);
    record_put_u32(header + 4, data_bytes + 36);
    memcpy(header + 8, "WAVEfmt ", 8);
    record_put_u32(header + 16, 16);
    record_put_u16(header + 20, 1);
    record_put_u16(header + 22, 2);
    record_put_u32(header + 24, 8000);
    record_put_u32(header + 28, 8000 * 2 * sizeof(int16_t));
    record_put_u16(header + 32, 2 * sizeof(int16_t));
    record_put_u16(header + 34, 16);
    memcpy(header + 36, "data", 4);
    record_put_u32(header + 40, data_bytes);
}

static void record_set_error(const char *reason)
{
    if (g_record.mutex && luat_rtos_mutex_lock(g_record.mutex, LUAT_WAIT_FOREVER) == 0) {
        g_record.status.state = VOIP_RECORD_ERROR;
        record_copy_text(g_record.status.reason, sizeof(g_record.status.reason), reason);
        g_record.stop_requested = 1;
        luat_rtos_mutex_unlock(g_record.mutex);
    }
}

static int record_finish_file(FILE **fp, uint32_t data_bytes)
{
    uint8_t header[44];
    int ret = 0;
    if (!*fp) return 0;
    record_make_wav_header(header, data_bytes);
    if (luat_fs_fseek(*fp, 0, SEEK_SET) == 0) {
        if (luat_fs_fwrite(header, 1, sizeof(header), *fp) != sizeof(header)) ret = -1;
    } else ret = -1;
    if (luat_fs_fflush(*fp) != 0) ret = -1;
    if (luat_fs_fclose(*fp) != 0) ret = -1;
    *fp = NULL;
    return ret;
}

static void record_writer_task(void *param)
{
    voip_record_msg_t msg;
    int16_t batch[VOIP_RECORD_WRITER_BATCH][VOIP_RECORD_FRAME_SAMPLES * 2];
    FILE *fp = NULL;
    uint32_t data_bytes = 0;
    uint32_t frames_since_flush = 0;
    (void)param;

    while (1) {
        int ret = luat_rtos_queue_recv(g_record.queue, &msg, sizeof(msg), 100);
        if (ret == 0 && msg.type == VOIP_RECORD_MSG_START) {
            uint8_t header[44];
            char path[VOIP_RECORD_PATH_MAX];
            int should_start = 0;
            if (g_record.mutex && luat_rtos_mutex_lock(g_record.mutex, LUAT_WAIT_FOREVER) == 0) {
                record_copy_text(path, sizeof(path), g_record.status.path);
                should_start = (g_record.status.state == VOIP_RECORD_ARMED && !g_record.stop_requested);
                luat_rtos_mutex_unlock(g_record.mutex);
            } else {
                path[0] = '\0';
            }
            if (!should_start) goto check_stop;
            fp = luat_fs_fopen(path, "wb");
            if (!fp) {
                record_set_error("open_failed");
            } else {
                record_make_wav_header(header, 0);
                if (luat_fs_fwrite(header, 1, sizeof(header), fp) != sizeof(header)) {
                    luat_fs_fclose(fp);
                    fp = NULL;
                    record_set_error("write_failed");
                } else {
                    data_bytes = 0;
                    frames_since_flush = 0;
                    if (g_record.mutex && luat_rtos_mutex_lock(g_record.mutex, LUAT_WAIT_FOREVER) == 0) {
                        should_start = !g_record.stop_requested;
                        if (should_start) g_record.status.state = VOIP_RECORD_RECORDING;
                        luat_rtos_mutex_unlock(g_record.mutex);
                    }
                    if (should_start && g_record.notify_cb) g_record.notify_cb(VOIP_RECORD_EVENT_STARTED);
                }
            }
        } else if (ret == 0 && msg.type == VOIP_RECORD_MSG_FRAME && fp) {
            uint32_t batch_count = 1;
            memcpy(batch[0], msg.pcm, VOIP_RECORD_FRAME_BYTES);
            while (batch_count < VOIP_RECORD_WRITER_BATCH &&
                   luat_rtos_queue_recv(g_record.queue, &msg, sizeof(msg), 0) == 0) {
                if (msg.type != VOIP_RECORD_MSG_FRAME) break;
                memcpy(batch[batch_count++], msg.pcm, VOIP_RECORD_FRAME_BYTES);
            }
            size_t write_bytes = batch_count * VOIP_RECORD_FRAME_BYTES;
            if (luat_fs_fwrite(batch, 1, write_bytes, fp) != write_bytes) {
                record_set_error("write_failed");
            } else {
                data_bytes += (uint32_t)write_bytes;
                frames_since_flush += batch_count;
                if (frames_since_flush >= 50) {
                    if (luat_fs_fflush(fp) != 0) {
                        record_set_error("write_failed");
                    }
                    frames_since_flush = 0;
                }
                if (g_record.mutex && luat_rtos_mutex_lock(g_record.mutex, LUAT_WAIT_FOREVER) == 0) {
                    g_record.status.bytes = data_bytes;
                    g_record.status.duration_ms = (data_bytes / VOIP_RECORD_FRAME_BYTES) * 20;
                    luat_rtos_mutex_unlock(g_record.mutex);
                }
            }
        }

check_stop:
        if (g_record.stop_requested) {
            uint32_t queued = 0;
            luat_rtos_queue_get_cnt(g_record.queue, &queued);
            if (queued == 0) {
                voip_record_event_t event = VOIP_RECORD_EVENT_STOPPED;
                int finish_ret = record_finish_file(&fp, data_bytes);
                if (g_record.mutex && luat_rtos_mutex_lock(g_record.mutex, LUAT_WAIT_FOREVER) == 0) {
                    if (g_record.status.state == VOIP_RECORD_ERROR) event = VOIP_RECORD_EVENT_ERROR;
                    if (finish_ret != 0) {
                        event = VOIP_RECORD_EVENT_ERROR;
                        record_copy_text(g_record.status.reason, sizeof(g_record.status.reason), "write_failed");
                    }
                    g_record.status.bytes = data_bytes;
                    g_record.status.duration_ms = (data_bytes / VOIP_RECORD_FRAME_BYTES) * 20;
                    g_record.status.state = VOIP_RECORD_IDLE;
                    g_record.tx_valid = 0;
                    g_record.rx_valid = 0;
                    g_record.stop_requested = 0;
                    luat_rtos_mutex_unlock(g_record.mutex);
                }
                if (g_record.notify_cb) g_record.notify_cb(event);
            }
        }
    }
}

static int record_send_start(void)
{
    voip_record_msg_t msg;
    memset(&msg, 0, sizeof(msg));
    msg.type = VOIP_RECORD_MSG_START;
    return luat_rtos_queue_send(g_record.queue, &msg, sizeof(msg), 0);
}

static void record_build_frame_locked(voip_record_msg_t *msg, const int16_t *rx_pcm)
{
    memset(msg, 0, sizeof(*msg));
    msg->type = VOIP_RECORD_MSG_FRAME;
    for (uint16_t i = 0; i < VOIP_RECORD_FRAME_SAMPLES; i++) {
        msg->pcm[i * 2] = g_record.tx_valid ? g_record.tx_pcm[i] : 0;
        msg->pcm[i * 2 + 1] = rx_pcm ? rx_pcm[i] : 0;
    }
    g_record.tx_valid = 0;
}

int luat_voip_record_init(voip_record_notify_cb_t notify_cb)
{
    int ret;
    if (g_record.runtime_ready) {
        g_record.notify_cb = notify_cb;
        return 0;
    }
    memset(&g_record, 0, sizeof(g_record));
    g_record.notify_cb = notify_cb;
    ret = luat_rtos_mutex_create(&g_record.mutex);
    if (ret != 0) return -1;
    ret = luat_rtos_queue_create(&g_record.queue, VOIP_RECORD_QUEUE_FRAMES, sizeof(voip_record_msg_t));
    if (ret != 0) {
        luat_rtos_mutex_delete(g_record.mutex);
        g_record.mutex = NULL;
        return -1;
    }
    ret = luat_rtos_task_create(&g_record.task, 8 * 1024, 60, "voip_rec", record_writer_task, NULL, 16);
    if (ret != 0) {
        luat_rtos_queue_delete(g_record.queue);
        luat_rtos_mutex_delete(g_record.mutex);
        g_record.queue = NULL;
        g_record.mutex = NULL;
        return -1;
    }
    g_record.status.state = VOIP_RECORD_IDLE;
    g_record.runtime_ready = 1;
    return 0;
}

int luat_voip_record_start(const char *path, uint32_t max_seconds, int media_running)
{
    if (!g_record.runtime_ready) return -3;
    if (g_record.mutex && luat_rtos_mutex_lock(g_record.mutex, LUAT_WAIT_FOREVER) == 0) {
        if (g_record.status.state != VOIP_RECORD_IDLE) {
            luat_rtos_mutex_unlock(g_record.mutex);
            return -2;
        }
        memset(&g_record.status, 0, sizeof(g_record.status));
        g_record.status.state = VOIP_RECORD_ARMED;
        record_copy_text(g_record.status.path, sizeof(g_record.status.path), path);
        record_copy_text(g_record.status.reason, sizeof(g_record.status.reason), "manual");
        max_seconds = max_seconds ? max_seconds : VOIP_RECORD_DEFAULT_MAX_S;
        g_record.max_frames = max_seconds > (UINT32_MAX / 50) ? UINT32_MAX : max_seconds * 50;
        g_record.accepted_frames = 0;
        g_record.tx_valid = 0;
        g_record.rx_valid = 0;
        g_record.stop_requested = 0;
        luat_rtos_mutex_unlock(g_record.mutex);
    }
    if (media_running && record_send_start() != 0) {
        record_set_error("no_memory");
        return -3;
    }
    return 0;
}

int luat_voip_record_media_started(void)
{
    int armed = 0;
    int ret;
    if (!g_record.runtime_ready) return 0;
    if (g_record.mutex && luat_rtos_mutex_lock(g_record.mutex, 0) == 0) {
        armed = (g_record.status.state == VOIP_RECORD_ARMED);
        luat_rtos_mutex_unlock(g_record.mutex);
    }
    if (!armed) return 0;
    ret = record_send_start();
    if (ret != 0) record_set_error("no_memory");
    return ret;
}

int luat_voip_record_stop(const char *reason)
{
    voip_record_msg_t msg;
    int flush_pending = 0;
    if (!g_record.runtime_ready) return 0;
    if (g_record.mutex && luat_rtos_mutex_lock(g_record.mutex, LUAT_WAIT_FOREVER) == 0) {
        if (g_record.status.state == VOIP_RECORD_IDLE) {
            luat_rtos_mutex_unlock(g_record.mutex);
            return 0;
        }
        if (g_record.status.state == VOIP_RECORD_RECORDING && g_record.rx_valid &&
            g_record.accepted_frames < g_record.max_frames) {
            record_build_frame_locked(&msg, g_record.rx_pcm);
            g_record.rx_valid = 0;
            g_record.accepted_frames++;
            flush_pending = 1;
        }
        if (g_record.status.state != VOIP_RECORD_ERROR && g_record.status.state != VOIP_RECORD_STOPPING) {
            g_record.status.state = VOIP_RECORD_STOPPING;
            record_copy_text(g_record.status.reason, sizeof(g_record.status.reason), reason ? reason : "manual");
        }
        luat_rtos_mutex_unlock(g_record.mutex);
    }
    if (flush_pending && luat_rtos_queue_send(g_record.queue, &msg, sizeof(msg), 0) != 0) {
        record_increment_drop();
        record_set_error("queue_overflow");
        return 0;
    }
    if (g_record.mutex && luat_rtos_mutex_lock(g_record.mutex, LUAT_WAIT_FOREVER) == 0) {
        g_record.stop_requested = 1;
        luat_rtos_mutex_unlock(g_record.mutex);
    }
    return 0;
}

void luat_voip_record_tap_tx(const int16_t *pcm, uint16_t samples)
{
    if (!pcm || !g_record.runtime_ready || samples == 0) return;
    if (luat_rtos_mutex_lock(g_record.mutex, 0) != 0) {
        record_increment_drop();
        return;
    }
    if (g_record.status.state == VOIP_RECORD_RECORDING) {
        uint16_t count = samples < VOIP_RECORD_FRAME_SAMPLES ? samples : VOIP_RECORD_FRAME_SAMPLES;
        memcpy(g_record.tx_pcm, pcm, count * sizeof(int16_t));
        if (count < VOIP_RECORD_FRAME_SAMPLES) {
            memset(g_record.tx_pcm + count, 0, (VOIP_RECORD_FRAME_SAMPLES - count) * sizeof(int16_t));
        }
        g_record.tx_valid = 1;
    }
    luat_rtos_mutex_unlock(g_record.mutex);
}

void luat_voip_record_tap_rx(const int16_t *pcm, uint16_t samples)
{
    voip_record_msg_t msg;
    uint16_t rx_count;
    if (!g_record.runtime_ready) return;
    if (luat_rtos_mutex_lock(g_record.mutex, 0) != 0) {
        record_increment_drop();
        return;
    }
    if (g_record.status.state != VOIP_RECORD_RECORDING) {
        luat_rtos_mutex_unlock(g_record.mutex);
        return;
    }
    rx_count = (pcm && samples < VOIP_RECORD_FRAME_SAMPLES) ? samples : VOIP_RECORD_FRAME_SAMPLES;
    if (!g_record.rx_valid) {
        memset(g_record.rx_pcm, 0, sizeof(g_record.rx_pcm));
        if (pcm && rx_count) memcpy(g_record.rx_pcm, pcm, rx_count * sizeof(int16_t));
        g_record.rx_valid = 1;
        luat_rtos_mutex_unlock(g_record.mutex);
        return;
    }
    if (g_record.accepted_frames >= g_record.max_frames) {
        g_record.status.state = VOIP_RECORD_ERROR;
        record_copy_text(g_record.status.reason, sizeof(g_record.status.reason), "max_duration");
        g_record.rx_valid = 0;
        g_record.stop_requested = 1;
        luat_rtos_mutex_unlock(g_record.mutex);
        return;
    }
    record_build_frame_locked(&msg, g_record.rx_pcm);
    memset(g_record.rx_pcm, 0, sizeof(g_record.rx_pcm));
    if (pcm && rx_count) memcpy(g_record.rx_pcm, pcm, rx_count * sizeof(int16_t));
    g_record.accepted_frames++;
    luat_rtos_mutex_unlock(g_record.mutex);
    if (luat_rtos_queue_send(g_record.queue, &msg, sizeof(msg), 0) != 0) {
        if (luat_rtos_mutex_lock(g_record.mutex, 0) == 0) {
            record_increment_drop();
            g_record.status.state = VOIP_RECORD_ERROR;
            record_copy_text(g_record.status.reason, sizeof(g_record.status.reason), "queue_overflow");
            g_record.stop_requested = 1;
            luat_rtos_mutex_unlock(g_record.mutex);
        }
    }
}

void luat_voip_record_get_status(voip_record_status_t *status)
{
    if (!status) return;
    memset(status, 0, sizeof(*status));
    if (!g_record.runtime_ready) return;
    if (luat_rtos_mutex_lock(g_record.mutex, LUAT_WAIT_FOREVER) == 0) {
        memcpy(status, &g_record.status, sizeof(*status));
        luat_rtos_queue_get_cnt(g_record.queue, &status->queued_frames);
        luat_rtos_mutex_unlock(g_record.mutex);
    }
}

const char *luat_voip_record_state_name(voip_record_state_t state)
{
    switch (state) {
    case VOIP_RECORD_IDLE: return "idle";
    case VOIP_RECORD_ARMED: return "armed";
    case VOIP_RECORD_RECORDING: return "recording";
    case VOIP_RECORD_STOPPING: return "stopping";
    case VOIP_RECORD_ERROR: return "error";
    default: return "idle";
    }
}

#endif
