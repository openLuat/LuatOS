#include "luat_voip_core.h"
#include "luat_voip_aec_sync.h"
#include "luat_conf_bsp.h"
#include "luat_mem.h"
#include "luat_mcu.h"

#include <stdint.h>
#include <string.h>

#ifdef LUAT_USE_VOIP_AEC
#include "speex/speex_echo.h"
#include "speex/speex_preprocess.h"
#endif

#if defined(LUAT_USE_VOIP_AEC) && defined(LUAT_USE_VOIP_AEC_BK) && \
    defined(LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC)
#include "modules/aec.h"
#endif

#define LUAT_LOG_TAG "voip_aec"
#include "luat_log.h"

typedef struct {
    const char *name;
    int (*init)(voip_ctx_t *ctx);
    void (*process)(voip_ctx_t *ctx, const int16_t *mic, const int16_t *ref, int16_t *out);
    void (*reset)(voip_ctx_t *ctx);
    void (*cleanup)(voip_ctx_t *ctx);
} voip_aec_ops_t;

#ifdef LUAT_USE_VOIP_AEC
static int voip_aec_speex_init(voip_ctx_t *ctx)
{
    int sample_rate = ctx->config.sample_rate ? (int)ctx->config.sample_rate : VOIP_SAMPLE_RATE_DEFAULT;
    int tail_samples = sample_rate * (ctx->config.aec_tail_ms ? ctx->config.aec_tail_ms : 120) / 1000;
    int denoise = ctx->config.aec_denoise ? 1 : 0;
    int agc = ctx->config.aec_agc ? 1 : 0;
    float agc_level = 6000.0f;
    int noise_suppress = -20;
    int echo_suppress = -40;
    int echo_suppress_active = -15;

    if (tail_samples < (int)ctx->frame_samples * 2) {
        tail_samples = ctx->frame_samples * 2;
    }
    ctx->aec_state = speex_echo_state_init((int)ctx->frame_samples, tail_samples);
    if (!ctx->aec_state) {
        return -1;
    }
    speex_echo_ctl((SpeexEchoState *)ctx->aec_state, SPEEX_ECHO_SET_SAMPLING_RATE, &sample_rate);

    if (denoise || agc) {
        ctx->aec_preprocess = speex_preprocess_state_init((int)ctx->frame_samples, sample_rate);
        if (!ctx->aec_preprocess) {
            speex_echo_state_destroy((SpeexEchoState *)ctx->aec_state);
            ctx->aec_state = NULL;
            return -1;
        }
        speex_preprocess_ctl((SpeexPreprocessState *)ctx->aec_preprocess,
                SPEEX_PREPROCESS_SET_ECHO_STATE, ctx->aec_state);
        speex_preprocess_ctl((SpeexPreprocessState *)ctx->aec_preprocess,
                SPEEX_PREPROCESS_SET_DENOISE, &denoise);
        speex_preprocess_ctl((SpeexPreprocessState *)ctx->aec_preprocess,
                SPEEX_PREPROCESS_SET_AGC, &agc);
        if (agc) {
            speex_preprocess_ctl((SpeexPreprocessState *)ctx->aec_preprocess,
                    SPEEX_PREPROCESS_SET_AGC_LEVEL, &agc_level);
        }
        if (denoise) {
            speex_preprocess_ctl((SpeexPreprocessState *)ctx->aec_preprocess,
                    SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, &noise_suppress);
            speex_preprocess_ctl((SpeexPreprocessState *)ctx->aec_preprocess,
                    SPEEX_PREPROCESS_SET_ECHO_SUPPRESS, &echo_suppress);
            speex_preprocess_ctl((SpeexPreprocessState *)ctx->aec_preprocess,
                    SPEEX_PREPROCESS_SET_ECHO_SUPPRESS_ACTIVE, &echo_suppress_active);
        }
    }
    return 0;
}

