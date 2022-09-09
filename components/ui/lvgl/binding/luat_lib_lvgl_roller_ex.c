/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"
#include "luat_malloc.h"
#include "luat_zbuff.h"

int luat_lv_roller_get_selected_str(lua_State *L) {
    LV_DEBUG("CALL lv_roller_get_selected_str");
    lv_obj_t* roller = (lv_obj_t*)lua_touserdata(L, 1);
    char buf[32] = {0};
    lv_roller_get_selected_str(roller, buf, 32);
    buf[31] = 0x00;
    lua_pushlstring(L, buf, strlen(buf));
    return 1;
}
