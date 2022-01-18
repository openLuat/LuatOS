
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_calendar_header_arrow_create(lv_obj_t* parent)
int luat_lv_calendar_header_arrow_create(lua_State *L) {
    LV_DEBUG("CALL lv_calendar_header_arrow_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_calendar_header_arrow_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

