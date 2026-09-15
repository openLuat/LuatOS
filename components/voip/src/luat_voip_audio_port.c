#include "luat_conf_bsp.h"

#ifdef LUAT_USE_VOIP_AUDIO_PORT
#include "luat_voip_core.h"
#include "luat_voip_audio_port.h"
#include "luat_voip_pcm.h"
#include "luat_mem.h"
#include <string.h>

LUAT_WEAK int luat_voip_audio_port_start(struct luat_audio_driver_ctrl *ctrl,
        uint32_t samples, uint16_t frame_ms, uint8_t slots)
{ (void)ctrl; (void)samples; (void)frame_ms; (void)slots; return 0; }
LUAT_WEAK void luat_voip_audio_port_stop(struct luat_audio_driver_ctrl *ctrl)
{ (void)ctrl; }
LUAT_WEAK int luat_voip_audio_port_commit(struct luat_audio_driver_ctrl *ctrl,
        uint8_t slot, const int16_t *pcm, uint32_t samples)
{ (void)ctrl; (void)slot; (void)pcm; (void)samples; return 0; }
LUAT_WEAK void *luat_voip_audio_resampler_create(uint32_t input_rate, uint32_t output_rate)
{ (void)input_rate; (void)output_rate; return NULL; }
LUAT_WEAK int luat_voip_audio_resampler_process(void *state, const int16_t *input,
        uint32_t *input_samples, int16_t *output, uint32_t *output_samples)
{ (void)state; (void)input; (void)input_samples; (void)output; (void)output_samples; return -1; }
LUAT_WEAK uint32_t luat_voip_audio_resampler_latency(void *state)
{ (void)state; return 0; }
LUAT_WEAK void luat_voip_audio_resampler_destroy(void *state)
{ (void)state; }

#ifdef LUAT_VOIP_AEC_PCM_DUMP
LUAT_WEAK void luat_voip_audio_trace_open(uint32_t input_rate, uint8_t input_channels)
{ (void)input_rate; (void)input_channels; }
LUAT_WEAK void luat_voip_audio_trace_pcm(uint8_t kind, const void *pcm, uint32_t bytes,
        uint32_t rate, uint8_t channels, uint64_t end_tick_ms, uint32_t sequence)
{ (void)kind; (void)pcm; (void)bytes; (void)rate; (void)channels; (void)end_tick_ms; (void)sequence; }
LUAT_WEAK void luat_voip_audio_trace_close(void) {}
#endif

#ifdef LUAT_USE_AUDIO_V2
#include "luat_audio_driver.h"

typedef struct {
    volatile uint32_t state; /* 0 free, 1 producer, 2 queued, 3 task */
    uint32_t sequence;
    uint32_t bytes;
    uint32_t render_sequence;
    uint64_t end_tick_ms;
    uint8_t pcm[VOIP_PCM_MAX_RAW_BYTES];
} voip_raw_slot_t;

typedef struct {
    voip_pcm_normalizer_t normalizer;
    voip_raw_slot_t raw[VOIP_MIC_SLOT_COUNT];
    uint32_t input_sequence;
    uint32_t processed_sequence;
    uint32_t normalized_sequence;
    uint32_t render_sequence;
    uint32_t input_rate; /* Immutable while ISR callbacks are enabled. */
    uint8_t channels;
    uint8_t write_slot;
} voip_audio_port_state_t;

static void voip_audio_input_drop(voip_ctx_t *ctx)
{
    __sync_add_and_fetch(&ctx->dropped_mic_events, 1);
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    ctx->aec_sync_fault = 1;
#endif
}

int voip_audio_port_prepare(voip_ctx_t *ctx)
{
    luat_audio_driver_ctrl_t *ctrl = ctx->audio_v2_ctrl;
    voip_audio_port_state_t *state;
    if (ctx->config.sample_rate != 8000 || ctx->frame_samples != VOIP_PCM_FRAME_SAMPLES ||
            ctrl->rx_param.data_align != 2 || !ctrl->rx_param.is_signed) return -1;
    state = luat_heap_calloc(1, sizeof(*state));
    if (!state) return -1;
    if (voip_pcm_normalizer_init(&state->normalizer, ctrl->rx_param.sample_rate,
            ctrl->rx_param.channel_nums) != 0) {
        luat_heap_free(state);
        return -1;
    }
    state->input_rate = ctrl->rx_param.sample_rate;
    state->channels = ctrl->rx_param.channel_nums;
    ctx->audio_port_state = state;
#ifdef LUAT_VOIP_AEC_PCM_DUMP
    luat_voip_audio_trace_open(state->input_rate, state->channels);
#endif
    return 0;
}

