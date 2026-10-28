#include "luat_cc_uart_media.h"

#include <string.h>
#if defined(_MSC_VER)
#include <intrin.h>
#endif

#define PHASE_ONE 1000000U
#define TARGET_SAMPLES (LUAT_CC_UART_MEDIA_FRAME * LUAT_CC_UART_MEDIA_PREBUFFER_FRAMES)

static void count_add(uint32_t *counter, uint32_t amount)
{
#if defined(_MSC_VER)
    (void)_InterlockedExchangeAdd((volatile long *)counter, (long)amount);
#elif defined(__GNUC__)
    (void)__sync_fetch_and_add(counter, amount);
#else
#error "UART CC counters require compiler atomics"
#endif
}

static void count_set(uint32_t *counter, uint32_t value)
{
#if defined(_MSC_VER)
    (void)_InterlockedExchange((volatile long *)counter, (long)value);
#elif defined(__GNUC__)
    (void)__sync_lock_test_and_set(counter, value);
#endif
}

static int check(luat_cc_uart_media_t *core, uint64_t session, uint32_t epoch)
{
    if (!core || !session || !epoch) return LUAT_CC_UART_MEDIA_BAD_ARG;
    if (core->session != session || core->epoch != epoch) {
        count_add(&core->counters.rejected_session, 1);
        return LUAT_CC_UART_MEDIA_STALE;
    }
    return core->running ? 0 : LUAT_CC_UART_MEDIA_STOPPED;
}

static void reset_queue(luat_cc_uart_media_t *core)
{
    count_add(&core->counters.flushed_samples, core->count);
    core->read = 0;
    core->count = 0;
    core->phase = 0;
    core->ready = 0;
    core->have_sequence = 0;
    core->occupancy_sum = 0;
    core->observation_ticks = 0;
    core->integral_scaled = 0;
    core->clock_ppm = 0;
}

void luat_cc_uart_media_init(luat_cc_uart_media_t *core)
{
    if (!core) return;
    memset(core, 0, sizeof(*core));
    core->clock.proportional_ppm = 1000;
    core->clock.integral_ppm = 10;
    core->clock.limit_ppm = 1000;
    core->clock.slew_ppm = 50;
}

int luat_cc_uart_media_configure(luat_cc_uart_media_t *core,
                                 const luat_cc_uart_media_clock_config_t *config)
{
    if (!core || !config || core->running || config->proportional_ppm < 0 ||
        config->proportional_ppm > 10000 || config->integral_ppm < 0 ||
        config->integral_ppm > 10000 || config->limit_ppm < 0 ||
        config->limit_ppm > 5000 || config->slew_ppm < 1 || config->slew_ppm > 5000)
        return LUAT_CC_UART_MEDIA_BAD_ARG;
    core->clock = *config;
    return 0;
}

int luat_cc_uart_media_start(luat_cc_uart_media_t *core, uint64_t session,
                             uint32_t epoch)
{
    if (!core || !session || !epoch) return LUAT_CC_UART_MEDIA_BAD_ARG;
    if (core->running && core->session == session && core->epoch == epoch) return 0;
    reset_queue(core);
    memset(&core->counters, 0, sizeof(core->counters));
    core->session = session;
    core->epoch = epoch;
    core->running = 1;
    return 0;
}

int luat_cc_uart_media_stop(luat_cc_uart_media_t *core, uint64_t session)
{
    if (!core || !session) return LUAT_CC_UART_MEDIA_BAD_ARG;
    if (core->session != session) return LUAT_CC_UART_MEDIA_STALE;
    core->running = 0;
    reset_queue(core);
    return 0;
}

int luat_cc_uart_media_flush(luat_cc_uart_media_t *core, uint64_t session,
                             uint32_t epoch)
{
    int ret = check(core, session, epoch);
    if (ret) return ret;
    reset_queue(core);
    return 0;
}

static void append_frame(luat_cc_uart_media_t *core, const int16_t *pcm)
{
    uint16_t i;
    uint16_t discard;
    if (core->count > LUAT_CC_UART_MEDIA_CAPACITY - LUAT_CC_UART_MEDIA_FRAME) {
        /* Keep the newest two existing frames plus this new frame. */
        discard = (uint16_t)(core->count -
                 (TARGET_SAMPLES - LUAT_CC_UART_MEDIA_FRAME));
        core->read = (uint16_t)((core->read + discard) % LUAT_CC_UART_MEDIA_CAPACITY);
        core->count = (uint16_t)(core->count - discard);
        core->phase = 0;
        count_add(&core->counters.dropped_samples, discard);
    }
    for (i = 0; i < LUAT_CC_UART_MEDIA_FRAME; ++i) {
        core->samples[(core->read + core->count + i) % LUAT_CC_UART_MEDIA_CAPACITY] =
            pcm ? pcm[i] : 0;
    }
    core->count = (uint16_t)(core->count + LUAT_CC_UART_MEDIA_FRAME);
    if (core->count > core->counters.high_water_samples)
        count_set(&core->counters.high_water_samples, core->count);
    if (core->count >= TARGET_SAMPLES) core->ready = 1;
}

