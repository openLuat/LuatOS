
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_label_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_label_create(lua_State *L) {
    LV_DEBUG("CALL lv_label_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_label_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_label_set_text(lv_obj_t* label, char* text)
int luat_lv_label_set_text(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_text");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    char* text = (char*)luaL_checkstring(L, 2);
    lv_label_set_text(label ,text);
    return 0;
}

//  void lv_label_set_text_static(lv_obj_t* label, char* text)
int luat_lv_label_set_text_static(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_text_static");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    char* text = (char*)luaL_checkstring(L, 2);
    lv_label_set_text_static(label ,text);
    return 0;
}

//  void lv_label_set_long_mode(lv_obj_t* label, lv_label_long_mode_t long_mode)
int luat_lv_label_set_long_mode(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_long_mode");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_long_mode_t long_mode = (lv_label_long_mode_t)luaL_checkinteger(L, 2);
    lv_label_set_long_mode(label ,long_mode);
    return 0;
}

//  void lv_label_set_align(lv_obj_t* label, lv_label_align_t align)
int luat_lv_label_set_align(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_align");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_align_t align = (lv_label_align_t)luaL_checkinteger(L, 2);
    lv_label_set_align(label ,align);
    return 0;
}

//  void lv_label_set_recolor(lv_obj_t* label, bool en)
int luat_lv_label_set_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_recolor");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_label_set_recolor(label ,en);
    return 0;
}

//  void lv_label_set_anim_speed(lv_obj_t* label, uint16_t anim_speed)
int luat_lv_label_set_anim_speed(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_anim_speed");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t anim_speed = (uint16_t)luaL_checkinteger(L, 2);
    lv_label_set_anim_speed(label ,anim_speed);
    return 0;
}

//  void lv_label_set_text_sel_start(lv_obj_t* label, uint32_t index)
int luat_lv_label_set_text_sel_start(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_text_sel_start");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t index = (uint32_t)luaL_checkinteger(L, 2);
    lv_label_set_text_sel_start(label ,index);
    return 0;
}

//  void lv_label_set_text_sel_end(lv_obj_t* label, uint32_t index)
int luat_lv_label_set_text_sel_end(lua_State *L) {
    LV_DEBUG("CALL lv_label_set_text_sel_end");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t index = (uint32_t)luaL_checkinteger(L, 2);
    lv_label_set_text_sel_end(label ,index);
    return 0;
}

//  char* lv_label_get_text(lv_obj_t* label)
int luat_lv_label_get_text(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_text");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_label_get_text(label);
    lua_pushstring(L, ret);
    return 1;
}

//  lv_label_long_mode_t lv_label_get_long_mode(lv_obj_t* label)
int luat_lv_label_get_long_mode(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_long_mode");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_long_mode_t ret;
    ret = lv_label_get_long_mode(label);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_label_align_t lv_label_get_align(lv_obj_t* label)
int luat_lv_label_get_align(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_align");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_align_t ret;
    ret = lv_label_get_align(label);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_label_get_recolor(lv_obj_t* label)
int luat_lv_label_get_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_recolor");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_label_get_recolor(label);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint16_t lv_label_get_anim_speed(lv_obj_t* label)
int luat_lv_label_get_anim_speed(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_anim_speed");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_label_get_anim_speed(label);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_label_get_letter_pos(lv_obj_t* label, uint32_t index, lv_point_t* pos)
int luat_lv_label_get_letter_pos(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_letter_pos");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t index = (uint32_t)luaL_checkinteger(L, 2);
    lv_point_t* pos = (lv_point_t*)lua_touserdata(L, 3);
    lv_label_get_letter_pos(label ,index ,pos);
    return 0;
}

//  uint32_t lv_label_get_letter_on(lv_obj_t* label, lv_point_t* pos)
int luat_lv_label_get_letter_on(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_letter_on");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    lv_point_t* pos = (lv_point_t*)lua_touserdata(L, 2);
    uint32_t ret;
    ret = lv_label_get_letter_on(label ,pos);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_label_is_char_under_pos(lv_obj_t* label, lv_point_t* pos)
int luat_lv_label_is_char_under_pos(lua_State *L) {
    LV_DEBUG("CALL lv_label_is_char_under_pos");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    lv_point_t* pos = (lv_point_t*)lua_touserdata(L, 2);
    bool ret;
    ret = lv_label_is_char_under_pos(label ,pos);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint32_t lv_label_get_text_sel_start(lv_obj_t* label)
int luat_lv_label_get_text_sel_start(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_text_sel_start");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_label_get_text_sel_start(label);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint32_t lv_label_get_text_sel_end(lv_obj_t* label)
int luat_lv_label_get_text_sel_end(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_text_sel_end");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_label_get_text_sel_end(label);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_style_list_t* lv_label_get_style(lv_obj_t* label, uint8_t type)
int luat_lv_label_get_style(lua_State *L) {
    LV_DEBUG("CALL lv_label_get_style");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t type = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_list_t* ret = NULL;
    ret = lv_label_get_style(label ,type);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_label_ins_text(lv_obj_t* label, uint32_t pos, char* txt)
int luat_lv_label_ins_text(lua_State *L) {
    LV_DEBUG("CALL lv_label_ins_text");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t pos = (uint32_t)luaL_checkinteger(L, 2);
    char* txt = (char*)luaL_checkstring(L, 3);
    lv_label_ins_text(label ,pos ,txt);
    return 0;
}

//  void lv_label_cut_text(lv_obj_t* label, uint32_t pos, uint32_t cnt)
int luat_lv_label_cut_text(lua_State *L) {
    LV_DEBUG("CALL lv_label_cut_text");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t pos = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t cnt = (uint32_t)luaL_checkinteger(L, 3);
    lv_label_cut_text(label ,pos ,cnt);
    return 0;
}

//  void lv_label_refr_text(lv_obj_t* label)
int luat_lv_label_refr_text(lua_State *L) {
    LV_DEBUG("CALL lv_label_refr_text");
    lv_obj_t* label = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_refr_text(label);
    return 0;
}

