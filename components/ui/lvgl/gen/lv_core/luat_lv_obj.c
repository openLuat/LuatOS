

#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_obj_create(lv_obj_t* parent, lv_obj_t* copy)
int luat_lv_obj_create(lua_State *L) {
    LV_DEBUG("CALL lv_obj_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_obj_create(parent ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_res_t lv_obj_del(lv_obj_t* obj)
int luat_lv_obj_del(lua_State *L) {
    LV_DEBUG("CALL lv_obj_del");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_res_t ret;
    ret = lv_obj_del(obj);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  void lv_obj_del_async(lv_obj_t* obj)
int luat_lv_obj_del_async(lua_State *L) {
    LV_DEBUG("CALL lv_obj_del_async");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_del_async(obj);
    return 0;
}

//  void lv_obj_clean(lv_obj_t* obj)
int luat_lv_obj_clean(lua_State *L) {
    LV_DEBUG("CALL lv_obj_clean");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_clean(obj);
    return 0;
}

//  void lv_obj_invalidate_area(lv_obj_t* obj, lv_area_t* area)
int luat_lv_obj_invalidate_area(lua_State *L) {
    LV_DEBUG("CALL lv_obj_invalidate_area");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* area = (lv_area_t*)lua_touserdata(L, 2);
    lv_obj_invalidate_area(obj ,area);
    return 0;
}

//  void lv_obj_invalidate(lv_obj_t* obj)
int luat_lv_obj_invalidate(lua_State *L) {
    LV_DEBUG("CALL lv_obj_invalidate");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_invalidate(obj);
    return 0;
}

//  bool lv_obj_area_is_visible(lv_obj_t* obj, lv_area_t* area)
int luat_lv_obj_area_is_visible(lua_State *L) {
    LV_DEBUG("CALL lv_obj_area_is_visible");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* area = (lv_area_t*)lua_touserdata(L, 2);
    bool ret;
    ret = lv_obj_area_is_visible(obj ,area);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_is_visible(lv_obj_t* obj)
int luat_lv_obj_is_visible(lua_State *L) {
    LV_DEBUG("CALL lv_obj_is_visible");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_is_visible(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_obj_set_parent(lv_obj_t* obj, lv_obj_t* parent)
int luat_lv_obj_set_parent(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_parent");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_set_parent(obj ,parent);
    return 0;
}

//  void lv_obj_move_foreground(lv_obj_t* obj)
int luat_lv_obj_move_foreground(lua_State *L) {
    LV_DEBUG("CALL lv_obj_move_foreground");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_move_foreground(obj);
    return 0;
}

//  void lv_obj_move_background(lv_obj_t* obj)
int luat_lv_obj_move_background(lua_State *L) {
    LV_DEBUG("CALL lv_obj_move_background");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_move_background(obj);
    return 0;
}

//  void lv_obj_set_pos(lv_obj_t* obj, lv_coord_t x, lv_coord_t y)
int luat_lv_obj_set_pos(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_pos");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_obj_set_pos(obj ,x ,y);
    return 0;
}

//  void lv_obj_set_x(lv_obj_t* obj, lv_coord_t x)
int luat_lv_obj_set_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_set_x(obj ,x);
    return 0;
}

//  void lv_obj_set_y(lv_obj_t* obj, lv_coord_t y)
int luat_lv_obj_set_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_set_y(obj ,y);
    return 0;
}

//  void lv_obj_set_size(lv_obj_t* obj, lv_coord_t w, lv_coord_t h)
int luat_lv_obj_set_size(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_size");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 3);
    lv_obj_set_size(obj ,w ,h);
    return 0;
}

//  void lv_obj_set_width(lv_obj_t* obj, lv_coord_t w)
int luat_lv_obj_set_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_set_width(obj ,w);
    return 0;
}

//  void lv_obj_set_height(lv_obj_t* obj, lv_coord_t h)
int luat_lv_obj_set_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_set_height(obj ,h);
    return 0;
}

//  void lv_obj_set_width_fit(lv_obj_t* obj, lv_coord_t w)
int luat_lv_obj_set_width_fit(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_width_fit");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_set_width_fit(obj ,w);
    return 0;
}

//  void lv_obj_set_height_fit(lv_obj_t* obj, lv_coord_t h)
int luat_lv_obj_set_height_fit(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_height_fit");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_set_height_fit(obj ,h);
    return 0;
}

//  void lv_obj_set_width_margin(lv_obj_t* obj, lv_coord_t w)
int luat_lv_obj_set_width_margin(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_width_margin");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_set_width_margin(obj ,w);
    return 0;
}

//  void lv_obj_set_height_margin(lv_obj_t* obj, lv_coord_t h)
int luat_lv_obj_set_height_margin(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_height_margin");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_set_height_margin(obj ,h);
    return 0;
}

//  void lv_obj_align(lv_obj_t* obj, lv_obj_t* base, lv_align_t align, lv_coord_t x_ofs, lv_coord_t y_ofs)
int luat_lv_obj_align(lua_State *L) {
    LV_DEBUG("CALL lv_obj_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* base = (lv_obj_t*)lua_touserdata(L, 2);
    lv_align_t align = (lv_align_t)luaL_checkinteger(L, 3);
    lv_coord_t x_ofs = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t y_ofs = (lv_coord_t)luaL_checknumber(L, 5);
    lv_obj_align(obj ,base ,align ,x_ofs ,y_ofs);
    return 0;
}

//  void lv_obj_align_x(lv_obj_t* obj, lv_obj_t* base, lv_align_t align, lv_coord_t x_ofs)
int luat_lv_obj_align_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_align_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* base = (lv_obj_t*)lua_touserdata(L, 2);
    lv_align_t align = (lv_align_t)luaL_checkinteger(L, 3);
    lv_coord_t x_ofs = (lv_coord_t)luaL_checknumber(L, 4);
    lv_obj_align_x(obj ,base ,align ,x_ofs);
    return 0;
}

//  void lv_obj_align_y(lv_obj_t* obj, lv_obj_t* base, lv_align_t align, lv_coord_t y_ofs)
int luat_lv_obj_align_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_align_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* base = (lv_obj_t*)lua_touserdata(L, 2);
    lv_align_t align = (lv_align_t)luaL_checkinteger(L, 3);
    lv_coord_t y_ofs = (lv_coord_t)luaL_checknumber(L, 4);
    lv_obj_align_y(obj ,base ,align ,y_ofs);
    return 0;
}

//  void lv_obj_align_mid(lv_obj_t* obj, lv_obj_t* base, lv_align_t align, lv_coord_t x_ofs, lv_coord_t y_ofs)
int luat_lv_obj_align_mid(lua_State *L) {
    LV_DEBUG("CALL lv_obj_align_mid");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* base = (lv_obj_t*)lua_touserdata(L, 2);
    lv_align_t align = (lv_align_t)luaL_checkinteger(L, 3);
    lv_coord_t x_ofs = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t y_ofs = (lv_coord_t)luaL_checknumber(L, 5);
    lv_obj_align_mid(obj ,base ,align ,x_ofs ,y_ofs);
    return 0;
}

//  void lv_obj_align_mid_x(lv_obj_t* obj, lv_obj_t* base, lv_align_t align, lv_coord_t x_ofs)
int luat_lv_obj_align_mid_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_align_mid_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* base = (lv_obj_t*)lua_touserdata(L, 2);
    lv_align_t align = (lv_align_t)luaL_checkinteger(L, 3);
    lv_coord_t x_ofs = (lv_coord_t)luaL_checknumber(L, 4);
    lv_obj_align_mid_x(obj ,base ,align ,x_ofs);
    return 0;
}

