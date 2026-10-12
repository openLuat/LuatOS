#include "luat_cc_pcm_core.h"

#include <string.h>

#if defined(_MSC_VER)
#include <intrin.h>
#endif

/* 调用方仍须串行化整个操作。计数器采用原子写入，
 * 同时遵守仓库对多线程访问统计量的要求。 */
static void counter_add(uint32_t *counter, uint32_t amount)
{
#if defined(_MSC_VER)
    (void)_InterlockedExchangeAdd((volatile long *)counter, (long)amount);
#elif defined(__GNUC__)
    (void)__sync_fetch_and_add(counter, amount);
#else
#error "CC PCM counters need an atomic implementation for this compiler"
#endif
}

static void counter_set(uint32_t *counter, uint32_t value)
{
#if defined(_MSC_VER)
    (void)_InterlockedExchange((volatile long *)counter, (long)value);
#elif defined(__GNUC__)
    (void)__sync_lock_test_and_set(counter, value);
#else
#error "CC PCM counters need an atomic implementation for this compiler"
#endif
}

static uint8_t next_frame(uint8_t index)
{
    return (uint8_t)((index + 1U) % LUAT_CC_PCM_CORE_QUEUE_FRAMES);
}

static uint16_t cc_samples(const luat_cc_pcm_core_t *core)
{
    return (core->cc_rate == 16000U) ? LUAT_CC_PCM_CORE_16K_SAMPLES :
                                     LUAT_CC_PCM_CORE_8K_SAMPLES;
}

static int check_session(luat_cc_pcm_core_t *core, uint32_t session)
{
    if (!core || !session) return LUAT_CC_PCM_CORE_BAD_ARG;
    if (core->session != session) {
        counter_add(&core->counters.rejected_session, 1);
        return LUAT_CC_PCM_CORE_STALE;
    }
    if (!core->running) {
        counter_add(&core->counters.rejected_stopped, 1);
        return LUAT_CC_PCM_CORE_STOPPED;
    }
    return 0;
}

static void flush_ul(luat_cc_pcm_core_t *core)
{
    counter_add(&core->counters.ul_flushed, core->ul_count);
    core->ul_count = 0;
    core->ul_ready = 0;
    core->ul_stream = 0;
    memset(core->ul_valid, 0, sizeof(core->ul_valid));
}

static void flush_queues(luat_cc_pcm_core_t *core)
{
    counter_add(&core->counters.dl_flushed, core->dl_count);
    core->dl_read = 0;
    core->dl_count = 0;
    flush_ul(core);
}

void luat_cc_pcm_core_init(luat_cc_pcm_core_t *core)
{
    if (core) memset(core, 0, sizeof(*core));
}

int luat_cc_pcm_core_start(luat_cc_pcm_core_t *core, uint32_t session,
                           uint32_t cc_rate)
{
    if (!core || !session || (cc_rate != 8000U && cc_rate != 16000U)) {
        return LUAT_CC_PCM_CORE_BAD_ARG;
    }
    if (core->running && core->session == session) {
        if (core->cc_rate != cc_rate) {
            flush_queues(core);
            counter_add(&core->counters.rate_changes, 1);
            core->cc_rate = cc_rate;
        }
        return 0;
    }
    flush_queues(core);
    memset(&core->counters, 0, sizeof(core->counters));
    core->session = session;
    core->cc_rate = cc_rate;
    core->running = 1;
    return 0;
}

int luat_cc_pcm_core_stop(luat_cc_pcm_core_t *core, uint32_t session)
{
    if (!core || !session) return LUAT_CC_PCM_CORE_BAD_ARG;
    if (core->session != session) {
        counter_add(&core->counters.rejected_session, 1);
        return LUAT_CC_PCM_CORE_STALE;
    }
    core->running = 0;
    flush_queues(core);
    return 0;
}

int luat_cc_pcm_core_flush(luat_cc_pcm_core_t *core, uint32_t session)
{
    int ret = check_session(core, session);
    if (ret) return ret;
    flush_queues(core);
    return 0;
}

