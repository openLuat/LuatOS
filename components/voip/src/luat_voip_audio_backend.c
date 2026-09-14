/* Optional physical audio backends for the generic VoIP RTP engine. */
#include "luat_conf_bsp.h"
#include "luat_voip_core.h"
#include "luat_audio.h"
#include "luat_mem.h"
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
#include "luat_mcu.h"
#endif
#include <string.h>

#if defined(LUAT_USE_VOIP_AUDIO_I2S) || defined(LUAT_USE_AUDIO_V2)
#include "luat_i2s.h"
#endif
#if defined(LUAT_USE_VOIP_AUDIO_DAC)
#include "luat_dac.h"
#endif
#if defined(LUAT_USE_AUDIO_V2)
#include "luat_audio_driver.h"
#include "luat_audio_core.h"
#endif

#if defined(LUAT_USE_RECORD) && defined(LUAT_USE_VOIP_AUDIO_DAC)
#define LUAT_VOIP_USE_RECORD_CALLBACK
#endif

#define LUAT_LOG_TAG "voip"
#include "luat_log.h"

#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
static void voip_audio_render_done(voip_ctx_t *ctx)
{
    uint32_t render_seq;
    uint8_t slot;
    int16_t *render_frame;
    if (!ctx || ctx->state != VOIP_STATE_RUNNING || !ctx->task_handle ||
        !ctx->duplex_play_buf || !ctx->play_slot_count) {
        return;
    }
    render_seq = ctx->render_done_seq + 1;
    slot = (uint8_t)((render_seq - 1) % ctx->play_slot_count);
    render_frame = ctx->duplex_play_buf + slot * ctx->frame_samples;
    voip_aec_render_push(ctx, render_frame, render_seq, luat_mcu_tick64_ms());
    __sync_synchronize();
    ctx->render_done_seq = render_seq;
    if (luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_SPK_DONE, slot, render_seq, 0, 0) != 0) {
        ctx->aec_sync_fault = 1;
    }
}
#endif

#if defined(LUAT_USE_VOIP_AUDIO_I2S) || defined(LUAT_USE_VOIP_AUDIO_DAC) || defined(LUAT_USE_AUDIO_V2)
static int voip_audio_capture_cb(uint8_t id, luat_i2s_event_t event, uint8_t *rx_data, uint32_t rx_len, void *param)
{
    voip_ctx_t *ctx = voip_get_ctx();
    (void)id;
    (void)param;
    if (event != LUAT_I2S_EVENT_RX_DONE || ctx->state != VOIP_STATE_RUNNING || !ctx->task_handle) {
        return 0;
    }
    if (ctx->audio_backend == VOIP_AUDIO_BACKEND_DUPLEX) {
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
        voip_audio_render_done(ctx);
#else
        ctx->last_completed_slot = (ctx->last_completed_slot + 1) % ctx->play_slot_count;
#endif
    }
    uint8_t mic_idx = ctx->mic_write_idx;
    uint32_t copy_len = rx_len > ctx->frame_bytes ? ctx->frame_bytes : rx_len;
    if (ctx->mic_buf[mic_idx]) {
        memcpy(ctx->mic_buf[mic_idx], rx_data, copy_len);
        if (copy_len < ctx->frame_bytes) {
            memset(((uint8_t *)ctx->mic_buf[mic_idx]) + copy_len, 0, ctx->frame_bytes - copy_len);
        }
    }
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    uint32_t capture_seq = ++ctx->capture_seq;
    ctx->mic_capture_seq[mic_idx] = capture_seq;
    ctx->mic_render_seq[mic_idx] = ctx->render_done_seq;
    ctx->mic_capture_tick_ms[mic_idx] = luat_mcu_tick64_ms();
    __sync_synchronize();
#endif
    uint32_t generation = ++ctx->mic_generation[mic_idx];
    if (luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_MIC_DATA, mic_idx,
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
            0,
#else
            ctx->last_completed_slot,
#endif
            generation, 0) != 0) {
        ctx->dropped_mic_events++;
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
        ctx->aec_sync_fault = 1;
#endif
    }
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
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
        voip_audio_render_done(ctx);