//  void lv_obj_align_mid_y(lv_obj_t* obj, lv_obj_t* base, lv_align_t align, lv_coord_t y_ofs)
int luat_lv_obj_align_mid_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_align_mid_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* base = (lv_obj_t*)lua_touserdata(L, 2);
    lv_align_t align = (lv_align_t)luaL_checkinteger(L, 3);
    lv_coord_t y_ofs = (lv_coord_t)luaL_checknumber(L, 4);
    lv_obj_align_mid_y(obj ,base ,align ,y_ofs);
    return 0;
}

//  void lv_obj_realign(lv_obj_t* obj)
int luat_lv_obj_realign(lua_State *L) {
    LV_DEBUG("CALL lv_obj_realign");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_realign(obj);
    return 0;
}

//  void lv_obj_set_auto_realign(lv_obj_t* obj, bool en)
int luat_lv_obj_set_auto_realign(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_auto_realign");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_obj_set_auto_realign(obj ,en);
    return 0;
}

//  void lv_obj_set_ext_click_area(lv_obj_t* obj, lv_coord_t left, lv_coord_t right, lv_coord_t top, lv_coord_t bottom)
int luat_lv_obj_set_ext_click_area(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_ext_click_area");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t left = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t right = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t top = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t bottom = (lv_coord_t)luaL_checknumber(L, 5);
    lv_obj_set_ext_click_area(obj ,left ,right ,top ,bottom);
    return 0;
}

//  void lv_obj_add_style(lv_obj_t* obj, uint8_t part, lv_style_t* style)
int luat_lv_obj_add_style(lua_State *L) {
    LV_DEBUG("CALL lv_obj_add_style");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 3);
    lv_obj_add_style(obj ,part ,style);
    return 0;
}

//  void lv_obj_remove_style(lv_obj_t* obj, uint8_t part, lv_style_t* style)
int luat_lv_obj_remove_style(lua_State *L) {
    LV_DEBUG("CALL lv_obj_remove_style");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 3);
    lv_obj_remove_style(obj ,part ,style);
    return 0;
}

//  void lv_obj_clean_style_list(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_clean_style_list(lua_State *L) {
    LV_DEBUG("CALL lv_obj_clean_style_list");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_obj_clean_style_list(obj ,part);
    return 0;
}

//  void lv_obj_reset_style_list(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_reset_style_list(lua_State *L) {
    LV_DEBUG("CALL lv_obj_reset_style_list");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_obj_reset_style_list(obj ,part);
    return 0;
}

//  void lv_obj_refresh_style(lv_obj_t* obj, uint8_t part, lv_style_property_t prop)
int luat_lv_obj_refresh_style(lua_State *L) {
    LV_DEBUG("CALL lv_obj_refresh_style");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_property_t prop = (lv_style_property_t)luaL_checkinteger(L, 3);
    lv_obj_refresh_style(obj ,part ,prop);
    return 0;
}

//  void lv_obj_report_style_mod(lv_style_t* style)
int luat_lv_obj_report_style_mod(lua_State *L) {
    LV_DEBUG("CALL lv_obj_report_style_mod");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_obj_report_style_mod(style);
    return 0;
}

//  bool lv_obj_remove_style_local_prop(lv_obj_t* obj, uint8_t part, lv_style_property_t prop)
int luat_lv_obj_remove_style_local_prop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_remove_style_local_prop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_property_t prop = (lv_style_property_t)luaL_checkinteger(L, 3);
    bool ret;
    ret = lv_obj_remove_style_local_prop(obj ,part ,prop);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_obj_set_hidden(lv_obj_t* obj, bool en)
int luat_lv_obj_set_hidden(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_hidden");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_obj_set_hidden(obj ,en);
    return 0;
}

//  void lv_obj_set_adv_hittest(lv_obj_t* obj, bool en)
int luat_lv_obj_set_adv_hittest(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_adv_hittest");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_obj_set_adv_hittest(obj ,en);
    return 0;
}

//  void lv_obj_set_click(lv_obj_t* obj, bool en)
int luat_lv_obj_set_click(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_click");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_obj_set_click(obj ,en);
    return 0;
}

//  void lv_obj_set_top(lv_obj_t* obj, bool en)
int luat_lv_obj_set_top(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_top");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_obj_set_top(obj ,en);
    return 0;
}

//  void lv_obj_set_drag(lv_obj_t* obj, bool en)
int luat_lv_obj_set_drag(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_drag");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_obj_set_drag(obj ,en);
    return 0;
}

//  void lv_obj_set_drag_dir(lv_obj_t* obj, lv_drag_dir_t drag_dir)
int luat_lv_obj_set_drag_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_drag_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_drag_dir_t drag_dir = (lv_drag_dir_t)luaL_checkinteger(L, 2);
    lv_obj_set_drag_dir(obj ,drag_dir);
    return 0;
}

//  void lv_obj_set_drag_throw(lv_obj_t* obj, bool en)
int luat_lv_obj_set_drag_throw(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_drag_throw");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_obj_set_drag_throw(obj ,en);
    return 0;
}

//  void lv_obj_set_drag_parent(lv_obj_t* obj, bool en)
int luat_lv_obj_set_drag_parent(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_drag_parent");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_obj_set_drag_parent(obj ,en);
    return 0;
}

