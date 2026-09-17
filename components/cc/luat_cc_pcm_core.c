#include "luat_cc_pcm_core.h"

#include <string.h>

#if defined(_MSC_VER)
#include <intrin.h>
#endif

/* Callers still serialize the whole operation. Atomic counter writes also
 * follow the repository rule for statistics touched by multiple threads. */
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

static void flush_queues(luat_cc_pcm_core_t *core)
{
    counter_add(&core->counters.dl_flushed, core->dl_count);
    counter_add(&core->counters.ul_flushed, core->ul_count);
    core->dl_read = 0;
    core->dl_count = 0;
    core->ul_read = 0;
    core->ul_count = 0;
    core->ul_ready = 0;
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
                             const int16_t *pcm, uint16_t samples)
{
    uint8_t write;
    int ret = check_session(core, session);
    if (ret) return ret;
    if (!pcm || samples != LUAT_CC_PCM_CORE_8K_SAMPLES) {
        counter_add(&core->counters.rejected_format, 1);
        return LUAT_CC_PCM_CORE_BAD_ARG;
    }
    if (core->ul_count == LUAT_CC_PCM_CORE_QUEUE_FRAMES) {
        core->ul_read = next_frame(core->ul_read);
        core->ul_count--;
        counter_add(&core->counters.ul_dropped, 1);
    }
    write = (uint8_t)((core->ul_read + core->ul_count) %
                       LUAT_CC_PCM_CORE_QUEUE_FRAMES);
    memcpy(core->ul[write], pcm, LUAT_CC_PCM_CORE_8K_SAMPLES * sizeof(int16_t));
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
    pcm = core->ul[core->ul_read];
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
    core->ul_read = next_frame(core->ul_read);
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
