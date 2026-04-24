#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_gpio.h"
#ifdef LUAT_USE_DRV_GPIO
#include "luat/drv_gpio.h"
#endif
#include "luat_dac.h"
#include "luat_fs.h"
#include "luat_i2s.h"
#include "luat_audio.h"
#include "luat_multimedia.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#define LUAT_LOG_TAG "audio"
#include "luat_log.h"

static luat_rtos_queue_t audio_queue_handle;
static luat_rtos_task_handle audio_task_handle;

#define LUAT_AUDIO_MAX_DEVICE_COUNT 2
#define LUAT_AUDIO_PLAY_PATH_MAX 255
#define LUAT_AUDIO_DECODE_OUT_SIZE (8 * 1024)
#define LUAT_AUDIO_DECODE_MIN_OUTPUT (4 * 1024)
#define LUAT_AUDIO_TASK_QUEUE_LEN 10
#define LUAT_AUDIO_TASK_STACK_SIZE (1024 * 12)
#define LUAT_AUDIO_TASK_PRIORITY 50

#ifdef LUAT_USE_DAC
#define LUAT_AUDIO_DAC_BLOCK_NUM 4

typedef struct {
    luat_rtos_semaphore_t block_sem;
    uint8_t *buffer;
    uint32_t block_size;
    uint32_t buffer_num;
    uint32_t next_block_idx;
} luat_audio_dac_loop_ctx_t;

static luat_audio_dac_loop_ctx_t g_dac_loop_ctx[LUAT_AUDIO_MAX_DEVICE_COUNT];

static int luat_audio_dac_block_done_cb(uint8_t id, luat_dac_event_t event, uint32_t tx_len, void *param)
{
    (void)id; (void)tx_len;
    luat_audio_dac_loop_ctx_t *ctx = (luat_audio_dac_loop_ctx_t *)param;
    if (ctx && ctx->block_sem) {
        if (event == LUAT_DAC_EVENT_TX_ONE_BLOCK_DONE || event == LUAT_DAC_EVENT_TX_DONE) {
            luat_rtos_semaphore_release(ctx->block_sem);
        }
    }
    return 0;
}

static void luat_audio_dac_loop_cleanup(luat_audio_dac_loop_ctx_t *ctx)
{
    if (!ctx) return;
    if (ctx->buffer) {
        luat_heap_free(ctx->buffer);
        ctx->buffer = NULL;
    }
    if (ctx->block_sem) {
        luat_rtos_semaphore_delete(ctx->block_sem);
        ctx->block_sem = NULL;
    }
    ctx->block_size = 0;
    ctx->buffer_num = 0;
    ctx->next_block_idx = 0;
}
#endif /* LUAT_USE_DAC */

typedef struct lua_State lua_State;

static void luat_audio_task(void *param);
extern int l_multimedia_raw_handler(lua_State *L, void* ptr);

typedef struct luat_audio_play_ctx {
    uint8_t multimedia_id;
    char path[LUAT_AUDIO_PLAY_PATH_MAX + 1];
} luat_audio_play_ctx_t;

typedef struct luat_audio_play_state {
    volatile uint8_t playing;
    volatile uint8_t task_running;
    volatile uint8_t stop_requested;
    int last_error;
} luat_audio_play_state_t;

static luat_audio_play_state_t g_audio_play_state[LUAT_AUDIO_MAX_DEVICE_COUNT];

static luat_audio_play_state_t* luat_audio_get_play_state(uint8_t multimedia_id) {
    if (multimedia_id >= LUAT_AUDIO_MAX_DEVICE_COUNT) {
        return NULL;
    }
    return &g_audio_play_state[multimedia_id];
}

static int luat_audio_str_ieq(const char *left, const char *right) {
    char left_ch;
    char right_ch;

    if (!left || !right) {
        return 0;
    }

    while (*left && *right) {
        left_ch = *left++;
        right_ch = *right++;
        if (left_ch >= 'A' && left_ch <= 'Z') {
            left_ch = left_ch - 'A' + 'a';
        }
        if (right_ch >= 'A' && right_ch <= 'Z') {
            right_ch = right_ch - 'A' + 'a';
        }
        if (left_ch != right_ch) {
            return 0;
        }
    }
    return (*left == 0) && (*right == 0);
}

static uint8_t luat_audio_detect_codec_type(const char *path) {
    const char *ext = strrchr(path, '.');
    if (!ext) {
        return LUAT_MULTIMEDIA_DATA_TYPE_MP3;
    }
    if (luat_audio_str_ieq(ext, ".wav")) {
        return LUAT_MULTIMEDIA_DATA_TYPE_WAV;
    }
    if (luat_audio_str_ieq(ext, ".amr")) {
        return LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB;
    }
    if (luat_audio_str_ieq(ext, ".awb")) {
        return LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB;
    }
    if (luat_audio_str_ieq(ext, ".ulaw") || luat_audio_str_ieq(ext, ".g711u")) {
        return LUAT_MULTIMEDIA_DATA_TYPE_ULAW;
    }
    if (luat_audio_str_ieq(ext, ".alaw") || luat_audio_str_ieq(ext, ".g711a")) {
        return LUAT_MULTIMEDIA_DATA_TYPE_ALAW;
    }
    if (luat_audio_str_ieq(ext, ".opus")) {
        return LUAT_MULTIMEDIA_DATA_TYPE_OPUS;
    }
    return LUAT_MULTIMEDIA_DATA_TYPE_MP3;
}