void voip_audio_port_cleanup(voip_ctx_t *ctx)
{
    voip_audio_port_state_t *state = ctx->audio_port_state;
    ctx->audio_port_state = NULL;
    if (!state) return;
#ifdef LUAT_VOIP_AEC_PCM_DUMP
    luat_voip_audio_trace_close();
#endif
    voip_pcm_normalizer_deinit(&state->normalizer);
    luat_heap_free(state);
}

int luat_voip_audio_capture(struct luat_audio_driver_ctrl *ctrl, const void *pcm,
        uint32_t bytes, uint32_t sample_rate, uint8_t bytes_per_sample,
        uint8_t channels, uint64_t end_tick_ms)
{
    voip_ctx_t *ctx = voip_get_ctx();
    voip_audio_port_state_t *state = ctx->audio_port_state;
    voip_raw_slot_t *slot;
    uint32_t sequence;
    if (ctx->audio_v2_ctrl != ctrl || !state) return 0;
    if (ctx->stop_requested || (ctx->state != VOIP_STATE_STARTING &&
            ctx->state != VOIP_STATE_RUNNING)) return 1;
    sequence = ++state->input_sequence;
    if (!pcm || bytes_per_sample != 2 || sample_rate != state->input_rate ||
            channels != state->channels || !bytes ||
            bytes % (2U * channels) || bytes > sample_rate / 50U * 2U * channels) {
        voip_audio_input_drop(ctx);
        return 1;
    }
    ctx->stats.audio_rx_samples += bytes / (2U * channels);
#ifdef LUAT_VOIP_AEC_PCM_DUMP
    luat_voip_audio_trace_pcm(LUAT_VOIP_TRACE_RAW_MIC, pcm, bytes,
            sample_rate, channels, end_tick_ms, sequence);
#endif
    slot = &state->raw[state->write_slot];
    if (!__sync_bool_compare_and_swap(&slot->state, 0, 1)) {
        voip_audio_input_drop(ctx);
        return 1;
    }
    memcpy(slot->pcm, pcm, bytes);
    slot->bytes = bytes;
    slot->sequence = sequence;
    slot->end_tick_ms = end_tick_ms;
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    slot->render_sequence = ctx->render_done_seq;
#else
    slot->render_sequence = 0;
#endif
    __sync_synchronize();
    slot->state = 2;
    if (luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_RAW_MIC_DATA,
            state->write_slot, sequence, ctx->audio_session, 0) != 0) {
        (void)__sync_bool_compare_and_swap(&slot->state, 2, 0);
        voip_audio_input_drop(ctx);
    }
    state->write_slot = (state->write_slot + 1U) % VOIP_MIC_SLOT_COUNT;
    return 1;
}

static void voip_audio_normalized_frame(void *user, const int16_t *pcm,
        uint32_t render_seq, uint64_t end_tick_ms)
{
    voip_ctx_t *ctx = user;
    voip_audio_port_state_t *state = ctx->audio_port_state;
    uint32_t capture_seq;
    if (ctx->stop_requested || ctx->state != VOIP_STATE_RUNNING) return;
    capture_seq = ++state->normalized_sequence;
    ctx->stats.audio_normalized_samples += ctx->frame_samples;
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    ctx->capture_seq = capture_seq;
#endif
#ifdef LUAT_VOIP_AEC_PCM_DUMP
    luat_voip_audio_trace_pcm(LUAT_VOIP_TRACE_MIC, pcm, ctx->frame_bytes,
            8000, 1, end_tick_ms, capture_seq);
#endif
    voip_audio_process_pcm(ctx, pcm, render_seq, capture_seq, end_tick_ms);
}