#else
        luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_SPK_DONE, 0, 0, 0, 0);
#endif
    }
    return 0;
}
#endif

#ifdef LUAT_USE_AUDIO_V2
/* audio_v2 直启 driver 模式下的 TX/RX block 事件接管（强符号，覆盖平台层 i2s 回调里的
 * weak 默认实现 luat_audio_voip_driver_event，如 luatos-soc-2024 luat_i2s_ec7xx.c）。
 * 在驱动 ISR 上下文中被调用，仅做帧拷贝和事件投递。 */
int luat_audio_voip_driver_event(uint32_t event, uint8_t *rx_data, uint32_t param, luat_audio_driver_ctrl_t *ctrl)
{
    voip_ctx_t *ctx = voip_get_ctx();
    if (ctx->state != VOIP_STATE_RUNNING || !ctx->audio_v2_ctrl || ctrl != (luat_audio_driver_ctrl_t *)ctx->audio_v2_ctrl) {
        return 0;
    }
    switch (event) {
    case LUAT_AUDIO_DRIVER_EVENT_RX_ONE_BLOCK_DONE:
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
        if (ctrl->opts->support_full_loop && ctx->task_handle) {
            voip_audio_render_done(ctx);
        }
        /* 一块 mic PCM 就绪，复用采集回调完成拷贝与 MIC_DATA 事件投递 */
        voip_audio_capture_cb(0, LUAT_I2S_EVENT_RX_DONE, rx_data, param, NULL);
#else
        voip_audio_capture_cb(0, LUAT_I2S_EVENT_RX_DONE, rx_data, param, NULL);
        if (ctrl->opts->support_full_loop && ctx->task_handle) {
            luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_SPK_DONE, 0, 0, 0, 0);
        }
#endif
        break;
    case LUAT_AUDIO_DRIVER_EVENT_TX_ONE_BLOCK_DONE:
        if (!ctrl->opts->support_full_loop && ctx->task_handle) {
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
            voip_audio_render_done(ctx);
#else
            luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_SPK_DONE, 0, 0, 0, 0);
#endif
        }
        break;
    default:
        break;
    }
    return 1;
}

#ifdef LUAT_USE_VOIP_AUDIO_DAC
/* Audio V2 DAC speech mode reports playback progress through this hook instead
 * of luat_audio_driver_event_callback(). Keep it out of Audio V2 I2S builds. */
void luat_audio_voip_dac_done_cb(void)
{
    voip_ctx_t *ctx = voip_get_ctx();
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    voip_audio_render_done(ctx);
#else
    if (ctx->state == VOIP_STATE_RUNNING && ctx->task_handle) {
        luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_SPK_DONE, 0, 0, 0, 0);
    }
#endif
}
#endif
#endif

#ifdef LUAT_USE_AUDIO_V2
/* audio_v2 driver 是总线无关的：I2S codec(如ES8311)与DAC都由 driver 托管。
 * 返回 0 表示 audio_v2 启动成功；失败时清理干净并返回 -1，由调用方回退 legacy 后端
 * （兼容 audio_mode="old" 等 legacy 音频框架已占用 DMA 的固件形态）。 */