static void luat_audio_release_decoder(luat_multimedia_codec_t *coder) {
    if (!coder) {
        return;
    }
    if (coder->fd) {
        luat_fs_fclose(coder->fd);
        coder->fd = NULL;
    }
#ifdef __LUATOS__
    if (coder->buff.addr) {
        luat_heap_free(coder->buff.addr);
        coder->buff.addr = NULL;
        coder->buff.len = 0;
        coder->buff.used = 0;
    }
#endif
    if (coder->ops && coder->ops->destroy && coder->ctx) {
        coder->ops->destroy(coder);
        coder->ctx = NULL;
    }
}

static void luat_audio_post_done_event(uint8_t multimedia_id) {
    rtos_msg_t msg = {0};
    msg.handler = l_multimedia_raw_handler;
    msg.arg1 = LUAT_MULTIMEDIA_CB_AUDIO_DONE;
    msg.arg2 = multimedia_id;
    luat_msgbus_put(&msg, 1);
}

static void luat_audio_wait_output_empty(uint8_t multimedia_id, luat_audio_conf_t *audio_conf, volatile uint8_t *stop_requested) {
    size_t total = 0;
    size_t remain = 0;

    if (!audio_conf || audio_conf->bus_type != LUAT_AUDIO_BUS_I2S) {
        return;
    }

    for (uint32_t i = 0; i < 800 && !(*stop_requested); i++) {
        if (luat_i2s_txbuff_info(audio_conf->codec_conf.i2s_id, &total, &remain) != 0) {
            break;
        }
        if (remain == 0) {
            break;
        }
        luat_rtos_task_sleep(5);
    }
    (void)multimedia_id;
}

static int luat_audio_task_bootstrap(void) {
    if (!audio_queue_handle) {
        if (luat_rtos_queue_create(&audio_queue_handle, LUAT_AUDIO_TASK_QUEUE_LEN, sizeof(OS_EVENT)) != 0) {
            return -1;
        }
    }
    if (!audio_task_handle) {
        if (luat_rtos_task_create(&audio_task_handle,
                                  LUAT_AUDIO_TASK_STACK_SIZE,
                                  LUAT_AUDIO_TASK_PRIORITY,
                                  "audio_thread",
                                  luat_audio_task,
                                  NULL,
                                  0) != 0) {
            return -1;
        }
    }
    return 0;
}

static int luat_audio_do_play_file(uint8_t multimedia_id, const char *path) {
    luat_audio_conf_t *audio_conf = luat_audio_get_config(multimedia_id);
    luat_audio_play_state_t *play_state = luat_audio_get_play_state(multimedia_id);
    luat_multimedia_codec_t coder;
    uint8_t restore_sleep_mode = LUAT_AUDIO_PM_RESUME;
    int ret = -1;
#ifdef __LUATOS__
    luat_zbuff_t out_buff;
#endif

    if (!audio_conf || !play_state || !path || !path[0]) {
        return -1;
    }

    memset(&coder, 0, sizeof(coder));
#ifdef __LUATOS__
    memset(&out_buff, 0, sizeof(out_buff));
#endif

    play_state->task_running = 1;
    play_state->last_error = 1;

    if (play_state->stop_requested) {
        play_state->last_error = -1;
        goto EXIT_TASK;
    }

    if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S && !audio_conf->codec_conf.codec_opts) {
        LLOGE("audio codec not ready");
        goto EXIT_TASK;
    }

    restore_sleep_mode = audio_conf->sleep_mode;
    if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S && restore_sleep_mode != LUAT_AUDIO_PM_RESUME) {
        if (luat_audio_pm_request(multimedia_id, LUAT_AUDIO_PM_RESUME) != 0) {
            LLOGE("audio pm resume failed");
            goto EXIT_TASK;
        }
    }

    coder.type = luat_audio_detect_codec_type(path);
    coder.is_decoder = 1;
    coder.ops = luat_codec_get_ops(coder.type);
    if (!coder.ops || !coder.ops->create || !coder.ops->decode_file_data) {
        LLOGE("audio codec unsupported %d", coder.type);
        goto EXIT_TASK;
    }

    coder.ctx = coder.ops->create(&coder);
    if (!coder.ctx) {
        LLOGE("audio codec create failed %d", coder.type);
        goto EXIT_TASK;
    }

    if (!luat_codec_get_audio_info(path, &coder)) {
        LLOGE("audio parse failed %s", path);
        goto EXIT_TASK;
    }
    
    if (luat_audio_start_raw(multimedia_id,
                             coder.audio_format ? coder.audio_format : LUAT_MULTIMEDIA_DATA_TYPE_PCM,
                             coder.num_channels ? coder.num_channels : 2,
                             coder.sample_rate ? coder.sample_rate : LUAT_I2S_HZ_44k,
                             coder.bits_per_sample ? (uint8_t)coder.bits_per_sample : LUAT_I2S_BITS_16,
                             coder.is_signed) != 0) {
        LLOGE("audio start raw failed");
        goto EXIT_TASK;
    }

