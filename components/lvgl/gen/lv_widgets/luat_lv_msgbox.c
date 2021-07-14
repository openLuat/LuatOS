
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_msgbox_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_msgbox_create(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_msgbox_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_msgbox_set_text(lv_obj_t* mbox, char* txt)
int luat_lv_msgbox_set_text(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_set_text");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_msgbox_set_text(mbox ,txt);
    return 0;
}

//  void lv_msgbox_set_anim_time(lv_obj_t* mbox, uint16_t anim_time)
int luat_lv_msgbox_set_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_set_anim_time");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t anim_time = (uint16_t)luaL_checkinteger(L, 2);
    lv_msgbox_set_anim_time(mbox ,anim_time);
    return 0;
}

//  void lv_msgbox_start_auto_close(lv_obj_t* mbox, uint16_t delay)
int luat_lv_msgbox_start_auto_close(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_start_auto_close");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t delay = (uint16_t)luaL_checkinteger(L, 2);
    lv_msgbox_start_auto_close(mbox ,delay);
    return 0;
}

//  void lv_msgbox_stop_auto_close(lv_obj_t* mbox)
int luat_lv_msgbox_stop_auto_close(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_stop_auto_close");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    lv_msgbox_stop_auto_close(mbox);
    return 0;
}

//  void lv_msgbox_set_recolor(lv_obj_t* mbox, bool en)
int luat_lv_msgbox_set_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_set_recolor");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_msgbox_set_recolor(mbox ,en);
    return 0;
}

//  char* lv_msgbox_get_text(lv_obj_t* mbox)
int luat_lv_msgbox_get_text(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_get_text");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_msgbox_get_text(mbox);
    lua_pushstring(L, ret);
    return 1;
}

//  uint16_t lv_msgbox_get_active_btn(lv_obj_t* mbox)
int luat_lv_msgbox_get_active_btn(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_get_active_btn");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_msgbox_get_active_btn(mbox);
    lua_pushinteger(L, ret);
    return 1;
}

//  char* lv_msgbox_get_active_btn_text(lv_obj_t* mbox)
int luat_lv_msgbox_get_active_btn_text(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_get_active_btn_text");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_msgbox_get_active_btn_text(mbox);
    lua_pushstring(L, ret);
    return 1;
}

//  uint16_t lv_msgbox_get_anim_time(lv_obj_t* mbox)
int luat_lv_msgbox_get_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_get_anim_time");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_msgbox_get_anim_time(mbox);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_msgbox_get_recolor(lv_obj_t* mbox)
int luat_lv_msgbox_get_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_get_recolor");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_msgbox_get_recolor(mbox);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_obj_t* lv_msgbox_get_btnmatrix(lv_obj_t* mbox)
int luat_lv_msgbox_get_btnmatrix(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_get_btnmatrix");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_msgbox_get_btnmatrix(mbox);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

