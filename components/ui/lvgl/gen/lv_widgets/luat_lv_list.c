
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_list_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_list_create(lua_State *L) {
    LV_DEBUG("CALL lv_list_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_list_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_list_clean(lv_obj_t* list)
int luat_lv_list_clean(lua_State *L) {
    LV_DEBUG("CALL lv_list_clean");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_list_clean(list);
    return 0;
}

//  lv_obj_t* lv_list_add_btn(lv_obj_t* list, void* img_src, char* txt)
int luat_lv_list_add_btn(lua_State *L) {
    LV_DEBUG("CALL lv_list_add_btn");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    void* img_src = (void*)lua_touserdata(L, 2);
    char* txt = (char*)luaL_checkstring(L, 3);
    lv_obj_t* ret = NULL;
    ret = lv_list_add_btn(list ,img_src ,txt);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  bool lv_list_remove(lv_obj_t* list, uint16_t index)
int luat_lv_list_remove(lua_State *L) {
    LV_DEBUG("CALL lv_list_remove");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t index = (uint16_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_list_remove(list ,index);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_list_focus_btn(lv_obj_t* list, lv_obj_t* btn)
int luat_lv_list_focus_btn(lua_State *L) {
    LV_DEBUG("CALL lv_list_focus_btn");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 2);
    lv_list_focus_btn(list ,btn);
    return 0;
}

//  void lv_list_set_scrollbar_mode(lv_obj_t* list, lv_scrollbar_mode_t mode)
int luat_lv_list_set_scrollbar_mode(lua_State *L) {
    LV_DEBUG("CALL lv_list_set_scrollbar_mode");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scrollbar_mode_t mode = (lv_scrollbar_mode_t)luaL_checkinteger(L, 2);
    lv_list_set_scrollbar_mode(list ,mode);
    return 0;
}

//  void lv_list_set_scroll_propagation(lv_obj_t* list, bool en)
int luat_lv_list_set_scroll_propagation(lua_State *L) {
    LV_DEBUG("CALL lv_list_set_scroll_propagation");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_list_set_scroll_propagation(list ,en);
    return 0;
}

//  void lv_list_set_edge_flash(lv_obj_t* list, bool en)
int luat_lv_list_set_edge_flash(lua_State *L) {
    LV_DEBUG("CALL lv_list_set_edge_flash");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_list_set_edge_flash(list ,en);
    return 0;
}

//  void lv_list_set_anim_time(lv_obj_t* list, uint16_t anim_time)
int luat_lv_list_set_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_list_set_anim_time");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t anim_time = (uint16_t)luaL_checkinteger(L, 2);
    lv_list_set_anim_time(list ,anim_time);
    return 0;
}

//  void lv_list_set_layout(lv_obj_t* list, lv_layout_t layout)
int luat_lv_list_set_layout(lua_State *L) {
    LV_DEBUG("CALL lv_list_set_layout");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_layout_t layout = (lv_layout_t)luaL_checkinteger(L, 2);
    lv_list_set_layout(list ,layout);
    return 0;
}

//  char* lv_list_get_btn_text(lv_obj_t* btn)
int luat_lv_list_get_btn_text(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_btn_text");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_list_get_btn_text(btn);
    lua_pushstring(L, ret);
    return 1;
}

//  lv_obj_t* lv_list_get_btn_label(lv_obj_t* btn)
int luat_lv_list_get_btn_label(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_btn_label");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_list_get_btn_label(btn);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_list_get_btn_img(lv_obj_t* btn)
int luat_lv_list_get_btn_img(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_btn_img");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_list_get_btn_img(btn);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_list_get_prev_btn(lv_obj_t* list, lv_obj_t* prev_btn)
int luat_lv_list_get_prev_btn(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_prev_btn");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* prev_btn = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_list_get_prev_btn(list ,prev_btn);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_obj_t* lv_list_get_next_btn(lv_obj_t* list, lv_obj_t* prev_btn)
int luat_lv_list_get_next_btn(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_next_btn");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* prev_btn = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_list_get_next_btn(list ,prev_btn);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  int32_t lv_list_get_btn_index(lv_obj_t* list, lv_obj_t* btn)
int luat_lv_list_get_btn_index(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_btn_index");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 2);
    int32_t ret;
    ret = lv_list_get_btn_index(list ,btn);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_list_get_size(lv_obj_t* list)
int luat_lv_list_get_size(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_size");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_list_get_size(list);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_obj_t* lv_list_get_btn_selected(lv_obj_t* list)
int luat_lv_list_get_btn_selected(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_btn_selected");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_list_get_btn_selected(list);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_layout_t lv_list_get_layout(lv_obj_t* list)
int luat_lv_list_get_layout(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_layout");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_layout_t ret;
    ret = lv_list_get_layout(list);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_scrollbar_mode_t lv_list_get_scrollbar_mode(lv_obj_t* list)
int luat_lv_list_get_scrollbar_mode(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_scrollbar_mode");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scrollbar_mode_t ret;
    ret = lv_list_get_scrollbar_mode(list);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_list_get_scroll_propagation(lv_obj_t* list)
int luat_lv_list_get_scroll_propagation(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_scroll_propagation");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_list_get_scroll_propagation(list);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_list_get_edge_flash(lv_obj_t* list)
int luat_lv_list_get_edge_flash(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_edge_flash");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_list_get_edge_flash(list);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint16_t lv_list_get_anim_time(lv_obj_t* list)
int luat_lv_list_get_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_list_get_anim_time");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_list_get_anim_time(list);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_list_up(lv_obj_t* list)
int luat_lv_list_up(lua_State *L) {
    LV_DEBUG("CALL lv_list_up");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_list_up(list);
    return 0;
}

//  void lv_list_down(lv_obj_t* list)
int luat_lv_list_down(lua_State *L) {
    LV_DEBUG("CALL lv_list_down");
    lv_obj_t* list = (lv_obj_t*)lua_touserdata(L, 1);
    lv_list_down(list);
    return 0;
}

//  void lv_list_focus(lv_obj_t* btn, lv_anim_enable_t anim)
int luat_lv_list_focus(lua_State *L) {
    LV_DEBUG("CALL lv_list_focus");
    lv_obj_t* btn = (lv_obj_t*)lua_touserdata(L, 1);
    lv_anim_enable_t anim = (lv_anim_enable_t)lua_toboolean(L, 2);
    lv_list_focus(btn ,anim);
    return 0;
}