static void voip_aec_speex_process(voip_ctx_t *ctx, const int16_t *mic,
        const int16_t *ref, int16_t *out)
{
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    speex_echo_cancellation((SpeexEchoState *)ctx->aec_state, mic, ref, out);
#else
    (void)ref;
    speex_echo_capture((SpeexEchoState *)ctx->aec_state, mic, out);
#endif
    if (ctx->aec_preprocess) {
        speex_preprocess_run((SpeexPreprocessState *)ctx->aec_preprocess, out);
    }
}

static void voip_aec_speex_reset(voip_ctx_t *ctx)
{
    if (ctx->aec_state) {
        speex_echo_state_reset((SpeexEchoState *)ctx->aec_state);
    }
}

static void voip_aec_speex_cleanup(voip_ctx_t *ctx)
{
    if (ctx->aec_preprocess) {
        speex_preprocess_state_destroy((SpeexPreprocessState *)ctx->aec_preprocess);
        ctx->aec_preprocess = NULL;
    }
    if (ctx->aec_state) {
        speex_echo_state_destroy((SpeexEchoState *)ctx->aec_state);
        ctx->aec_state = NULL;
    }
}

static const voip_aec_ops_t g_voip_aec_speex_ops = {
    .name = "speex",
    .init = voip_aec_speex_init,
    .process = voip_aec_speex_process,
    .reset = voip_aec_speex_reset,
    .cleanup = voip_aec_speex_cleanup,
};
#endif

#if defined(LUAT_USE_VOIP_AEC) && defined(LUAT_USE_VOIP_AEC_BK) && \
    defined(LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC)
#define VOIP_BK_AEC_MAX_DELAY_SAMPLES 1000
#define VOIP_BK_AEC_FLAG_EC 0x01
#define VOIP_BK_AEC_FLAG_NS 0x02
#define VOIP_BK_AEC_FLAG_BPF 0x04
#define VOIP_BK_AEC_FLAG_VOIP_DENOISE     (VOIP_BK_AEC_FLAG_EC | VOIP_BK_AEC_FLAG_NS | VOIP_BK_AEC_FLAG_BPF)

typedef struct {
    AECContext *instance;
    int16_t *ref_buf;
    int16_t *mic_buf;
    int16_t *out_buf;
    uint32_t frame_samples;
} voip_bk_aec_state_t;

static int voip_aec_bk_bind_buffers(voip_ctx_t *ctx, voip_bk_aec_state_t *state)
{
    uint32_t addr = 0;

    state->frame_samples = 0;
    aec_ctrl(state->instance, AEC_CTRL_CMD_GET_FRAME_SAMPLE,
            (uint32_t)(uintptr_t)&state->frame_samples);
    aec_ctrl(state->instance, AEC_CTRL_CMD_GET_RX_BUF, (uint32_t)(uintptr_t)&addr);
    state->ref_buf = (int16_t *)(uintptr_t)addr;
    addr = 0;
    aec_ctrl(state->instance, AEC_CTRL_CMD_GET_TX_BUF, (uint32_t)(uintptr_t)&addr);
    state->mic_buf = (int16_t *)(uintptr_t)addr;
    addr = 0;
    aec_ctrl(state->instance, AEC_CTRL_CMD_GET_OUT_BUF, (uint32_t)(uintptr_t)&addr);
    state->out_buf = (int16_t *)(uintptr_t)addr;

    if (state->frame_samples != ctx->frame_samples || !state->ref_buf ||
        !state->mic_buf || !state->out_buf) {
        LLOGE("BK AEC invalid internal buffers frame=%u expected=%u ref=%p mic=%p out=%p",
                state->frame_samples, ctx->frame_samples, state->ref_buf,
                state->mic_buf, state->out_buf);
        return -1;
    }
    return 0;
}