int luat_cc_pcm_core_push_dl(luat_cc_pcm_core_t *core, uint32_t session,
                             const int16_t *pcm, uint16_t samples)
{
    uint8_t write;
    int ret = check_session(core, session);
    if (ret) return ret;
    if (!pcm || samples != cc_samples(core)) {
        counter_add(&core->counters.rejected_format, 1);
        return LUAT_CC_PCM_CORE_BAD_ARG;
    }
    if (core->dl_count == LUAT_CC_PCM_CORE_QUEUE_FRAMES) {
        core->dl_read = next_frame(core->dl_read);
        core->dl_count--;
        counter_add(&core->counters.dl_dropped, 1);
    }
    write = (uint8_t)((core->dl_read + core->dl_count) %
                       LUAT_CC_PCM_CORE_QUEUE_FRAMES);
    memcpy(core->dl[write], pcm, (size_t)samples * sizeof(int16_t));
    core->dl_count++;
    counter_add(&core->counters.dl_pushed, 1);
    if (core->dl_count > core->counters.dl_high_water) {
        counter_set(&core->counters.dl_high_water, core->dl_count);
    }
    return 1;
}

int luat_cc_pcm_core_pop_dl(luat_cc_pcm_core_t *core, uint32_t session,
                            int16_t *out)
{
    const int16_t *pcm;
    uint16_t i;
    int ret = check_session(core, session);
    if (ret) return ret;
    if (!out) {
        counter_add(&core->counters.rejected_format, 1);
        return LUAT_CC_PCM_CORE_BAD_ARG;
    }
    if (!core->dl_count) {
        counter_add(&core->counters.dl_underflows, 1);
        return 0;
    }
    pcm = core->dl[core->dl_read];
    if (core->cc_rate == 16000U) {
        for (i = 0; i < LUAT_CC_PCM_CORE_8K_SAMPLES; i++) {
            out[i] = (int16_t)(((int32_t)pcm[i * 2U] +
                               (int32_t)pcm[i * 2U + 1U]) / 2);
        }
    } else {
        memcpy(out, pcm, LUAT_CC_PCM_CORE_8K_SAMPLES * sizeof(int16_t));
    }
    core->dl_read = next_frame(core->dl_read);
    core->dl_count--;
    counter_add(&core->counters.dl_popped, 1);
    return LUAT_CC_PCM_CORE_8K_SAMPLES;
}

int luat_cc_pcm_core_push_ul(luat_cc_pcm_core_t *core, uint32_t session,
                             uint32_t stream, uint16_t sequence,
                             const int16_t *pcm, uint16_t samples)
{
    uint8_t write = LUAT_CC_PCM_CORE_QUEUE_FRAMES;
    uint16_t distance;
    int ret = check_session(core, session);
    if (ret) return ret;
    if (!stream || !pcm || samples != LUAT_CC_PCM_CORE_8K_SAMPLES) {
        counter_add(&core->counters.rejected_format, 1);
        return LUAT_CC_PCM_CORE_BAD_ARG;
    }
    if (core->ul_stream != stream) {
        flush_ul(core);
        core->ul_stream = stream;
        core->ul_expected = sequence;
    }
    distance = (uint16_t)(sequence - core->ul_expected);
    if (distance >= 0x8000U) {
        counter_add(&core->counters.ul_late, 1);
        return 0;
    }
    if (distance >= LUAT_CC_PCM_CORE_QUEUE_FRAMES) {
        uint16_t advance = (uint16_t)(distance - (LUAT_CC_PCM_CORE_QUEUE_FRAMES - 1U));
        uint32_t discarded = 0;
        for (uint8_t i = 0; i < LUAT_CC_PCM_CORE_QUEUE_FRAMES; ++i) {
            if (core->ul_valid[i] &&
                (uint16_t)(core->ul_seq[i] - core->ul_expected) < advance) {
                core->ul_valid[i] = 0;
                core->ul_count--;
                discarded++;
            }
        }
        counter_add(&core->counters.ul_dropped, discarded);
        counter_add(&core->counters.ul_lost, advance - discarded);
        core->ul_expected = (uint16_t)(core->ul_expected + advance);
    }
    for (uint8_t i = 0; i < LUAT_CC_PCM_CORE_QUEUE_FRAMES; ++i) {
        if (!core->ul_valid[i]) write = i;
        else if (core->ul_seq[i] == sequence) {
            counter_add(&core->counters.ul_duplicate, 1);
            return 0;
        }
    }
    /* 六个不同的序号位置始终能放入六个槽位。 */
    if (write == LUAT_CC_PCM_CORE_QUEUE_FRAMES) return LUAT_CC_PCM_CORE_BAD_ARG;
    memcpy(core->ul[write], pcm, LUAT_CC_PCM_CORE_8K_SAMPLES * sizeof(int16_t));
    core->ul_seq[write] = sequence;
    core->ul_valid[write] = 1;
    core->ul_count++;
    counter_add(&core->counters.ul_pushed, 1);
    if (core->ul_count > core->counters.ul_high_water) {
        counter_set(&core->counters.ul_high_water, core->ul_count);
    }
    return 1;
}

