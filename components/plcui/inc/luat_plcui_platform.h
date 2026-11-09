/** @file luat_plcui_platform.h PC platform boundary for the XML runtime. */
#ifndef LUAT_PLCUI_PLATFORM_H
#define LUAT_PLCUI_PLATFORM_H
#include "lvgl.h"
#ifdef __cplusplus
extern "C" {
#endif
int plcui_platform_init(int width, int height);
void plcui_platform_deinit(void);
void plcui_platform_poll(void);
lv_display_t *plcui_platform_display(void);
int plcui_platform_snapshot(const char *path);
int plcui_platform_timer_start(uint32_t period_ms, void (*callback)(void *), void *parameter);
void plcui_platform_timer_stop(void);
#ifdef __cplusplus
}
#endif
#endif
