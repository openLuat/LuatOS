
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_obj_del(lv_obj_t* obj)
int luat_lv_obj_del(lua_State *L) {
    LV_DEBUG("CALL lv_obj_del");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_del(obj);
    return 0;
}

//  void lv_obj_clean(lv_obj_t* obj)
int luat_lv_obj_clean(lua_State *L) {
    LV_DEBUG("CALL lv_obj_clean");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_clean(obj);
    return 0;
}

//  void lv_obj_del_delayed(lv_obj_t* obj, uint32_t delay_ms)
int luat_lv_obj_del_delayed(lua_State *L) {
    LV_DEBUG("CALL lv_obj_del_delayed");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t delay_ms = (uint32_t)luaL_checkinteger(L, 2);
    lv_obj_del_delayed(obj ,delay_ms);
    return 0;
}

//  void lv_obj_del_async(lv_obj_t* obj)
int luat_lv_obj_del_async(lua_State *L) {
    LV_DEBUG("CALL lv_obj_del_async");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_del_async(obj);
    return 0;
}

//  void lv_obj_set_parent(lv_obj_t* obj, lv_obj_t* parent)
int luat_lv_obj_set_parent(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_parent");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_set_parent(obj ,parent);
    return 0;
}

//  void lv_obj_swap(lv_obj_t* obj1, lv_obj_t* obj2)
int luat_lv_obj_swap(lua_State *L) {
    LV_DEBUG("CALL lv_obj_swap");
    lv_obj_t* obj1 = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* obj2 = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_swap(obj1 ,obj2);
    return 0;
}