//  void lv_obj_set_focus_parent(lv_obj_t* obj, bool en)
int luat_lv_obj_set_focus_parent(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_focus_parent");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_obj_set_focus_parent(obj ,en);
    return 0;
}

//  void lv_obj_set_gesture_parent(lv_obj_t* obj, bool en)
int luat_lv_obj_set_gesture_parent(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_gesture_parent");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_obj_set_gesture_parent(obj ,en);
    return 0;
}

//  void lv_obj_set_parent_event(lv_obj_t* obj, bool en)
int luat_lv_obj_set_parent_event(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_parent_event");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_obj_set_parent_event(obj ,en);
    return 0;
}

//  void lv_obj_set_base_dir(lv_obj_t* obj, lv_bidi_dir_t dir)
int luat_lv_obj_set_base_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_base_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_bidi_dir_t dir = (lv_bidi_dir_t)luaL_checkinteger(L, 2);
    lv_obj_set_base_dir(obj ,dir);
    return 0;
}

//  void lv_obj_add_protect(lv_obj_t* obj, uint8_t prot)
int luat_lv_obj_add_protect(lua_State *L) {
    LV_DEBUG("CALL lv_obj_add_protect");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t prot = (uint8_t)luaL_checkinteger(L, 2);
    lv_obj_add_protect(obj ,prot);
    return 0;
}

//  void lv_obj_clear_protect(lv_obj_t* obj, uint8_t prot)
int luat_lv_obj_clear_protect(lua_State *L) {
    LV_DEBUG("CALL lv_obj_clear_protect");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t prot = (uint8_t)luaL_checkinteger(L, 2);
    lv_obj_clear_protect(obj ,prot);
    return 0;
}

//  void lv_obj_set_state(lv_obj_t* obj, lv_state_t state)
int luat_lv_obj_set_state(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_state");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_obj_set_state(obj ,state);
    return 0;
}

//  void lv_obj_add_state(lv_obj_t* obj, lv_state_t state)
int luat_lv_obj_add_state(lua_State *L) {
    LV_DEBUG("CALL lv_obj_add_state");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_obj_add_state(obj ,state);
    return 0;
}

//  void lv_obj_clear_state(lv_obj_t* obj, lv_state_t state)
int luat_lv_obj_clear_state(lua_State *L) {
    LV_DEBUG("CALL lv_obj_clear_state");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_obj_clear_state(obj ,state);
    return 0;
}

//  void lv_obj_finish_transitions(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_finish_transitions(lua_State *L) {
    LV_DEBUG("CALL lv_obj_finish_transitions");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_obj_finish_transitions(obj ,part);
    return 0;
}