static int voip_aec_bk_configure(voip_ctx_t *ctx)
{
    voip_bk_aec_state_t *state = (voip_bk_aec_state_t *)ctx->aec_state;
    uint32_t flags = ctx->config.aec_denoise ?
            VOIP_BK_AEC_FLAG_VOIP_DENOISE : VOIP_BK_AEC_FLAG_EC;

    if (!state || !state->instance) {
        return -1;
    }
    aec_init(state->instance, (int16_t)ctx->config.sample_rate);
    if (voip_aec_bk_bind_buffers(ctx, state) != 0) {
        return -1;
    }
    aec_ctrl(state->instance, AEC_CTRL_CMD_SET_FLAGS, flags);
    aec_ctrl(state->instance, AEC_CTRL_CMD_SET_MIC_DELAY, 0);
    /* Conservative vendor profile: preserve sustained near-end speech. */
    aec_ctrl(state->instance, AEC_CTRL_CMD_SET_EC_DEPTH, 5);
    aec_ctrl(state->instance, AEC_CTRL_CMD_SET_TxRxThr, 13);
    aec_ctrl(state->instance, AEC_CTRL_CMD_SET_TxRxFlr, 1);
    aec_ctrl(state->instance, AEC_CTRL_CMD_SET_REF_SCALE, 0);
    if (ctx->config.aec_denoise) {
        aec_ctrl(state->instance, AEC_CTRL_CMD_SET_NS_LEVEL, 2);
        aec_ctrl(state->instance, AEC_CTRL_CMD_SET_NS_PARA, 1);
    }
    LLOGI("BK AEC profile flags=0x%02x depth=5 thr=13 flr=1 frame=%u internal ref=%p mic=%p out=%p",
            (unsigned)flags, state->frame_samples, state->ref_buf,
            state->mic_buf, state->out_buf);
    return 0;
}

static int voip_aec_bk_init(voip_ctx_t *ctx)
{
    voip_bk_aec_state_t *state;
    uint32_t bytes;

    if ((ctx->config.sample_rate != 8000 && ctx->config.sample_rate != 16000) ||
        ctx->frame_samples != ctx->config.sample_rate / 50) {
        LLOGE("BK AEC requires 8/16kHz and 20ms frames");
        return -1;
    }
    bytes = aec_size(VOIP_BK_AEC_MAX_DELAY_SAMPLES);
    state = (voip_bk_aec_state_t *)luat_heap_calloc(1, sizeof(*state));
    if (!state) {
        return -1;
    }
    state->instance = (AECContext *)luat_heap_calloc(1, bytes);
    if (!state->instance) {
        luat_heap_free(state);
        return -1;
    }
    ctx->aec_state = state;
    if (voip_aec_bk_configure(ctx) != 0) {
        luat_heap_free(state->instance);
        luat_heap_free(state);
        ctx->aec_state = NULL;
        return -1;
    }
    return 0;
}

static void voip_aec_bk_process(voip_ctx_t *ctx, const int16_t *mic,
        const int16_t *ref, int16_t *out)
{
    voip_bk_aec_state_t *state = (voip_bk_aec_state_t *)ctx->aec_state;

    if (!state || !state->instance || !state->ref_buf || !state->mic_buf ||
        !state->out_buf) {
        memcpy(out, mic, ctx->frame_bytes);
        return;
    }
    memcpy(state->ref_buf, ref, ctx->frame_bytes);
    memcpy(state->mic_buf, mic, ctx->frame_bytes);
    aec_proc(state->instance, state->ref_buf, state->mic_buf, state->out_buf);
    memcpy(out, state->out_buf, ctx->frame_bytes);
}

static void voip_aec_bk_reset(voip_ctx_t *ctx)
{
    if (ctx->aec_state && voip_aec_bk_configure(ctx) != 0) {
        LLOGE("BK AEC reset failed");
    }
}

static void voip_aec_bk_cleanup(voip_ctx_t *ctx)
{
    voip_bk_aec_state_t *state = (voip_bk_aec_state_t *)ctx->aec_state;

    if (state) {
        if (state->instance) {
            luat_heap_free(state->instance);
            state->instance = NULL;
        }
        luat_heap_free(state);
        ctx->aec_state = NULL;
    }
}