//  void lv_obj_move_to_index(lv_obj_t* obj, int32_t index)
int luat_lv_obj_move_to_index(lua_State *L) {
    LV_DEBUG("CALL lv_obj_move_to_index");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t index = (int32_t)luaL_checkinteger(L, 2);
    lv_obj_move_to_index(obj ,index);
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

//  lv_obj_t* lv_obj_get_child(lv_obj_t* obj, int32_t id)
int luat_lv_obj_get_child(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_child");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t id = (int32_t)luaL_checkinteger(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_obj_get_child(obj ,id);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  uint32_t lv_obj_get_child_cnt(lv_obj_t* obj)
int luat_lv_obj_get_child_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_child_cnt");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_obj_get_child_cnt(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint32_t lv_obj_get_index(lv_obj_t* obj)
int luat_lv_obj_get_index(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_index");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_obj_get_index(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_tree_walk(lv_obj_t* start_obj, lv_obj_tree_walk_cb_t cb, void* user_data)
int luat_lv_obj_tree_walk(lua_State *L) {
    LV_DEBUG("CALL lv_obj_tree_walk");
    lv_obj_t* start_obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_tree_walk_cb_t cb;
    // miss arg convert
    void* user_data = (void*)lua_touserdata(L, 3);
    lv_obj_tree_walk(start_obj ,cb ,user_data);
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

//  bool lv_obj_refr_size(lv_obj_t* obj)
int luat_lv_obj_refr_size(lua_State *L) {
    LV_DEBUG("CALL lv_obj_refr_size");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_refr_size(obj);
    lua_pushboolean(L, ret);
    return 1;
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

//  void lv_obj_set_content_width(lv_obj_t* obj, lv_coord_t w)
int luat_lv_obj_set_content_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_content_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_set_content_width(obj ,w);
    return 0;
}

//  void lv_obj_set_content_height(lv_obj_t* obj, lv_coord_t h)
int luat_lv_obj_set_content_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_content_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_set_content_height(obj ,h);
    return 0;
}

//  void lv_obj_set_layout(lv_obj_t* obj, uint32_t layout)
int luat_lv_obj_set_layout(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_layout");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t layout = (uint32_t)luaL_checkinteger(L, 2);
    lv_obj_set_layout(obj ,layout);
    return 0;
}

//  bool lv_obj_is_layout_positioned(lv_obj_t* obj)
int luat_lv_obj_is_layout_positioned(lua_State *L) {
    LV_DEBUG("CALL lv_obj_is_layout_positioned");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_is_layout_positioned(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_obj_mark_layout_as_dirty(lv_obj_t* obj)
int luat_lv_obj_mark_layout_as_dirty(lua_State *L) {
    LV_DEBUG("CALL lv_obj_mark_layout_as_dirty");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_mark_layout_as_dirty(obj);
    return 0;
}

//  void lv_obj_update_layout(lv_obj_t* obj)
int luat_lv_obj_update_layout(lua_State *L) {
    LV_DEBUG("CALL lv_obj_update_layout");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_update_layout(obj);
    return 0;
}

//  void lv_obj_set_align(lv_obj_t* obj, lv_align_t align)
int luat_lv_obj_set_align(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_align_t align = (lv_align_t)luaL_checkinteger(L, 2);
    lv_obj_set_align(obj ,align);
    return 0;
}

//  void lv_obj_align(lv_obj_t* obj, lv_align_t align, lv_coord_t x_ofs, lv_coord_t y_ofs)
int luat_lv_obj_align(lua_State *L) {
    LV_DEBUG("CALL lv_obj_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_align_t align = (lv_align_t)luaL_checkinteger(L, 2);
    lv_coord_t x_ofs = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t y_ofs = (lv_coord_t)luaL_checknumber(L, 4);
    lv_obj_align(obj ,align ,x_ofs ,y_ofs);
    return 0;
}

//  void lv_obj_align_to(lv_obj_t* obj, lv_obj_t* base, lv_align_t align, lv_coord_t x_ofs, lv_coord_t y_ofs)
int luat_lv_obj_align_to(lua_State *L) {
    LV_DEBUG("CALL lv_obj_align_to");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* base = (lv_obj_t*)lua_touserdata(L, 2);
    lv_align_t align = (lv_align_t)luaL_checkinteger(L, 3);
    lv_coord_t x_ofs = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t y_ofs = (lv_coord_t)luaL_checknumber(L, 5);
    lv_obj_align_to(obj ,base ,align ,x_ofs ,y_ofs);
    return 0;
}

//  void lv_obj_center(lv_obj_t* obj)
int luat_lv_obj_center(lua_State *L) {
    LV_DEBUG("CALL lv_obj_center");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_center(obj);
    return 0;
}

//  void lv_obj_get_coords(lv_obj_t* obj, lv_area_t* coords)
int luat_lv_obj_get_coords(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_coords");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* coords = (lv_area_t*)lua_touserdata(L, 2);
    lv_obj_get_coords(obj ,coords);
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

//  lv_coord_t lv_obj_get_x2(lv_obj_t* obj)
int luat_lv_obj_get_x2(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_x2");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_x2(obj);
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

//  lv_coord_t lv_obj_get_y2(lv_obj_t* obj)
int luat_lv_obj_get_y2(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_y2");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_y2(obj);
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

//  lv_coord_t lv_obj_get_content_width(lv_obj_t* obj)
int luat_lv_obj_get_content_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_content_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_content_width(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_content_height(lv_obj_t* obj)
int luat_lv_obj_get_content_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_content_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_content_height(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_get_content_coords(lv_obj_t* obj, lv_area_t* area)
int luat_lv_obj_get_content_coords(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_content_coords");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* area = (lv_area_t*)lua_touserdata(L, 2);
    lv_obj_get_content_coords(obj ,area);
    return 0;
}

//  lv_coord_t lv_obj_get_self_width(lv_obj_t* obj)
int luat_lv_obj_get_self_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_self_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_self_width(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_self_height(lv_obj_t* obj)
int luat_lv_obj_get_self_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_self_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_self_height(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_obj_refresh_self_size(lv_obj_t* obj)
int luat_lv_obj_refresh_self_size(lua_State *L) {
    LV_DEBUG("CALL lv_obj_refresh_self_size");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_refresh_self_size(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_obj_refr_pos(lv_obj_t* obj)
int luat_lv_obj_refr_pos(lua_State *L) {
    LV_DEBUG("CALL lv_obj_refr_pos");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_refr_pos(obj);
    return 0;
}

//  void lv_obj_move_to(lv_obj_t* obj, lv_coord_t x, lv_coord_t y)
int luat_lv_obj_move_to(lua_State *L) {
    LV_DEBUG("CALL lv_obj_move_to");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_obj_move_to(obj ,x ,y);
    return 0;
}

//  void lv_obj_move_children_by(lv_obj_t* obj, lv_coord_t x_diff, lv_coord_t y_diff, bool ignore_floating)
int luat_lv_obj_move_children_by(lua_State *L) {
    LV_DEBUG("CALL lv_obj_move_children_by");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x_diff = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y_diff = (lv_coord_t)luaL_checknumber(L, 3);
    bool ignore_floating = (bool)lua_toboolean(L, 4);
    lv_obj_move_children_by(obj ,x_diff ,y_diff ,ignore_floating);
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

//  void lv_obj_set_ext_click_area(lv_obj_t* obj, lv_coord_t size)
int luat_lv_obj_set_ext_click_area(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_ext_click_area");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t size = (lv_coord_t)luaL_checknumber(L, 2);
    lv_obj_set_ext_click_area(obj ,size);
    return 0;
}

//  void lv_obj_get_click_area(lv_obj_t* obj, lv_area_t* area)
int luat_lv_obj_get_click_area(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_click_area");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* area = (lv_area_t*)lua_touserdata(L, 2);
    lv_obj_get_click_area(obj ,area);
    return 0;
}

//  bool lv_obj_hit_test(lv_obj_t* obj, lv_point_t* point)
int luat_lv_obj_hit_test(lua_State *L) {
    LV_DEBUG("CALL lv_obj_hit_test");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_point_t* point = (lv_point_t*)lua_touserdata(L, 2);
    bool ret;
    ret = lv_obj_hit_test(obj ,point);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_obj_set_scrollbar_mode(lv_obj_t* obj, lv_scrollbar_mode_t mode)
int luat_lv_obj_set_scrollbar_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_scrollbar_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scrollbar_mode_t mode = (lv_scrollbar_mode_t)luaL_checkinteger(L, 2);
    lv_obj_set_scrollbar_mode(obj ,mode);
    return 0;
}

//  void lv_obj_set_scroll_dir(lv_obj_t* obj, lv_dir_t dir)
int luat_lv_obj_set_scroll_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_scroll_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dir_t dir = (lv_dir_t)luaL_checkinteger(L, 2);
    lv_obj_set_scroll_dir(obj ,dir);
    return 0;
}

//  void lv_obj_set_scroll_snap_x(lv_obj_t* obj, lv_scroll_snap_t align)
int luat_lv_obj_set_scroll_snap_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_scroll_snap_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scroll_snap_t align = (lv_scroll_snap_t)luaL_checkinteger(L, 2);
    lv_obj_set_scroll_snap_x(obj ,align);
    return 0;
}

//  void lv_obj_set_scroll_snap_y(lv_obj_t* obj, lv_scroll_snap_t align)
int luat_lv_obj_set_scroll_snap_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_scroll_snap_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scroll_snap_t align = (lv_scroll_snap_t)luaL_checkinteger(L, 2);
    lv_obj_set_scroll_snap_y(obj ,align);
    return 0;
}

//  lv_scrollbar_mode_t lv_obj_get_scrollbar_mode(lv_obj_t* obj)
int luat_lv_obj_get_scrollbar_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scrollbar_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scrollbar_mode_t ret;
    ret = lv_obj_get_scrollbar_mode(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_dir_t lv_obj_get_scroll_dir(lv_obj_t* obj)
int luat_lv_obj_get_scroll_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scroll_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_dir_t ret;
    ret = lv_obj_get_scroll_dir(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_scroll_snap_t lv_obj_get_scroll_snap_x(lv_obj_t* obj)
int luat_lv_obj_get_scroll_snap_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scroll_snap_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scroll_snap_t ret;
    ret = lv_obj_get_scroll_snap_x(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_scroll_snap_t lv_obj_get_scroll_snap_y(lv_obj_t* obj)
int luat_lv_obj_get_scroll_snap_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scroll_snap_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scroll_snap_t ret;
    ret = lv_obj_get_scroll_snap_y(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_scroll_x(lv_obj_t* obj)
int luat_lv_obj_get_scroll_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scroll_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_scroll_x(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_scroll_y(lv_obj_t* obj)
int luat_lv_obj_get_scroll_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scroll_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_scroll_y(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_scroll_top(lv_obj_t* obj)
int luat_lv_obj_get_scroll_top(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scroll_top");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_scroll_top(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_scroll_bottom(lv_obj_t* obj)
int luat_lv_obj_get_scroll_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scroll_bottom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_scroll_bottom(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_scroll_left(lv_obj_t* obj)
int luat_lv_obj_get_scroll_left(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scroll_left");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_scroll_left(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_scroll_right(lv_obj_t* obj)
int luat_lv_obj_get_scroll_right(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scroll_right");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_scroll_right(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_get_scroll_end(lv_obj_t* obj, lv_point_t* end)
int luat_lv_obj_get_scroll_end(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scroll_end");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_point_t* end = (lv_point_t*)lua_touserdata(L, 2);
    lv_obj_get_scroll_end(obj ,end);
    return 0;
}

//  void lv_obj_scroll_by(lv_obj_t* obj, lv_coord_t x, lv_coord_t y, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_by(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_by");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)lua_toboolean(L, 4);
    lv_obj_scroll_by(obj ,x ,y ,anim_en);
    return 0;
}

//  void lv_obj_scroll_to(lv_obj_t* obj, lv_coord_t x, lv_coord_t y, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_to(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_to");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)lua_toboolean(L, 4);
    lv_obj_scroll_to(obj ,x ,y ,anim_en);
    return 0;
}

//  void lv_obj_scroll_to_x(lv_obj_t* obj, lv_coord_t x, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_to_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_to_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_obj_scroll_to_x(obj ,x ,anim_en);
    return 0;
}

//  void lv_obj_scroll_to_y(lv_obj_t* obj, lv_coord_t y, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_to_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_to_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 2);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_obj_scroll_to_y(obj ,y ,anim_en);
    return 0;
}

//  void lv_obj_scroll_to_view(lv_obj_t* obj, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_to_view(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_to_view");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)lua_toboolean(L, 2);
    lv_obj_scroll_to_view(obj ,anim_en);
    return 0;
}

//  void lv_obj_scroll_to_view_recursive(lv_obj_t* obj, lv_anim_enable_t anim_en)
int luat_lv_obj_scroll_to_view_recursive(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scroll_to_view_recursive");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)lua_toboolean(L, 2);
    lv_obj_scroll_to_view_recursive(obj ,anim_en);
    return 0;
}

//  bool lv_obj_is_scrolling(lv_obj_t* obj)
int luat_lv_obj_is_scrolling(lua_State *L) {
    LV_DEBUG("CALL lv_obj_is_scrolling");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_is_scrolling(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_obj_update_snap(lv_obj_t* obj, lv_anim_enable_t anim_en)
int luat_lv_obj_update_snap(lua_State *L) {
    LV_DEBUG("CALL lv_obj_update_snap");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)lua_toboolean(L, 2);
    lv_obj_update_snap(obj ,anim_en);
    return 0;
}

//  void lv_obj_get_scrollbar_area(lv_obj_t* obj, lv_area_t* hor, lv_area_t* ver)
int luat_lv_obj_get_scrollbar_area(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_scrollbar_area");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* hor = (lv_area_t*)lua_touserdata(L, 2);
    lv_area_t* ver = (lv_area_t*)lua_touserdata(L, 3);
    lv_obj_get_scrollbar_area(obj ,hor ,ver);
    return 0;
}

//  void lv_obj_scrollbar_invalidate(lv_obj_t* obj)
int luat_lv_obj_scrollbar_invalidate(lua_State *L) {
    LV_DEBUG("CALL lv_obj_scrollbar_invalidate");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_scrollbar_invalidate(obj);
    return 0;
}

//  void lv_obj_readjust_scroll(lv_obj_t* obj, lv_anim_enable_t anim_en)
int luat_lv_obj_readjust_scroll(lua_State *L) {
    LV_DEBUG("CALL lv_obj_readjust_scroll");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)lua_toboolean(L, 2);
    lv_obj_readjust_scroll(obj ,anim_en);
    return 0;
}

//  void lv_obj_add_style(lv_obj_t* obj, lv_style_t* style, lv_style_selector_t selector)
int luat_lv_obj_add_style(lua_State *L) {
    LV_DEBUG("CALL lv_obj_add_style");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_add_style(obj ,style ,selector);
    return 0;
}

//  void lv_obj_remove_style(lv_obj_t* obj, lv_style_t* style, lv_style_selector_t selector)
int luat_lv_obj_remove_style(lua_State *L) {
    LV_DEBUG("CALL lv_obj_remove_style");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_remove_style(obj ,style ,selector);
    return 0;
}

//  void lv_obj_remove_style_all(lv_obj_t* obj)
int luat_lv_obj_remove_style_all(lua_State *L) {
    LV_DEBUG("CALL lv_obj_remove_style_all");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_remove_style_all(obj);
    return 0;
}

//  void lv_obj_report_style_change(lv_style_t* style)
int luat_lv_obj_report_style_change(lua_State *L) {
    LV_DEBUG("CALL lv_obj_report_style_change");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_obj_report_style_change(style);
    return 0;
}

//  void lv_obj_refresh_style(lv_obj_t* obj, lv_part_t part, lv_style_prop_t prop)
int luat_lv_obj_refresh_style(lua_State *L) {
    LV_DEBUG("CALL lv_obj_refresh_style");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_part_t part = (lv_part_t)luaL_checkinteger(L, 2);
    lv_style_prop_t prop = (lv_style_prop_t)luaL_checkinteger(L, 3);
    lv_obj_refresh_style(obj ,part ,prop);
    return 0;
}

//  void lv_obj_enable_style_refresh(bool en)
int luat_lv_obj_enable_style_refresh(lua_State *L) {
    LV_DEBUG("CALL lv_obj_enable_style_refresh");
    bool en = (bool)lua_toboolean(L, 1);
    lv_obj_enable_style_refresh(en);
    return 0;
}

//  lv_style_value_t lv_obj_get_style_prop(lv_obj_t* obj, lv_part_t part, lv_style_prop_t prop)
int luat_lv_obj_get_style_prop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_prop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_part_t part = (lv_part_t)luaL_checkinteger(L, 2);
    lv_style_prop_t prop = (lv_style_prop_t)luaL_checkinteger(L, 3);
    lv_style_value_t ret;
    ret = lv_obj_get_style_prop(obj ,part ,prop);
    return 0;
}

//  void lv_obj_set_local_style_prop(lv_obj_t* obj, lv_style_prop_t prop, lv_style_value_t value, lv_style_selector_t selector)
int luat_lv_obj_set_local_style_prop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_local_style_prop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_style_prop_t prop = (lv_style_prop_t)luaL_checkinteger(L, 2);
    lv_style_value_t value;
    // miss arg convert
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 4);
    lv_obj_set_local_style_prop(obj ,prop ,value ,selector);
    return 0;
}

//  lv_res_t lv_obj_get_local_style_prop(lv_obj_t* obj, lv_style_prop_t prop, lv_style_value_t* value, lv_style_selector_t selector)
int luat_lv_obj_get_local_style_prop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_local_style_prop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_style_prop_t prop = (lv_style_prop_t)luaL_checkinteger(L, 2);
    lv_style_value_t* value = (lv_style_value_t*)lua_touserdata(L, 3);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 4);
    lv_res_t ret;
    ret = lv_obj_get_local_style_prop(obj ,prop ,value ,selector);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  bool lv_obj_remove_local_style_prop(lv_obj_t* obj, lv_style_prop_t prop, lv_style_selector_t selector)
int luat_lv_obj_remove_local_style_prop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_remove_local_style_prop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_style_prop_t prop = (lv_style_prop_t)luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    bool ret;
    ret = lv_obj_remove_local_style_prop(obj ,prop ,selector);
    lua_pushboolean(L, ret);
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

//  lv_state_t lv_obj_style_get_selector_state(lv_style_selector_t selector)
int luat_lv_obj_style_get_selector_state(lua_State *L) {
    LV_DEBUG("CALL lv_obj_style_get_selector_state");
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 1);
    lv_state_t ret;
    ret = lv_obj_style_get_selector_state(selector);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_part_t lv_obj_style_get_selector_part(lv_style_selector_t selector)
int luat_lv_obj_style_get_selector_part(lua_State *L) {
    LV_DEBUG("CALL lv_obj_style_get_selector_part");
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 1);
    lv_part_t ret;
    ret = lv_obj_style_get_selector_part(selector);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_width(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_min_width(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_min_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_min_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_min_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_max_width(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_max_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_max_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_max_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_height(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_height(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_min_height(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_min_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_min_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_min_height(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_max_height(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_max_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_max_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_max_height(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_x(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_x(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_y(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_y(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_align_t lv_obj_get_style_align(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_align(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_align_t ret;
    ret = lv_obj_get_style_align(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_transform_width(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_transform_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transform_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_transform_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_transform_height(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_transform_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transform_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_transform_height(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_translate_x(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_translate_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_translate_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_translate_x(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_translate_y(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_translate_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_translate_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_translate_y(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_transform_zoom(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_transform_zoom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transform_zoom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_transform_zoom(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_transform_angle(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_transform_angle(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transform_angle");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_transform_angle(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_pad_top(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_pad_top(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pad_top");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_pad_top(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_pad_bottom(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_pad_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pad_bottom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_pad_bottom(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_pad_left(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_pad_left(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pad_left");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_pad_left(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_pad_right(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_pad_right(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pad_right");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_pad_right(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_pad_row(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_pad_row(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pad_row");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_pad_row(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_pad_column(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_pad_column(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_pad_column");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_pad_column(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_radius(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_radius(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_radius");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_radius(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_obj_get_style_clip_corner(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_clip_corner(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_clip_corner");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_get_style_clip_corner(obj ,part);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_opa_t lv_obj_get_style_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_color_filter_dsc_t* lv_obj_get_style_color_filter_dsc(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_color_filter_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_color_filter_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_filter_dsc_t* ret = NULL;
    ret = lv_obj_get_style_color_filter_dsc(obj ,part);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_opa_t lv_obj_get_style_color_filter_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_color_filter_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_color_filter_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_color_filter_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint32_t lv_obj_get_style_anim_time(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_anim_time");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t ret;
    ret = lv_obj_get_style_anim_time(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint32_t lv_obj_get_style_anim_speed(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_anim_speed(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_anim_speed");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t ret;
    ret = lv_obj_get_style_anim_speed(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_style_transition_dsc_t* lv_obj_get_style_transition(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_transition(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_transition");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_style_transition_dsc_t* ret = NULL;
    ret = lv_obj_get_style_transition(obj ,part);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_blend_mode_t lv_obj_get_style_blend_mode(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t ret;
    ret = lv_obj_get_style_blend_mode(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_obj_get_style_layout(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_layout(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_layout");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    uint16_t ret;
    ret = lv_obj_get_style_layout(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_base_dir_t lv_obj_get_style_base_dir(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_base_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_base_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_base_dir_t ret;
    ret = lv_obj_get_style_base_dir(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_color_t lv_obj_get_style_bg_color(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_bg_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_obj_get_style_bg_color_filtered(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_bg_color_filtered(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_opa_t lv_obj_get_style_bg_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_bg_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_color_t lv_obj_get_style_bg_grad_color(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_grad_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_grad_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_bg_grad_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_obj_get_style_bg_grad_color_filtered(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_grad_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_grad_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_bg_grad_color_filtered(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_grad_dir_t lv_obj_get_style_bg_grad_dir(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_grad_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_grad_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_grad_dir_t ret;
    ret = lv_obj_get_style_bg_grad_dir(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_bg_main_stop(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_main_stop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_main_stop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_bg_main_stop(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_bg_grad_stop(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_grad_stop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_grad_stop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_bg_grad_stop(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void* lv_obj_get_style_bg_img_src(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_img_src(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_img_src");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    void* ret = NULL;
    ret = lv_obj_get_style_bg_img_src(obj ,part);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_opa_t lv_obj_get_style_bg_img_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_img_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_img_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_bg_img_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_color_t lv_obj_get_style_bg_img_recolor(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_img_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_img_recolor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_bg_img_recolor(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_obj_get_style_bg_img_recolor_filtered(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_img_recolor_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_img_recolor_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_bg_img_recolor_filtered(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_opa_t lv_obj_get_style_bg_img_recolor_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_img_recolor_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_img_recolor_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_bg_img_recolor_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_obj_get_style_bg_img_tiled(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_bg_img_tiled(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_bg_img_tiled");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_get_style_bg_img_tiled(obj ,part);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_color_t lv_obj_get_style_border_color(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_border_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_border_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_obj_get_style_border_color_filtered(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_border_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_border_color_filtered(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_opa_t lv_obj_get_style_border_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_border_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_border_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_border_width(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_border_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_border_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_border_side_t lv_obj_get_style_border_side(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_border_side(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_side");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_border_side_t ret;
    ret = lv_obj_get_style_border_side(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_obj_get_style_border_post(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_border_post(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_border_post");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_get_style_border_post(obj ,part);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_color_t lv_obj_get_style_text_color(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_text_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_text_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_obj_get_style_text_color_filtered(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_text_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_text_color_filtered(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_opa_t lv_obj_get_style_text_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_text_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_text_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_font_t* lv_obj_get_style_text_font(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_text_font(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_font");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_font_t* ret = NULL;
    ret = lv_obj_get_style_text_font(obj ,part);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_coord_t lv_obj_get_style_text_letter_space(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_text_letter_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_letter_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_text_letter_space(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_text_line_space(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_text_line_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_line_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_text_line_space(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_text_decor_t lv_obj_get_style_text_decor(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_text_decor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_decor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_text_decor_t ret;
    ret = lv_obj_get_style_text_decor(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_text_align_t lv_obj_get_style_text_align(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_text_align(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_text_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_text_align_t ret;
    ret = lv_obj_get_style_text_align(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_opa_t lv_obj_get_style_img_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_img_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_img_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_img_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_color_t lv_obj_get_style_img_recolor(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_img_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_img_recolor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_img_recolor(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_obj_get_style_img_recolor_filtered(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_img_recolor_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_img_recolor_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_img_recolor_filtered(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_opa_t lv_obj_get_style_img_recolor_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_img_recolor_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_img_recolor_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_img_recolor_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_outline_width(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_outline_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_outline_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_outline_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_color_t lv_obj_get_style_outline_color(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_outline_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_outline_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_outline_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_obj_get_style_outline_color_filtered(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_outline_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_outline_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_outline_color_filtered(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_opa_t lv_obj_get_style_outline_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_outline_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_outline_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_outline_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_outline_pad(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_outline_pad(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_outline_pad");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_outline_pad(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_shadow_width(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_shadow_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_shadow_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_shadow_ofs_x(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_shadow_ofs_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_ofs_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_shadow_ofs_x(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_shadow_ofs_y(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_shadow_ofs_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_ofs_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_shadow_ofs_y(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_shadow_spread(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_shadow_spread(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_spread");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_shadow_spread(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_color_t lv_obj_get_style_shadow_color(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_shadow_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_shadow_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_obj_get_style_shadow_color_filtered(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_shadow_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_shadow_color_filtered(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_opa_t lv_obj_get_style_shadow_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_shadow_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_shadow_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_shadow_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_line_width(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_line_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_line_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_line_dash_width(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_line_dash_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_dash_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_line_dash_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_line_dash_gap(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_line_dash_gap(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_dash_gap");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_line_dash_gap(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_obj_get_style_line_rounded(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_line_rounded(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_rounded");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_get_style_line_rounded(obj ,part);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_color_t lv_obj_get_style_line_color(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_line_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_line_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_obj_get_style_line_color_filtered(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_line_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_line_color_filtered(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_opa_t lv_obj_get_style_line_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_line_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_line_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_line_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_style_arc_width(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_arc_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_arc_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_get_style_arc_width(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_obj_get_style_arc_rounded(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_arc_rounded(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_arc_rounded");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_get_style_arc_rounded(obj ,part);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_color_t lv_obj_get_style_arc_color(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_arc_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_arc_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_arc_color(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_obj_get_style_arc_color_filtered(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_arc_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_arc_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_color_t ret;
    ret = lv_obj_get_style_arc_color_filtered(obj ,part);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_opa_t lv_obj_get_style_arc_opa(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_arc_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_arc_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_opa_t ret;
    ret = lv_obj_get_style_arc_opa(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void* lv_obj_get_style_arc_img_src(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_get_style_arc_img_src(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_style_arc_img_src");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    void* ret = NULL;
    ret = lv_obj_get_style_arc_img_src(obj ,part);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_obj_set_style_width(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_width(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_min_width(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_min_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_min_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_min_width(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_max_width(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_max_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_max_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_max_width(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_height(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_height(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_min_height(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_min_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_min_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_min_height(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_max_height(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_max_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_max_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_max_height(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_x(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_x(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_y(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_y(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_align(lv_obj_t* obj, lv_align_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_align(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_align_t value = (lv_align_t)luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_align(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_transform_width(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_transform_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_transform_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_transform_width(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_transform_height(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_transform_height(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_transform_height");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_transform_height(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_translate_x(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_translate_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_translate_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_translate_x(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_translate_y(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_translate_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_translate_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_translate_y(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_transform_zoom(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_transform_zoom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_transform_zoom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_transform_zoom(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_transform_angle(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_transform_angle(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_transform_angle");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_transform_angle(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_pad_top(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_pad_top(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_pad_top");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_pad_top(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_pad_bottom(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_pad_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_pad_bottom");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_pad_bottom(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_pad_left(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_pad_left(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_pad_left");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_pad_left(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_pad_right(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_pad_right(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_pad_right");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_pad_right(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_pad_row(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_pad_row(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_pad_row");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_pad_row(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_pad_column(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_pad_column(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_pad_column");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_pad_column(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_radius(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_radius(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_radius");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_radius(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_clip_corner(lv_obj_t* obj, bool value, lv_style_selector_t selector)
int luat_lv_obj_set_style_clip_corner(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_clip_corner");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool value = (bool)lua_toboolean(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_clip_corner(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_color_filter_dsc(lv_obj_t* obj, lv_color_filter_dsc_t* value, lv_style_selector_t selector)
int luat_lv_obj_set_style_color_filter_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_color_filter_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_filter_dsc_t* value = (lv_color_filter_dsc_t*)lua_touserdata(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_color_filter_dsc(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_color_filter_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_color_filter_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_color_filter_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_color_filter_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_anim_time(lv_obj_t* obj, uint32_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_anim_time");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t value = (uint32_t)luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_anim_time(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_anim_speed(lv_obj_t* obj, uint32_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_anim_speed(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_anim_speed");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t value = (uint32_t)luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_anim_speed(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_transition(lv_obj_t* obj, lv_style_transition_dsc_t* value, lv_style_selector_t selector)
int luat_lv_obj_set_style_transition(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_transition");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_style_transition_dsc_t* value = (lv_style_transition_dsc_t*)lua_touserdata(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_transition(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_blend_mode(lv_obj_t* obj, lv_blend_mode_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_blend_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_blend_mode_t value = (lv_blend_mode_t)luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_blend_mode(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_layout(lv_obj_t* obj, uint16_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_layout(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_layout");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t value = (uint16_t)luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_layout(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_base_dir(lv_obj_t* obj, lv_base_dir_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_base_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_base_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_base_dir_t value = (lv_base_dir_t)luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_base_dir(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_color(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_color(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_color_filtered(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_color_filtered(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_grad_color(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_grad_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_grad_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_grad_color(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_grad_color_filtered(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_grad_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_grad_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_grad_color_filtered(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_grad_dir(lv_obj_t* obj, lv_grad_dir_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_grad_dir(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_grad_dir");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_grad_dir_t value = (lv_grad_dir_t)luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_grad_dir(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_main_stop(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_main_stop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_main_stop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_main_stop(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_grad_stop(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_grad_stop(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_grad_stop");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_grad_stop(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_img_src(lv_obj_t* obj, void* value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_img_src(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_img_src");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    void* value = (void*)lua_touserdata(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_img_src(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_img_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_img_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_img_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_img_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_img_recolor(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_img_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_img_recolor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_img_recolor(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_img_recolor_filtered(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_img_recolor_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_img_recolor_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_img_recolor_filtered(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_img_recolor_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_img_recolor_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_img_recolor_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_img_recolor_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_bg_img_tiled(lv_obj_t* obj, bool value, lv_style_selector_t selector)
int luat_lv_obj_set_style_bg_img_tiled(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_bg_img_tiled");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool value = (bool)lua_toboolean(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_bg_img_tiled(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_border_color(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_border_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_border_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_border_color(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_border_color_filtered(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_border_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_border_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_border_color_filtered(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_border_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_border_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_border_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_border_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_border_width(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_border_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_border_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_border_width(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_border_side(lv_obj_t* obj, lv_border_side_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_border_side(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_border_side");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_border_side_t value = (lv_border_side_t)luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_border_side(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_border_post(lv_obj_t* obj, bool value, lv_style_selector_t selector)
int luat_lv_obj_set_style_border_post(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_border_post");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool value = (bool)lua_toboolean(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_border_post(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_text_color(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_text_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_text_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_text_color(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_text_color_filtered(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_text_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_text_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_text_color_filtered(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_text_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_text_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_text_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_text_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_text_font(lv_obj_t* obj, lv_font_t* value, lv_style_selector_t selector)
int luat_lv_obj_set_style_text_font(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_text_font");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_font_t* value = (lv_font_t*)lua_touserdata(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_text_font(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_text_letter_space(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_text_letter_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_text_letter_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_text_letter_space(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_text_line_space(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_text_line_space(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_text_line_space");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_text_line_space(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_text_decor(lv_obj_t* obj, lv_text_decor_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_text_decor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_text_decor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_text_decor_t value = (lv_text_decor_t)luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_text_decor(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_text_align(lv_obj_t* obj, lv_text_align_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_text_align(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_text_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_text_align_t value = (lv_text_align_t)luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_text_align(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_img_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_img_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_img_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_img_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_img_recolor(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_img_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_img_recolor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_img_recolor(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_img_recolor_filtered(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_img_recolor_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_img_recolor_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_img_recolor_filtered(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_img_recolor_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_img_recolor_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_img_recolor_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_img_recolor_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_outline_width(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_outline_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_outline_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_outline_width(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_outline_color(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_outline_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_outline_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_outline_color(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_outline_color_filtered(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_outline_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_outline_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_outline_color_filtered(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_outline_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_outline_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_outline_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_outline_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_outline_pad(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_outline_pad(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_outline_pad");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_outline_pad(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_shadow_width(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_shadow_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_shadow_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_shadow_width(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_shadow_ofs_x(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_shadow_ofs_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_shadow_ofs_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_shadow_ofs_x(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_shadow_ofs_y(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_shadow_ofs_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_shadow_ofs_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_shadow_ofs_y(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_shadow_spread(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_shadow_spread(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_shadow_spread");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_shadow_spread(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_shadow_color(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_shadow_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_shadow_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_shadow_color(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_shadow_color_filtered(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_shadow_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_shadow_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_shadow_color_filtered(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_shadow_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_shadow_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_shadow_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_shadow_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_line_width(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_line_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_line_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_line_width(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_line_dash_width(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_line_dash_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_line_dash_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_line_dash_width(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_line_dash_gap(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_line_dash_gap(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_line_dash_gap");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_line_dash_gap(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_line_rounded(lv_obj_t* obj, bool value, lv_style_selector_t selector)
int luat_lv_obj_set_style_line_rounded(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_line_rounded");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool value = (bool)lua_toboolean(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_line_rounded(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_line_color(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_line_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_line_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_line_color(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_line_color_filtered(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_line_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_line_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_line_color_filtered(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_line_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_line_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_line_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_line_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_arc_width(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_arc_width(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_arc_width");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_arc_width(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_arc_rounded(lv_obj_t* obj, bool value, lv_style_selector_t selector)
int luat_lv_obj_set_style_arc_rounded(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_arc_rounded");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool value = (bool)lua_toboolean(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_arc_rounded(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_arc_color(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_arc_color(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_arc_color");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_arc_color(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_arc_color_filtered(lv_obj_t* obj, lv_color_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_arc_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_arc_color_filtered");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_arc_color_filtered(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_arc_opa(lv_obj_t* obj, lv_opa_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_arc_opa(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_arc_opa");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_arc_opa(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_arc_img_src(lv_obj_t* obj, void* value, lv_style_selector_t selector)
int luat_lv_obj_set_style_arc_img_src(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_arc_img_src");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    void* value = (void*)lua_touserdata(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_arc_img_src(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_pad_all(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_pad_all(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_pad_all");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_pad_all(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_pad_hor(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_pad_hor(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_pad_hor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_pad_hor(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_pad_ver(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_pad_ver(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_pad_ver");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_pad_ver(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_pad_gap(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_pad_gap(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_pad_gap");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_pad_gap(obj ,value ,selector);
    return 0;
}

//  void lv_obj_set_style_size(lv_obj_t* obj, lv_coord_t value, lv_style_selector_t selector)
int luat_lv_obj_set_style_size(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_style_size");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 2);
    lv_style_selector_t selector = (lv_style_selector_t)luaL_checkinteger(L, 3);
    lv_obj_set_style_size(obj ,value ,selector);
    return 0;
}

//  lv_text_align_t lv_obj_calculate_style_text_align(lv_obj_t* obj, lv_part_t part, char* txt)
int luat_lv_obj_calculate_style_text_align(lua_State *L) {
    LV_DEBUG("CALL lv_obj_calculate_style_text_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_part_t part = (lv_part_t)luaL_checkinteger(L, 2);
    char* txt = (char*)luaL_checkstring(L, 3);
    lv_text_align_t ret;
    ret = lv_obj_calculate_style_text_align(obj ,part ,txt);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_x_aligned(lv_obj_t* obj)
int luat_lv_obj_get_x_aligned(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_x_aligned");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_x_aligned(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_get_y_aligned(lv_obj_t* obj)
int luat_lv_obj_get_y_aligned(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_y_aligned");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_obj_get_y_aligned(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_init_draw_rect_dsc(lv_obj_t* obj, uint32_t part, lv_draw_rect_dsc_t* draw_dsc)
int luat_lv_obj_init_draw_rect_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_init_draw_rect_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_draw_rect_dsc_t* draw_dsc = (lv_draw_rect_dsc_t*)lua_touserdata(L, 3);
    lv_obj_init_draw_rect_dsc(obj ,part ,draw_dsc);
    return 0;
}

//  void lv_obj_init_draw_label_dsc(lv_obj_t* obj, uint32_t part, lv_draw_label_dsc_t* draw_dsc)
int luat_lv_obj_init_draw_label_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_init_draw_label_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_draw_label_dsc_t* draw_dsc = (lv_draw_label_dsc_t*)lua_touserdata(L, 3);
    lv_obj_init_draw_label_dsc(obj ,part ,draw_dsc);
    return 0;
}

//  void lv_obj_init_draw_img_dsc(lv_obj_t* obj, uint32_t part, lv_draw_img_dsc_t* draw_dsc)
int luat_lv_obj_init_draw_img_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_init_draw_img_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_draw_img_dsc_t* draw_dsc = (lv_draw_img_dsc_t*)lua_touserdata(L, 3);
    lv_obj_init_draw_img_dsc(obj ,part ,draw_dsc);
    return 0;
}

//  void lv_obj_init_draw_line_dsc(lv_obj_t* obj, uint32_t part, lv_draw_line_dsc_t* draw_dsc)
int luat_lv_obj_init_draw_line_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_init_draw_line_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_draw_line_dsc_t* draw_dsc = (lv_draw_line_dsc_t*)lua_touserdata(L, 3);
    lv_obj_init_draw_line_dsc(obj ,part ,draw_dsc);
    return 0;
}

//  void lv_obj_init_draw_arc_dsc(lv_obj_t* obj, uint32_t part, lv_draw_arc_dsc_t* draw_dsc)
int luat_lv_obj_init_draw_arc_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_init_draw_arc_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_draw_arc_dsc_t* draw_dsc = (lv_draw_arc_dsc_t*)lua_touserdata(L, 3);
    lv_obj_init_draw_arc_dsc(obj ,part ,draw_dsc);
    return 0;
}

//  lv_coord_t lv_obj_calculate_ext_draw_size(lv_obj_t* obj, uint32_t part)
int luat_lv_obj_calculate_ext_draw_size(lua_State *L) {
    LV_DEBUG("CALL lv_obj_calculate_ext_draw_size");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t part = (uint32_t)luaL_checkinteger(L, 2);
    lv_coord_t ret;
    ret = lv_obj_calculate_ext_draw_size(obj ,part);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_obj_draw_dsc_init(lv_obj_draw_part_dsc_t* dsc, lv_area_t* clip_area)
int luat_lv_obj_draw_dsc_init(lua_State *L) {
    LV_DEBUG("CALL lv_obj_draw_dsc_init");
    lv_obj_draw_part_dsc_t* dsc = (lv_obj_draw_part_dsc_t*)lua_touserdata(L, 1);
    lv_area_t* clip_area = (lv_area_t*)lua_touserdata(L, 2);
    lv_obj_draw_dsc_init(dsc ,clip_area);
    return 0;
}

//  bool lv_obj_draw_part_check_type(lv_obj_draw_part_dsc_t* dsc, struct _lv_obj_class_t* class_p, uint32_t type)
int luat_lv_obj_draw_part_check_type(lua_State *L) {
    LV_DEBUG("CALL lv_obj_draw_part_check_type");
    lv_obj_draw_part_dsc_t* dsc = (lv_obj_draw_part_dsc_t*)lua_touserdata(L, 1);
    struct _lv_obj_class_t* class_p = (struct _lv_obj_class_t*)lua_touserdata(L, 2);
    uint32_t type = (uint32_t)luaL_checkinteger(L, 3);
    bool ret;
    ret = lv_obj_draw_part_check_type(dsc ,class_p ,type);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_obj_refresh_ext_draw_size(lv_obj_t* obj)
int luat_lv_obj_refresh_ext_draw_size(lua_State *L) {
    LV_DEBUG("CALL lv_obj_refresh_ext_draw_size");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_refresh_ext_draw_size(obj);
    return 0;
}

//  lv_obj_t* lv_obj_class_create_obj(struct _lv_obj_class_t* class_p, lv_obj_t* parent)
int luat_lv_obj_class_create_obj(lua_State *L) {
    LV_DEBUG("CALL lv_obj_class_create_obj");
    struct _lv_obj_class_t* class_p = (struct _lv_obj_class_t*)lua_touserdata(L, 1);
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_obj_class_create_obj(class_p ,parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_obj_class_init_obj(lv_obj_t* obj)
int luat_lv_obj_class_init_obj(lua_State *L) {
    LV_DEBUG("CALL lv_obj_class_init_obj");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_class_init_obj(obj);
    return 0;
}

//  bool lv_obj_is_editable(lv_obj_t* obj)
int luat_lv_obj_is_editable(lua_State *L) {
    LV_DEBUG("CALL lv_obj_is_editable");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_is_editable(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_is_group_def(lv_obj_t* obj)
int luat_lv_obj_is_group_def(lua_State *L) {
    LV_DEBUG("CALL lv_obj_is_group_def");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_is_group_def(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_res_t lv_obj_event_base(lv_obj_class_t* class_p, lv_event_t* e)
int luat_lv_obj_event_base(lua_State *L) {
    LV_DEBUG("CALL lv_obj_event_base");
    lv_obj_class_t* class_p = (lv_obj_class_t*)lua_touserdata(L, 1);
    lv_event_t* e = (lv_event_t*)lua_touserdata(L, 2);
    lv_res_t ret;
    ret = lv_obj_event_base(class_p ,e);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  bool lv_obj_remove_event_dsc(lv_obj_t* obj, struct _lv_event_dsc_t* event_dsc)
int luat_lv_obj_remove_event_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_obj_remove_event_dsc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    struct _lv_event_dsc_t* event_dsc = (struct _lv_event_dsc_t*)lua_touserdata(L, 2);
    bool ret;
    ret = lv_obj_remove_event_dsc(obj ,event_dsc);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_obj_t* lv_obj_create(lv_obj_t* parent)
int luat_lv_obj_create(lua_State *L) {
    LV_DEBUG("CALL lv_obj_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_obj_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_obj_add_flag(lv_obj_t* obj, lv_obj_flag_t f)
int luat_lv_obj_add_flag(lua_State *L) {
    LV_DEBUG("CALL lv_obj_add_flag");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_flag_t f = (lv_obj_flag_t)luaL_checkinteger(L, 2);
    lv_obj_add_flag(obj ,f);
    return 0;
}

//  void lv_obj_clear_flag(lv_obj_t* obj, lv_obj_flag_t f)
int luat_lv_obj_clear_flag(lua_State *L) {
    LV_DEBUG("CALL lv_obj_clear_flag");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_flag_t f = (lv_obj_flag_t)luaL_checkinteger(L, 2);
    lv_obj_clear_flag(obj ,f);
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

//  void lv_obj_set_user_data(lv_obj_t* obj, void* user_data)
int luat_lv_obj_set_user_data(lua_State *L) {
    LV_DEBUG("CALL lv_obj_set_user_data");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    void* user_data = (void*)lua_touserdata(L, 2);
    lv_obj_set_user_data(obj ,user_data);
    return 0;
}

//  bool lv_obj_has_flag(lv_obj_t* obj, lv_obj_flag_t f)
int luat_lv_obj_has_flag(lua_State *L) {
    LV_DEBUG("CALL lv_obj_has_flag");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_flag_t f = (lv_obj_flag_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_has_flag(obj ,f);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_has_flag_any(lv_obj_t* obj, lv_obj_flag_t f)
int luat_lv_obj_has_flag_any(lua_State *L) {
    LV_DEBUG("CALL lv_obj_has_flag_any");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_flag_t f = (lv_obj_flag_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_has_flag_any(obj ,f);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_state_t lv_obj_get_state(lv_obj_t* obj)
int luat_lv_obj_get_state(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_state");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_state_t ret;
    ret = lv_obj_get_state(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_obj_has_state(lv_obj_t* obj, lv_state_t state)
int luat_lv_obj_has_state(lua_State *L) {
    LV_DEBUG("CALL lv_obj_has_state");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_obj_has_state(obj ,state);
    lua_pushboolean(L, ret);
    return 1;
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

//  void* lv_obj_get_user_data(lv_obj_t* obj)
int luat_lv_obj_get_user_data(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_user_data");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    void* ret = NULL;
    ret = lv_obj_get_user_data(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_obj_allocate_spec_attr(lv_obj_t* obj)
int luat_lv_obj_allocate_spec_attr(lua_State *L) {
    LV_DEBUG("CALL lv_obj_allocate_spec_attr");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_allocate_spec_attr(obj);
    return 0;
}

//  bool lv_obj_check_type(lv_obj_t* obj, lv_obj_class_t* class_p)
int luat_lv_obj_check_type(lua_State *L) {
    LV_DEBUG("CALL lv_obj_check_type");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_class_t* class_p = (lv_obj_class_t*)lua_touserdata(L, 2);
    bool ret;
    ret = lv_obj_check_type(obj ,class_p);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_obj_has_class(lv_obj_t* obj, lv_obj_class_t* class_p)
int luat_lv_obj_has_class(lua_State *L) {
    LV_DEBUG("CALL lv_obj_has_class");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_class_t* class_p = (lv_obj_class_t*)lua_touserdata(L, 2);
    bool ret;
    ret = lv_obj_has_class(obj ,class_p);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_obj_class_t* lv_obj_get_class(lv_obj_t* obj)
int luat_lv_obj_get_class(lua_State *L) {
    LV_DEBUG("CALL lv_obj_get_class");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_class_t* ret = NULL;
    ret = lv_obj_get_class(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  bool lv_obj_is_valid(lv_obj_t* obj)
int luat_lv_obj_is_valid(lua_State *L) {
    LV_DEBUG("CALL lv_obj_is_valid");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_obj_is_valid(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_coord_t lv_obj_dpx(lv_obj_t* obj, lv_coord_t n)
int luat_lv_obj_dpx(lua_State *L) {
    LV_DEBUG("CALL lv_obj_dpx");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t n = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t ret;
    ret = lv_obj_dpx(obj ,n);
    lua_pushinteger(L, ret);
    return 1;
}

