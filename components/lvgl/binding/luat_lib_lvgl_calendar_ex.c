/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "luat_lvgl.h"
#include "lvgl.h"
#include "luat_malloc.h"

/*
创建一个calendar_date_t
@api lvgl.calendar_date_t()
@return userdata calendar_date_t
@usage
local calendar_date_t = lvgl.calendar_date_t()
*/
int luat_lv_calendar_date_t(lua_State *L) {
    lv_calendar_date_t* today = (lv_calendar_date_t*)luat_heap_malloc(sizeof(lv_calendar_date_t));
    lua_pushlightuserdata(L, today);
    return 1;
}
