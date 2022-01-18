
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_msgbox_get_title(lv_obj_t* obj)
int luat_lv_msgbox_get_title(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_get_title");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_msgbox_get_title(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_msgbox_get_close_btn(lv_obj_t* obj)
int luat_lv_msgbox_get_close_btn(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_get_close_btn");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_msgbox_get_close_btn(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_msgbox_get_text(lv_obj_t* obj)
int luat_lv_msgbox_get_text(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_get_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_msgbox_get_text(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_msgbox_get_content(lv_obj_t* obj)
int luat_lv_msgbox_get_content(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_get_content");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_msgbox_get_content(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_msgbox_get_btns(lv_obj_t* obj)
int luat_lv_msgbox_get_btns(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_get_btns");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_msgbox_get_btns(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
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

//  void lv_msgbox_close(lv_obj_t* mbox)
int luat_lv_msgbox_close(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_close");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    lv_msgbox_close(mbox);
    return 0;
}

//  void lv_msgbox_close_async(lv_obj_t* mbox)
int luat_lv_msgbox_close_async(lua_State *L) {
    LV_DEBUG("CALL lv_msgbox_close_async");
    lv_obj_t* mbox = (lv_obj_t*)lua_touserdata(L, 1);
    lv_msgbox_close_async(mbox);
    return 0;
}

