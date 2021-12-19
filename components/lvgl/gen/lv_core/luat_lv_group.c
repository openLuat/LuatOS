
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_group_t* lv_group_create()
int luat_lv_group_create(lua_State *L) {
    LV_DEBUG("CALL lv_group_create");
    lv_group_t* ret = NULL;
    ret = lv_group_create();
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_group_del(lv_group_t* group)
int luat_lv_group_del(lua_State *L) {
    LV_DEBUG("CALL lv_group_del");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    lv_group_del(group);
    return 0;
}

//  void lv_group_add_obj(lv_group_t* group, lv_obj_t* obj)
int luat_lv_group_add_obj(lua_State *L) {
    LV_DEBUG("CALL lv_group_add_obj");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 2);
    lv_group_add_obj(group ,obj);
    return 0;
}

//  void lv_group_remove_obj(lv_obj_t* obj)
int luat_lv_group_remove_obj(lua_State *L) {
    LV_DEBUG("CALL lv_group_remove_obj");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_group_remove_obj(obj);
    return 0;
}

//  void lv_group_remove_all_objs(lv_group_t* group)
int luat_lv_group_remove_all_objs(lua_State *L) {
    LV_DEBUG("CALL lv_group_remove_all_objs");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    lv_group_remove_all_objs(group);
    return 0;
}

//  void lv_group_focus_obj(lv_obj_t* obj)
int luat_lv_group_focus_obj(lua_State *L) {
    LV_DEBUG("CALL lv_group_focus_obj");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_group_focus_obj(obj);
    return 0;
}

//  void lv_group_focus_next(lv_group_t* group)
int luat_lv_group_focus_next(lua_State *L) {
    LV_DEBUG("CALL lv_group_focus_next");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    lv_group_focus_next(group);
    return 0;
}

//  void lv_group_focus_prev(lv_group_t* group)
int luat_lv_group_focus_prev(lua_State *L) {
    LV_DEBUG("CALL lv_group_focus_prev");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    lv_group_focus_prev(group);
    return 0;
}

//  void lv_group_focus_freeze(lv_group_t* group, bool en)
int luat_lv_group_focus_freeze(lua_State *L) {
    LV_DEBUG("CALL lv_group_focus_freeze");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_group_focus_freeze(group ,en);
    return 0;
}

//  lv_res_t lv_group_send_data(lv_group_t* group, uint32_t c)
int luat_lv_group_send_data(lua_State *L) {
    LV_DEBUG("CALL lv_group_send_data");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    uint32_t c = (uint32_t)luaL_checkinteger(L, 2);
    lv_res_t ret;
    ret = lv_group_send_data(group ,c);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  void lv_group_set_refocus_policy(lv_group_t* group, lv_group_refocus_policy_t policy)
int luat_lv_group_set_refocus_policy(lua_State *L) {
    LV_DEBUG("CALL lv_group_set_refocus_policy");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    lv_group_refocus_policy_t policy = luaL_checkinteger(L, 2);
    // miss arg convert
    lv_group_set_refocus_policy(group ,policy);
    return 0;
}

//  void lv_group_set_editing(lv_group_t* group, bool edit)
int luat_lv_group_set_editing(lua_State *L) {
    LV_DEBUG("CALL lv_group_set_editing");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    bool edit = (bool)lua_toboolean(L, 2);
    lv_group_set_editing(group ,edit);
    return 0;
}

//  void lv_group_set_click_focus(lv_group_t* group, bool en)
int luat_lv_group_set_click_focus(lua_State *L) {
    LV_DEBUG("CALL lv_group_set_click_focus");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_group_set_click_focus(group ,en);
    return 0;
}

//  void lv_group_set_wrap(lv_group_t* group, bool en)
int luat_lv_group_set_wrap(lua_State *L) {
    LV_DEBUG("CALL lv_group_set_wrap");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_group_set_wrap(group ,en);
    return 0;
}

//  lv_obj_t* lv_group_get_focused(lv_group_t* group)
int luat_lv_group_get_focused(lua_State *L) {
    LV_DEBUG("CALL lv_group_get_focused");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_group_get_focused(group);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_group_user_data_t* lv_group_get_user_data(lv_group_t* group)
int luat_lv_group_get_user_data(lua_State *L) {
    LV_DEBUG("CALL lv_group_get_user_data");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    lv_group_user_data_t* ret = NULL;
    ret = lv_group_get_user_data(group);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  bool lv_group_get_editing(lv_group_t* group)
int luat_lv_group_get_editing(lua_State *L) {
    LV_DEBUG("CALL lv_group_get_editing");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_group_get_editing(group);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_group_get_click_focus(lv_group_t* group)
int luat_lv_group_get_click_focus(lua_State *L) {
    LV_DEBUG("CALL lv_group_get_click_focus");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_group_get_click_focus(group);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_group_get_wrap(lv_group_t* group)
int luat_lv_group_get_wrap(lua_State *L) {
    LV_DEBUG("CALL lv_group_get_wrap");
    lv_group_t* group = (lv_group_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_group_get_wrap(group);
    lua_pushboolean(L, ret);
    return 1;
}
