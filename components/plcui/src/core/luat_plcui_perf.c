/** @file luat_plcui_perf.c Passive switch tracing; no I/O or cache policy changes. */
#include "luat_base.h"
#include "luat_plcui_perf.h"
#include "luat_plcui_debug.h"
#if PLCUI_PERF_ENABLE && PLCUI_PERF_VERBOSE && defined(LUAT_USE_PLCUI)
#include "luat_mcu.h"
#include "lvgl9/src/core/lv_global.h"
#include "lvgl9/src/misc/cache/lv_cache.h"
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#define LUAT_LOG_TAG "plcui.perf"
#include "luat_log.h"

/* Observe updates after the first frame without delaying the application.
 * End after 200ms without a dirty frame, or at most 1s after the first frame.
 * Only four frame records and three slow-image samples per phase are retained. */
typedef struct {
    uint32_t prepare, render, flush, preserve, copy, pan, flushes, submit;
    uint32_t refresh_start, render_start, flush_start;
    bool rendered, failed;
} perf_frame_t;
typedef struct { uint32_t us; char file[96]; plcui_perf_sample_t sample; } perf_slow_t;
static struct {
    bool active, armed, first_submit;
    plcui_document_t *owner;
    lv_obj_t *screen;
    uint32_t id, request, begin, arm, first, first_refresh, last_frame;
    uint32_t steps[PERF_STEP_COUNT], components[7], component_us[7], component_max[7];
    uint32_t textarea[PERF_TA_COUNT];
    uint32_t frames, cache_start, cache_max;
    plcui_perf_phase_t phase;
    char from[PLCUI_ID_MAX], page[PLCUI_ID_MAX];
    plcui_perf_sample_t stats[PERF_PHASE_COUNT];
    perf_slow_t slow[PERF_PHASE_COUNT][3];
    perf_frame_t frame, saved[4];
} trace;
static lv_display_t *attached;
static plcui_document_t *pending_owner;
static int pending_page;
static uint32_t pending_at, sequence;
static const char *phases[] = {"check", "create", "switch", "draw"};

uint32_t plcui_perf_now(void)
{
    return PLCUI_PERF_VERBOSE ? plcui_debug_now() : 0;
}

bool plcui_perf_active(void) { return trace.active; }

static uint32_t cache_used(void)
{
    if (!lv_is_initialized() || !lv_image_cache_is_enabled()) return 0;
    lv_cache_t *cache = LV_GLOBAL_DEFAULT()->img_cache;
    return cache ? (uint32_t)lv_cache_get_size(cache, NULL) : 0;
}

void plcui_perf_add(plcui_perf_metric_t metric, uint32_t us, uint32_t bytes)
{
    if (!trace.active || metric >= PERF_METRIC_COUNT) return;
    plcui_perf_metric_value_t *v = &trace.stats[trace.phase].value[metric];
    v->us += us; v->calls++; v->bytes += bytes;
}

void plcui_perf_snapshot(plcui_perf_sample_t *sample)
{
    memset(sample, 0, sizeof(*sample));
    if (trace.active) *sample = trace.stats[trace.phase];
}

void plcui_perf_slow(unsigned kind, const char *path, uint32_t us, const plcui_perf_sample_t *before)
{
    if (!trace.active || kind >= 3) return;
    perf_slow_t *slow = &trace.slow[trace.phase][kind];
    if (us <= slow->us) return;
    slow->us = us;
    const char *file = path ? strrchr(path, '/') : NULL;
    snprintf(slow->file, sizeof(slow->file), "%s", file ? file + 1 : path ? path : "?");
    for (unsigned i = 0; i < PERF_METRIC_COUNT; ++i) {
        const plcui_perf_metric_value_t *v = &trace.stats[trace.phase].value[i];
        slow->sample.value[i].us = v->us - before->value[i].us;
        slow->sample.value[i].calls = v->calls - before->value[i].calls;
        slow->sample.value[i].bytes = v->bytes - before->value[i].bytes;
    }
}

