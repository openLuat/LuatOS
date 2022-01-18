
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_spinner_create(lv_obj_t* parent, uint32_t time, uint32_t arc_length)
int luat_lv_spinner_create(lua_State *L) {
    LV_DEBUG("CALL lv_spinner_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t time = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t arc_length = (uint32_t)luaL_checkinteger(L, 3);
    lv_obj_t* ret = NULL;
    ret = lv_spinner_create(parent ,time ,arc_length);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

