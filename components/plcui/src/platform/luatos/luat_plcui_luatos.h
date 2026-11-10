/** @file luat_plcui_luatos.h Private LuatOS platform entry points. */
#ifndef LUAT_PLCUI_LUATOS_H
#define LUAT_PLCUI_LUATOS_H

#include "luat_plcui_platform.h"
#include "luat_tp.h"

int plcui_luatos_display_init(int width, int height);
void plcui_luatos_display_deinit(void);
lv_display_t *plcui_luatos_display(void);
void plcui_luatos_display_poll(void);
int plcui_luatos_input_init(lv_display_t *display);
void plcui_luatos_input_deinit(void);
void plcui_luatos_input_poll(void);
int plcui_platform_bind_touch(luat_tp_config_t *config);

#endif