static const voip_aec_ops_t g_voip_aec_bk_ops = {
    .name = "bk",
    .init = voip_aec_bk_init,
    .process = voip_aec_bk_process,
    .reset = voip_aec_bk_reset,
    .cleanup = voip_aec_bk_cleanup,
};
#endif
#ifdef LUAT_VOIP_AEC_PCM_DUMP
LUAT_WEAK void luat_voip_aec_pcm_dump(const int16_t *mic, const int16_t *ref,
        const int16_t *out, uint16_t samples, uint64_t capture_tick_ms)
{
    (void)mic;
    (void)ref;
    (void)out;
    (void)samples;
    (void)capture_tick_ms;
}
#endif

#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
static void voip_aec_backend_reset(voip_ctx_t *ctx)
{
    const voip_aec_ops_t *ops = (const voip_aec_ops_t *)ctx->aec_ops;
    if (ops && ops->reset) {
        ops->reset(ctx);
    }
}
#endif

int voip_aec_init(voip_ctx_t *ctx)
{
    const voip_aec_ops_t *ops = NULL;
    if (!ctx || !ctx->config.aec_enable) {
        return 0;
    }
#ifndef LUAT_USE_VOIP_AEC
    LLOGE("AEC requested but SpeexDSP is not enabled");
    return -1;
#else
    if (!ctx->aec_out_buf) {
        LLOGE("AEC buffers are not allocated");
        return -1;
    }
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    if (!ctx->aec_ref_buf || !ctx->aec_ref_history) {
        LLOGE("synchronized AEC reference buffers are not allocated");
        return -1;
    }
    if ((uint32_t)ctx->config.aec_delay_samples + ctx->frame_samples >
        (uint32_t)VOIP_AEC_REF_HISTORY_FRAMES * ctx->frame_samples) {
        LLOGE("AEC delay %u exceeds reference history", ctx->config.aec_delay_samples);
        return -1;
    }
#endif

    switch ((voip_aec_mode_t)ctx->config.aec_mode) {
    case VOIP_AEC_MODE_SPEEX:
        ops = &g_voip_aec_speex_ops;
        break;
    case VOIP_AEC_MODE_BK:
#if defined(LUAT_USE_VOIP_AEC_BK) && defined(LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC)
        ops = &g_voip_aec_bk_ops;
#else
        LLOGE("BK AEC requested but this target does not provide it");
        return -1;
#endif
        break;
    default:
        LLOGE("unsupported AEC mode %u", ctx->config.aec_mode);
        return -1;
    }

#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    memset((void *)ctx->aec_ref_seq, 0, sizeof(ctx->aec_ref_seq));
    memset(ctx->aec_ref_tick_ms, 0, sizeof(ctx->aec_ref_tick_ms));
#endif
    ctx->aec_ops = ops;
    if (ops->init(ctx) != 0) {
        ctx->aec_ops = NULL;
        LLOGE("%s AEC init failed", ops->name);
        return -1;
    }
    ctx->aec_ready = 1;
    ctx->stats.aec_mode = ctx->config.aec_mode;
    LLOGI("AEC ready mode=%s frame=%u delay=%u denoise=%u agc=%u",
            ops->name, ctx->frame_samples, ctx->config.aec_delay_samples,
            ctx->config.aec_denoise, ctx->config.aec_agc);
    return 0;
#endif
}

void voip_aec_cleanup(voip_ctx_t *ctx)
{
    const voip_aec_ops_t *ops;
    if (!ctx) {
        return;
    }
    ctx->aec_ready = 0;
    ops = (const voip_aec_ops_t *)ctx->aec_ops;
    if (ops && ops->cleanup) {
        ops->cleanup(ctx);
    }
    ctx->aec_ops = NULL;
    ctx->aec_state = NULL;
    ctx->aec_preprocess = NULL;
}

