
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_line_create(lv_obj_t* parent)
int luat_lv_line_create(lua_State *L) {
    LV_DEBUG("CALL lv_line_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_line_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_line_set_y_invert(lv_obj_t* obj, bool en)
int luat_lv_line_set_y_invert(lua_State *L) {
    LV_DEBUG("CALL lv_line_set_y_invert");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_line_set_y_invert(obj ,en);
    return 0;
}

//  bool lv_line_get_y_invert(lv_obj_t* obj)
int luat_lv_line_get_y_invert(lua_State *L) {
    LV_DEBUG("CALL lv_line_get_y_invert");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_line_get_y_invert(obj);
    lua_pushboolean(L, ret);
    return 1;
}