int luat_cc_pcm_core_pop_ul(luat_cc_pcm_core_t *core, uint32_t session,
                            int16_t *out, uint16_t capacity_samples)
{
    const int16_t *pcm;
    uint16_t samples;
    uint16_t i;
    uint8_t slot = LUAT_CC_PCM_CORE_QUEUE_FRAMES;
    int ret = check_session(core, session);
    if (ret) return ret;
    samples = cc_samples(core);
    if (!out || capacity_samples < samples) {
        counter_add(&core->counters.rejected_format, 1);
        return LUAT_CC_PCM_CORE_BAD_ARG;
    }
    if (!core->ul_ready) {
        if (core->ul_count < LUAT_CC_PCM_CORE_PREBUFFER_FRAMES) {
            memset(out, 0, (size_t)samples * sizeof(int16_t));
            counter_add(&core->counters.ul_prebuffer_silence, 1);
            return samples;
        }
        core->ul_ready = 1;
    }
    if (!core->ul_count) {
        memset(out, 0, (size_t)samples * sizeof(int16_t));
        core->ul_ready = 0;
        counter_add(&core->counters.ul_underflows, 1);
        return samples;
    }
    for (uint8_t n = 0; n < LUAT_CC_PCM_CORE_QUEUE_FRAMES; ++n) {
        if (core->ul_valid[n] && core->ul_seq[n] == core->ul_expected) {
            slot = n;
            break;
        }
    }
    core->ul_expected = (uint16_t)(core->ul_expected + 1U);
    if (slot == LUAT_CC_PCM_CORE_QUEUE_FRAMES) {
        memset(out, 0, (size_t)samples * sizeof(int16_t));
        counter_add(&core->counters.ul_lost, 1);
        return samples;
    }
    pcm = core->ul[slot];
    if (core->cc_rate == 16000U) {
        for (i = 0; i < LUAT_CC_PCM_CORE_8K_SAMPLES; i++) {
            int16_t next = (i + 1U < LUAT_CC_PCM_CORE_8K_SAMPLES) ?
                           pcm[i + 1U] : pcm[i];
            out[i * 2U] = pcm[i];
            out[i * 2U + 1U] = (int16_t)(((int32_t)pcm[i] +
                                        (int32_t)next) / 2);
        }
    } else {
        memcpy(out, pcm, (size_t)samples * sizeof(int16_t));
    }
    core->ul_valid[slot] = 0;
    core->ul_count--;
    counter_add(&core->counters.ul_popped, 1);
    return samples;
}

void luat_cc_pcm_core_get_stats(const luat_cc_pcm_core_t *core,
                               luat_cc_pcm_core_stats_t *out)
{
    if (!core || !out) return;
    *out = core->counters;
    out->session = core->session;
    out->cc_rate = core->cc_rate;
    out->running = core->running;
    out->dl_queued = core->dl_count;
    out->ul_queued = core->ul_count;
    out->ul_ready = core->ul_ready;
}
