/*
 * luat_cc_bridge.c - CC(VoLTE) <-> VoIP(SIP) 桥接功能
 *
 * 从 luat_lib_cc_v2.c 拆出的桥接代码，便于单独维护，来源提交：
 *   144285f86 add: voip,cc, 支持sip和cc通话语音流传输
 *   a4a5db00b add: voip,cc, 添加支持在4g->sip桥接通话的早期媒体功能
 *   ae88b9075 fix: cc,voip, 误把 rate=1 当成 16 kHz,导致移动卡实际 8 kHz 语音被错误按 16 kHz 处理
 *
 * 数据通路：
 *   下行(对端->SIP)：CP DSP -> play_save_fifo -> (16k->8k降采样) -> voip_bridge_pcm_in -> RTP
 *   上行(SIP->对端)：RTP -> voip_bridge_pcm_out() -> extern-record source -> CP DSP
 */

#include "luat_cc_bridge.h"

#if defined(LUAT_USE_AUDIO_V2) && defined(LUAT_USE_CC_VOIP_BRIDGE)
#include <string.h>
#include "luat_rtos.h"
#include "luat_voip_core.h"

#define LUAT_LOG_TAG "cc"
#include "luat_log.h"

#define CC_BRIDGE_SOURCE_STOP_TIMEOUT_MS 2000

extern const int16_t ringback_8k_data[8000];

/* -------------------- 模块私有状态(原 _l_cc 内的桥接字段) -------------------- */
static volatile uint8_t s_bridge_enabled;  /* Explicit CC selection, off at boot. */
static luat_rtos_timer_t s_tone_timer;      /* 原 _l_cc.bridge_tone_timer */
static luat_rtos_timer_t s_drain_timer;     /* 原 _l_cc.bridge_drain_timer */
static luat_rtos_timer_t s_uplink_source_timer;
typedef enum {
    CC_BRIDGE_SOURCE_IDLE = 0,
    CC_BRIDGE_SOURCE_STARTING,
    CC_BRIDGE_SOURCE_ACTIVE,
    CC_BRIDGE_SOURCE_STOPPING,
} luat_cc_bridge_source_state_t;

/* Owned here for the entire lifetime, including asynchronous destruction. */
static luat_audio_extern_source_t s_source;
static volatile luat_cc_bridge_source_state_t s_source_state;
static uint32_t s_source_request_id;
static luat_audio_extern_source_t *s_uplink_source;
static uint16_t s_uplink_source_cc_sr;
/* Timer stop only queues a command on EC7xx. These locks also join any
 * in-flight PCM access before CC cancels/frees the borrowed resources.
 * Keep source and drain locks separate: source start waits for audio task,
 * which may itself call drain_downlink. Timer callbacks never wait on them. */
static luat_rtos_mutex_t s_uplink_lock;
static luat_rtos_mutex_t s_uplink_lifecycle_lock;
static luat_rtos_mutex_t s_drain_lock;
static uint8_t s_uplink_allowed;
static uint8_t s_uplink_stop_requested;
static uint8_t s_drain_allowed;
/* The shared RTOS timer task has a small stack (2 KB on EC718HM).
 * Keep the resampling workspace off that stack: PCM out can also call the
 * VoIP recording tap. All accesses are serialized by s_uplink_lock. */
static int16_t s_uplink_voip_pcm[320];
static int16_t s_uplink_cc_pcm[320];

