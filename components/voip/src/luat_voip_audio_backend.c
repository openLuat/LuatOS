/* Optional physical audio backends for the generic VoIP RTP engine. */
#include "luat_conf_bsp.h"
#include "luat_voip_core.h"
#include "luat_audio.h"
#include "luat_mem.h"
#include <string.h>

#if defined(LUAT_USE_VOIP_AUDIO_I2S)
#include "luat_i2s.h"
#endif
#if defined(LUAT_USE_VOIP_AUDIO_DAC)
#include "luat_dac.h"
#endif
#if defined(LUAT_USE_VOIP_AUDIO_V2)
#include "luat_audio_driver.h"
#endif

#define LUAT_LOG_TAG "voip"
#include "luat_log.h"

#if defined(LUAT_USE_VOIP_AUDIO_I2S) || defined(LUAT_USE_VOIP_AUDIO_DAC)
static int voip_audio_capture_cb(uint8_t id, luat_i2s_event_t event, uint8_t *rx_data, uint32_t rx_len, void *param)
{
    voip_ctx_t *ctx = voip_get_ctx();
    (void)id;
    (void)param;
    if (event != LUAT_I2S_EVENT_RX_DONE || ctx->state != VOIP_STATE_RUNNING || !ctx->task_handle) {
        return 0;
    }
    uint8_t mic_idx = ctx->mic_write_idx;
    uint32_t copy_len = rx_len > ctx->frame_bytes ? ctx->frame_bytes : rx_len;
    if (ctx->mic_buf[mic_idx]) {
        memcpy(ctx->mic_buf[mic_idx], rx_data, copy_len);
        if (copy_len < ctx->frame_bytes) {
            memset(((uint8_t *)ctx->mic_buf[mic_idx]) + copy_len, 0, ctx->frame_bytes - copy_len);
        }
    }
    uint32_t generation = ++ctx->mic_generation[mic_idx];
    if (ctx->audio_backend == VOIP_AUDIO_BACKEND_DUPLEX) {
        ctx->last_completed_slot = (ctx->last_completed_slot + 1) % ctx->play_slot_count;
    }
    luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_MIC_DATA, mic_idx, ctx->last_completed_slot, generation, 0);
    ctx->mic_write_idx = (ctx->mic_write_idx + 1) % VOIP_MIC_SLOT_COUNT;
    return 0;
}
#endif

#if defined(LUAT_USE_VOIP_AUDIO_DAC)
static int voip_dac_play_cb(uint8_t id, luat_dac_event_t event, uint32_t tx_len, void *param)
{
    voip_ctx_t *ctx = (voip_ctx_t *)param;
    (void)id;
    (void)tx_len;
    if (event == LUAT_DAC_EVENT_TX_ONE_BLOCK_DONE && ctx->state == VOIP_STATE_RUNNING) {
        luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_SPK_DONE, 0, 0, 0, 0);
    }
    return 0;
}
#endif

#ifdef LUAT_USE_VOIP_AUDIO_V2
void luat_audio_voip_dac_done_cb(void)
{
    voip_ctx_t *ctx = voip_get_ctx();
    if (ctx->state == VOIP_STATE_RUNNING && ctx->task_handle) {
        luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_SPK_DONE, 0, 0, 0, 0);
    }
}
#endif