#ifndef __LUATOS__
    LLOGE("audio decode path requires __LUATOS__");
    goto EXIT_TASK;
#else
#ifdef LUAT_USE_DAC
    if (audio_conf->bus_type == LUAT_AUDIO_BUS_DAC) {
        /* Ping-pong async write:
         * Decode into buf[0], start async DMA (ONESHOT, exact decoded size, no padding).
         * While DMA plays buf[0], decode into buf[1].
         * On TX_DONE semaphore: start DMA on buf[1], decode into buf[0]. Repeat.
         * This avoids the zero-padding speed/artifact issue of fixed-size buffer_loop. */
        luat_audio_dac_loop_ctx_t *dac_ctx = &g_dac_loop_ctx[multimedia_id];
        luat_dac_config_t *dac_cfg;
        int decode_ok;
        uint8_t cur_idx;

        dac_ctx->block_size = LUAT_AUDIO_DECODE_OUT_SIZE;
        dac_ctx->buffer_num = 2;
        dac_ctx->next_block_idx = 0;
        dac_ctx->buffer = NULL;
        dac_ctx->block_sem = NULL;

        dac_ctx->buffer = luat_heap_malloc(dac_ctx->block_size * 2);
        if (!dac_ctx->buffer) {
            LLOGE("dac pingpong buffer alloc failed");
            goto EXIT_TASK;
        }

        if (luat_rtos_semaphore_create(&dac_ctx->block_sem, 0) != 0) {
            LLOGE("dac pingpong semaphore create failed");
            luat_audio_dac_loop_cleanup(dac_ctx);
            goto EXIT_TASK;
        }

        /* Register TX_DONE callback so async luat_dac_write signals decode task */
        dac_cfg = luat_dac_get_config(audio_conf->codec_conf.dac_id);
        dac_cfg->luat_dac_event_callback = luat_audio_dac_block_done_cb;
        dac_cfg->userdata = dac_ctx;

        /* Pre-fill buf[0] and start first DMA */
        out_buff.addr = dac_ctx->buffer;
        out_buff.len  = dac_ctx->block_size;
        out_buff.used = 0;
        decode_ok = coder.ops->decode_file_data(&coder, &out_buff, LUAT_AUDIO_DECODE_MIN_OUTPUT);
        cur_idx = 0;

        if (decode_ok && out_buff.used > 0) {
            /* luat_dac_write with callback registered is async: copies data then returns */
            if (luat_dac_write(audio_conf->codec_conf.dac_id,
                               dac_ctx->buffer, out_buff.used) != 0) {
                LLOGE("dac write failed");
                luat_audio_dac_loop_cleanup(dac_ctx);
                goto EXIT_TASK;
            }

            while (!play_state->stop_requested) {
                /* Decode into the OTHER buffer while DMA plays current */
                uint8_t next_idx = 1 - cur_idx;
                out_buff.addr = dac_ctx->buffer + (uint32_t)next_idx * dac_ctx->block_size;
                out_buff.len  = dac_ctx->block_size;
                out_buff.used = 0;
                decode_ok = coder.ops->decode_file_data(&coder, &out_buff, LUAT_AUDIO_DECODE_MIN_OUTPUT);

                /* Wait for current DMA to finish (TX_DONE fires when ONESHOT completes) */
                if (luat_rtos_semaphore_take(dac_ctx->block_sem, 5000) != 0) {
                    LLOGE("dac tx timeout");
                    break;
                }
                if (play_state->stop_requested) break;
                if (!decode_ok || out_buff.used == 0) break;

                /* Start DMA on next buffer with exact decoded byte count — no padding */
                if (luat_dac_write(audio_conf->codec_conf.dac_id,
                                   out_buff.addr, out_buff.used) != 0) {
                    LLOGE("dac write failed");
                    break;
                }
                cur_idx = next_idx;
            }

            /* Wait for the last buffer to finish playing */
            if (!play_state->stop_requested) {
                luat_rtos_semaphore_take(dac_ctx->block_sem, 5000);
            }
        }

        out_buff.addr = NULL; /* prevent double-free in EXIT_TASK */
    } else
#endif /* LUAT_USE_DAC */
    {
        out_buff.type = LUAT_HEAP_SRAM;
        out_buff.len = LUAT_AUDIO_DECODE_OUT_SIZE;
        out_buff.addr = luat_heap_malloc(out_buff.len);
        if (!out_buff.addr) {
            LLOGE("audio decode buffer alloc failed");
            goto EXIT_TASK;
        }

        while (!play_state->stop_requested) {
            out_buff.used = 0;
            if (!coder.ops->decode_file_data(&coder, &out_buff, LUAT_AUDIO_DECODE_MIN_OUTPUT)) {
                break;
            }
            if (out_buff.used == 0) {
                continue;
            }
            if (luat_audio_write_raw(multimedia_id, out_buff.addr, (uint32_t)out_buff.used) != 0) {
                LLOGE("audio write raw failed");
                goto EXIT_TASK;
            }
        }
    }
