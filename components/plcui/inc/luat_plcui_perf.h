/** @file luat_plcui_perf.h Bounded UI-thread-only switch diagnostics. */
#ifndef LUAT_PLCUI_PERF_H
#define LUAT_PLCUI_PERF_H
#include "luat_plcui.h"

typedef enum {
    PERF_CHECK, PERF_CREATE, PERF_SWITCH, PERF_DRAW, PERF_PHASE_COUNT
} plcui_perf_phase_t;
typedef enum {
    PERF_STAT, PERF_INFO, PERF_CODEC_INFO,
    PERF_LV_OPEN, PERF_LV_READ, PERF_LV_SEEK, PERF_LV_TELL, PERF_LV_CLOSE,
    PERF_OPEN, PERF_SIZE, PERF_ALLOC, PERF_READ, PERF_CLOSE,
    PERF_SAFETY, PERF_HW, PERF_SW, PERF_POST, PERF_EVICT, PERF_RETRY,
    PERF_FONT_LOOKUP, PERF_FONT_BITMAP, PERF_PROBE, PERF_PROBE_CLOSE,
    PERF_CHECKED, PERF_REUSED, PERF_MISS,
    PERF_REAL_OPEN, PERF_REAL_CLOSE,
    PERF_METRIC_COUNT
} plcui_perf_metric_t;
typedef enum {
    PERF_STEP_CHECK, PERF_STEP_CREATE, PERF_STEP_INPUT, PERF_STEP_DISPATCH,
    PERF_STEP_ACTIVATE, PERF_STEP_DESTROY, PERF_STEP_INIT, PERF_STEP_COUNT
} plcui_perf_step_t;
typedef struct { uint32_t us, calls, bytes; } plcui_perf_metric_value_t;
typedef struct { plcui_perf_metric_value_t value[PERF_METRIC_COUNT]; } plcui_perf_sample_t;
typedef enum {
    PERF_TA_NATIVE, PERF_TA_COMMON, PERF_TA_STYLE, PERF_TA_MODE,
    PERF_TA_TEXT, PERF_TA_LIMITS, PERF_TA_FINAL, PERF_TA_COUNT
} plcui_perf_textarea_stage_t;

#if PLCUI_PERF_ENABLE && PLCUI_PERF_VERBOSE && defined(LUAT_USE_PLCUI)
uint32_t plcui_perf_now(void);
bool plcui_perf_active(void);
void plcui_perf_add(plcui_perf_metric_t metric, uint32_t us, uint32_t bytes);
void plcui_perf_snapshot(plcui_perf_sample_t *sample);
/* kind: 0=complete resource check, 1=decoder open/miss, 2=codec info callback. */
void plcui_perf_slow(unsigned kind, const char *path, uint32_t us, const plcui_perf_sample_t *before);
void plcui_perf_request(plcui_document_t *doc, int page);
void plcui_perf_begin(plcui_document_t *doc, int page);
void plcui_perf_phase(plcui_perf_phase_t phase);
void plcui_perf_step(plcui_perf_step_t step, uint32_t us);
void plcui_perf_component(unsigned type, uint32_t us);
void plcui_perf_textarea(plcui_perf_textarea_stage_t stage, uint32_t us);
void plcui_perf_arm(lv_obj_t *screen);
void plcui_perf_flush(uint32_t preserve_us, uint32_t copy_us, uint32_t pan_us, bool last, bool success);
void plcui_perf_poll(void);
void plcui_perf_fail(const char *reason);
void plcui_perf_cancel(plcui_document_t *doc);
void plcui_perf_reset(void);
#else
static inline uint32_t plcui_perf_now(void) { return 0; }
static inline bool plcui_perf_active(void) { return false; }
static inline void plcui_perf_add(plcui_perf_metric_t m, uint32_t u, uint32_t b) { (void)m; (void)u; (void)b; }
static inline void plcui_perf_snapshot(plcui_perf_sample_t *s) { (void)s; }
static inline void plcui_perf_slow(unsigned k, const char *p, uint32_t u, const plcui_perf_sample_t *s) { (void)k; (void)p; (void)u; (void)s; }
static inline void plcui_perf_request(plcui_document_t *d, int p) { (void)d; (void)p; }
static inline void plcui_perf_begin(plcui_document_t *d, int p) { (void)d; (void)p; }
static inline void plcui_perf_phase(plcui_perf_phase_t p) { (void)p; }
static inline void plcui_perf_step(plcui_perf_step_t s, uint32_t u) { (void)s; (void)u; }
static inline void plcui_perf_component(unsigned t, uint32_t u) { (void)t; (void)u; }
static inline void plcui_perf_textarea(plcui_perf_textarea_stage_t s, uint32_t u) { (void)s; (void)u; }
static inline void plcui_perf_arm(lv_obj_t *s) { (void)s; }
static inline void plcui_perf_flush(uint32_t a, uint32_t b, uint32_t c, bool l, bool s) { (void)a; (void)b; (void)c; (void)l; (void)s; }
static inline void plcui_perf_poll(void) {}
static inline void plcui_perf_fail(const char *r) { (void)r; }
static inline void plcui_perf_cancel(plcui_document_t *d) { (void)d; }
static inline void plcui_perf_reset(void) {}
#endif
#endif
