
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_imgbtn_create(lv_obj_t* parent)
int luat_lv_imgbtn_create(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_imgbtn_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_imgbtn_set_state(lv_obj_t* imgbtn, lv_imgbtn_state_t state)
int luat_lv_imgbtn_set_state(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_set_state");
    lv_obj_t* imgbtn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_imgbtn_state_t state;
    // miss arg convert
    lv_imgbtn_set_state(imgbtn ,state);
    return 0;
}

//  void* lv_imgbtn_get_src_left(lv_obj_t* imgbtn, lv_imgbtn_state_t state)
int luat_lv_imgbtn_get_src_left(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_get_src_left");
    lv_obj_t* imgbtn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_imgbtn_state_t state;
    // miss arg convert
    void* ret = NULL;
    ret = lv_imgbtn_get_src_left(imgbtn ,state);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void* lv_imgbtn_get_src_middle(lv_obj_t* imgbtn, lv_imgbtn_state_t state)
int luat_lv_imgbtn_get_src_middle(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_get_src_middle");
    lv_obj_t* imgbtn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_imgbtn_state_t state;
    // miss arg convert
    void* ret = NULL;
    ret = lv_imgbtn_get_src_middle(imgbtn ,state);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void* lv_imgbtn_get_src_right(lv_obj_t* imgbtn, lv_imgbtn_state_t state)
int luat_lv_imgbtn_get_src_right(lua_State *L) {
    LV_DEBUG("CALL lv_imgbtn_get_src_right");
    lv_obj_t* imgbtn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_imgbtn_state_t state;
    // miss arg convert
    void* ret = NULL;
    ret = lv_imgbtn_get_src_right(imgbtn ,state);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

