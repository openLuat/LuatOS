
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_btnmatrix_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_btnmatrix_create(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_btnmatrix_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_btnmatrix_set_focused_btn(lv_obj_t* btnm, uint16_t id)
int luat_lv_btnmatrix_set_focused_btn(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_focused_btn");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 2);
    lv_btnmatrix_set_focused_btn(btnm ,id);
    return 0;
}

//  void lv_btnmatrix_set_recolor(lv_obj_t* btnm, bool en)
int luat_lv_btnmatrix_set_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_recolor");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_btnmatrix_set_recolor(btnm ,en);
    return 0;
}

//  void lv_btnmatrix_set_btn_ctrl(lv_obj_t* btnm, uint16_t btn_id, lv_btnmatrix_ctrl_t ctrl)
int luat_lv_btnmatrix_set_btn_ctrl(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_btn_ctrl");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t btn_id = (uint16_t)luaL_checkinteger(L, 2);
    lv_btnmatrix_ctrl_t ctrl = (lv_btnmatrix_ctrl_t)luaL_checkinteger(L, 3);
    lv_btnmatrix_set_btn_ctrl(btnm ,btn_id ,ctrl);
    return 0;
}

//  void lv_btnmatrix_clear_btn_ctrl(lv_obj_t* btnm, uint16_t btn_id, lv_btnmatrix_ctrl_t ctrl)
int luat_lv_btnmatrix_clear_btn_ctrl(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_clear_btn_ctrl");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t btn_id = (uint16_t)luaL_checkinteger(L, 2);
    lv_btnmatrix_ctrl_t ctrl = (lv_btnmatrix_ctrl_t)luaL_checkinteger(L, 3);
    lv_btnmatrix_clear_btn_ctrl(btnm ,btn_id ,ctrl);
    return 0;
}

//  void lv_btnmatrix_set_btn_ctrl_all(lv_obj_t* btnm, lv_btnmatrix_ctrl_t ctrl)
int luat_lv_btnmatrix_set_btn_ctrl_all(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_btn_ctrl_all");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btnmatrix_ctrl_t ctrl = (lv_btnmatrix_ctrl_t)luaL_checkinteger(L, 2);
    lv_btnmatrix_set_btn_ctrl_all(btnm ,ctrl);
    return 0;
}

//  void lv_btnmatrix_clear_btn_ctrl_all(lv_obj_t* btnm, lv_btnmatrix_ctrl_t ctrl)
int luat_lv_btnmatrix_clear_btn_ctrl_all(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_clear_btn_ctrl_all");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btnmatrix_ctrl_t ctrl = (lv_btnmatrix_ctrl_t)luaL_checkinteger(L, 2);
    lv_btnmatrix_clear_btn_ctrl_all(btnm ,ctrl);
    return 0;
}

//  void lv_btnmatrix_set_btn_width(lv_obj_t* btnm, uint16_t btn_id, uint8_t width)
int luat_lv_btnmatrix_set_btn_width(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_btn_width");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t btn_id = (uint16_t)luaL_checkinteger(L, 2);
    uint8_t width = (uint8_t)luaL_checkinteger(L, 3);
    lv_btnmatrix_set_btn_width(btnm ,btn_id ,width);
    return 0;
}

//  void lv_btnmatrix_set_one_check(lv_obj_t* btnm, bool one_chk)
int luat_lv_btnmatrix_set_one_check(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_one_check");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    bool one_chk = (bool)lua_toboolean(L, 2);
    lv_btnmatrix_set_one_check(btnm ,one_chk);
    return 0;
}

//  void lv_btnmatrix_set_align(lv_obj_t* btnm, lv_label_align_t align)
int luat_lv_btnmatrix_set_align(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_align");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_align_t align = (lv_label_align_t)luaL_checkinteger(L, 2);
    lv_btnmatrix_set_align(btnm ,align);
    return 0;
}

//  bool lv_btnmatrix_get_recolor(lv_obj_t* btnm)
int luat_lv_btnmatrix_get_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_get_recolor");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_btnmatrix_get_recolor(btnm);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint16_t lv_btnmatrix_get_active_btn(lv_obj_t* btnm)
int luat_lv_btnmatrix_get_active_btn(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_get_active_btn");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_btnmatrix_get_active_btn(btnm);
    lua_pushinteger(L, ret);
    return 1;
}

//  char* lv_btnmatrix_get_active_btn_text(lv_obj_t* btnm)
int luat_lv_btnmatrix_get_active_btn_text(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_get_active_btn_text");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_btnmatrix_get_active_btn_text(btnm);
    lua_pushstring(L, ret);
    return 1;
}

//  uint16_t lv_btnmatrix_get_focused_btn(lv_obj_t* btnm)
int luat_lv_btnmatrix_get_focused_btn(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_get_focused_btn");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_btnmatrix_get_focused_btn(btnm);
    lua_pushinteger(L, ret);
    return 1;
}

//  char* lv_btnmatrix_get_btn_text(lv_obj_t* btnm, uint16_t btn_id)
int luat_lv_btnmatrix_get_btn_text(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_get_btn_text");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t btn_id = (uint16_t)luaL_checkinteger(L, 2);
    char* ret = NULL;
    ret = lv_btnmatrix_get_btn_text(btnm ,btn_id);
    lua_pushstring(L, ret);
    return 1;
}

//  bool lv_btnmatrix_get_btn_ctrl(lv_obj_t* btnm, uint16_t btn_id, lv_btnmatrix_ctrl_t ctrl)
int luat_lv_btnmatrix_get_btn_ctrl(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_get_btn_ctrl");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t btn_id = (uint16_t)luaL_checkinteger(L, 2);
    lv_btnmatrix_ctrl_t ctrl = (lv_btnmatrix_ctrl_t)luaL_checkinteger(L, 3);
    bool ret;
    ret = lv_btnmatrix_get_btn_ctrl(btnm ,btn_id ,ctrl);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_btnmatrix_get_one_check(lv_obj_t* btnm)
int luat_lv_btnmatrix_get_one_check(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_get_one_check");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_btnmatrix_get_one_check(btnm);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_label_align_t lv_btnmatrix_get_align(lv_obj_t* btnm)
int luat_lv_btnmatrix_get_align(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_get_align");
    lv_obj_t* btnm = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_align_t ret;
    ret = lv_btnmatrix_get_align(btnm);
    lua_pushinteger(L, ret);
    return 1;
}

