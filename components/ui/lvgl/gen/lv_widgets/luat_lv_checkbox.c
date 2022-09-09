
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_checkbox_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_checkbox_create(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_checkbox_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_checkbox_set_text(lv_obj_t* cb, char* txt)
int luat_lv_checkbox_set_text(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_set_text");
    lv_obj_t* cb = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_checkbox_set_text(cb ,txt);
    return 0;
}

//  void lv_checkbox_set_text_static(lv_obj_t* cb, char* txt)
int luat_lv_checkbox_set_text_static(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_set_text_static");
    lv_obj_t* cb = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_checkbox_set_text_static(cb ,txt);
    return 0;
}

//  void lv_checkbox_set_checked(lv_obj_t* cb, bool checked)
int luat_lv_checkbox_set_checked(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_set_checked");
    lv_obj_t* cb = (lv_obj_t*)lua_touserdata(L, 1);
    bool checked = (bool)lua_toboolean(L, 2);
    lv_checkbox_set_checked(cb ,checked);
    return 0;
}

//  void lv_checkbox_set_disabled(lv_obj_t* cb)
int luat_lv_checkbox_set_disabled(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_set_disabled");
    lv_obj_t* cb = (lv_obj_t*)lua_touserdata(L, 1);
    lv_checkbox_set_disabled(cb);
    return 0;
}

//  void lv_checkbox_set_state(lv_obj_t* cb, lv_btn_state_t state)
int luat_lv_checkbox_set_state(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_set_state");
    lv_obj_t* cb = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btn_state_t state = (lv_btn_state_t)luaL_checkinteger(L, 2);
    lv_checkbox_set_state(cb ,state);
    return 0;
}

//  char* lv_checkbox_get_text(lv_obj_t* cb)
int luat_lv_checkbox_get_text(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_get_text");
    lv_obj_t* cb = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_checkbox_get_text(cb);
    lua_pushstring(L, ret);
    return 1;
}

//  bool lv_checkbox_is_checked(lv_obj_t* cb)
int luat_lv_checkbox_is_checked(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_is_checked");
    lv_obj_t* cb = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_checkbox_is_checked(cb);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_checkbox_is_inactive(lv_obj_t* cb)
int luat_lv_checkbox_is_inactive(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_is_inactive");
    lv_obj_t* cb = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_checkbox_is_inactive(cb);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_btn_state_t lv_checkbox_get_state(lv_obj_t* cb)
int luat_lv_checkbox_get_state(lua_State *L) {
    LV_DEBUG("CALL lv_checkbox_get_state");
    lv_obj_t* cb = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btn_state_t ret;
    ret = lv_checkbox_get_state(cb);
    lua_pushinteger(L, ret);
    return 1;
}