int voip_audio_backend_start(voip_ctx_t *ctx, uint32_t sample_rate)
{
    luat_audio_conf_t *audio_conf = luat_audio_get_config(ctx->config.multimedia_id);
    if (!audio_conf) {
        LLOGE("audio config not found for multimedia_id=%u", ctx->config.multimedia_id);
        return -1;
    }
    memset(ctx->duplex_play_buf, 0, ctx->frame_bytes * ctx->play_slot_count);

    if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S) {
#ifdef LUAT_USE_VOIP_AUDIO_I2S
        luat_i2s_conf_t *i2s = luat_i2s_get_config((uint8_t)audio_conf->codec_conf.i2s_id);
        if (!i2s) return -1;
        if (luat_i2s_save_old_config(audio_conf->codec_conf.i2s_id) == 0) ctx->i2s_config_saved = 1;
        i2s->is_full_duplex = 1;
        i2s->cb_rx_len = ctx->frame_bytes;
        i2s->luat_i2s_event_callback = voip_audio_capture_cb;
        ctx->audio_backend = VOIP_AUDIO_BACKEND_DUPLEX;
        if (luat_audio_record_and_play(ctx->config.multimedia_id, sample_rate, (const uint8_t *)ctx->duplex_play_buf,
                                       ctx->frame_bytes, ctx->play_slot_count) != 0) {
            if (ctx->i2s_config_saved) {
                luat_i2s_load_old_config(audio_conf->codec_conf.i2s_id);
                ctx->i2s_config_saved = 0;
            }
            return -1;
        }
#else
        LLOGE("voip i2s backend is disabled in this firmware");
        return -1;
#endif
    } else if (audio_conf->bus_type == LUAT_AUDIO_BUS_DAC) {
#ifdef LUAT_USE_VOIP_AUDIO_DAC
        ctx->audio_backend = VOIP_AUDIO_BACKEND_NONE;
        luat_audio_record_set_callback(voip_audio_capture_cb);
#ifdef LUAT_USE_VOIP_AUDIO_V2
        luat_audio_driver_ctrl_t *ctrl = luat_audio_driver_probe(NULL);
        if (!ctrl) return -1;
        if (LUAT_AUDIO_DRIVER_STATE_INITED == ctrl->state) {
            if (ctrl->opts->activate(ctrl)) return -1;
            ctrl->state = LUAT_AUDIO_DRIVER_STATE_ACTIVE;
        }
        if (ctrl->opts->modify_audio_common_param(ctrl, sample_rate, 2, 1, 0) != LUAT_ERROR_NONE ||
            ctrl->opts->modify_audio_common_param(ctrl, sample_rate, 2, 1, 1) != LUAT_ERROR_NONE) return -1;
        ctrl->request_work_mode = LUAT_AUDIO_DRIVER_MODE_SPEECH_WITH_BUFFER;
        if (luat_audio_driver_start(ctrl, &ctrl->tx_param, &ctrl->rx_param, (uint32_t *)ctx->duplex_play_buf,
                                    ctx->frame_bytes, ctx->play_slot_count) != 0) return -1;
        ctx->audio_v2_ctrl = ctrl;
#else
        if (luat_audio_record_and_play(ctx->config.multimedia_id, sample_rate, (const uint8_t *)ctx->duplex_play_buf,
                                       ctx->frame_bytes, ctx->play_slot_count) != 0) return -1;
        luat_dac_config_t config = {
            .dac_chl = LUAT_DAC_CHL_L, .bits = LUAT_DAC_BITS_16, .samp_rate = sample_rate,
            .luat_dac_event_callback = voip_dac_play_cb, .userdata = ctx
        };
        luat_dac_setup(0, &config);
        luat_dac_buffer_loop(ctx->config.multimedia_id, ctx->duplex_play_buf, ctx->frame_bytes, ctx->play_slot_count);
#endif
#else
        LLOGE("voip dac backend is disabled in this firmware");
        return -1;
#endif
    } else {
        LLOGE("voip audio backend: unsupported bus=%u", audio_conf->bus_type);
        return -1;
    }
    ctx->audio_started = 1;
    ctx->last_completed_slot = ctx->play_slot_count - 1;
    return 0;
}

void voip_audio_backend_stop(voip_ctx_t *ctx)
{
    if (!ctx->audio_started) return;
    luat_audio_conf_t *audio_conf = luat_audio_get_config(ctx->config.multimedia_id);
    if (!audio_conf) return;
    if (ctx->duplex_play_buf) memset(ctx->duplex_play_buf, 0, ctx->frame_bytes * ctx->play_slot_count);
#ifdef LUAT_USE_VOIP_AUDIO_V2
    if (ctx->audio_v2_ctrl) {
        /* deactivate owns the audio_v2 stop transition; do not stop twice. */
        luat_audio_driver_deactivate((luat_audio_driver_ctrl_t *)ctx->audio_v2_ctrl);
        ctx->audio_v2_ctrl = NULL;
    } else
#endif
    {
        luat_audio_record_stop(ctx->config.multimedia_id);
        if (audio_conf->bus_type == LUAT_AUDIO_BUS_I2S) {
#ifdef LUAT_USE_VOIP_AUDIO_I2S
            luat_i2s_load_old_config(audio_conf->codec_conf.i2s_id);
            ctx->i2s_config_saved = 0;
#endif
        } else {
#ifdef LUAT_USE_VOIP_AUDIO_DAC
            luat_dac_close(0);
#endif
        }
    }
    ctx->audio_backend = VOIP_AUDIO_BACKEND_NONE;
    ctx->audio_started = 0;
}