static int voip_audio_v2_start(voip_ctx_t *ctx, uint32_t sample_rate)
{
    luat_audio_driver_ctrl_t *ctrl = luat_audio_driver_probe(NULL);
    if (!ctrl) {
        LLOGE("no audio_v2 driver found");
        return -1;
    }
    uint8_t activated = 0;
#ifdef LUAT_VOIP_USE_RECORD_CALLBACK
    uint8_t record_cb_set = 0;
#endif
    if (LUAT_AUDIO_DRIVER_STATE_INITED == ctrl->state) {
        if (ctrl->opts->activate(ctrl)) {
            LLOGW("audio_v2 activate failed, try legacy backend");
            return -1;
        }
        ctrl->state = LUAT_AUDIO_DRIVER_STATE_ACTIVE;
        activated = 1;
    }
    if (ctrl->opts->modify_audio_common_param(ctrl, sample_rate, 2, 1, 0) != LUAT_ERROR_NONE ||
        ctrl->opts->modify_audio_common_param(ctrl, sample_rate, 2, 1, 1) != LUAT_ERROR_NONE) {
        LLOGE("audio_v2 modify param failed");
        goto fail;
    }
    ctrl->request_work_mode = LUAT_AUDIO_DRIVER_MODE_SPEECH_WITH_BUFFER;
#ifdef LUAT_VOIP_USE_RECORD_CALLBACK
    /* BK72xx Audio V2 speech mode sends ADC frames through the legacy record
     * callback entry rather than luat_audio_driver_event_callback(). */
    luat_audio_record_set_callback(voip_audio_capture_cb);
    record_cb_set = 1;
#endif
    /* 注意：luat_audio_driver_start 失败时会自行 deactivate 并把 state 重置为 INITED，
     * 这里提前清 activated 标记，避免 fail 路径重复 deactivate */
    activated = 0;
    if (luat_audio_driver_start(ctrl, &ctrl->tx_param, &ctrl->rx_param, (uint32_t *)ctx->duplex_play_buf,
                                ctx->frame_bytes, ctx->play_slot_count) != 0) {
        LLOGE("audio_v2 speech with buffer start failed");
        goto fail;
    }
    ctx->audio_v2_ctrl = ctrl;
    ctx->audio_backend = VOIP_AUDIO_BACKEND_NONE;
    return 0;
fail:
#ifdef LUAT_VOIP_USE_RECORD_CALLBACK
    if (record_cb_set) {
        luat_audio_record_set_callback(NULL);
    }
#endif
    if (activated) {
        luat_audio_driver_deactivate(ctrl);
    }
    return -1;
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

#ifdef LUAT_USE_AUDIO_V2
    if (voip_audio_v2_start(ctx, sample_rate) == 0) {
        ctx->audio_started = 1;
        ctx->last_completed_slot = ctx->play_slot_count - 1;
        return 0;
    }
    /* audio_v2 不可用（如 legacy 音频框架占用 DMA），回退 legacy 后端 */
#endif
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    if (audio_conf->bus_type == LUAT_AUDIO_BUS_DAC && ctx->config.aec_enable) {
        LLOGE("AEC requires the Audio V2 DAC backend; legacy DAC fallback refused");
        return -1;
    }
#endif
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
#ifdef LUAT_VOIP_USE_RECORD_CALLBACK
        luat_audio_record_set_callback(voip_audio_capture_cb);
#endif
        if (luat_audio_record_and_play(ctx->config.multimedia_id, sample_rate, (const uint8_t *)ctx->duplex_play_buf,
                                       ctx->frame_bytes, ctx->play_slot_count) != 0) return -1;
        luat_dac_config_t config = {
            .dac_chl = LUAT_DAC_CHL_L, .bits = LUAT_DAC_BITS_16, .samp_rate = sample_rate,
            .luat_dac_event_callback = voip_dac_play_cb, .userdata = ctx
        };
        luat_dac_setup(0, &config);
        luat_dac_buffer_loop(ctx->config.multimedia_id, ctx->duplex_play_buf, ctx->frame_bytes, ctx->play_slot_count);
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
#ifdef LUAT_USE_AUDIO_V2
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
#ifdef LUAT_VOIP_USE_RECORD_CALLBACK
    luat_audio_record_set_callback(NULL);
#endif
    ctx->audio_backend = VOIP_AUDIO_BACKEND_NONE;
    ctx->audio_started = 0;
}
