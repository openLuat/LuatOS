
#ifndef LUAT_LVGL_CALENDAR_EX
#define LUAT_LVGL_CALENDAR_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_calendar_date_t(lua_State *L);

#define LUAT_LV_CALENDAR_EX_RLT {"calendar_date_t", luat_lv_calendar_date_t, 0},\


#endif
