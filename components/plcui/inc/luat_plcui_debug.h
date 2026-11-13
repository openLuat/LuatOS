/** @file luat_plcui_debug.h Small UI-thread-only component timing summaries. */
#ifndef LUAT_PLCUI_DEBUG_H
#define LUAT_PLCUI_DEBUG_H
#include "luat_plcui_perf.h"

#if PLCUI_PERF_ENABLE && defined(LUAT_USE_PLCUI)
bool plcui_debug_enabled(void);
uint32_t plcui_debug_now(void);
void plcui_debug_set(bool enabled);
void plcui_debug_record(unsigned type, const char *phase, const char *operation,
                        const char *page, const char *id, uint32_t us, bool success);
void plcui_debug_poll(void);
#else
static inline bool plcui_debug_enabled(void) { return false; }
static inline uint32_t plcui_debug_now(void) { return 0; }
static inline void plcui_debug_set(bool e) { (void)e; }
static inline void plcui_debug_record(unsigned t, const char *p, const char *o,
                                     const char *pg, const char *i, uint32_t u, bool s)
{ (void)t; (void)p; (void)o; (void)pg; (void)i; (void)u; (void)s; }
static inline void plcui_debug_poll(void) {}
#endif
#endif
