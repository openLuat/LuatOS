
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_label_create(lv_obj_t* parent)
int luat_lv_label_create(lua_State *L) {
    LV_DEBUG("CALL lv_label_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_label_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_label_set_text(lv_obj_t* obj, char* text)
int luat_lv_label_set_text(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* text = (char*)luaL_checkstring(L, 2);
    lv_label_set_text(obj ,text);
    return 0;
}

//  void lv_label_set_text_static(lv_obj_t* obj, char* text)
int luat_lv_label_set_text_static(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_text_static");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* text = (char*)luaL_checkstring(L, 2);
    lv_label_set_text_static(obj ,text);
    return 0;
}

//  void lv_label_set_long_mode(lv_obj_t* obj, lv_label_long_mode_t long_mode)
int luat_lv_label_set_long_mode(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_long_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_long_mode_t long_mode = (lv_label_long_mode_t)luaL_checkinteger(L, 2);
    lv_label_set_long_mode(obj ,long_mode);
    return 0;
}

//  void lv_label_set_recolor(lv_obj_t* obj, bool en)
int luat_lv_label_set_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_recolor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_label_set_recolor(obj ,en);
    return 0;
}

//  void lv_label_set_text_sel_start(lv_obj_t* obj, uint32_t index)
int luat_lv_label_set_text_sel_start(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_text_sel_start");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t index = (uint32_t)luaL_checkinteger(L, 2);
    lv_label_set_text_sel_start(obj ,index);
    return 0;
}

//  void lv_label_set_text_sel_end(lv_obj_t* obj, uint32_t index)
int luat_lv_label_set_text_sel_end(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_text_sel_end");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t index = (uint32_t)luaL_checkinteger(L, 2);
    lv_label_set_text_sel_end(obj ,index);
    return 0;
}

//  char* lv_label_get_text(lv_obj_t* obj)
int luat_lv_label_get_text(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_label_get_text(obj);
    lua_pushstring(L, ret);
    return 1;
}

//  lv_label_long_mode_t lv_label_get_long_mode(lv_obj_t* obj)
int luat_lv_label_get_long_mode(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_long_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_long_mode_t ret;
    ret = lv_label_get_long_mode(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_label_get_recolor(lv_obj_t* obj)
int luat_lv_label_get_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_recolor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_label_get_recolor(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_label_get_letter_pos(lv_obj_t* obj, uint32_t char_id, lv_point_t* pos)
int luat_lv_label_get_letter_pos(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_letter_pos");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t char_id = (uint32_t)luaL_checkinteger(L, 2);
    lv_point_t* pos = (lv_point_t*)lua_touserdata(L, 3);
    lv_label_get_letter_pos(obj ,char_id ,pos);
    return 0;
}

//  uint32_t lv_label_get_letter_on(lv_obj_t* obj, lv_point_t* pos_in)
int luat_lv_label_get_letter_on(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_letter_on");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_point_t* pos_in = (lv_point_t*)lua_touserdata(L, 2);
    uint32_t ret;
    ret = lv_label_get_letter_on(obj ,pos_in);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_label_is_char_under_pos(lv_obj_t* obj, lv_point_t* pos)
int luat_lv_label_is_char_under_pos(lua_State *L) {
    LV_DEBUG("CALL lv_label_is_char_under_pos");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_point_t* pos = (lv_point_t*)lua_touserdata(L, 2);
    bool ret;
    ret = lv_label_is_char_under_pos(obj ,pos);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint32_t lv_label_get_text_selection_start(lv_obj_t* obj)
int luat_lv_label_get_text_selection_start(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_text_selection_start");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_label_get_text_selection_start(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint32_t lv_label_get_text_selection_end(lv_obj_t* obj)
int luat_lv_label_get_text_selection_end(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_text_selection_end");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_label_get_text_selection_end(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_label_ins_text(lv_obj_t* obj, uint32_t pos, char* txt)
int luat_lv_label_ins_text(lua_State *L) {
    LV_DEBUG("CALL lv_label_ins_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t pos = (uint32_t)luaL_checkinteger(L, 2);
    char* txt = (char*)luaL_checkstring(L, 3);
    lv_label_ins_text(obj ,pos ,txt);
    return 0;
}

//  void lv_label_cut_text(lv_obj_t* obj, uint32_t pos, uint32_t cnt)
int luat_lv_label_cut_text(lua_State *L) {
    LV_DEBUG("CALL lv_label_cut_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t pos = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t cnt = (uint32_t)luaL_checkinteger(L, 3);
    lv_label_cut_text(obj ,pos ,cnt);
    return 0;
}

