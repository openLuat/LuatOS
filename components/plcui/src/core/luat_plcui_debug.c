/** @file luat_plcui_debug.c Bounded component create/prepare/update timing. */
#include "luat_base.h"
#include "luat_plcui_debug.h"
#if PLCUI_PERF_ENABLE && defined(LUAT_USE_PLCUI)
#include "luat_mcu.h"
#include <stdio.h>
#include <string.h>
#define LUAT_LOG_TAG "plcui.debug"
#include "luat_log.h"

#define DEBUG_BUCKETS 64U
typedef struct {
    const char *phase, *operation;
    uint64_t total_us;
    uint32_t count, failures, max_us;
    unsigned type;
    char page[PLCUI_ID_MAX], id[PLCUI_ID_MAX];
} debug_bucket_t;
static struct {
    bool enabled;
    uint32_t since, dropped;
    unsigned used;
    debug_bucket_t buckets[DEBUG_BUCKETS];
} debug;
static const char *types[] = {"image", "label", "textarea", "keyboard", "container", "table", "chart"};

bool plcui_debug_enabled(void) { return debug.enabled; }

uint32_t plcui_debug_now(void)
{
    if (!debug.enabled) return 0;
    int period = luat_mcu_us_period();
    return (uint32_t)(period > 0 ? luat_mcu_tick64() / (unsigned)period
                                : luat_mcu_tick64_ms() * 1000U);
}

static void debug_flush(void)
{
    for (unsigned i = 0; i < debug.used; ++i) {
        debug_bucket_t *b = &debug.buckets[i];
        char line[512];
        snprintf(line, sizeof(line),
                 "phase=%s type=%s op=%s count=%u failed=%u total_us=%llu avg_us=%llu max_us=%u slow_page=%s slow_id=%s",
                 b->phase, types[b->type], b->operation, (unsigned)b->count, (unsigned)b->failures,
                 (unsigned long long)b->total_us, (unsigned long long)(b->total_us / b->count),
                 (unsigned)b->max_us, b->page, b->id);
        LLOGI("%s", line);
    }
    if (debug.dropped) LLOGW("component timing buckets full, dropped=%u", (unsigned)debug.dropped);
    debug.used = 0;
    debug.dropped = 0;
    debug.since = plcui_debug_now();
}

void plcui_debug_set(bool enabled)
{
    if (enabled == debug.enabled) return;
    if (!enabled) debug_flush();
    memset(&debug, 0, sizeof(debug));
    debug.enabled = enabled;
    if (enabled) debug.since = plcui_debug_now();
}

/* phase/operation are static C strings, never borrowed Lua strings. */
void plcui_debug_record(unsigned type, const char *phase, const char *operation,
                        const char *page, const char *id, uint32_t us, bool success)
{
    if (!debug.enabled || type >= sizeof(types) / sizeof(types[0])) return;
    debug_bucket_t *b = NULL;
    for (unsigned i = 0; i < debug.used; ++i) {
        debug_bucket_t *candidate = &debug.buckets[i];
        if (candidate->type == type && !strcmp(candidate->phase, phase)
            && !strcmp(candidate->operation, operation)) { b = candidate; break; }
    }
    if (!b) {
        if (debug.used == DEBUG_BUCKETS) { debug.dropped++; return; }
        b = &debug.buckets[debug.used++];
        memset(b, 0, sizeof(*b));
        b->type = type; b->phase = phase; b->operation = operation;
    }
    b->total_us += us;
    b->count++;
    if (!success) b->failures++;
    if (b->count == 1 || us > b->max_us) {
        b->max_us = us;
        snprintf(b->page, sizeof(b->page), "%s", page);
        snprintf(b->id, sizeof(b->id), "%s", id);
    }
}

void plcui_debug_poll(void)
{
    if (debug.enabled && (debug.used || debug.dropped)
        && (uint32_t)(plcui_debug_now() - debug.since) >= 1000000U) debug_flush();
}
#endif