//  void* lv_obj_allocate_ext_attr(lv_obj_t* obj, uint16_t ext_size)
int luat_lv_obj_allocate_ext_attr(lua_State *L) {
    LV_DEBUG("CALL lv_obj_allocate_ext_attr");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ext_size = (uint16_t)luaL_checkinteger(L, 2);
    void* ret = NULL;
    ret = lv_obj_allocate_ext_attr(obj ,ext_size);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_obj_refresh_ext_draw_pad(lv_obj_t* obj)
int luat_lv_obj_refresh_ext_draw_pad(lua_State *L) {
    LV_DEBUG("CALL lv_obj_refresh_ext_draw_pad");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_refresh_ext_draw_pad(obj);
    return 0;
}

//  lv_obj_t* lv_obj_get_screen(lv_obj_t* obj)
int luat_lv_obj_get_screen(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_screen");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_obj_get_screen(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_disp_t* lv_obj_get_disp(lv_obj_t* obj)
int luat_lv_obj_get_disp(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_disp");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_disp_t* ret = NULL;
    ret = lv_obj_get_disp(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_obj_get_parent(lv_obj_t* obj)
int luat_lv_obj_get_parent(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_parent");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_obj_get_parent(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_obj_get_child(lv_obj_t* obj, lv_obj_t* child)
int luat_lv_obj_get_child(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_child");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* child = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_obj_get_child(obj ,child);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_obj_get_child_back(lv_obj_t* obj, lv_obj_t* child)
int luat_lv_obj_get_child_back(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_child_back");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* child = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_obj_get_child_back(obj ,child);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  uint16_t lv_obj_count_children(lv_obj_t* obj)
int luat_lv_obj_count_children(lua_State *L) {
    LV_DEBUG("CALL lv_obj_count_children");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_obj_count_children(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_obj_count_children_recursive(lv_obj_t* obj)
int luat_lv_obj_count_children_recursive(lua_State *L) {
    LV_DEBUG("CALL lv_obj_count_children_recursive");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_obj_count_children_recursive(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_get_coords(lv_obj_t* obj, lv_area_t* cords_p)
int luat_lv_obj_get_coords(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_coords");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* cords_p = (lv_area_t*)lua_touserdata(L, 2);
    lv_obj_get_coords(obj ,cords_p);
    return 0;
}

//  void lv_obj_get_inner_coords(lv_obj_t* obj, lv_area_t* coords_p)
int luat_lv_obj_get_inner_coords(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_inner_coords");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* coords_p = (lv_area_t*)lua_touserdata(L, 2);
    lv_obj_get_inner_coords(obj ,coords_p);
    return 0;
}

//  lv_coord_t lv_obj_get_x(lv_obj_t* obj)
int luat_lv_obj_get_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_x(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_y(lv_obj_t* obj)
int luat_lv_obj_get_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_y(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_width(lv_obj_t* obj)
int luat_lv_obj_get_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_width(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_height(lv_obj_t* obj)
int luat_lv_obj_get_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_height(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_width_fit(lv_obj_t* obj)
int luat_lv_obj_get_width_fit(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_width_fit");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_width_fit(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_height_fit(lv_obj_t* obj)
int luat_lv_obj_get_height_fit(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_height_fit");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_height_fit(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_height_margin(lv_obj_t* obj)
int luat_lv_obj_get_height_margin(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_height_margin");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_height_margin(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_width_margin(lv_obj_t* obj)
int luat_lv_obj_get_width_margin(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_width_margin");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_width_margin(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_width_grid(lv_obj_t* obj, uint8_t div, uint8_t span)
int luat_lv_obj_get_width_grid(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_width_grid");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t div = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t span = (uint8_t)luaL_checkinteger(L, 3);
    lv_coord_t ret;
    ret = lv_obj_get_width_grid(obj ,div ,span);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_height_grid(lv_obj_t* obj, uint8_t div, uint8_t span)
int luat_lv_obj_get_height_grid(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_height_grid");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t div = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t span = (uint8_t)luaL_checkinteger(L, 3);
    lv_coord_t ret;
    ret = lv_obj_get_height_grid(obj ,div ,span);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_obj_get_auto_realign(lv_obj_t* obj)
int luat_lv_obj_get_auto_realign(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_auto_realign");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_get_auto_realign(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_ext_click_pad_left(lv_obj_t* obj)
int luat_lv_obj_get_ext_click_pad_left(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_ext_click_pad_left");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_ext_click_pad_left(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_ext_click_pad_right(lv_obj_t* obj)
int luat_lv_obj_get_ext_click_pad_right(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_ext_click_pad_right");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_ext_click_pad_right(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_ext_click_pad_top(lv_obj_t* obj)
int luat_lv_obj_get_ext_click_pad_top(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_ext_click_pad_top");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_ext_click_pad_top(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_ext_click_pad_bottom(lv_obj_t* obj)
int luat_lv_obj_get_ext_click_pad_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_ext_click_pad_bottom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_ext_click_pad_bottom(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_ext_draw_pad(lv_obj_t* obj)
int luat_lv_obj_get_ext_draw_pad(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_ext_draw_pad");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_ext_draw_pad(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_style_list_t* lv_obj_get_style_list(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_list(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_list");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_list_t* ret = NULL;
    ret = lv_obj_get_style_list(obj ,part);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_style_t* lv_obj_get_local_style(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_local_style(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_local_style");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_t* ret = NULL;
    ret = lv_obj_get_local_style(obj ,part);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_style_int_t lv_obj_get_style_radius(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_radius(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_radius");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_radius(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_radius(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_radius(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_radius");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_radius(obj ,part ,state ,value);
    return 0;
}

//  bool lv_obj_get_style_clip_corner(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_clip_corner(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_clip_corner");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_get_style_clip_corner(obj ,part);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_clip_corner(lv_obj_t* obj, uint8_t part, lv_state_t state, bool value)
int luat_lv_obj_set_style_local_clip_corner(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_clip_corner");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    bool value = (bool)lua_toboolean(L, 4);
    lv_obj_set_style_local_clip_corner(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_size(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_size(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_size");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_size(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_size(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_size(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_size");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_size(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transform_width(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transform_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transform_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transform_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transform_width(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transform_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transform_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transform_width(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transform_height(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transform_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transform_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transform_height(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transform_height(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transform_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transform_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transform_height(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transform_angle(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transform_angle(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transform_angle");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transform_angle(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transform_angle(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transform_angle(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transform_angle");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transform_angle(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transform_zoom(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transform_zoom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transform_zoom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transform_zoom(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transform_zoom(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transform_zoom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transform_zoom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transform_zoom(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_opa_scale(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_opa_scale(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_opa_scale");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_opa_scale(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_opa_scale(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_opa_scale(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_opa_scale");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_opa_scale(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_pad_top(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_pad_top(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pad_top");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_pad_top(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_pad_top(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_pad_top(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pad_top");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_pad_top(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_pad_bottom(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_pad_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pad_bottom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_pad_bottom(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_pad_bottom(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_pad_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pad_bottom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_pad_bottom(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_pad_left(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_pad_left(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pad_left");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_pad_left(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_pad_left(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_pad_left(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pad_left");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_pad_left(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_pad_right(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_pad_right(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pad_right");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_pad_right(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_pad_right(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_pad_right(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pad_right");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_pad_right(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_pad_inner(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_pad_inner(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pad_inner");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_pad_inner(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_pad_inner(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_pad_inner(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pad_inner");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_pad_inner(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_margin_top(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_margin_top(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_margin_top");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_margin_top(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_margin_top(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_margin_top(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_margin_top");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_margin_top(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_margin_bottom(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_margin_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_margin_bottom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_margin_bottom(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_margin_bottom(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_margin_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_margin_bottom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_margin_bottom(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_margin_left(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_margin_left(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_margin_left");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_margin_left(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_margin_left(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_margin_left(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_margin_left");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_margin_left(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_margin_right(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_margin_right(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_margin_right");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_margin_right(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_margin_right(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_margin_right(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_margin_right");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_margin_right(obj ,part ,state ,value);
    return 0;
}

//  lv_blend_mode_t lv_obj_get_style_bg_blend_mode(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_bg_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t ret;
    ret = lv_obj_get_style_bg_blend_mode(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_bg_blend_mode(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_blend_mode_t value)
int luat_lv_obj_set_style_local_bg_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_bg_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_blend_mode_t value = (lv_blend_mode_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_bg_blend_mode(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_bg_main_stop(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_bg_main_stop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_main_stop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_bg_main_stop(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_bg_main_stop(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_bg_main_stop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_bg_main_stop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_bg_main_stop(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_bg_grad_stop(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_bg_grad_stop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_grad_stop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_bg_grad_stop(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_bg_grad_stop(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_bg_grad_stop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_bg_grad_stop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_bg_grad_stop(obj ,part ,state ,value);
    return 0;
}

//  lv_grad_dir_t lv_obj_get_style_bg_grad_dir(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_bg_grad_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_grad_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_grad_dir_t ret;
    ret = lv_obj_get_style_bg_grad_dir(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_bg_grad_dir(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_grad_dir_t value)
int luat_lv_obj_set_style_local_bg_grad_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_bg_grad_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_grad_dir_t value = (lv_grad_dir_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_bg_grad_dir(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_bg_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_bg_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_bg_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_bg_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_bg_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_bg_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_bg_color(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_bg_grad_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_bg_grad_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_grad_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_bg_grad_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_bg_grad_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_bg_grad_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_bg_grad_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_bg_grad_color(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_bg_opa(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_bg_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_bg_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_bg_opa(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_bg_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_bg_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_bg_opa(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_border_width(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_border_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_border_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_border_width(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_border_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_border_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_border_width(obj ,part ,state ,value);
    return 0;
}

//  lv_border_side_t lv_obj_get_style_border_side(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_border_side(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_side");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_border_side_t ret;
    ret = lv_obj_get_style_border_side(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_border_side(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_border_side_t value)
int luat_lv_obj_set_style_local_border_side(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_border_side");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_border_side_t value = (lv_border_side_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_border_side(obj ,part ,state ,value);
    return 0;
}

//  lv_blend_mode_t lv_obj_get_style_border_blend_mode(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_border_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t ret;
    ret = lv_obj_get_style_border_blend_mode(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_border_blend_mode(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_blend_mode_t value)
int luat_lv_obj_set_style_local_border_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_border_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_blend_mode_t value = (lv_blend_mode_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_border_blend_mode(obj ,part ,state ,value);
    return 0;
}

//  bool lv_obj_get_style_border_post(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_border_post(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_post");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_get_style_border_post(obj ,part);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_border_post(lv_obj_t* obj, uint8_t part, lv_state_t state, bool value)
int luat_lv_obj_set_style_local_border_post(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_border_post");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    bool value = (bool)lua_toboolean(L, 4);
    lv_obj_set_style_local_border_post(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_border_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_border_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_border_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_border_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_border_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_border_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_border_color(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_border_opa(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_border_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_border_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_border_opa(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_border_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_border_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_border_opa(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_outline_width(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_outline_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_outline_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_outline_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_outline_width(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_outline_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_outline_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_outline_width(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_outline_pad(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_outline_pad(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_outline_pad");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_outline_pad(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_outline_pad(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_outline_pad(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_outline_pad");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_outline_pad(obj ,part ,state ,value);
    return 0;
}

//  lv_blend_mode_t lv_obj_get_style_outline_blend_mode(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_outline_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_outline_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t ret;
    ret = lv_obj_get_style_outline_blend_mode(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_outline_blend_mode(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_blend_mode_t value)
int luat_lv_obj_set_style_local_outline_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_outline_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_blend_mode_t value = (lv_blend_mode_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_outline_blend_mode(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_outline_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_outline_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_outline_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_outline_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_outline_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_outline_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_outline_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_outline_color(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_outline_opa(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_outline_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_outline_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_outline_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_outline_opa(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_outline_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_outline_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_outline_opa(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_shadow_width(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_shadow_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_shadow_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_shadow_width(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_shadow_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_shadow_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_shadow_width(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_shadow_ofs_x(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_shadow_ofs_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_ofs_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_shadow_ofs_x(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_shadow_ofs_x(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_shadow_ofs_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_shadow_ofs_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_shadow_ofs_x(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_shadow_ofs_y(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_shadow_ofs_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_ofs_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_shadow_ofs_y(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_shadow_ofs_y(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_shadow_ofs_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_shadow_ofs_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_shadow_ofs_y(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_shadow_spread(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_shadow_spread(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_spread");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_shadow_spread(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_shadow_spread(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_shadow_spread(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_shadow_spread");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_shadow_spread(obj ,part ,state ,value);
    return 0;
}

//  lv_blend_mode_t lv_obj_get_style_shadow_blend_mode(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_shadow_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t ret;
    ret = lv_obj_get_style_shadow_blend_mode(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_shadow_blend_mode(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_blend_mode_t value)
int luat_lv_obj_set_style_local_shadow_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_shadow_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_blend_mode_t value = (lv_blend_mode_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_shadow_blend_mode(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_shadow_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_shadow_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_shadow_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_shadow_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_shadow_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_shadow_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_shadow_color(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_shadow_opa(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_shadow_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_shadow_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_shadow_opa(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_shadow_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_shadow_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_shadow_opa(obj ,part ,state ,value);
    return 0;
}

//  bool lv_obj_get_style_pattern_repeat(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_pattern_repeat(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pattern_repeat");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_get_style_pattern_repeat(obj ,part);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_pattern_repeat(lv_obj_t* obj, uint8_t part, lv_state_t state, bool value)
int luat_lv_obj_set_style_local_pattern_repeat(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pattern_repeat");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    bool value = (bool)lua_toboolean(L, 4);
    lv_obj_set_style_local_pattern_repeat(obj ,part ,state ,value);
    return 0;
}

//  lv_blend_mode_t lv_obj_get_style_pattern_blend_mode(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_pattern_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pattern_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t ret;
    ret = lv_obj_get_style_pattern_blend_mode(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_pattern_blend_mode(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_blend_mode_t value)
int luat_lv_obj_set_style_local_pattern_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pattern_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_blend_mode_t value = (lv_blend_mode_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_pattern_blend_mode(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_pattern_recolor(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_pattern_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pattern_recolor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_pattern_recolor(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_pattern_recolor(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_pattern_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pattern_recolor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_pattern_recolor(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_pattern_opa(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_pattern_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pattern_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_pattern_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_pattern_opa(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_pattern_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pattern_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_pattern_opa(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_pattern_recolor_opa(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_pattern_recolor_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pattern_recolor_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_pattern_recolor_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_pattern_recolor_opa(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_pattern_recolor_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pattern_recolor_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_pattern_recolor_opa(obj ,part ,state ,value);
    return 0;
}

//  void* lv_obj_get_style_pattern_image(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_pattern_image(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pattern_image");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    void* ret = NULL;
    ret = lv_obj_get_style_pattern_image(obj ,part);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_obj_set_style_local_pattern_image(lv_obj_t* obj, uint8_t part, lv_state_t state, void* value)
int luat_lv_obj_set_style_local_pattern_image(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pattern_image");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    void* value = (void*)lua_touserdata(L, 4);
    lv_obj_set_style_local_pattern_image(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_value_letter_space(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_value_letter_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_value_letter_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_value_letter_space(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_value_letter_space(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_value_letter_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_value_letter_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_value_letter_space(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_value_line_space(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_value_line_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_value_line_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_value_line_space(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_value_line_space(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_value_line_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_value_line_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_value_line_space(obj ,part ,state ,value);
    return 0;
}

//  lv_blend_mode_t lv_obj_get_style_value_blend_mode(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_value_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_value_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t ret;
    ret = lv_obj_get_style_value_blend_mode(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_value_blend_mode(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_blend_mode_t value)
int luat_lv_obj_set_style_local_value_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_value_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_blend_mode_t value = (lv_blend_mode_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_value_blend_mode(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_value_ofs_x(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_value_ofs_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_value_ofs_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_value_ofs_x(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_value_ofs_x(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_value_ofs_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_value_ofs_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_value_ofs_x(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_value_ofs_y(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_value_ofs_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_value_ofs_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_value_ofs_y(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_value_ofs_y(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_value_ofs_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_value_ofs_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_value_ofs_y(obj ,part ,state ,value);
    return 0;
}

//  lv_align_t lv_obj_get_style_value_align(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_value_align(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_value_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_align_t ret;
    ret = lv_obj_get_style_value_align(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_value_align(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_align_t value)
int luat_lv_obj_set_style_local_value_align(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_value_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_align_t value = (lv_align_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_value_align(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_value_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_value_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_value_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_value_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_value_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_value_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_value_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_value_color(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_value_opa(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_value_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_value_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_value_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_value_opa(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_value_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_value_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_value_opa(obj ,part ,state ,value);
    return 0;
}

//  lv_font_t* lv_obj_get_style_value_font(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_value_font(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_value_font");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_font_t* ret = NULL;
    ret = lv_obj_get_style_value_font(obj ,part);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_obj_set_style_local_value_font(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_font_t* value)
int luat_lv_obj_set_style_local_value_font(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_value_font");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_font_t* value = (lv_font_t*)lua_touserdata(L, 4);
    lv_obj_set_style_local_value_font(obj ,part ,state ,value);
    return 0;
}

//  char* lv_obj_get_style_value_str(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_value_str(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_value_str");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    char* ret = NULL;
    ret = lv_obj_get_style_value_str(obj ,part);
    lua_pushstring(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_value_str(lv_obj_t* obj, uint8_t part, lv_state_t state, char* value)
int luat_lv_obj_set_style_local_value_str(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_value_str");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    char* value = (char*)luaL_checkstring(L, 4);
    lv_obj_set_style_local_value_str(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_text_letter_space(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_text_letter_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_letter_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_text_letter_space(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_text_letter_space(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_text_letter_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_text_letter_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_text_letter_space(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_text_line_space(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_text_line_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_line_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_text_line_space(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_text_line_space(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_text_line_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_text_line_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_text_line_space(obj ,part ,state ,value);
    return 0;
}

//  lv_text_decor_t lv_obj_get_style_text_decor(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_text_decor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_decor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_text_decor_t ret;
    ret = lv_obj_get_style_text_decor(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_text_decor(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_text_decor_t value)
int luat_lv_obj_set_style_local_text_decor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_text_decor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_text_decor_t value = (lv_text_decor_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_text_decor(obj ,part ,state ,value);
    return 0;
}

//  lv_blend_mode_t lv_obj_get_style_text_blend_mode(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_text_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t ret;
    ret = lv_obj_get_style_text_blend_mode(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_text_blend_mode(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_blend_mode_t value)
int luat_lv_obj_set_style_local_text_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_text_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_blend_mode_t value = (lv_blend_mode_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_text_blend_mode(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_text_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_text_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_text_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_text_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_text_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_text_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_text_color(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_text_sel_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_text_sel_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_sel_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_text_sel_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_text_sel_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_text_sel_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_text_sel_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_text_sel_color(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_text_sel_bg_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_text_sel_bg_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_sel_bg_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_text_sel_bg_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_text_sel_bg_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_text_sel_bg_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_text_sel_bg_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_text_sel_bg_color(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_text_opa(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_text_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_text_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_text_opa(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_text_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_text_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_text_opa(obj ,part ,state ,value);
    return 0;
}

//  lv_font_t* lv_obj_get_style_text_font(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_text_font(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_font");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_font_t* ret = NULL;
    ret = lv_obj_get_style_text_font(obj ,part);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_obj_set_style_local_text_font(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_font_t* value)
int luat_lv_obj_set_style_local_text_font(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_text_font");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_font_t* value = (lv_font_t*)lua_touserdata(L, 4);
    lv_obj_set_style_local_text_font(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_line_width(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_line_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_line_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_line_width(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_line_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_line_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_line_width(obj ,part ,state ,value);
    return 0;
}

//  lv_blend_mode_t lv_obj_get_style_line_blend_mode(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_line_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t ret;
    ret = lv_obj_get_style_line_blend_mode(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_line_blend_mode(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_blend_mode_t value)
int luat_lv_obj_set_style_local_line_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_line_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_blend_mode_t value = (lv_blend_mode_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_line_blend_mode(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_line_dash_width(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_line_dash_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_dash_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_line_dash_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_line_dash_width(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_line_dash_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_line_dash_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_line_dash_width(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_line_dash_gap(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_line_dash_gap(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_dash_gap");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_line_dash_gap(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_line_dash_gap(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_line_dash_gap(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_line_dash_gap");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_line_dash_gap(obj ,part ,state ,value);
    return 0;
}

//  bool lv_obj_get_style_line_rounded(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_line_rounded(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_rounded");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_get_style_line_rounded(obj ,part);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_line_rounded(lv_obj_t* obj, uint8_t part, lv_state_t state, bool value)
int luat_lv_obj_set_style_local_line_rounded(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_line_rounded");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    bool value = (bool)lua_toboolean(L, 4);
    lv_obj_set_style_local_line_rounded(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_line_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_line_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_line_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_line_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_line_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_line_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_line_color(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_line_opa(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_line_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_line_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_line_opa(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_line_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_line_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_line_opa(obj ,part ,state ,value);
    return 0;
}

//  lv_blend_mode_t lv_obj_get_style_image_blend_mode(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_image_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_image_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t ret;
    ret = lv_obj_get_style_image_blend_mode(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_image_blend_mode(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_blend_mode_t value)
int luat_lv_obj_set_style_local_image_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_image_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_blend_mode_t value = (lv_blend_mode_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_image_blend_mode(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_image_recolor(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_image_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_image_recolor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_image_recolor(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_image_recolor(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_image_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_image_recolor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_image_recolor(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_image_opa(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_image_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_image_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_image_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_image_opa(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_image_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_image_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_image_opa(obj ,part ,state ,value);
    return 0;
}

//  lv_opa_t lv_obj_get_style_image_recolor_opa(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_image_recolor_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_image_recolor_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_image_recolor_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_image_recolor_opa(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_opa_t value)
int luat_lv_obj_set_style_local_image_recolor_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_image_recolor_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 4);
    lv_obj_set_style_local_image_recolor_opa(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transition_time(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transition_time(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transition_time");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transition_time(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transition_time(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transition_time(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transition_time");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transition_time(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transition_delay(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transition_delay(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transition_delay");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transition_delay(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transition_delay(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transition_delay(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transition_delay");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transition_delay(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transition_prop_1(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transition_prop_1(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transition_prop_1");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transition_prop_1(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transition_prop_1(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transition_prop_1(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transition_prop_1");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transition_prop_1(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transition_prop_2(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transition_prop_2(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transition_prop_2");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transition_prop_2(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transition_prop_2(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transition_prop_2(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transition_prop_2");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transition_prop_2(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transition_prop_3(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transition_prop_3(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transition_prop_3");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transition_prop_3(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transition_prop_3(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transition_prop_3(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transition_prop_3");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transition_prop_3(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transition_prop_4(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transition_prop_4(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transition_prop_4");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transition_prop_4(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transition_prop_4(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transition_prop_4(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transition_prop_4");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transition_prop_4(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transition_prop_5(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transition_prop_5(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transition_prop_5");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transition_prop_5(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transition_prop_5(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transition_prop_5(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transition_prop_5");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transition_prop_5(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_transition_prop_6(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transition_prop_6(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transition_prop_6");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_transition_prop_6(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_transition_prop_6(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_transition_prop_6(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transition_prop_6");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_transition_prop_6(obj ,part ,state ,value);
    return 0;
}

#if LV_USE_ANIMATION
//  lv_anim_path_t* lv_obj_get_style_transition_path(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_transition_path(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transition_path");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_anim_path_t* ret = NULL;
    ret = lv_obj_get_style_transition_path(obj ,part);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_obj_set_style_local_transition_path(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_anim_path_t* value)
int luat_lv_obj_set_style_local_transition_path(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_transition_path");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_anim_path_t* value = (lv_anim_path_t*)lua_touserdata(L, 4);
    lv_obj_set_style_local_transition_path(obj ,part ,state ,value);
    return 0;
}
#endif

//  lv_style_int_t lv_obj_get_style_scale_width(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_scale_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_scale_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_scale_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_scale_width(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_scale_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_scale_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_scale_width(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_scale_border_width(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_scale_border_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_scale_border_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_scale_border_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_scale_border_width(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_scale_border_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_scale_border_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_scale_border_width(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_scale_end_border_width(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_scale_end_border_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_scale_end_border_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_scale_end_border_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_scale_end_border_width(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_scale_end_border_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_scale_end_border_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_scale_end_border_width(obj ,part ,state ,value);
    return 0;
}

//  lv_style_int_t lv_obj_get_style_scale_end_line_width(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_scale_end_line_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_scale_end_line_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_style_int_t ret;
    ret = lv_obj_get_style_scale_end_line_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_set_style_local_scale_end_line_width(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_scale_end_line_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_scale_end_line_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_scale_end_line_width(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_scale_grad_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_scale_grad_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_scale_grad_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_scale_grad_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_scale_grad_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_scale_grad_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_scale_grad_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_scale_grad_color(obj ,part ,state ,value);
    return 0;
}

//  lv_color_t lv_obj_get_style_scale_end_color(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_style_scale_end_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_scale_end_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_scale_end_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_obj_set_style_local_scale_end_color(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_color_t value)
int luat_lv_obj_set_style_local_scale_end_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_scale_end_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 4);
    lv_obj_set_style_local_scale_end_color(obj ,part ,state ,value);
    return 0;
}

//  void lv_obj_set_style_local_pad_all(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_pad_all(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pad_all");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_pad_all(obj ,part ,state ,value);
    return 0;
}

//  void lv_obj_set_style_local_pad_hor(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_pad_hor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pad_hor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_pad_hor(obj ,part ,state ,value);
    return 0;
}

//  void lv_obj_set_style_local_pad_ver(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_pad_ver(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_pad_ver");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_pad_ver(obj ,part ,state ,value);
    return 0;
}

//  void lv_obj_set_style_local_margin_all(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_margin_all(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_margin_all");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_margin_all(obj ,part ,state ,value);
    return 0;
}

//  void lv_obj_set_style_local_margin_hor(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_margin_hor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_margin_hor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_margin_hor(obj ,part ,state ,value);
    return 0;
}

//  void lv_obj_set_style_local_margin_ver(lv_obj_t* obj, uint8_t part, lv_state_t state, lv_style_int_t value)
int luat_lv_obj_set_style_local_margin_ver(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_local_margin_ver");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 3);
    lv_style_int_t value = (lv_style_int_t)luaL_checkinteger(L, 4);
    lv_obj_set_style_local_margin_ver(obj ,part ,state ,value);
    return 0;
}

//  bool lv_obj_get_hidden(lv_obj_t* obj)
int luat_lv_obj_get_hidden(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_hidden");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_get_hidden(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_get_adv_hittest(lv_obj_t* obj)
int luat_lv_obj_get_adv_hittest(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_adv_hittest");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_get_adv_hittest(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_get_click(lv_obj_t* obj)
int luat_lv_obj_get_click(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_click");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_get_click(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_get_top(lv_obj_t* obj)
int luat_lv_obj_get_top(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_top");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_get_top(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_get_drag(lv_obj_t* obj)
int luat_lv_obj_get_drag(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_drag");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_get_drag(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_drag_dir_t lv_obj_get_drag_dir(lv_obj_t* obj)
int luat_lv_obj_get_drag_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_drag_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_drag_dir_t ret;
    ret = lv_obj_get_drag_dir(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_obj_get_drag_throw(lv_obj_t* obj)
int luat_lv_obj_get_drag_throw(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_drag_throw");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_get_drag_throw(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_get_drag_parent(lv_obj_t* obj)
int luat_lv_obj_get_drag_parent(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_drag_parent");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_get_drag_parent(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_get_focus_parent(lv_obj_t* obj)
int luat_lv_obj_get_focus_parent(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_focus_parent");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_get_focus_parent(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_get_parent_event(lv_obj_t* obj)
int luat_lv_obj_get_parent_event(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_parent_event");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_get_parent_event(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_get_gesture_parent(lv_obj_t* obj)
int luat_lv_obj_get_gesture_parent(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_gesture_parent");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_get_gesture_parent(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_bidi_dir_t lv_obj_get_base_dir(lv_obj_t* obj)
int luat_lv_obj_get_base_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_base_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_bidi_dir_t ret;
    ret = lv_obj_get_base_dir(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint8_t lv_obj_get_protect(lv_obj_t* obj)
int luat_lv_obj_get_protect(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_protect");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t ret;
    ret = lv_obj_get_protect(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_obj_is_protected(lv_obj_t* obj, uint8_t prot)
int luat_lv_obj_is_protected(lua_State *L) {
    LV_DEBUG("CALL lv_obj_is_protected");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t prot = (uint8_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_is_protected(obj ,prot);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_state_t lv_obj_get_state(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_state(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_state");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_state_t ret;
    ret = lv_obj_get_state(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_obj_is_point_on_coords(lv_obj_t* obj, lv_point_t* point)
int luat_lv_obj_is_point_on_coords(lua_State *L) {
    LV_DEBUG("CALL lv_obj_is_point_on_coords");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_point_t* point = (lv_point_t*)lua_touserdata(L, 2);
    bool ret;
    ret = lv_obj_is_point_on_coords(obj ,point);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_hittest(lv_obj_t* obj, lv_point_t* point)
int luat_lv_obj_hittest(lua_State *L) {
    LV_DEBUG("CALL lv_obj_hittest");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_point_t* point = (lv_point_t*)lua_touserdata(L, 2);
    bool ret;
    ret = lv_obj_hittest(obj ,point);
    lua_pushboolean(L, ret);
    return 1;
}

//  void* lv_obj_get_ext_attr(lv_obj_t* obj)
int luat_lv_obj_get_ext_attr(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_ext_attr");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    void* ret = NULL;
    ret = lv_obj_get_ext_attr(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_obj_get_type(lv_obj_t* obj, lv_obj_type_t* buf)
int luat_lv_obj_get_type(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_type");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_type_t* buf = (lv_obj_type_t*)lua_touserdata(L, 2);
    lv_obj_get_type(obj ,buf);
    return 0;
}

//  lv_obj_user_data_t lv_obj_get_user_data(lv_obj_t* obj)
int luat_lv_obj_get_user_data(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_user_data");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_user_data_t ret;
    ret = lv_obj_get_user_data(obj);
    return 0;
}

//  lv_obj_user_data_t* lv_obj_get_user_data_ptr(lv_obj_t* obj)
int luat_lv_obj_get_user_data_ptr(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_user_data_ptr");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_user_data_t* ret = NULL;
    ret = lv_obj_get_user_data_ptr(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_obj_set_user_data(lv_obj_t* obj, lv_obj_user_data_t data)
int luat_lv_obj_set_user_data(lua_State *L) {
    // LV_DEBUG("CALL lv_obj_set_user_data");
    // lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    // lv_obj_user_data_t data;
    // miss arg convert
    // lv_obj_set_user_data(obj ,data);
    return 0;
}

//  void* lv_obj_get_group(lv_obj_t* obj)
int luat_lv_obj_get_group(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_group");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    void* ret = NULL;
    ret = lv_obj_get_group(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  bool lv_obj_is_focused(lv_obj_t* obj)
int luat_lv_obj_is_focused(lua_State *L) {
    LV_DEBUG("CALL lv_obj_is_focused");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_is_focused(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_obj_t* lv_obj_get_focused_obj(lv_obj_t* obj)
int luat_lv_obj_get_focused_obj(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_focused_obj");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_obj_get_focused_obj(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_res_t lv_obj_handle_get_type_signal(lv_obj_type_t* buf, char* name)
int luat_lv_obj_handle_get_type_signal(lua_State *L) {
    LV_DEBUG("CALL lv_obj_handle_get_type_signal");
    lv_obj_type_t* buf = (lv_obj_type_t*)lua_touserdata(L, 1);
    char* name = (char*)luaL_checkstring(L, 2);
    lv_res_t ret;
    ret = lv_obj_handle_get_type_signal(buf ,name);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  void lv_obj_init_draw_rect_dsc(lv_obj_t* obj, uint8_t type, lv_draw_rect_dsc_t* draw_dsc)
int luat_lv_obj_init_draw_rect_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_init_draw_rect_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t type = (uint8_t)luaL_checkinteger(L, 2);
    lv_draw_rect_dsc_t* draw_dsc = (lv_draw_rect_dsc_t*)lua_touserdata(L, 3);
    lv_obj_init_draw_rect_dsc(obj ,type ,draw_dsc);
    return 0;
}

//  void lv_obj_init_draw_label_dsc(lv_obj_t* obj, uint8_t type, lv_draw_label_dsc_t* draw_dsc)
int luat_lv_obj_init_draw_label_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_init_draw_label_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t type = (uint8_t)luaL_checkinteger(L, 2);
    lv_draw_label_dsc_t* draw_dsc = (lv_draw_label_dsc_t*)lua_touserdata(L, 3);
    lv_obj_init_draw_label_dsc(obj ,type ,draw_dsc);
    return 0;
}

//  void lv_obj_init_draw_img_dsc(lv_obj_t* obj, uint8_t part, lv_draw_img_dsc_t* draw_dsc)
int luat_lv_obj_init_draw_img_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_init_draw_img_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_draw_img_dsc_t* draw_dsc = (lv_draw_img_dsc_t*)lua_touserdata(L, 3);
    lv_obj_init_draw_img_dsc(obj ,part ,draw_dsc);
    return 0;
}

//  void lv_obj_init_draw_line_dsc(lv_obj_t* obj, uint8_t part, lv_draw_line_dsc_t* draw_dsc)
int luat_lv_obj_init_draw_line_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_init_draw_line_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_draw_line_dsc_t* draw_dsc = (lv_draw_line_dsc_t*)lua_touserdata(L, 3);
    lv_obj_init_draw_line_dsc(obj ,part ,draw_dsc);
    return 0;
}

//  lv_coord_t lv_obj_get_draw_rect_ext_pad_size(lv_obj_t* obj, uint8_t part)
int luat_lv_obj_get_draw_rect_ext_pad_size(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_draw_rect_ext_pad_size");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t part = (uint8_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_draw_rect_ext_pad_size(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_fade_in(lv_obj_t* obj, uint32_t time, uint32_t delay)
int luat_lv_obj_fade_in(lua_State *L) {
    LV_DEBUG("CALL lv_obj_fade_in");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t time = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t delay = (uint32_t)luaL_checkinteger(L, 3);
    lv_obj_fade_in(obj ,time ,delay);
    return 0;
}

//  void lv_obj_fade_out(lv_obj_t* obj, uint32_t time, uint32_t delay)
int luat_lv_obj_fade_out(lua_State *L) {
    LV_DEBUG("CALL lv_obj_fade_out");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t time = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t delay = (uint32_t)luaL_checkinteger(L, 3);
    lv_obj_fade_out(obj ,time ,delay);
    return 0;
}

