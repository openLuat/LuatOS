

#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_page_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_page_create(lua_State *L) {
    LV_DEBUG("CALL lv_page_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_page_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_page_clean(lv_obj_t* page)
int luat_lv_page_clean(lua_State *L) {
    LV_DEBUG("CALL lv_page_clean");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_page_clean(page);
    return 0;
}

//  lv_obj_t* lv_page_get_scrollable(lv_obj_t* page)
int luat_lv_page_get_scrollable(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_scrollable");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_page_get_scrollable(page);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  uint16_t lv_page_get_anim_time(lv_obj_t* page)
int luat_lv_page_get_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_anim_time");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_page_get_anim_time(page);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_page_set_scrollbar_mode(lv_obj_t* page, lv_scrollbar_mode_t sb_mode)
int luat_lv_page_set_scrollbar_mode(lua_State *L) {
    LV_DEBUG("CALL lv_page_set_scrollbar_mode");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scrollbar_mode_t sb_mode = (lv_scrollbar_mode_t)luaL_checkinteger(L, 2);
    lv_page_set_scrollbar_mode(page ,sb_mode);
    return 0;
}

//  void lv_page_set_anim_time(lv_obj_t* page, uint16_t anim_time)
int luat_lv_page_set_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_page_set_anim_time");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t anim_time = (uint16_t)luaL_checkinteger(L, 2);
    lv_page_set_anim_time(page ,anim_time);
    return 0;
}

//  void lv_page_set_scroll_propagation(lv_obj_t* page, bool en)
int luat_lv_page_set_scroll_propagation(lua_State *L) {
    LV_DEBUG("CALL lv_page_set_scroll_propagation");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_page_set_scroll_propagation(page ,en);
    return 0;
}

//  void lv_page_set_edge_flash(lv_obj_t* page, bool en)
int luat_lv_page_set_edge_flash(lua_State *L) {
    LV_DEBUG("CALL lv_page_set_edge_flash");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_page_set_edge_flash(page ,en);
    return 0;
}

//  void lv_page_set_scrollable_fit4(lv_obj_t* page, lv_fit_t left, lv_fit_t right, lv_fit_t top, lv_fit_t bottom)
int luat_lv_page_set_scrollable_fit4(lua_State *L) {
    LV_DEBUG("CALL lv_page_set_scrollable_fit4");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t left = (lv_fit_t)luaL_checkinteger(L, 2);
    lv_fit_t right = (lv_fit_t)luaL_checkinteger(L, 3);
    lv_fit_t top = (lv_fit_t)luaL_checkinteger(L, 4);
    lv_fit_t bottom = (lv_fit_t)luaL_checkinteger(L, 5);
    lv_page_set_scrollable_fit4(page ,left ,right ,top ,bottom);
    return 0;
}

//  void lv_page_set_scrollable_fit2(lv_obj_t* page, lv_fit_t hor, lv_fit_t ver)
int luat_lv_page_set_scrollable_fit2(lua_State *L) {
    LV_DEBUG("CALL lv_page_set_scrollable_fit2");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t hor = (lv_fit_t)luaL_checkinteger(L, 2);
    lv_fit_t ver = (lv_fit_t)luaL_checkinteger(L, 3);
    lv_page_set_scrollable_fit2(page ,hor ,ver);
    return 0;
}

//  void lv_page_set_scrollable_fit(lv_obj_t* page, lv_fit_t fit)
int luat_lv_page_set_scrollable_fit(lua_State *L) {
    LV_DEBUG("CALL lv_page_set_scrollable_fit");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t fit = (lv_fit_t)luaL_checkinteger(L, 2);
    lv_page_set_scrollable_fit(page ,fit);
    return 0;
}

//  void lv_page_set_scrl_width(lv_obj_t* page, lv_coord_t w)
int luat_lv_page_set_scrl_width(lua_State *L) {
    LV_DEBUG("CALL lv_page_set_scrl_width");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 2);
    lv_page_set_scrl_width(page ,w);
    return 0;
}

//  void lv_page_set_scrl_height(lv_obj_t* page, lv_coord_t h)
int luat_lv_page_set_scrl_height(lua_State *L) {
    LV_DEBUG("CALL lv_page_set_scrl_height");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 2);
    lv_page_set_scrl_height(page ,h);
    return 0;
}

//  void lv_page_set_scrl_layout(lv_obj_t* page, lv_layout_t layout)
int luat_lv_page_set_scrl_layout(lua_State *L) {
    LV_DEBUG("CALL lv_page_set_scrl_layout");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_layout_t layout = (lv_layout_t)luaL_checkinteger(L, 2);
    lv_page_set_scrl_layout(page ,layout);
    return 0;
}

