
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_btnmatrix_create(lv_obj_t* parent)
int luat_lv_btnmatrix_create(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_btnmatrix_create(parent);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  void lv_btnmatrix_set_selected_btn(lv_obj_t* obj, uint16_t btn_id)
int luat_lv_btnmatrix_set_selected_btn(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_selected_btn");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t btn_id = (uint16_t)luaL_checkinteger(L, 2);
    lv_btnmatrix_set_selected_btn(obj ,btn_id);
    return 0;
}

//  void lv_btnmatrix_set_btn_ctrl(lv_obj_t* obj, uint16_t btn_id, lv_btnmatrix_ctrl_t ctrl)
int luat_lv_btnmatrix_set_btn_ctrl(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_btn_ctrl");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t btn_id = (uint16_t)luaL_checkinteger(L, 2);
    lv_btnmatrix_ctrl_t ctrl;
    // miss arg convert
    lv_btnmatrix_set_btn_ctrl(obj ,btn_id ,ctrl);
    return 0;
}

//  void lv_btnmatrix_clear_btn_ctrl(lv_obj_t* obj, uint16_t btn_id, lv_btnmatrix_ctrl_t ctrl)
int luat_lv_btnmatrix_clear_btn_ctrl(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_clear_btn_ctrl");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t btn_id = (uint16_t)luaL_checkinteger(L, 2);
    lv_btnmatrix_ctrl_t ctrl;
    // miss arg convert
    lv_btnmatrix_clear_btn_ctrl(obj ,btn_id ,ctrl);
    return 0;
}

//  void lv_btnmatrix_set_btn_ctrl_all(lv_obj_t* obj, lv_btnmatrix_ctrl_t ctrl)
int luat_lv_btnmatrix_set_btn_ctrl_all(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_btn_ctrl_all");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btnmatrix_ctrl_t ctrl;
    // miss arg convert
    lv_btnmatrix_set_btn_ctrl_all(obj ,ctrl);
    return 0;
}

//  void lv_btnmatrix_clear_btn_ctrl_all(lv_obj_t* obj, lv_btnmatrix_ctrl_t ctrl)
int luat_lv_btnmatrix_clear_btn_ctrl_all(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_clear_btn_ctrl_all");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_btnmatrix_ctrl_t ctrl;
    // miss arg convert
    lv_btnmatrix_clear_btn_ctrl_all(obj ,ctrl);
    return 0;
}

//  void lv_btnmatrix_set_btn_width(lv_obj_t* obj, uint16_t btn_id, uint8_t width)
int luat_lv_btnmatrix_set_btn_width(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_btn_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t btn_id = (uint16_t)luaL_checkinteger(L, 2);
    uint8_t width = (uint8_t)luaL_checkinteger(L, 3);
    lv_btnmatrix_set_btn_width(obj ,btn_id ,width);
    return 0;
}

//  void lv_btnmatrix_set_one_checked(lv_obj_t* obj, bool en)
int luat_lv_btnmatrix_set_one_checked(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_set_one_checked");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_btnmatrix_set_one_checked(obj ,en);
    return 0;
}

//  uint16_t lv_btnmatrix_get_selected_btn(lv_obj_t* obj)
int luat_lv_btnmatrix_get_selected_btn(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_get_selected_btn");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_btnmatrix_get_selected_btn(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  char* lv_btnmatrix_get_btn_text(lv_obj_t* obj, uint16_t btn_id)
int luat_lv_btnmatrix_get_btn_text(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_get_btn_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t btn_id = (uint16_t)luaL_checkinteger(L, 2);
    char* ret = NULL;
    ret = lv_btnmatrix_get_btn_text(obj ,btn_id);
    lua_pushstring(L, ret);
    return 1;
}

//  bool lv_btnmatrix_has_btn_ctrl(lv_obj_t* obj, uint16_t btn_id, lv_btnmatrix_ctrl_t ctrl)
int luat_lv_btnmatrix_has_btn_ctrl(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_has_btn_ctrl");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t btn_id = (uint16_t)luaL_checkinteger(L, 2);
    lv_btnmatrix_ctrl_t ctrl;
    // miss arg convert
    bool ret;
    ret = lv_btnmatrix_has_btn_ctrl(obj ,btn_id ,ctrl);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_btnmatrix_get_one_checked(lv_obj_t* obj)
int luat_lv_btnmatrix_get_one_checked(lua_State *L) {
    LV_DEBUG("CALL lv_btnmatrix_get_one_checked");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_btnmatrix_get_one_checked(obj);
    lua_pushboolean(L, ret);
    return 1;
}