#endif /* __LUATOS__ */

    if (play_state->stop_requested) {
        play_state->last_error = -1;
    } else {
        luat_audio_wait_output_empty(multimedia_id, audio_conf, &play_state->stop_requested);
        play_state->last_error = play_state->stop_requested ? -1 : 0;
        ret = play_state->last_error;
    }

EXIT_TASK:
    if (play_state->stop_requested) {
        play_state->last_error = -1;
    }
#ifdef __LUATOS__
    if (out_buff.addr) {
        luat_heap_free(out_buff.addr);
        out_buff.addr = NULL;
    }
#endif
#ifdef LUAT_USE_DAC
    /* Stop DMA first, then free the DMA buffer (order is critical) */
    if (audio_conf && audio_conf->bus_type == LUAT_AUDIO_BUS_DAC) {
        luat_dac_close(audio_conf->codec_conf.dac_id);
        luat_audio_dac_loop_cleanup(&g_dac_loop_ctx[multimedia_id]);
    }
#endif
    luat_audio_release_decoder(&coder);
    luat_audio_stop_raw(multimedia_id);
    if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S && restore_sleep_mode != LUAT_AUDIO_PM_RESUME) {
        luat_audio_pm_request(multimedia_id, (luat_audio_pm_mode_t)restore_sleep_mode);
    }
    play_state->playing = 0;
    play_state->task_running = 0;
    play_state->stop_requested = 0;
    return ret;
}

LUAT_WEAK luat_audio_conf_t *luat_audio_get_config(uint8_t multimedia_id){
    return NULL;
}

LUAT_WEAK int luat_audio_play_multi_files(uint8_t multimedia_id, uData_t *info, uint32_t files_num, uint8_t error_stop){
    return -1;
}


LUAT_WEAK int luat_audio_play_file(uint8_t multimedia_id, const char *path){
	luat_audio_conf_t *audio_conf = luat_audio_get_config(multimedia_id);
    luat_audio_play_state_t *play_state = luat_audio_get_play_state(multimedia_id);
    luat_audio_play_ctx_t *play_ctx;
    OS_EVENT audio_event = {0};
    // LLOGD("audio play file %d: %s", multimedia_id, path);
    // LLOGD("audio play file %d: %p, %p", multimedia_id, audio_conf, play_state);
    if (!audio_conf || !play_state || !path || !path[0]) {
        return -1;
    }
    // LLOGD("audio play file %d: %d, %d", multimedia_id, play_state->playing, play_state->task_running);
    if (play_state->playing || play_state->task_running) {
        luat_audio_play_stop(multimedia_id);
        for (uint32_t i = 0; i < 500 && (play_state->playing || play_state->task_running); i++) {
            luat_rtos_task_sleep(2);
        }
        if (play_state->playing || play_state->task_running) {
            return -1;
        }
    }

    play_ctx = luat_heap_malloc(sizeof(luat_audio_play_ctx_t));
    if (!play_ctx) {
        play_state->last_error = 1;
        return -1;
    }

    memset(play_ctx, 0, sizeof(luat_audio_play_ctx_t));
    play_ctx->multimedia_id = multimedia_id;
    strncpy(play_ctx->path, path, LUAT_AUDIO_PLAY_PATH_MAX);
    play_ctx->path[LUAT_AUDIO_PLAY_PATH_MAX] = 0;

    play_state->stop_requested = 0;
    play_state->playing = 1;
    play_state->last_error = 1;

    audio_event.ID = AUDIO_EVENT_PLAY_FILE;
    audio_event.Param1 = play_ctx;
    if (luat_rtos_queue_send(audio_queue_handle, &audio_event, sizeof(OS_EVENT), 0) != 0) {
        play_state->playing = 0;
        luat_heap_free(play_ctx);
        return -1;
    }

    return 0;
}

LUAT_WEAK uint8_t luat_audio_is_finish(uint8_t multimedia_id){
    luat_audio_play_state_t *play_state = luat_audio_get_play_state(multimedia_id);
    luat_audio_conf_t *audio_conf = luat_audio_get_config(multimedia_id);
    size_t total = 0;
    size_t remain = 0;

    if (!play_state || !audio_conf) {
        return 1;
    }
    if (play_state->playing || play_state->task_running) {
        return 0;
    }
    if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S) {
        if (luat_i2s_txbuff_info(audio_conf->codec_conf.i2s_id, &total, &remain) != 0) {
            return 1;
        }
        return remain == 0;
    }
    return 1;
}

LUAT_WEAK int luat_audio_play_stop(uint8_t multimedia_id){
    luat_audio_conf_t *audio_conf = luat_audio_get_config(multimedia_id);
    luat_audio_play_state_t *play_state = luat_audio_get_play_state(multimedia_id);
    uint8_t was_active;

    if (!audio_conf || !play_state) {
        return -1;
    }

    was_active = play_state->playing || play_state->task_running;
    play_state->stop_requested = 1;

    for (uint32_t i = 0; i < 500 && (play_state->playing || play_state->task_running); i++) {
        luat_rtos_task_sleep(2);
    }

    if (play_state->playing || play_state->task_running) {
        luat_audio_stop_raw(multimedia_id);
    }
    if (was_active && !(play_state->playing || play_state->task_running)) {
        play_state->last_error = -1;
    }
    return 0;
}