int luat_cc_uart_media_push(luat_cc_uart_media_t *core, uint64_t session,
                            uint32_t epoch, uint32_t sequence,
                            const int16_t *pcm)
{
    uint32_t distance, missing, pad;
    int ret = check(core, session, epoch);
    if (ret) return ret;
    if (!pcm) {
        count_add(&core->counters.rejected_format, 1);
        return LUAT_CC_UART_MEDIA_BAD_ARG;
    }
    if (core->have_sequence) {
        distance = sequence - core->last_sequence;
        if (!distance) {
            count_add(&core->counters.duplicate_frames, 1);
            return 0;
        }
        if (distance >= 0x80000000U) {
            count_add(&core->counters.late_frames, 1);
            return 0;
        }
        missing = distance - 1U;
        if (missing) {
            count_add(&core->counters.lost_frames, missing);
            /* A large gap cannot monopolize the realtime worker. Fresh audio
             * follows only a bounded silence window, with normal overflow. */
            pad = missing < LUAT_CC_UART_MEDIA_QUEUE_FRAMES ? missing :
                  LUAT_CC_UART_MEDIA_QUEUE_FRAMES;
            while (pad--) append_frame(core, NULL);
        }
    }
    append_frame(core, pcm);
    core->last_sequence = sequence;
    core->have_sequence = 1;
    count_add(&core->counters.pushed, 1);
    return 1;
}

static int32_t clamp32(int32_t value, int32_t limit)
{
    if (value > limit) return limit;
    if (value < -limit) return -limit;
    return value;
}

static void observe_clock(luat_cc_uart_media_t *core)
{
    int32_t error, target, delta, limit;
    core->occupancy_sum += core->count;
    if (++core->observation_ticks != 50U) return;
    /* error is in thousandths of a frame, averaged over a complete second. */
    error = (int32_t)((uint64_t)core->occupancy_sum * 1000U /
                     (50U * LUAT_CC_UART_MEDIA_FRAME)) - 3000;
    limit = core->clock.limit_ppm;
    core->integral_scaled = clamp32(core->integral_scaled +
                                    core->clock.integral_ppm * error,
                                    limit * 1000);
    target = clamp32(core->clock.proportional_ppm * error / 1000 +
                     core->integral_scaled / 1000, limit);
    delta = clamp32(target - core->clock_ppm, core->clock.slew_ppm);
    core->clock_ppm += delta;
    core->occupancy_sum = 0;
    core->observation_ticks = 0;
}

int luat_cc_uart_media_pop(luat_cc_uart_media_t *core, uint64_t session,
                           uint32_t epoch, int16_t *out)
{
    uint32_t step, last_phase, need, position, fraction, consumed;
    uint16_t i;
    int32_t a, b;
    int ret = check(core, session, epoch);
    if (ret) return ret;
    if (!out) return LUAT_CC_UART_MEDIA_BAD_ARG;
    if (!core->ready) {
        memset(out, 0, LUAT_CC_UART_MEDIA_FRAME * sizeof(*out));
        count_add(&core->counters.prebuffer_silence, 1);
        return LUAT_CC_UART_MEDIA_FRAME;
    }
    observe_clock(core);
    step = (uint32_t)((int32_t)PHASE_ONE + core->clock_ppm);
    last_phase = core->phase + (LUAT_CC_UART_MEDIA_FRAME - 1U) * step;
    need = last_phase / PHASE_ONE + 1U + ((last_phase % PHASE_ONE) != 0U);
    consumed = (core->phase + LUAT_CC_UART_MEDIA_FRAME * step) / PHASE_ONE;
    if (need > core->count || consumed > core->count) {
        memset(out, 0, LUAT_CC_UART_MEDIA_FRAME * sizeof(*out));
        /* Already buffered fragments cannot become an old tail after priming. */
        count_add(&core->counters.flushed_samples, core->count);
        core->count = 0;
        core->read = 0;
        core->phase = 0;
        core->ready = 0;
        core->occupancy_sum = 0;
        core->observation_ticks = 0;
        count_add(&core->counters.underflows, 1);
        return LUAT_CC_UART_MEDIA_FRAME;
    }
    for (i = 0; i < LUAT_CC_UART_MEDIA_FRAME; ++i) {
        position = core->phase / PHASE_ONE;
        fraction = core->phase % PHASE_ONE;
        a = core->samples[(core->read + position) % LUAT_CC_UART_MEDIA_CAPACITY];
        if (fraction) {
            b = core->samples[(core->read + position + 1U) % LUAT_CC_UART_MEDIA_CAPACITY];
            out[i] = (int16_t)(a + (int32_t)((int64_t)(b - a) * fraction / PHASE_ONE));
        } else {
            out[i] = (int16_t)a;
        }
        core->phase += step;
    }
    consumed = core->phase / PHASE_ONE;
    core->phase %= PHASE_ONE;
    core->read = (uint16_t)((core->read + consumed) % LUAT_CC_UART_MEDIA_CAPACITY);
    core->count = (uint16_t)(core->count - consumed);
    count_add(&core->counters.popped, 1);
    return LUAT_CC_UART_MEDIA_FRAME;
}