void voip_aec_render_push(voip_ctx_t *ctx, const int16_t *render_pcm,
        uint32_t render_seq, uint64_t tick_ms)
{
#ifndef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
#ifdef LUAT_USE_VOIP_AEC
    if (ctx && ctx->aec_ready && render_pcm && ctx->aec_state &&
        ctx->aec_ops == &g_voip_aec_speex_ops) {
        speex_echo_playback((SpeexEchoState *)ctx->aec_state, render_pcm);
    }
#else
    (void)ctx;
    (void)render_pcm;
#endif
    (void)render_seq;
    (void)tick_ms;
#else
    uint32_t slot;
    int16_t *dst;
    if (!ctx || !ctx->aec_ready || !render_pcm || !render_seq ||
        !ctx->aec_ref_history || !ctx->frame_bytes) {
        return;
    }

    slot = (render_seq - 1) % VOIP_AEC_REF_HISTORY_FRAMES;
    dst = ctx->aec_ref_history + slot * ctx->frame_samples;
    ctx->aec_ref_seq[slot] = 0;
    __sync_synchronize();
    memcpy(dst, render_pcm, ctx->frame_bytes);
    ctx->aec_ref_tick_ms[slot] = tick_ms;
    __sync_synchronize();
    ctx->aec_ref_seq[slot] = render_seq;
#endif
}

#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
static int voip_aec_build_reference(voip_ctx_t *ctx, uint32_t render_seq,
        uint64_t capture_tick_ms)
{
    uint64_t source_sample;
    uint64_t render_tick_ms;
    uint32_t copied = 0;
    uint32_t frame_samples = ctx->frame_samples;
    uint32_t latest_slot;
    uint32_t latest_committed_seq;
    int sync_status;

    if (!render_seq || !frame_samples) {
        ctx->stats.aec_ref_underflow++;
        return -1;
    }
    latest_slot = (render_seq - 1) % VOIP_AEC_REF_HISTORY_FRAMES;
    latest_committed_seq = ctx->aec_ref_seq[latest_slot];
    sync_status = voip_aec_sync_history_status(latest_committed_seq,
            render_seq, render_seq, VOIP_AEC_REF_HISTORY_FRAMES);
    if (sync_status != VOIP_AEC_SYNC_OK) {
        ctx->stats.aec_ref_underflow++;
        return -1;
    }
    __sync_synchronize();
    render_tick_ms = ctx->aec_ref_tick_ms[latest_slot];
    __sync_synchronize();
    if (ctx->aec_ref_seq[latest_slot] != render_seq) {
        ctx->stats.aec_ref_overflow++;
        return -1;
    }
    sync_status = voip_aec_sync_reference_start(render_seq, frame_samples,
            ctx->config.sample_rate, ctx->config.aec_delay_samples,
            render_tick_ms, capture_tick_ms, &source_sample);
    if (sync_status != VOIP_AEC_SYNC_OK) {
        if (sync_status == VOIP_AEC_SYNC_WARMUP) {
            return 1;
        }
        if (sync_status == VOIP_AEC_SYNC_OVERFLOW) {
            ctx->stats.aec_ref_overflow++;
        } else {
            ctx->stats.aec_ref_underflow++;
        }
        return -1;
    }

    while (copied < frame_samples) {
        uint32_t source_seq = (uint32_t)(source_sample / frame_samples) + 1;
        uint32_t source_offset = (uint32_t)(source_sample % frame_samples);
        uint32_t count = frame_samples - source_offset;
        uint32_t slot = (source_seq - 1) % VOIP_AEC_REF_HISTORY_FRAMES;
        uint32_t committed_seq = ctx->aec_ref_seq[slot];

        if (count > frame_samples - copied) {
            count = frame_samples - copied;
        }
        sync_status = voip_aec_sync_history_status(committed_seq, source_seq,
                render_seq, VOIP_AEC_REF_HISTORY_FRAMES);
        if (sync_status != VOIP_AEC_SYNC_OK) {
            if (sync_status == VOIP_AEC_SYNC_OVERFLOW) {
                ctx->stats.aec_ref_overflow++;
            } else {
                ctx->stats.aec_ref_underflow++;
            }
            return -1;
        }
        memcpy(ctx->aec_ref_buf + copied,
                ctx->aec_ref_history + slot * frame_samples + source_offset,
                count * sizeof(int16_t));
        __sync_synchronize();
        if (ctx->aec_ref_seq[slot] != source_seq) {
            ctx->stats.aec_ref_overflow++;
            return -1;
        }
        copied += count;
        source_sample += count;
    }
    return 0;
}
#endif