LUAT_WEAK int luat_audio_play_get_last_error(uint8_t multimedia_id){
    luat_audio_play_state_t *play_state = luat_audio_get_play_state(multimedia_id);
    if (!play_state) {
        return 1;
    }
    return play_state->last_error;
}

LUAT_WEAK int luat_audio_start_raw(uint8_t multimedia_id, uint8_t audio_format, uint8_t num_channels, uint32_t sample_rate, uint8_t bits_per_sample, uint8_t is_signed){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        // LLOGD("luat_audio_start_raw: bus_type=%d, format=%d, channels=%d, sample_rate=%d, bits_per_sample=%d, is_signed=%d",
        //         audio_conf->bus_type, audio_format, num_channels, sample_rate, bits_per_sample, is_signed);
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
            luat_i2s_conf_t * i2s_conf = luat_i2s_get_config(audio_conf->codec_conf.i2s_id);
            i2s_conf->data_bits = bits_per_sample;
            i2s_conf->sample_rate = sample_rate,
            luat_i2s_modify(audio_conf->codec_conf.i2s_id,i2s_conf->channel_format,i2s_conf->data_bits, i2s_conf->sample_rate);
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_RATE,sample_rate);
            luat_audio_pa(multimedia_id,1,0);
        }
#ifdef LUAT_USE_DAC
        else if(audio_conf->bus_type == LUAT_AUDIO_BUS_DAC){
            // luat_dac_config_t config;
            // luat_dac_config_t* config_old = luat_dac_get_config(multimedia_id);
            // memcpy(&config, config_old, sizeof(luat_dac_config_t));
            // config.dac_chl = num_channels;
            // config.samp_rate = sample_rate;
            // config.bits = bits_per_sample;
            // luat_dac_setup(audio_conf->codec_conf.dac_id, &config);
            luat_dac_modify(multimedia_id,num_channels,bits_per_sample,sample_rate);
        }
#endif
    }
    return 0;
}

LUAT_WEAK int luat_audio_write_raw(uint8_t multimedia_id, uint8_t *data, uint32_t len){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
            int send_bytes = 0;
            while (send_bytes < len) {
                int length = luat_i2s_send(audio_conf->codec_conf.i2s_id,data + send_bytes, len - send_bytes);
                if (length > 0) {
                    send_bytes += length;
                }
                luat_rtos_task_sleep(1);
            }
        }
#ifdef LUAT_USE_DAC
        else if(audio_conf->bus_type == LUAT_AUDIO_BUS_DAC){
            luat_dac_config_t* dac_config = luat_dac_get_config(audio_conf->codec_conf.dac_id);
            luat_dac_write(dac_config->dac_chl, data, len);
        }
#endif
    }
    return 0;
}

LUAT_WEAK int luat_audio_stop_raw(uint8_t multimedia_id){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
            return luat_i2s_close(audio_conf->codec_conf.i2s_id);
        }
#ifdef LUAT_USE_DAC
        else if (audio_conf->bus_type == LUAT_AUDIO_BUS_DAC) {
            luat_dac_close(audio_conf->codec_conf.dac_id);
            return 0;
        }
#endif
    }
    return -1;
}

LUAT_WEAK int luat_audio_end_raw(uint8_t multimedia_id){
    return -1;
}

LUAT_WEAK int luat_audio_pause_raw(uint8_t multimedia_id, uint8_t is_pause){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
            if (is_pause){
                luat_audio_pa(multimedia_id,0,0);
                luat_i2s_pause(audio_conf->codec_conf.i2s_id);
            }else{
                luat_audio_pa(multimedia_id,1,0);
                luat_i2s_resume(audio_conf->codec_conf.i2s_id);
            }
            return 0;
        }
    }
    return -1;
}

//以上函数通用方法待实现


LUAT_WEAK void luat_audio_config_pa(uint8_t multimedia_id, uint32_t pin, int level, uint32_t dummy_time_len, uint32_t pa_delay_time){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (pin != LUAT_GPIO_NONE && pin<LUAT_GPIO_PIN_MAX && pin>0){
            audio_conf->pa_pin = pin;
            audio_conf->pa_on_level = level;
            luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, !level);
        #ifdef LUAT_USE_DRV_GPIO
            luat_drv_gpio_set(pin, !level);
        #else
            luat_gpio_set(pin, !level);
        #endif
            audio_conf->pa_is_control_enable = 1;
            luat_rtos_timer_create(&audio_conf->pa_delay_timer);
        }else{
            audio_conf->pa_pin = LUAT_GPIO_NONE;
        }
        audio_conf->after_sleep_ready_time = dummy_time_len;
        audio_conf->pa_delay_time = pa_delay_time;
    }
}

LUAT_WEAK void luat_audio_config_dac(uint8_t multimedia_id, int pin, int level, uint32_t dac_off_delay_time){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (pin != LUAT_GPIO_NONE){
            luat_gpio_mode(pin, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, level);
            audio_conf->power_pin = pin;
            audio_conf->power_on_level = level;
            audio_conf->power_off_delay_time = dac_off_delay_time;
        }else{
            audio_conf->power_pin = LUAT_GPIO_NONE;
        }
    }
}