int luat_cc_bridge_session_start(void)
{
    if (!luat_cc_bridge_mode_on()) return -LUAT_ERROR_OPERATION_FAILED;
    /* Called by the serialized CC media-start path, before audio callbacks. */
    if ((!s_uplink_lock && luat_rtos_mutex_create(&s_uplink_lock)) ||
        (!s_uplink_lifecycle_lock && luat_rtos_mutex_create(&s_uplink_lifecycle_lock)) ||
        (!s_drain_lock && luat_rtos_mutex_create(&s_drain_lock))) {
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    luat_rtos_mutex_lock(s_uplink_lifecycle_lock, LUAT_WAIT_FOREVER);
    luat_rtos_mutex_lock(s_uplink_lock, LUAT_WAIT_FOREVER);
    if (s_uplink_source) {
        luat_rtos_mutex_unlock(s_uplink_lock);
        luat_rtos_mutex_unlock(s_uplink_lifecycle_lock);
        LLOGE("previous CC bridge source is still retiring");
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    s_uplink_allowed = 1;
    s_uplink_stop_requested = 0;
    luat_rtos_mutex_unlock(s_uplink_lock);
    luat_rtos_mutex_unlock(s_uplink_lifecycle_lock);
    luat_rtos_mutex_lock(s_drain_lock, LUAT_WAIT_FOREVER);
    s_drain_allowed = 1;
    luat_rtos_mutex_unlock(s_drain_lock);
    return LUAT_ERROR_NONE;
}
static uint8_t  s_tone_on;                  /* 原 _l_cc.bridge_tone_on */
static uint32_t s_tone_pos;                 /* 原 _l_cc.bridge_tone_pos */

static int16_t  s_downlink_pcm_buf[VOIP_BRIDGE_BUF_SAMPLES];

/*
 * The generic RAW codec batches 8000 bytes, which adds 250--500 ms of
 * latency here.  Bridge PCM is already decoded and arrives in 20 ms blocks,
 * so use a small pass-through codec for the extern stream.
 */
static int _bridge_pcm_codec_init(luat_audio_data_codec_t *codec, uint8_t is_encode)
{
    (void)codec;
    (void)is_encode;
    return LUAT_ERROR_NONE;
}

static void _bridge_pcm_codec_deinit(luat_audio_data_codec_t *codec)
{
    (void)codec;
}

static const luat_audio_data_codec_opts_t s_bridge_pcm_codec = {
    .init = _bridge_pcm_codec_init,
    .deinit = _bridge_pcm_codec_deinit,
    .set_record_info = luat_audio_codec_wav_set_record_info,
    .decode = NULL,
    .decode_min_input_len = 320,
    .decode_max_output_len = 320,
    .type = LUAT_AUDIO_DATA_CODEC_TYPE_CC_BRIDGE_PCM,
    .is_hardware = 0,
    .support_detect = 0,
    .encode_raw_mode = 1,
    .decode_raw_mode = 1,
};

/* -------------------- 早期彩铃(early media) -------------------- */

static void _bridge_tone_pcm_in(const int16_t *pcm, uint32_t samples)
{
    voip_ctx_t *voip_ctx = voip_get_ctx();
    if (!pcm || !samples || !voip_ctx) {
        return;
    }
    if (!luat_cc_bridge_mode_on() || voip_ctx->state != VOIP_STATE_RUNNING) {
        return;
    }
    while (samples > 0) {
        int consumed = voip_bridge_pcm_in(pcm, samples > VOIP_BRIDGE_BUF_SAMPLES ? VOIP_BRIDGE_BUF_SAMPLES : (uint16_t)samples);
        if (consumed <= 0) {
            break;
        }
        pcm += consumed;
        samples -= (uint32_t)consumed;
    }
}

uint8_t luat_cc_bridge_tone_is_on(void)
{
    return s_tone_on;
}

void luat_cc_bridge_tone_stop(void)
{
    if (s_tone_timer && s_tone_on) {
        luat_rtos_timer_stop(s_tone_timer);
    }
    if (s_tone_on) {
        LLOGI("CC bridge early tone stopped");
    }
    s_tone_on = 0;
    s_tone_pos = 0;
}

static void _bridge_tone_timer_cb(LUAT_RT_CB_PARAM)
{
    (void)param;
    voip_ctx_t *voip_ctx = voip_get_ctx();
    uint16_t samples;
    int16_t silence[160] = {0};
    uint32_t tone_pos;

    if (!s_tone_on) {
        return;
    }
    if (!voip_ctx || !luat_cc_bridge_mode_on() || voip_ctx->state != VOIP_STATE_RUNNING) {
        return;
    }
    if (luat_cc_call_running()) {
        luat_cc_bridge_tone_stop();
        return;
    }

    samples = voip_ctx->frame_samples ? voip_ctx->frame_samples : 160;
    if (samples > 160) {
        samples = 160;
    }

    tone_pos = s_tone_pos % 24000;
    if (tone_pos < 8000) {
        uint32_t left = 8000 - tone_pos;
        if (left < samples) {
            _bridge_tone_pcm_in(&ringback_8k_data[tone_pos], left);
            _bridge_tone_pcm_in(silence, samples - left);
        } else {
            _bridge_tone_pcm_in(&ringback_8k_data[tone_pos], samples);
        }
    } else {
        _bridge_tone_pcm_in(silence, samples);
    }
    s_tone_pos = (s_tone_pos + samples) % 24000;
}

void luat_cc_bridge_tone_start(void)
{
    voip_ctx_t *voip_ctx = voip_get_ctx();
    if (!voip_ctx || !luat_cc_bridge_mode_on() || voip_ctx->state != VOIP_STATE_RUNNING) {
        return;
    }
    if (luat_cc_call_running()) {
        return;
    }
    if (!s_tone_timer) {
        if (luat_rtos_timer_create(&s_tone_timer) != 0) {
            LLOGE("create CC bridge early tone timer failed");
            return;
        }
    }
    s_tone_pos = 0;
    if (luat_rtos_timer_start(s_tone_timer, 20, 1, _bridge_tone_timer_cb, NULL) == 0) {
        if (!s_tone_on) {
            LLOGI("CC bridge early tone started");
        }
        s_tone_on = 1;
    } else {
        LLOGE("start CC bridge early tone timer failed");
    }
}

/* -------------------- 采样率转换 -------------------- */

static void _downsample_16k_to_8k(int16_t *inout, uint32_t in_samples, uint32_t *out_samples)
{
    uint32_t j = 0;
    uint32_t i = 0;
    for (; i + 1 < in_samples; i += 2) {
        inout[j++] = (int16_t)(((int32_t)inout[i] + (int32_t)inout[i + 1]) / 2);
    }
    if (i < in_samples) {
        inout[j++] = inout[i];
    }
    *out_samples = j;
}

/* -------------------- 下行(CC -> VoIP) -------------------- */

void luat_cc_bridge_real_downlink_seen(uint32_t bytes)
{
    if (bytes && luat_cc_bridge_mode_on()) voip_bridge_tone(0);
}

int luat_cc_bridge_set_enabled(uint8_t enabled)
{
    voip_ctx_t *voip_ctx = voip_get_ctx();
    int ret = -LUAT_ERROR_OPERATION_FAILED;
    enabled = enabled ? 1 : 0;

    /* EC7xx CC media transitions run in tasks. Keep the idle check and selection
     * together; this short scheduler section performs no waits or allocation. */
    luat_rtos_task_suspend_all();
    if (enabled == s_bridge_enabled) {
        ret = LUAT_ERROR_NONE;
    } else if (voip_ctx && voip_ctx->state == VOIP_STATE_IDLE &&
               !luat_cc_bridge_is_busy() && !s_tone_on && !s_uplink_source) {
        ret = enabled ? voip_set_audio_mode(VOIP_AUDIO_MODE_BRIDGE) : LUAT_ERROR_NONE;
        if (!ret) s_bridge_enabled = enabled;
    }
    luat_rtos_task_resume_all();
    return ret;
}

uint8_t luat_cc_bridge_mode_on(void)
{
    voip_ctx_t *voip_ctx = voip_get_ctx();
    return (s_bridge_enabled && voip_ctx && voip_ctx->audio_mode == VOIP_AUDIO_MODE_BRIDGE) ? 1 : 0;
}

/* -------------------- 上行(VoIP -> CC)缓冲管理 -------------------- */

void luat_cc_bridge_flush_sip_uplink(void)
{
    voip_ctx_t *voip_ctx = voip_get_ctx();
    if (!voip_ctx || !luat_cc_bridge_mode_on() || !voip_ctx->bridge_rx_buf) {
        return;
    }
    if (voip_ctx->bridge_mutex) luat_rtos_mutex_lock(voip_ctx->bridge_mutex, LUAT_WAIT_FOREVER);
    voip_ctx->bridge_rx_write_idx = 0;
    voip_ctx->bridge_rx_read_idx = 0;
    voip_ctx->bridge_rx_count = 0;
    if (voip_ctx->bridge_mutex) luat_rtos_mutex_unlock(voip_ctx->bridge_mutex);
    LLOGI("CC bridge SIP uplink buffer flushed");
}

static void _bridge_drain_downlink_locked(void)
{
    voip_ctx_t *voip_ctx = voip_get_ctx();
    luat_fifo_t *play_fifo = luat_cc_get_play_fifo();
    uint32_t read_len;
    uint32_t read_limit;
    uint16_t cc_sr;
    uint16_t voip_sr;
    uint8_t drained_frames = 0;

    if (!play_fifo || !voip_ctx ||
        !luat_cc_bridge_mode_on() ||
        voip_ctx->state != VOIP_STATE_RUNNING) {
        return;
    }

    cc_sr = luat_cc_get_sample_rate();
    voip_sr = voip_ctx->config.sample_rate ? voip_ctx->config.sample_rate : 8000;
    read_limit = (cc_sr == 16000) ? 640 : 320;
    if (read_limit > sizeof(s_downlink_pcm_buf)) {
        read_limit = sizeof(s_downlink_pcm_buf);
    }

    while (drained_frames < 2 &&
        (read_len = luat_fifo_read(play_fifo, (uint8_t *)s_downlink_pcm_buf, read_limit)) > 0) {
        int16_t *pcm_ptr;
        uint32_t samples_remaining;
        drained_frames++;

        luat_cc_bridge_tone_stop();
        luat_cc_bridge_real_downlink_seen(read_len);

        if (cc_sr == 16000 && voip_sr == 8000) {
            uint32_t in_samples = read_len / sizeof(int16_t);
            uint32_t out_samples = 0;
            _downsample_16k_to_8k(s_downlink_pcm_buf, in_samples, &out_samples);
            pcm_ptr = s_downlink_pcm_buf;
            samples_remaining = out_samples;
        } else {
            pcm_ptr = s_downlink_pcm_buf;
            samples_remaining = read_len / sizeof(int16_t);
        }

        while (samples_remaining > 0) {
            int consumed = voip_bridge_pcm_in(pcm_ptr, samples_remaining);
            if (consumed <= 0) {
                break;
            }
            pcm_ptr += consumed;
            samples_remaining -= consumed;
        }
    }
}

void luat_cc_bridge_drain_downlink(void)
{
    if (!s_drain_lock || luat_rtos_mutex_lock(s_drain_lock, 0)) return;
    if (s_drain_allowed) _bridge_drain_downlink_locked();
    luat_rtos_mutex_unlock(s_drain_lock);
}

static void _bridge_drain_timer_cb(LUAT_RT_CB_PARAM)
{
    (void)param;
    luat_cc_bridge_drain_downlink();
}

void luat_cc_bridge_drain_start(void)
{
    voip_ctx_t *voip_ctx = voip_get_ctx();
    if (!voip_ctx || !luat_cc_bridge_mode_on() || !s_drain_lock) {
        return;
    }
    luat_rtos_mutex_lock(s_drain_lock, LUAT_WAIT_FOREVER);
    if (!s_drain_allowed) goto done;
    if (!s_drain_timer && luat_rtos_timer_create(&s_drain_timer) != 0) {
        LLOGE("create CC bridge downlink drain timer failed");
        goto done;
    }
    luat_rtos_timer_stop(s_drain_timer);
    if (luat_rtos_timer_start(s_drain_timer, 20, 1, _bridge_drain_timer_cb, NULL) == 0) {
        LLOGI("CC bridge downlink drain started");
    } else {
        LLOGE("start CC bridge downlink drain timer failed");
    }
done:
    luat_rtos_mutex_unlock(s_drain_lock);
}

void luat_cc_bridge_drain_stop(void)
{
    if (!s_drain_lock) return;
    luat_rtos_mutex_lock(s_drain_lock, LUAT_WAIT_FOREVER);
    s_drain_allowed = 0;
    if (s_drain_timer) luat_rtos_timer_stop(s_drain_timer);
    luat_rtos_mutex_unlock(s_drain_lock);
}

/* -------------------- 上行(SIP -> CC extern source) -------------------- */

static void _bridge_uplink_source_feed_locked(void)
{
    voip_ctx_t *voip_ctx = voip_get_ctx();
    int16_t *voip_pcm = s_uplink_voip_pcm;
    int16_t *cc_pcm = s_uplink_cc_pcm;
    uint16_t voip_sr;
    uint16_t cc_samples;
    int got;

    if (!s_uplink_source || !voip_ctx || !luat_cc_bridge_mode_on() ||
        voip_ctx->state != VOIP_STATE_RUNNING) {
        return;
    }
    voip_sr = voip_ctx->config.sample_rate ? voip_ctx->config.sample_rate : 8000;
    cc_samples = (s_uplink_source_cc_sr == 16000) ? 320 : 160;

    if (voip_sr == 8000 && s_uplink_source_cc_sr == 16000) {
        got = voip_bridge_pcm_out(voip_pcm, 160);
        if (got < 0) got = 0;
        if (got < 160) memset(voip_pcm + got, 0, (160 - got) * sizeof(int16_t));
        for (uint16_t i = 0; i < 160; i++) {
            int16_t next = (i + 1 < 160) ? voip_pcm[i + 1] : voip_pcm[i];
            cc_pcm[i * 2] = voip_pcm[i];
            cc_pcm[i * 2 + 1] = (int16_t)(((int32_t)voip_pcm[i] + (int32_t)next) / 2);
        }
    } else if (voip_sr == 16000 && s_uplink_source_cc_sr == 8000) {
        got = voip_bridge_pcm_out(voip_pcm, 320);
        if (got < 0) got = 0;
        if (got < 320) memset(voip_pcm + got, 0, (320 - got) * sizeof(int16_t));
        for (uint16_t i = 0; i < 160; i++) {
            cc_pcm[i] = (int16_t)(((int32_t)voip_pcm[i * 2] + (int32_t)voip_pcm[i * 2 + 1]) / 2);
        }
    } else {
        got = voip_bridge_pcm_out(cc_pcm, cc_samples);
        if (got < 0) got = 0;
        if (got < cc_samples) memset(cc_pcm + got, 0, (cc_samples - got) * sizeof(int16_t));
    }
    luat_audio_extern_source_feed(s_uplink_source, (const uint8_t *)cc_pcm, cc_samples * sizeof(int16_t));
}

static void _bridge_uplink_source_timer_cb(LUAT_RT_CB_PARAM)
{
    (void)param;
    if (!s_uplink_lock || luat_rtos_mutex_lock(s_uplink_lock, 0)) return;
    if (s_uplink_allowed) _bridge_uplink_source_feed_locked();
    luat_rtos_mutex_unlock(s_uplink_lock);
}

static int _bridge_uplink_source_start(luat_audio_extern_source_t *source, const luat_audio_common_param_t *cc_param, uint32_t request_id)
{
    int ret = -LUAT_ERROR_OPERATION_FAILED;
    uint16_t cc_sr;

    if (!source || !cc_param || !luat_cc_bridge_mode_on() || !s_uplink_lock || !s_uplink_lifecycle_lock) {
        return -LUAT_ERROR_PARAM_INVALID;
    }
    luat_rtos_mutex_lock(s_uplink_lifecycle_lock, LUAT_WAIT_FOREVER);
    luat_rtos_mutex_lock(s_uplink_lock, LUAT_WAIT_FOREVER);
    if (!s_uplink_allowed || !source->request || source->request->request_id != request_id) goto done;
    if (s_uplink_source) goto done;
    /* Create the timer before registering the source to keep failure cleanup
     * with the owning CC request. */
    if (!s_uplink_source_timer && luat_rtos_timer_create(&s_uplink_source_timer) != 0) goto done;
    cc_sr = cc_param->sample_rate == 16000 ? 16000 : 8000;
    luat_rtos_mutex_unlock(s_uplink_lock);

    ret = luat_audio_request_add_source_stream(source, &s_bridge_pcm_codec, cc_param, 1, source);
    if (ret) {
        LLOGE("CC bridge extern-record source start failed %d", ret);
        goto lifecycle_done;
    }

    luat_rtos_mutex_lock(s_uplink_lock, LUAT_WAIT_FOREVER);
    s_uplink_source = source;
    s_uplink_source_cc_sr = cc_sr;
    s_uplink_stop_requested = 0;
    if (luat_rtos_timer_start(s_uplink_source_timer, 20, 1, _bridge_uplink_source_timer_cb, NULL) != 0) {
        s_uplink_allowed = 0;
        s_uplink_stop_requested = 1;
        luat_rtos_mutex_unlock(s_uplink_lock);
        luat_audio_request_delete_source(source);
        ret = -LUAT_ERROR_OPERATION_FAILED;
        goto lifecycle_done;
    }
    LLOGI("CC bridge extern-record source started sr=%u", (unsigned)s_uplink_source_cc_sr);
done:
    luat_rtos_mutex_unlock(s_uplink_lock);
lifecycle_done:
    luat_rtos_mutex_unlock(s_uplink_lifecycle_lock);
    return ret;
}

static void _bridge_uplink_source_detached(luat_audio_extern_source_t *source)
{
    if (!source || !s_uplink_lock) return;
    luat_rtos_mutex_lock(s_uplink_lock, LUAT_WAIT_FOREVER);
    if (s_uplink_source == source) {
        s_uplink_allowed = 0;
        s_uplink_stop_requested = 1;
        if (s_uplink_source_timer) luat_rtos_timer_stop(s_uplink_source_timer);
    }
    luat_rtos_mutex_unlock(s_uplink_lock);
}

static int _bridge_uplink_source_stop(void)
{
    luat_audio_extern_source_t *source;
    volatile luat_audio_extern_source_t *source_state;
    uint8_t need_delete = 0;
    uint32_t wait_ms = 0;

    if (!s_uplink_lock || !s_uplink_lifecycle_lock) return LUAT_ERROR_NONE;
    luat_rtos_mutex_lock(s_uplink_lifecycle_lock, LUAT_WAIT_FOREVER);
    luat_rtos_mutex_lock(s_uplink_lock, LUAT_WAIT_FOREVER);
    s_uplink_allowed = 0;
    if (s_uplink_source_timer) luat_rtos_timer_stop(s_uplink_source_timer);
    source = s_uplink_source;
    if (source && !s_uplink_stop_requested) {
        s_uplink_stop_requested = 1;
        need_delete = 1;
    }
    luat_rtos_mutex_unlock(s_uplink_lock);

    if (!source) {
        luat_rtos_mutex_unlock(s_uplink_lifecycle_lock);
        return LUAT_ERROR_NONE;
    }
    source_state = source;
    if (need_delete) {
        /* This synchronously detaches the source from the audio request. The
         * luat_tts task still owns final destruction, so wait for both the
         * source done flag and codec unbind before the static source can be
         * reused by another call. */
        luat_audio_request_delete_source(source);
    }
    while ((!source_state->is_done || source_state->codec.opts) &&
        wait_ms < CC_BRIDGE_SOURCE_STOP_TIMEOUT_MS) {
        luat_rtos_task_sleep(1);
        wait_ms++;
    }
    if (!source_state->is_done || source_state->codec.opts) {
        LLOGE("CC bridge extern-record source stop timeout source=%p", source);
        luat_rtos_mutex_unlock(s_uplink_lifecycle_lock);
        return -LUAT_ERROR_OPERATION_FAILED;
    }

    luat_rtos_mutex_lock(s_uplink_lock, LUAT_WAIT_FOREVER);
    if (s_uplink_source == source) {
        s_uplink_source = NULL;
        s_uplink_source_cc_sr = 0;
        s_uplink_stop_requested = 0;
    }
    luat_rtos_mutex_unlock(s_uplink_lock);
    luat_rtos_mutex_unlock(s_uplink_lifecycle_lock);
    LLOGI("CC bridge extern-record source stopped wait=%u", (unsigned)wait_ms);
    return LUAT_ERROR_NONE;
}

int luat_cc_bridge_source_start(luat_audio_request_block_t *request,
    const luat_audio_common_param_t *cc_param, uint32_t request_id)
{
    uint32_t critical;
    int ret;

    critical = luat_rtos_entry_critical();
    if (s_source_state != CC_BRIDGE_SOURCE_IDLE) {
        luat_rtos_exit_critical(critical);
        return -LUAT_ERROR_OPERATION_FAILED;
    }
    s_source_state = CC_BRIDGE_SOURCE_STARTING;
    s_source_request_id = request_id;
    luat_rtos_exit_critical(critical);

    s_source.request = request;
    ret = _bridge_uplink_source_start(&s_source, cc_param, request_id);

    critical = luat_rtos_entry_critical();
    if (s_source_state == CC_BRIDGE_SOURCE_STARTING &&
        s_source_request_id == request_id) {
        if (ret == LUAT_ERROR_NONE) {
            s_source_state = CC_BRIDGE_SOURCE_ACTIVE;
        } else {
            s_source_state = CC_BRIDGE_SOURCE_STOPPING;
        }
    }
    luat_rtos_exit_critical(critical);
    if (ret != LUAT_ERROR_NONE) {
        /* A failure after registration (for example timer start failure) can
         * still leave destruction with luat_tts. Join it before exposing the
         * static source as reusable. */
        luat_cc_bridge_source_stop();
    }
    return ret;
}

int luat_cc_bridge_source_stop(void)
{
    uint32_t critical;
    uint32_t request_id;
    int ret;

    critical = luat_rtos_entry_critical();
    if (s_source_state == CC_BRIDGE_SOURCE_IDLE) {
        luat_rtos_exit_critical(critical);
        return LUAT_ERROR_NONE;
    }
    request_id = s_source_request_id;
    s_source_state = CC_BRIDGE_SOURCE_STOPPING;
    luat_rtos_exit_critical(critical);

    ret = _bridge_uplink_source_stop();
    if (ret != LUAT_ERROR_NONE) {
        LLOGE("CC bridge source stop failed request_id=%u", (unsigned)request_id);
        return ret;
    }

    critical = luat_rtos_entry_critical();
    if (s_source_state == CC_BRIDGE_SOURCE_STOPPING &&
        s_source_request_id == request_id) {
        s_source_state = CC_BRIDGE_SOURCE_IDLE;
        s_source_request_id = 0;
    }
    luat_rtos_exit_critical(critical);
    return LUAT_ERROR_NONE;
}

uint8_t luat_cc_bridge_source_decode_done(const uint8_t *data, uint32_t param)
{
    if (data != (const uint8_t *)&s_source || param != 1) return 0;
    uint32_t critical;
    _bridge_uplink_source_detached(&s_source);
    critical = luat_rtos_entry_critical();
    if (s_source_state == CC_BRIDGE_SOURCE_STARTING ||
        s_source_state == CC_BRIDGE_SOURCE_ACTIVE) {
        s_source_state = CC_BRIDGE_SOURCE_STOPPING;
    }
    luat_rtos_exit_critical(critical);
    /* The callback precedes final luat_tts destruction. Keep the
     * source in STOPPING until the bridge stop path observes codec
     * unbind; publishing EXT_SRC_DONE here would also corrupt the
     * state of the unrelated cc.extern_source API. */
    LLOGI("CC bridge extern-record source detached request_id=%u",
        (unsigned)s_source_request_id);
    return 1;
}

uint8_t luat_cc_bridge_source_is_idle(void)
{
    return s_source_state == CC_BRIDGE_SOURCE_IDLE;
}

uint8_t luat_cc_bridge_source_is_stopping(void)
{
    return s_source_state == CC_BRIDGE_SOURCE_STOPPING;
}

#endif /* LUAT_USE_AUDIO_V2 && LUAT_USE_CC_VOIP_BRIDGE */