/* The CCM4211 logger drops the tag for long format strings. Keep its
 * format short and format the bounded summary only after sampling stops. */
static void perf_log(const char *format, ...)
{
    char line[512];
    va_list args;
    va_start(args, format);
    vsnprintf(line, sizeof(line), format, args);
    va_end(args);
    LLOGI("%s", line);
}

static void finish(const char *status)
{
    if (!trace.active) return;
    uint32_t end_cache = cache_used();
    trace.active = false; /* Logging itself is outside the measured intervals. */
    perf_log("SWITCH seq=%u from=%s page=%s status=%s queue_us=%u check_us=%u create_us=%u input_us=%u dispatch_us=%u activate_us=%u destroy_us=%u",
          trace.id, trace.from, trace.page, status, trace.begin - trace.request,
          trace.steps[0], trace.steps[1], trace.steps[2], trace.steps[3], trace.steps[4], trace.steps[5]);
    perf_log("PRESENT seq=%u first_submit_us=%u first_refresh_us=%u frames=%u cache_start=%u cache_end=%u cache_max=%u",
          trace.id, trace.first_submit ? trace.first - trace.request : 0,
          trace.frames ? trace.first_refresh - trace.request : 0,
          trace.frames, trace.cache_start, end_cache, trace.cache_max);
    perf_log("INIT seq=%u work_us=%u", trace.id, trace.steps[PERF_STEP_INIT]);
    if (trace.components[PLCUI_TEXTAREA])
        perf_log("TEXTAREA seq=%u count=%u native_us=%u common_us=%u style_us=%u mode_us=%u text_us=%u limits_us=%u final_us=%u",
                 trace.id, trace.components[PLCUI_TEXTAREA], trace.textarea[0], trace.textarea[1],
                 trace.textarea[2], trace.textarea[3], trace.textarea[4], trace.textarea[5], trace.textarea[6]);
    for (unsigned f = 0; f < trace.frames && f < 4; ++f) {
        perf_frame_t *v = &trace.saved[f];
        perf_log("FRAME seq=%u n=%u layout_prepare_us=%u render_incl_flush_us=%u flush_us=%u draw_other_us=%u preserve_us=%u copy_us=%u pan_call_us=%u flushes=%u failed=%u",
              trace.id, f + 1, v->prepare, v->render, v->flush,
              v->render >= v->flush ? v->render - v->flush : 0,
              v->preserve, v->copy, v->pan, v->flushes, (unsigned)v->failed);
    }
    for (unsigned p = 0; p < PERF_PHASE_COUNT; ++p) {
        plcui_perf_metric_value_t *v = trace.stats[p].value;
        uint32_t count = 0;
        for (unsigned m = 0; m < PERF_METRIC_COUNT; ++m) count += v[m].calls;
        if (!count) continue;
        if (v[PERF_REAL_OPEN].calls || v[PERF_REAL_CLOSE].calls)
            perf_log("FOPEN seq=%u phase=%s open_n=%u open_us=%u close_n=%u close_us=%u",
                     trace.id, phases[p], v[PERF_REAL_OPEN].calls, v[PERF_REAL_OPEN].us,
                     v[PERF_REAL_CLOSE].calls, v[PERF_REAL_CLOSE].us);
        perf_log("IMAGE seq=%u phase=%s checked=%u reused=%u adapter_opens=%u hw_calls=%u sw_calls=%u evictions=%u oom_retries=%u",
              trace.id, phases[p], v[PERF_CHECKED].calls, v[PERF_REUSED].calls,
              v[PERF_MISS].calls, v[PERF_HW].calls, v[PERF_SW].calls, v[PERF_EVICT].calls, v[PERF_RETRY].calls);
        perf_log("LVFS seq=%u phase=%s stat_n=%u stat_us=%u open_n=%u open_us=%u read_n=%u read_us=%u read_bytes=%u seek_n=%u seek_us=%u tell_us=%u close_us=%u",
              trace.id, phases[p], v[PERF_STAT].calls, v[PERF_STAT].us,
              v[PERF_LV_OPEN].calls, v[PERF_LV_OPEN].us, v[PERF_LV_READ].calls, v[PERF_LV_READ].us,
              v[PERF_LV_READ].bytes, v[PERF_LV_SEEK].calls, v[PERF_LV_SEEK].us, v[PERF_LV_TELL].us, v[PERF_LV_CLOSE].us);
        perf_log("DIRECT seq=%u phase=%s open_n=%u open_us=%u size_us=%u alloc_us=%u read_n=%u read_us=%u read_bytes=%u close_us=%u",
              trace.id, phases[p], v[PERF_OPEN].calls, v[PERF_OPEN].us, v[PERF_SIZE].us,
              v[PERF_ALLOC].us, v[PERF_READ].calls, v[PERF_READ].us, v[PERF_READ].bytes, v[PERF_CLOSE].us);
        perf_log("CODEC seq=%u phase=%s info_total_us=%u codec_info_n=%u codec_info_us=%u probe_us=%u probe_close_us=%u safety_us=%u hw_call_us=%u sw_open_us=%u post_us=%u evict_us=%u",
              trace.id, phases[p], v[PERF_INFO].us, v[PERF_CODEC_INFO].calls, v[PERF_CODEC_INFO].us,
              v[PERF_PROBE].us, v[PERF_PROBE_CLOSE].us, v[PERF_SAFETY].us, v[PERF_HW].us, v[PERF_SW].us, v[PERF_POST].us, v[PERF_EVICT].us);
        if (v[PERF_FONT_LOOKUP].calls || v[PERF_FONT_BITMAP].calls)
            perf_log("FONT seq=%u phase=%s lookup_n=%u lookup_us=%u bitmap_n=%u bitmap_us=%u",
                  trace.id, phases[p], v[PERF_FONT_LOOKUP].calls, v[PERF_FONT_LOOKUP].us,
                  v[PERF_FONT_BITMAP].calls, v[PERF_FONT_BITMAP].us);
        for (unsigned k = 0; k < 3; ++k) {
            perf_slow_t *slow = &trace.slow[p][k];
            if (!slow->us) continue;
            plcui_perf_metric_value_t *s = slow->sample.value;
            perf_log("SLOW seq=%u phase=%s kind=%u file=%s total_us=%u stat_us=%u info_us=%u lvopen_us=%u open_us=%u read_us=%u hw_us=%u sw_us=%u",
                  trace.id, phases[p], k, slow->file, slow->us, s[PERF_STAT].us, s[PERF_INFO].us,
                  s[PERF_LV_OPEN].us, s[PERF_OPEN].us, s[PERF_READ].us, s[PERF_HW].us, s[PERF_SW].us);
        }
    }
    for (unsigned t = 0; t < 7; ++t) if (trace.components[t])
        perf_log("WIDGET seq=%u type=%u count=%u total_us=%u max_us=%u",
              trace.id, t, trace.components[t], trace.component_us[t], trace.component_max[t]);
}

