
#ifndef LUAT_LVGL_CALENDAR_EX
#define LUAT_LVGL_CALENDAR_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_calendar_set_highlighted_dates(lua_State *L);

#define LUAT_LV_CALENDAR_EX_RLT {"calendar_set_highlighted_dates", luat_lv_calendar_set_highlighted_dates, 0},\

#endif