int luat_cc_uart_media_ready(const luat_cc_uart_media_t *core)
{
    return core && core->running && core->ready;
}

void luat_cc_uart_media_get_stats(const luat_cc_uart_media_t *core,
                                 luat_cc_uart_media_stats_t *out)
{
    if (!core || !out) return;
    memcpy(out, &core->counters, sizeof(*out));
    out->session = core->session;
    out->epoch = core->epoch;
    out->queued_samples = core->count;
    out->clock_ppm = core->clock_ppm;
    out->running = core->running;
    out->ready = core->ready;
}

void luat_cc_uart_resampler_init(luat_cc_uart_resampler_t *resampler)
{
    if (resampler) memset(resampler, 0, sizeof(*resampler));
}

/* 15-tap Hamming-windowed sinc, cutoff 3.4 kHz at 16 kHz, Q15 unity gain.
 * Both polyphase sums are exactly 16384 to avoid an upsampled DC ripple.
 * Both directions run this filter on the 16 kHz grid. Its history crosses
 * frame boundaries; 8->16 applies gain two after zero insertion. */
static const int16_t lowpass[15] = {
    9, 215, 202, -922, -1696, 1955, 9677, 13888,
    9677, 1955, -1696, -922, 202, 215, 9
};

static int16_t filter(luat_cc_uart_resampler_t *state, int16_t sample, int gain)
{
    int64_t sum = 0;
    int32_t value;
    unsigned i, at;
    state->history[state->at] = sample;
    at = state->at;
    for (i = 0; i < 15U; ++i) {
        sum += (int32_t)state->history[at] * lowpass[i];
        at = at ? at - 1U : 14U;
    }
    state->at = (uint8_t)((state->at + 1U) % 15U);
    value = (int32_t)(sum * gain / 32768);
    if (value > 32767) value = 32767;
    if (value < -32768) value = -32768;
    return (int16_t)value;
}

int luat_cc_uart_resampler_convert(luat_cc_uart_resampler_t *resampler,
                                   const int16_t *in, uint16_t input_samples,
                                   uint32_t input_rate, int16_t *out,
                                   uint16_t output_capacity,
                                   uint32_t output_rate)
{
    uint16_t i, output_samples;
    int16_t value;
    if (!resampler || !in || !out ||
        (input_rate != 8000U && input_rate != 16000U) ||
        (output_rate != 8000U && output_rate != 16000U) ||
        input_samples != input_rate / 50U) return LUAT_CC_UART_MEDIA_BAD_ARG;
    output_samples = (uint16_t)(output_rate / 50U);
    if (output_capacity < output_samples) return LUAT_CC_UART_MEDIA_BAD_ARG;
    if (resampler->input_rate != input_rate || resampler->output_rate != output_rate) {
        luat_cc_uart_resampler_init(resampler);
        resampler->input_rate = (uint16_t)input_rate;
        resampler->output_rate = (uint16_t)output_rate;
    }
    if (input_rate == output_rate) {
        memcpy(out, in, (size_t)output_samples * sizeof(*out));
    } else if (input_rate == 8000U) {
        for (i = 0; i < input_samples; ++i) {
            out[i * 2U] = filter(resampler, in[i], 2);
            out[i * 2U + 1U] = filter(resampler, 0, 2);
        }
    } else {
        for (i = 0; i < input_samples; ++i) {
            value = filter(resampler, in[i], 1);
            if (!(i & 1U)) out[i / 2U] = value;
        }
    }
    return output_samples;
}
