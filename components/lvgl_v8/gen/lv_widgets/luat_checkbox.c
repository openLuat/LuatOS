
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_checkbox_create(lv_obj_t* parent)
int luat_lv_checkbox_create(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_checkbox_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_checkbox_set_text(lv_obj_t* obj, char* txt)
int luat_lv_checkbox_set_text(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_set_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_checkbox_set_text(obj ,txt);
    return 0;
}

//  void lv_checkbox_set_text_static(lv_obj_t* obj, char* txt)
int luat_lv_checkbox_set_text_static(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_set_text_static");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_checkbox_set_text_static(obj ,txt);
    return 0;
}

//  char* lv_checkbox_get_text(lv_obj_t* obj)
int luat_lv_checkbox_get_text(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_get_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_checkbox_get_text(obj);
    lua_pushstring(L, ret);
    return 1;
}

