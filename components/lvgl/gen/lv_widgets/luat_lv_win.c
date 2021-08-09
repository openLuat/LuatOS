
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_win_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_win_create(lua_State *L) {
    LV_DEBUG("CALL lv_win_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_win_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_win_clean(lv_obj_t* win)
int luat_lv_win_clean(lua_State *L) {
    LV_DEBUG("CALL lv_win_clean");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_win_clean(win);
    return 0;
}

//  lv_obj_t* lv_win_add_btn_right(lv_obj_t* win, void* img_src)
int luat_lv_win_add_btn_right(lua_State *L) {
    LV_DEBUG("CALL lv_win_add_btn_right");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    void* img_src = (void*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_win_add_btn_right(win ,img_src);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_win_add_btn_left(lv_obj_t* win, void* img_src)
int luat_lv_win_add_btn_left(lua_State *L) {
    LV_DEBUG("CALL lv_win_add_btn_left");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    void* img_src = (void*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_win_add_btn_left(win ,img_src);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_win_set_title(lv_obj_t* win, char* title)
int luat_lv_win_set_title(lua_State *L) {
    LV_DEBUG("CALL lv_win_set_title");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    char* title = (char*)luaL_checkstring(L, 2);
    lv_win_set_title(win ,title);
    return 0;
}

//  void lv_win_set_header_height(lv_obj_t* win, lv_coord_t size)
int luat_lv_win_set_header_height(lua_State *L) {
    LV_DEBUG("CALL lv_win_set_header_height");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t size = (lv_coord_t)luaL_checknumber(L, 2);
    lv_win_set_header_height(win ,size);
    return 0;
}

//  void lv_win_set_btn_width(lv_obj_t* win, lv_coord_t width)
int luat_lv_win_set_btn_width(lua_State *L) {
    LV_DEBUG("CALL lv_win_set_btn_width");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t width = (lv_coord_t)luaL_checknumber(L, 2);
    lv_win_set_btn_width(win ,width);
    return 0;
}

//  void lv_win_set_content_size(lv_obj_t* win, lv_coord_t w, lv_coord_t h)
int luat_lv_win_set_content_size(lua_State *L) {
    LV_DEBUG("CALL lv_win_set_content_size");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 3);
    lv_win_set_content_size(win ,w ,h);
    return 0;
}

//  void lv_win_set_layout(lv_obj_t* win, lv_layout_t layout)
int luat_lv_win_set_layout(lua_State *L) {
    LV_DEBUG("CALL lv_win_set_layout");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_layout_t layout = (lv_layout_t)luaL_checkinteger(L, 2);
    lv_win_set_layout(win ,layout);
    return 0;
}

//  void lv_win_set_scrollbar_mode(lv_obj_t* win, lv_scrollbar_mode_t sb_mode)
int luat_lv_win_set_scrollbar_mode(lua_State *L) {
    LV_DEBUG("CALL lv_win_set_scrollbar_mode");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scrollbar_mode_t sb_mode = (lv_scrollbar_mode_t)luaL_checkinteger(L, 2);
    lv_win_set_scrollbar_mode(win ,sb_mode);
    return 0;
}

//  void lv_win_set_anim_time(lv_obj_t* win, uint16_t anim_time)
int luat_lv_win_set_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_win_set_anim_time");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t anim_time = (uint16_t)luaL_checkinteger(L, 2);
    lv_win_set_anim_time(win ,anim_time);
    return 0;
}

//  void lv_win_set_drag(lv_obj_t* win, bool en)
int luat_lv_win_set_drag(lua_State *L) {
    LV_DEBUG("CALL lv_win_set_drag");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_win_set_drag(win ,en);
    return 0;
}

//  void lv_win_title_set_alignment(lv_obj_t* win, uint8_t alignment)
int luat_lv_win_title_set_alignment(lua_State *L) {
    LV_DEBUG("CALL lv_win_title_set_alignment");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t alignment = (uint8_t)luaL_checkinteger(L, 2);
    lv_win_title_set_alignment(win ,alignment);
    return 0;
}

//  char* lv_win_get_title(lv_obj_t* win)
int luat_lv_win_get_title(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_title");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_win_get_title(win);
    lua_pushstring(L, ret);
    return 1;
}

//  lv_obj_t* lv_win_get_content(lv_obj_t* win)
int luat_lv_win_get_content(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_content");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_win_get_content(win);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_coord_t lv_win_get_header_height(lv_obj_t* win)
int luat_lv_win_get_header_height(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_header_height");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_win_get_header_height(win);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_win_get_btn_width(lv_obj_t* win)
int luat_lv_win_get_btn_width(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_btn_width");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_win_get_btn_width(win);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_obj_t* lv_win_get_from_btn(lv_obj_t* ctrl_btn)
int luat_lv_win_get_from_btn(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_from_btn");
    lv_obj_t* ctrl_btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_win_get_from_btn(ctrl_btn);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_layout_t lv_win_get_layout(lv_obj_t* win)
int luat_lv_win_get_layout(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_layout");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_layout_t ret;
    ret = lv_win_get_layout(win);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_scrollbar_mode_t lv_win_get_sb_mode(lv_obj_t* win)
int luat_lv_win_get_sb_mode(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_sb_mode");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scrollbar_mode_t ret;
    ret = lv_win_get_sb_mode(win);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_win_get_anim_time(lv_obj_t* win)
int luat_lv_win_get_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_anim_time");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_win_get_anim_time(win);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_win_get_width(lv_obj_t* win)
int luat_lv_win_get_width(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_width");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_win_get_width(win);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_win_get_drag(lv_obj_t* win)
int luat_lv_win_get_drag(lua_State *L) {
    LV_DEBUG("CALL lv_win_get_drag");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_win_get_drag(win);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint8_t lv_win_title_get_alignment(lv_obj_t* win)
int luat_lv_win_title_get_alignment(lua_State *L) {
    LV_DEBUG("CALL lv_win_title_get_alignment");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t ret;
    ret = lv_win_title_get_alignment(win);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_win_focus(lv_obj_t* win, lv_obj_t* obj, lv_anim_enable_t anim_en)
int luat_lv_win_focus(lua_State *L) {
    LV_DEBUG("CALL lv_win_focus");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 2);
    lv_anim_enable_t anim_en = (lv_anim_enable_t)lua_toboolean(L, 3);
    lv_win_focus(win ,obj ,anim_en);
    return 0;
}

//  void lv_win_scroll_hor(lv_obj_t* win, lv_coord_t dist)
int luat_lv_win_scroll_hor(lua_State *L) {
    LV_DEBUG("CALL lv_win_scroll_hor");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t dist = (lv_coord_t)luaL_checknumber(L, 2);
    lv_win_scroll_hor(win ,dist);
    return 0;
}

//  void lv_win_scroll_ver(lv_obj_t* win, lv_coord_t dist)
int luat_lv_win_scroll_ver(lua_State *L) {
    LV_DEBUG("CALL lv_win_scroll_ver");
    lv_obj_t* win = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t dist = (lv_coord_t)luaL_checknumber(L, 2);
    lv_win_scroll_ver(win ,dist);
    return 0;
}