int voip_audio_port_process_raw(voip_ctx_t *ctx, uint32_t index,
        uint32_t sequence, uint32_t session)
{
    voip_audio_port_state_t *state = ctx->audio_port_state;
    voip_raw_slot_t *slot;
    int ret;
    if (!state || index >= VOIP_MIC_SLOT_COUNT || session != ctx->audio_session) return 0;
    slot = &state->raw[index];
    if (slot->sequence != sequence || !__sync_bool_compare_and_swap(&slot->state, 2, 3)) return 0;
    if (state->processed_sequence && sequence != state->processed_sequence + 1U) {
        uint32_t rate = state->input_rate;
        uint8_t channels = state->channels;
        voip_pcm_normalizer_deinit(&state->normalizer);
        if (voip_pcm_normalizer_init(&state->normalizer, rate, channels) != 0) {
            __sync_lock_release(&slot->state);
            return -1;
        }
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
        ctx->aec_sync_fault = 1;
#endif
    }
    state->processed_sequence = sequence;
    ret = voip_pcm_normalizer_push(&state->normalizer, slot->pcm, slot->bytes,
            slot->render_sequence, slot->end_tick_ms, voip_audio_normalized_frame, ctx);
    __sync_lock_release(&slot->state);
    return ret < 0 ? -1 : 0;
}

int luat_voip_audio_rendered(struct luat_audio_driver_ctrl *ctrl, uint8_t slot,
        const int16_t *pcm, uint32_t samples, uint64_t end_tick_ms)
{
    voip_ctx_t *ctx = voip_get_ctx();
    voip_audio_port_state_t *state = ctx->audio_port_state;
    uint32_t sequence;
    if (ctx->audio_v2_ctrl != ctrl || !state) return 0;
    if (ctx->stop_requested || (ctx->state != VOIP_STATE_STARTING &&
            ctx->state != VOIP_STATE_RUNNING)) return 1;
    if (!pcm || samples != ctx->frame_samples || slot >= ctx->play_slot_count) {
        voip_audio_input_drop(ctx);
        return 1;
    }
    sequence = ++state->render_sequence;
    ctx->stats.audio_render_samples += samples;
#ifdef LUAT_VOIP_AEC_PCM_DUMP
    luat_voip_audio_trace_pcm(LUAT_VOIP_TRACE_RENDER, pcm, samples * sizeof(int16_t),
            ctx->config.sample_rate, 1, end_tick_ms, sequence);
#endif
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
    voip_aec_render_push(ctx, pcm, sequence, end_tick_ms);
    __sync_synchronize();
    ctx->render_done_seq = sequence;
#else
    voip_aec_render_push(ctx, pcm, sequence, end_tick_ms);
#endif
    if (luat_rtos_event_send(ctx->task_handle, VOIP_EVENT_SPK_DONE, slot, sequence, ctx->audio_session, 0) != 0) {
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
        ctx->aec_sync_fault = 1;
#endif
    }
    return 1;
}

int luat_voip_audio_underrun(struct luat_audio_driver_ctrl *ctrl)
{
    voip_ctx_t *ctx = voip_get_ctx();
    if (ctx->audio_v2_ctrl != ctrl || !ctx->audio_port_state) return 0;
    if (!ctx->stop_requested && ctx->state == VOIP_STATE_RUNNING) {
        ctx->stats.audio_tx_underrun++;
    }
    return 1;
}

int voip_audio_port_commit(voip_ctx_t *ctx, uint8_t slot)
{
    int ret;
    if (!ctx->audio_port_state || !ctx->audio_v2_ctrl) return 0;
    ret = luat_voip_audio_port_commit(ctx->audio_v2_ctrl, slot,
            ctx->duplex_play_buf + slot * ctx->frame_samples, ctx->frame_samples);
    if (ret < 0) {
        ctx->stats.audio_tx_commit_fail++;
#ifdef LUAT_USE_VOIP_AEC_SYNC_AUDIO_V2_DAC
        ctx->aec_sync_fault = 1;
#endif
    }
    return ret;
}
#endif
#endif /* LUAT_USE_VOIP_AUDIO_PORT */