const int16_t *voip_aec_process_frame(voip_ctx_t *ctx, const int16_t *mic_pcm,
        uint32_t render_seq, uint32_t capture_seq, uint64_t capture_tick_ms)
{
    const voip_aec_ops_t *ops;
    uint64_t start_tick;
    uint64_t elapsed_tick;
    uint32_t us_period;
    uint32_t elapsed_us;
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    uint8_t sync_bad = 0;
#endif

    if (!ctx || !mic_pcm) {
        return mic_pcm;
    }
    if (!ctx->aec_ready || !ctx->aec_ops) {
        return mic_pcm;
    }

    for (uint32_t i = 0; i < ctx->frame_samples; i++) {
        if (mic_pcm[i] >= 32760 || mic_pcm[i] <= -32760) {
            ctx->stats.aec_mic_clipped++;
        }
    }

#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    ctx->stats.aec_seq_skew = (int32_t)capture_seq - (int32_t)render_seq;
    if (ctx->aec_sync_fault) {
        ctx->aec_sync_fault = 0;
        sync_bad = 1;
    }
    if ((ctx->aec_last_capture_seq && capture_seq != ctx->aec_last_capture_seq + 1) ||
        (ctx->aec_last_render_seq && render_seq < ctx->aec_last_render_seq) ||
        (ctx->aec_last_render_seq && render_seq - ctx->aec_last_render_seq > 2)) {
        sync_bad = 1;
    }
    ctx->aec_last_capture_seq = capture_seq;
    ctx->aec_last_render_seq = render_seq;
    if (sync_bad) {
        ctx->stats.aec_sync_resets++;
        voip_aec_backend_reset(ctx);
        return mic_pcm;
    }

    sync_bad = (uint8_t)voip_aec_build_reference(ctx, render_seq, capture_tick_ms);
    if (sync_bad) {
        if (sync_bad != 1) {
            ctx->stats.aec_sync_resets++;
            voip_aec_backend_reset(ctx);
        }
        return mic_pcm;
    }
#else
    (void)render_seq;
    (void)capture_seq;
#endif

    ops = (const voip_aec_ops_t *)ctx->aec_ops;
    start_tick = luat_mcu_tick64();
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    ops->process(ctx, mic_pcm, ctx->aec_ref_buf, ctx->aec_out_buf);
#else
    ops->process(ctx, mic_pcm, NULL, ctx->aec_out_buf);
#endif
    for (uint32_t i = 0; i < ctx->frame_samples; i++) {
        if (ctx->aec_out_buf[i] >= 32760 || ctx->aec_out_buf[i] <= -32760) {
            ctx->stats.aec_out_clipped++;
        }
    }
    elapsed_tick = luat_mcu_tick64() - start_tick;
    us_period = (uint32_t)luat_mcu_us_period();
    elapsed_us = us_period ? (uint32_t)(elapsed_tick / us_period) : (uint32_t)elapsed_tick;
    if (elapsed_us > ctx->stats.aec_max_process_us) {
        ctx->stats.aec_max_process_us = elapsed_us;
    }

#ifdef LUAT_VOIP_AEC_PCM_DUMP
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    luat_voip_aec_pcm_dump(mic_pcm, ctx->aec_ref_buf, ctx->aec_out_buf,
            ctx->frame_samples, capture_tick_ms);
#else
    luat_voip_aec_pcm_dump(mic_pcm, NULL, ctx->aec_out_buf,
            ctx->frame_samples, capture_tick_ms);
#endif
#else
    (void)capture_tick_ms;
#endif
    return ctx->aec_out_buf;
}

const char *voip_aec_mode_name(const voip_ctx_t *ctx)
{
    const voip_aec_ops_t *ops;
    if (!ctx || !ctx->aec_ready) {
        return "off";
    }
    ops = (const voip_aec_ops_t *)ctx->aec_ops;
    return ops ? ops->name : "off";
}
