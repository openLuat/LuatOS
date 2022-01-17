
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_spangroup_create(lv_obj_t* par)
int luat_lv_spangroup_create(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_spangroup_create(par);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_span_t* lv_spangroup_new_span(lv_obj_t* obj)
int luat_lv_spangroup_new_span(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_new_span");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_span_t* ret = NULL;
    ret = lv_spangroup_new_span(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_spangroup_del_span(lv_obj_t* obj, lv_span_t* span)
int luat_lv_spangroup_del_span(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_del_span");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_span_t* span = (lv_span_t*)lua_touserdata(L, 2);
    lv_spangroup_del_span(obj ,span);
    return 0;
}

//  void lv_span_set_text(lv_span_t* span, char* text)
int luat_lv_span_set_text(lua_State *L) {
    LV_DEBUG("CALL lv_span_set_text");
    lv_span_t* span = (lv_span_t*)lua_touserdata(L, 1);
    char* text = (char*)luaL_checkstring(L, 2);
    lv_span_set_text(span ,text);
    return 0;
}

//  void lv_span_set_text_static(lv_span_t* span, char* text)
int luat_lv_span_set_text_static(lua_State *L) {
    LV_DEBUG("CALL lv_span_set_text_static");
    lv_span_t* span = (lv_span_t*)lua_touserdata(L, 1);
    char* text = (char*)luaL_checkstring(L, 2);
    lv_span_set_text_static(span ,text);
    return 0;
}

//  void lv_spangroup_set_align(lv_obj_t* obj, lv_text_align_t align)
int luat_lv_spangroup_set_align(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_set_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_text_align_t align = (lv_text_align_t)luaL_checkinteger(L, 2);
    lv_spangroup_set_align(obj ,align);
    return 0;
}

//  void lv_spangroup_set_overflow(lv_obj_t* obj, lv_span_overflow_t overflow)
int luat_lv_spangroup_set_overflow(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_set_overflow");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_span_overflow_t overflow;
    // miss arg convert
    lv_spangroup_set_overflow(obj ,overflow);
    return 0;
}

//  void lv_spangroup_set_indent(lv_obj_t* obj, lv_coord_t indent)
int luat_lv_spangroup_set_indent(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_set_indent");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t indent = (lv_coord_t)luaL_checknumber(L, 2);
    lv_spangroup_set_indent(obj ,indent);
    return 0;
}

//  void lv_spangroup_set_mode(lv_obj_t* obj, lv_span_mode_t mode)
int luat_lv_spangroup_set_mode(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_set_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_span_mode_t mode;
    // miss arg convert
    lv_spangroup_set_mode(obj ,mode);
    return 0;
}

//  lv_span_t* lv_spangroup_get_child(lv_obj_t* obj, int32_t id)
int luat_lv_spangroup_get_child(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_get_child");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t id = (int32_t)luaL_checkinteger(L, 2);
    lv_span_t* ret = NULL;
    ret = lv_spangroup_get_child(obj ,id);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  uint32_t lv_spangroup_get_child_cnt(lv_obj_t* obj)
int luat_lv_spangroup_get_child_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_get_child_cnt");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_spangroup_get_child_cnt(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_text_align_t lv_spangroup_get_align(lv_obj_t* obj)
int luat_lv_spangroup_get_align(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_get_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_text_align_t ret;
    ret = lv_spangroup_get_align(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_span_overflow_t lv_spangroup_get_overflow(lv_obj_t* obj)
int luat_lv_spangroup_get_overflow(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_get_overflow");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_span_overflow_t ret;
    ret = lv_spangroup_get_overflow(obj);
    return 0;
}

//  lv_coord_t lv_spangroup_get_indent(lv_obj_t* obj)
int luat_lv_spangroup_get_indent(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_get_indent");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_spangroup_get_indent(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_span_mode_t lv_spangroup_get_mode(lv_obj_t* obj)
int luat_lv_spangroup_get_mode(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_get_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_span_mode_t ret;
    ret = lv_spangroup_get_mode(obj);
    return 0;
}

//  lv_coord_t lv_spangroup_get_max_line_h(lv_obj_t* obj)
int luat_lv_spangroup_get_max_line_h(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_get_max_line_h");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_spangroup_get_max_line_h(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_spangroup_get_expand_width(lv_obj_t* obj)
int luat_lv_spangroup_get_expand_width(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_get_expand_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_spangroup_get_expand_width(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_spangroup_get_expand_height(lv_obj_t* obj, lv_coord_t width)
int luat_lv_spangroup_get_expand_height(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_get_expand_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t width = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t ret;
    ret = lv_spangroup_get_expand_height(obj ,width);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_spangroup_refr_mode(lv_obj_t* obj)
int luat_lv_spangroup_refr_mode(lua_State *L) {
    LV_DEBUG("CALL lv_spangroup_refr_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_spangroup_refr_mode(obj);
    return 0;
}