static LUAT_RT_RET_TYPE pa_delay_timer_cb(LUAT_RT_CB_PARAM){
    uint8_t multimedia_id = (uint8_t)(uint32_t)param;
    luat_audio_pa(multimedia_id,1, 0);
}

LUAT_WEAK void luat_audio_pa(uint8_t multimedia_id,uint8_t on, uint32_t delay){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (!audio_conf->pa_is_control_enable) return;
        
        if (audio_conf->pa_delay_timer!=NULL&&delay>0){
            luat_rtos_timer_start(audio_conf->pa_delay_timer,delay,0,pa_delay_timer_cb,(void*)(uint32_t)multimedia_id);
        }
        else{
        #ifdef LUAT_USE_DRV_GPIO
            luat_drv_gpio_set(audio_conf->pa_pin, on?audio_conf->pa_on_level:!audio_conf->pa_on_level);
        #else
            luat_gpio_set(audio_conf->pa_pin, on?audio_conf->pa_on_level:!audio_conf->pa_on_level);
        #endif
            //LLOGD("PA %d,%d,%d", audio_conf->pa_pin, audio_conf->pa_on_level, on);
            if (on) audio_conf->pa_on_enable = 1;
        }
    }
}

LUAT_WEAK void luat_audio_power(uint8_t multimedia_id,uint8_t on){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->power_pin == LUAT_GPIO_NONE) return;
    #ifdef LUAT_USE_DRV_GPIO
        luat_drv_gpio_set(audio_conf->power_pin, on?audio_conf->power_on_level:!audio_conf->power_on_level);
    #else
        luat_gpio_set(audio_conf->power_pin, on?audio_conf->power_on_level:!audio_conf->power_on_level);
    #endif
    }
}

LUAT_WEAK uint16_t luat_audio_vol(uint8_t multimedia_id, uint16_t vol){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf == NULL || vol < 0 || vol > 1000) return -1;
    if (audio_conf->codec_conf.codec_opts && audio_conf->codec_conf.codec_opts->no_control) {
    	audio_conf->soft_vol = vol;
    	return vol;
    }
    audio_conf->soft_vol = vol<=100?100:vol;
    if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
        uint8_t sleep_mode = audio_conf->sleep_mode;
        audio_conf->last_vol = vol;
        if (sleep_mode && audio_conf->codec_conf.codec_opts->no_control!=1) luat_audio_pm_request(multimedia_id,LUAT_AUDIO_PM_RESUME);
        if (vol <= 100){
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL,vol);
            vol = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_GET_VOICE_VOL,0);
        }else{
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL,100);
        }
        if (sleep_mode && audio_conf->codec_conf.codec_opts->no_control!=1) luat_audio_pm_request(multimedia_id,sleep_mode);
        return vol;
    }
#ifdef LUAT_USE_DAC
    else if(audio_conf->bus_type == LUAT_AUDIO_BUS_DAC){
        luat_dac_set_vol(audio_conf->codec_conf.dac_id, vol);
        return vol;
    }
#endif
    return -1;
}

LUAT_WEAK uint8_t luat_audio_mic_vol(uint8_t multimedia_id, uint16_t vol){
    if(vol < 0 || vol > 100) return -1;
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
            if (audio_conf->codec_conf.codec_opts->no_control) return -1;
            uint8_t sleep_mode = audio_conf->sleep_mode;
            if (sleep_mode) luat_audio_pm_request(multimedia_id,LUAT_AUDIO_PM_RESUME);
            audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MIC_VOL,vol);
            vol = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_GET_MIC_VOL,0);
            if (sleep_mode) luat_audio_pm_request(multimedia_id,sleep_mode);
            audio_conf->last_mic_vol = vol;
            return vol;
        }else if(audio_conf->bus_type == LUAT_AUDIO_BUS_DAC){
            luat_adc_set_vol(audio_conf->codec_conf.adc_id, vol);
            return vol;
        }
    }
    return -1;
}

//通用方式待实现
LUAT_WEAK int luat_audio_play_blank(uint8_t multimedia_id, uint8_t on_off){
    return -1;
}

LUAT_WEAK uint8_t luat_audio_mute(uint8_t multimedia_id, uint8_t on){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
    	if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S)
    	{
    		if (audio_conf->codec_conf.codec_opts->no_control)
    		{
    			luat_audio_play_blank(multimedia_id, 1);
    		}
    		else
    		{
    			audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MUTE,on);
    			return audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_GET_MUTE,0);
    		}

    	}
    }
    return -1;
}

LUAT_WEAK int luat_audio_setup_codec(uint8_t multimedia_id, const luat_audio_codec_conf_t *codec_conf){
	luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf){
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
            audio_conf->codec_conf= *codec_conf;
            return 0;
        }
    }
    return -1;
}