static void display_event(lv_event_t *event)
{
    if (!trace.active || !trace.armed || lv_display_get_screen_active(attached) != trace.screen) return;
    uint32_t now = plcui_perf_now();
    perf_frame_t *f = &trace.frame;
    switch (lv_event_get_code(event)) {
    case LV_EVENT_REFR_START:
        memset(f, 0, sizeof(*f)); f->refresh_start = now; break;
    case LV_EVENT_RENDER_START:
        f->rendered = true; f->render_start = now; f->prepare = now - f->refresh_start; break;
    case LV_EVENT_FLUSH_START: f->flush_start = now; break;
    case LV_EVENT_FLUSH_FINISH:
        f->flush += now - f->flush_start; f->flushes++;
        if (lv_display_flush_is_last(attached) && !f->failed && !trace.first_submit) {
            trace.first_submit = true; trace.first = now;
        }
        break;
    case LV_EVENT_RENDER_READY: f->render = now - f->render_start; break;
    case LV_EVENT_REFR_READY:
        if (!f->rendered) break;
        if (!trace.frames) trace.first_refresh = now;
        if (trace.frames < 4) trace.saved[trace.frames] = *f;
        trace.frames++; trace.last_frame = now;
        break;
    default: break;
    }
}

void plcui_perf_request(plcui_document_t *doc, int page)
{
    if (!PLCUI_PERF_VERBOSE || !plcui_debug_enabled()) return;
    if (page < 0) { if (pending_owner == doc) pending_owner = NULL; return; }
    pending_owner = doc; pending_page = page; pending_at = plcui_perf_now();
}

