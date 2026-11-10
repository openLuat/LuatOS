/** @file luat_plcui_platform.h SDL/LuatOS boundary for the XML runtime. */
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
int plcui_fs_init(void);
enum { PLCUI_PLATFORM_UNSUPPORTED = -2 };
const char *plcui_platform_name(void);
uint32_t plcui_platform_state_lock(void);
void plcui_platform_state_unlock(uint32_t token);
struct luat_tp_config;
int plcui_platform_bind_touch(struct luat_tp_config *config);
int plcui_platform_image_init(void);
void plcui_platform_image_deinit(void);
uint32_t plcui_platform_image_hw_count(void);
uint32_t plcui_platform_image_sw_count(void);
#ifdef __cplusplus
}
#endif
#endif