//  lv_scrollbar_mode_t lv_page_get_scrollbar_mode(lv_obj_t* page)
int luat_lv_page_get_scrollbar_mode(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_scrollbar_mode");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scrollbar_mode_t ret;
    ret = lv_page_get_scrollbar_mode(page);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_page_get_scroll_propagation(lv_obj_t* page)
int luat_lv_page_get_scroll_propagation(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_scroll_propagation");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_page_get_scroll_propagation(page);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_page_get_edge_flash(lv_obj_t* page)
int luat_lv_page_get_edge_flash(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_edge_flash");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_page_get_edge_flash(page);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_coord_t lv_page_get_width_fit(lv_obj_t* page)
int luat_lv_page_get_width_fit(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_width_fit");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_page_get_width_fit(page);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_page_get_height_fit(lv_obj_t* page)
int luat_lv_page_get_height_fit(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_height_fit");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_page_get_height_fit(page);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_page_get_width_grid(lv_obj_t* page, uint8_t div, uint8_t span)
int luat_lv_page_get_width_grid(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_width_grid");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t div = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t span = (uint8_t)luaL_checkinteger(L, 3);
    lv_coord_t ret;
    ret = lv_page_get_width_grid(page ,div ,span);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_page_get_height_grid(lv_obj_t* page, uint8_t div, uint8_t span)
int luat_lv_page_get_height_grid(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_height_grid");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t div = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t span = (uint8_t)luaL_checkinteger(L, 3);
    lv_coord_t ret;
    ret = lv_page_get_height_grid(page ,div ,span);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_page_get_scrl_width(lv_obj_t* page)
int luat_lv_page_get_scrl_width(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_scrl_width");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_page_get_scrl_width(page);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_page_get_scrl_height(lv_obj_t* page)
int luat_lv_page_get_scrl_height(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_scrl_height");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_page_get_scrl_height(page);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_layout_t lv_page_get_scrl_layout(lv_obj_t* page)
int luat_lv_page_get_scrl_layout(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_scrl_layout");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_layout_t ret;
    ret = lv_page_get_scrl_layout(page);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_page_get_scrl_fit_left(lv_obj_t* page)
int luat_lv_page_get_scrl_fit_left(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_scrl_fit_left");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_page_get_scrl_fit_left(page);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_page_get_scrl_fit_right(lv_obj_t* page)
int luat_lv_page_get_scrl_fit_right(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_scrl_fit_right");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_page_get_scrl_fit_right(page);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_page_get_scrl_fit_top(lv_obj_t* page)
int luat_lv_page_get_scrl_fit_top(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_scrl_fit_top");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_page_get_scrl_fit_top(page);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_fit_t lv_page_get_scrl_fit_bottom(lv_obj_t* page)
int luat_lv_page_get_scrl_fit_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_page_get_scrl_fit_bottom");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_fit_t ret;
    ret = lv_page_get_scrl_fit_bottom(page);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_page_on_edge(lv_obj_t* page, lv_page_edge_t edge)
int luat_lv_page_on_edge(lua_State *L) {
    LV_DEBUG("CALL lv_page_on_edge");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_page_edge_t edge = luaL_checkinteger(L, 2);
    // miss arg convert
    bool ret;
    ret = lv_page_on_edge(page ,edge);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_page_glue_obj(lv_obj_t* obj, bool glue)
int luat_lv_page_glue_obj(lua_State *L) {
    LV_DEBUG("CALL lv_page_glue_obj");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool glue = (bool)lua_toboolean(L, 2);
    lv_page_glue_obj(obj ,glue);
    return 0;
}

//  void lv_page_focus(lv_obj_t* page, lv_obj_t* obj, lv_anim_enable_t anim_en)
int luat_lv_page_focus(lua_State *L) {
    LV_DEBUG("CALL lv_page_focus");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 2);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_page_focus(page ,obj ,anim_en);
    return 0;
}

//  void lv_page_scroll_hor(lv_obj_t* page, lv_coord_t dist)
int luat_lv_page_scroll_hor(lua_State *L) {
    LV_DEBUG("CALL lv_page_scroll_hor");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t dist = (lv_coord_t)luaL_checknumber(L, 2);
    lv_page_scroll_hor(page ,dist);
    return 0;
}

//  void lv_page_scroll_ver(lv_obj_t* page, lv_coord_t dist)
int luat_lv_page_scroll_ver(lua_State *L) {
    LV_DEBUG("CALL lv_page_scroll_ver");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t dist = (lv_coord_t)luaL_checknumber(L, 2);
    lv_page_scroll_ver(page ,dist);
    return 0;
}

//  void lv_page_start_edge_flash(lv_obj_t* page, lv_page_edge_t edge)
int luat_lv_page_start_edge_flash(lua_State *L) {
    LV_DEBUG("CALL lv_page_start_edge_flash");
    lv_obj_t* page = (lv_obj_t*)lua_touserdata(L, 1);
    lv_page_edge_t edge = luaL_checkinteger(L, 2);
    // miss arg convert
    lv_page_start_edge_flash(page ,edge);
    return 0;
}