void plcui_perf_begin(plcui_document_t *doc, int page)
{
    if (!PLCUI_PERF_VERBOSE || !plcui_debug_enabled()) return;
    if (trace.active) finish("superseded");
    memset(&trace, 0, sizeof(trace));
    trace.active = true; trace.owner = doc; trace.id = ++sequence;
    trace.begin = plcui_perf_now(); trace.request = trace.begin;
    if (pending_owner == doc && pending_page == page) trace.request = pending_at;
    pending_owner = NULL;
    snprintf(trace.page, sizeof(trace.page), "%s", doc->pages[page].id);
    snprintf(trace.from, sizeof(trace.from), "%s", doc->current_page >= 0 ? doc->pages[doc->current_page].id : "none");
    trace.cache_start = cache_used();
    lv_cache_t *cache = LV_GLOBAL_DEFAULT()->img_cache;
    trace.cache_max = cache ? (uint32_t)lv_cache_get_max_size(cache, NULL) : 0;
    lv_display_t *display = plcui_platform_display();
    if (display && attached != display) {
        lv_display_add_event_cb(display, display_event, LV_EVENT_ALL, NULL); attached = display;
    }
}

void plcui_perf_phase(plcui_perf_phase_t phase) { if (trace.active) trace.phase = phase; }
void plcui_perf_step(plcui_perf_step_t step, uint32_t us) { if (trace.active && step < PERF_STEP_COUNT) trace.steps[step] += us; }
void plcui_perf_component(unsigned type, uint32_t us)
{
    if (!trace.active || type >= 7) return;
    trace.components[type]++; trace.component_us[type] += us;
    if (us > trace.component_max[type]) trace.component_max[type] = us;
}
void plcui_perf_textarea(plcui_perf_textarea_stage_t stage, uint32_t us)
{
    if (trace.active && stage < PERF_TA_COUNT) trace.textarea[stage] += us;
}
void plcui_perf_arm(lv_obj_t *screen)
{
    if (!trace.active) return;
    trace.screen = screen; trace.arm = plcui_perf_now(); trace.armed = true; trace.phase = PERF_DRAW;
}
void plcui_perf_flush(uint32_t preserve_us, uint32_t copy_us, uint32_t pan_us, bool last, bool success)
{
    (void)last;
    if (!trace.active || !trace.armed || lv_display_get_screen_active(attached) != trace.screen) return;
    trace.frame.preserve += preserve_us; trace.frame.copy += copy_us; trace.frame.pan += pan_us;
    if (!success) trace.frame.failed = true;
}
void plcui_perf_poll(void)
{
    if (!trace.active || !trace.armed) return;
    uint32_t now = plcui_perf_now();
    if (!trace.frames) { if (now - trace.arm >= 2000000U) finish("no_frame"); return; }
    if (now - trace.last_frame >= 200000U || now - trace.first_refresh >= 1000000U)
        finish(trace.first_submit ? "ok" : "no_submit");
}
void plcui_perf_fail(const char *reason) { finish(reason); }
void plcui_perf_cancel(plcui_document_t *doc)
{
    if (pending_owner == doc) pending_owner = NULL;
    if (trace.active && trace.owner == doc) finish("closed");
}
void plcui_perf_reset(void)
{
    if (trace.active) finish("deinit");
    attached = NULL; pending_owner = NULL;
}
#endif