static void luat_audio_task(void *param){
    OS_EVENT audio_event;
    luat_audio_play_ctx_t *play_ctx;
    while (1){
        int ret = luat_rtos_queue_recv(audio_queue_handle, &audio_event, sizeof(OS_EVENT), LUAT_WAIT_FOREVER);
        // LLOGD("rtos_pop_from_queue ret:%d",ret);
        // LLOGD("audio_event ret:%d Param1:%d Param2:%d Param3:%d ",
        //     audio_event.ID, audio_event.Param1, audio_event.Param2, audio_event.Param3);
        if (ret == 0){
            switch (audio_event.ID)
            {
            case AUDIO_EVENT_RUN_FUNCTION:{
                CBDataFun_t CB = (CBDataFun_t)(audio_event.Param1);
                CB(audio_event.Param2, audio_event.Param3);
                break;
            }
            case AUDIO_EVENT_PLAY_FILE:
                play_ctx = (luat_audio_play_ctx_t *)audio_event.Param1;
                if (play_ctx) {
                    luat_audio_do_play_file(play_ctx->multimedia_id, play_ctx->path);
                    luat_audio_post_done_event(play_ctx->multimedia_id);
                    luat_heap_free(play_ctx);
                }
                break;
            default:
                break;
            }
        }
    }
}

LUAT_WEAK int luat_audio_init(uint8_t multimedia_id, uint16_t init_vol, uint16_t init_mic_vol){
	luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf == NULL) return -1;
    if (luat_audio_task_bootstrap() != 0) return -1;
    audio_conf->last_wakeup_time_ms = luat_mcu_tick64_ms();
    audio_conf->last_vol = init_vol;
    audio_conf->last_mic_vol = init_mic_vol;
    if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
    	if (audio_conf->codec_conf.codec_opts->no_control)
    	{
    		audio_conf->sleep_mode = LUAT_AUDIO_PM_SHUTDOWN;
    		return 0;
    	}
    	luat_audio_power_keep_ctrl_by_bsp(1);
        int result = audio_conf->codec_conf.codec_opts->init(&audio_conf->codec_conf, LUAT_CODEC_MODE_SLAVE);
        if (result) return result;
        LLOGD("codec init %s ",audio_conf->codec_conf.codec_opts->name);
        result = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_RATE, LUAT_I2S_HZ_16k);
        if (result) return result;
        result = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_BITS, LUAT_I2S_BITS_16);
        if (result) return result;
        result = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_FORMAT,LUAT_CODEC_FORMAT_I2S);
        if (result) return result;
        result = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL, init_vol);
        if (result) return result;
        result = audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MIC_VOL, init_mic_vol);
        if (result) return result;

        if (!audio_conf->pa_is_control_enable)	//PA无法控制的状态，则通过静音来控制
        {
        	audio_conf->codec_conf.codec_opts->start(&audio_conf->codec_conf);
        	audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MUTE, 1);
        }
        else
        {
            luat_audio_pm_request(multimedia_id,LUAT_AUDIO_PM_STANDBY); //默认进入standby模式

        }
        audio_conf->sleep_mode = LUAT_AUDIO_PM_STANDBY;
    }else if(audio_conf->bus_type == LUAT_AUDIO_BUS_DAC){
        luat_dac_config_t* dac_config = luat_dac_get_config(audio_conf->codec_conf.dac_id);
        dac_config->samp_rate = LUAT_DAC_SAMP_16000;
        dac_config->bits = LUAT_DAC_BITS_16;
        dac_config->dac_chl = LUAT_DAC_CHL_L;
        luat_dac_setup(audio_conf->codec_conf.dac_id, dac_config);
    }else{
        LLOGE("unsupported bus type %d", audio_conf->bus_type);
        return -1;
    }

	return 0;
}

LUAT_WEAK int luat_audio_set_bus_type(uint8_t multimedia_id,uint8_t bus_type){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);  // 获取音频配置
    if (audio_conf){
        if (bus_type == LUAT_AUDIO_BUS_I2S || bus_type == LUAT_AUDIO_BUS_DAC){
            audio_conf->codec_conf.multimedia_id = multimedia_id;
            audio_conf->bus_type = bus_type;
            return 0;
        }
    }
    return -1;  // 配置无效或不支持的总线类型
}

LUAT_WEAK int luat_audio_pm_request(uint8_t multimedia_id,luat_audio_pm_mode_t mode){
    luat_audio_conf_t* audio_conf = luat_audio_get_config(multimedia_id);
    if (audio_conf!=NULL && audio_conf->bus_type == LUAT_AUDIO_BUS_I2S){
    	if (!audio_conf->pa_is_control_enable)
    	{
    		if (mode)
    		{
    			luat_audio_mute(multimedia_id, 1);
    		}
    		else
    		{
    			luat_audio_mute(multimedia_id, 0);
    		}
    		audio_conf->sleep_mode = mode;
        	return 0;
    	}
    	if (audio_conf->codec_conf.codec_opts->no_control)	//codec没有寄存器的情况
    	{
			switch(mode)
			{
			case LUAT_AUDIO_PM_RESUME:
				luat_audio_power_keep_ctrl_by_bsp(1);
				luat_audio_play_blank(multimedia_id, 1);
				luat_audio_power(multimedia_id,1);
				break;
			case LUAT_AUDIO_PM_STANDBY:	//只关PA，codec不关，这样下次播放的时候不需要重新启动codec，节省启动时间
				luat_audio_power_keep_ctrl_by_bsp(1);
				luat_audio_play_blank(multimedia_id, 1);
				luat_audio_pa(multimedia_id,0,0);
				break;
			default:
				luat_audio_power_keep_ctrl_by_bsp(0);
				luat_audio_pa(multimedia_id,0,0);
				if (audio_conf->power_off_delay_time)
					luat_rtos_task_sleep(audio_conf->power_off_delay_time);
				luat_audio_power(multimedia_id,0);
				audio_conf->wakeup_ready = 0;
				audio_conf->pa_on_enable = 0;
#ifdef __LUATOS__
				luat_audio_play_blank(multimedia_id, 0);
#endif
				break;
			}
			audio_conf->sleep_mode = mode;


    	}
    	else	//codec有寄存器的情况
    	{
    		if (audio_conf->sleep_mode == mode) return 0;
    		switch (mode){
			case LUAT_AUDIO_PM_RESUME:
				luat_audio_power_keep_ctrl_by_bsp(1);
				if (!audio_conf->speech_uplink_type && !audio_conf->speech_downlink_type && !audio_conf->record_mode)
				{
					//LLOGD("audio pm !");
					luat_audio_play_blank(multimedia_id, 1);
				}
				if (LUAT_AUDIO_PM_POWER_OFF == audio_conf->sleep_mode)	//之前已经强制断电过了，就必须重新初始化
				{
					luat_audio_init(multimedia_id, audio_conf->last_vol, audio_conf->last_mic_vol);
				}
				//LLOGD("audio pm %d,%d", audio_conf->last_vol, audio_conf->last_mic_vol);
				luat_i2s_conf_t *i2s = luat_i2s_get_config(audio_conf->codec_conf.i2s_id);
				audio_conf->codec_conf.codec_opts->start(&audio_conf->codec_conf);
				audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_BITS, i2s->data_bits);
				audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_VOICE_VOL, audio_conf->last_vol);
				audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_SET_MIC_VOL, audio_conf->last_mic_vol);
				audio_conf->last_wakeup_time_ms = luat_mcu_tick64_ms();
				audio_conf->sleep_mode = LUAT_AUDIO_PM_RESUME;
				break;
			case LUAT_AUDIO_PM_STANDBY:
				luat_audio_power_keep_ctrl_by_bsp(1);
				luat_audio_pa(multimedia_id,0,0);
				if (audio_conf->power_off_delay_time)
					luat_rtos_task_sleep(audio_conf->power_off_delay_time);
				audio_conf->codec_conf.codec_opts->stop(&audio_conf->codec_conf);
				audio_conf->sleep_mode = LUAT_AUDIO_PM_STANDBY;
#ifdef __LUATOS__
				luat_audio_play_blank(multimedia_id, 0);
#endif
				break;
			case LUAT_AUDIO_PM_SHUTDOWN:
				luat_audio_pa(multimedia_id,0,0);
				if (audio_conf->power_off_delay_time)
					luat_rtos_task_sleep(audio_conf->power_off_delay_time);
				audio_conf->codec_conf.codec_opts->control(&audio_conf->codec_conf,LUAT_CODEC_MODE_PWRDOWN,0);
				luat_audio_power_keep_ctrl_by_bsp(0);
				audio_conf->wakeup_ready = 0;
				audio_conf->pa_on_enable = 0;
				audio_conf->sleep_mode = LUAT_AUDIO_PM_SHUTDOWN;
#ifdef __LUATOS__
				luat_audio_play_blank(multimedia_id, 0);
#endif
				break;
			case LUAT_AUDIO_PM_POWER_OFF:
				luat_audio_pa(multimedia_id,0,0);
				if (audio_conf->power_off_delay_time)
					luat_rtos_task_sleep(audio_conf->power_off_delay_time);
				luat_audio_power(multimedia_id,0);
				luat_audio_power_keep_ctrl_by_bsp(0);
				audio_conf->wakeup_ready = 0;
				audio_conf->pa_on_enable = 0;
				audio_conf->sleep_mode = LUAT_AUDIO_PM_POWER_OFF;
#ifdef __LUATOS__
				luat_audio_play_blank(multimedia_id, 0);
#endif
				break;
			default:
				return -1;
			}
    	}

        return 0;
    }
    return -1;
}

LUAT_WEAK void luat_audio_power_keep_ctrl_by_bsp(uint8_t on_off)
{
	;
}

LUAT_WEAK void luat_audio_run_callback_in_task(void *api, uint8_t *data, uint32_t len)
{
    if (luat_audio_task_bootstrap() != 0) {
        ((CBDataFun_t)api)(data, len);
        return;
    }
    OS_EVENT audio_event = {
        .ID = AUDIO_EVENT_RUN_FUNCTION,
        .Param1 = api,
        .Param2 = data,
        .Param3 = len,
    };
    luat_rtos_queue_send(audio_queue_handle, &audio_event, sizeof(OS_EVENT), 0);
}

LUAT_WEAK void luat_audio_setup_record_callback(uint8_t multimedia_id, void* callback, void *param)
{
	return ;
}

LUAT_WEAK int luat_adc_set_vol(uint32_t ch, uint8_t vol) {return -1;}
