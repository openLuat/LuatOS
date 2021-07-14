
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_textarea_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_textarea_create(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_textarea_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_textarea_add_char(lv_obj_t* ta, uint32_t c)
int luat_lv_textarea_add_char(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_add_char");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t c = (uint32_t)luaL_checkinteger(L, 2);
    lv_textarea_add_char(ta ,c);
    return 0;
}

//  void lv_textarea_add_text(lv_obj_t* ta, char* txt)
int luat_lv_textarea_add_text(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_add_text");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_textarea_add_text(ta ,txt);
    return 0;
}

//  void lv_textarea_del_char(lv_obj_t* ta)
int luat_lv_textarea_del_char(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_del_char");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_del_char(ta);
    return 0;
}

//  void lv_textarea_del_char_forward(lv_obj_t* ta)
int luat_lv_textarea_del_char_forward(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_del_char_forward");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_del_char_forward(ta);
    return 0;
}

//  void lv_textarea_set_text(lv_obj_t* ta, char* txt)
int luat_lv_textarea_set_text(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_text");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_textarea_set_text(ta ,txt);
    return 0;
}

//  void lv_textarea_set_placeholder_text(lv_obj_t* ta, char* txt)
int luat_lv_textarea_set_placeholder_text(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_placeholder_text");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_textarea_set_placeholder_text(ta ,txt);
    return 0;
}

//  void lv_textarea_set_cursor_pos(lv_obj_t* ta, int32_t pos)
int luat_lv_textarea_set_cursor_pos(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_cursor_pos");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t pos = (int32_t)luaL_checkinteger(L, 2);
    lv_textarea_set_cursor_pos(ta ,pos);
    return 0;
}

//  void lv_textarea_set_cursor_hidden(lv_obj_t* ta, bool hide)
int luat_lv_textarea_set_cursor_hidden(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_cursor_hidden");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool hide = (bool)lua_toboolean(L, 2);
    lv_textarea_set_cursor_hidden(ta ,hide);
    return 0;
}

//  void lv_textarea_set_cursor_click_pos(lv_obj_t* ta, bool en)
int luat_lv_textarea_set_cursor_click_pos(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_cursor_click_pos");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_textarea_set_cursor_click_pos(ta ,en);
    return 0;
}

//  void lv_textarea_set_pwd_mode(lv_obj_t* ta, bool en)
int luat_lv_textarea_set_pwd_mode(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_pwd_mode");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_textarea_set_pwd_mode(ta ,en);
    return 0;
}

//  void lv_textarea_set_one_line(lv_obj_t* ta, bool en)
int luat_lv_textarea_set_one_line(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_one_line");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_textarea_set_one_line(ta ,en);
    return 0;
}

//  void lv_textarea_set_text_align(lv_obj_t* ta, lv_label_align_t align)
int luat_lv_textarea_set_text_align(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_text_align");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    lv_label_align_t align = (lv_label_align_t)luaL_checkinteger(L, 2);
    lv_textarea_set_text_align(ta ,align);
    return 0;
}

//  void lv_textarea_set_accepted_chars(lv_obj_t* ta, char* list)
int luat_lv_textarea_set_accepted_chars(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_accepted_chars");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    char* list = (char*)luaL_checkstring(L, 2);
    lv_textarea_set_accepted_chars(ta ,list);
    return 0;
}

//  void lv_textarea_set_max_length(lv_obj_t* ta, uint32_t num)
int luat_lv_textarea_set_max_length(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_max_length");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t num = (uint32_t)luaL_checkinteger(L, 2);
    lv_textarea_set_max_length(ta ,num);
    return 0;
}

//  void lv_textarea_set_insert_replace(lv_obj_t* ta, char* txt)
int luat_lv_textarea_set_insert_replace(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_insert_replace");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_textarea_set_insert_replace(ta ,txt);
    return 0;
}

//  void lv_textarea_set_scrollbar_mode(lv_obj_t* ta, lv_scrollbar_mode_t mode)
int luat_lv_textarea_set_scrollbar_mode(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_scrollbar_mode");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scrollbar_mode_t mode = (lv_scrollbar_mode_t)luaL_checkinteger(L, 2);
    lv_textarea_set_scrollbar_mode(ta ,mode);
    return 0;
}

//  void lv_textarea_set_scroll_propagation(lv_obj_t* ta, bool en)
int luat_lv_textarea_set_scroll_propagation(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_scroll_propagation");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_textarea_set_scroll_propagation(ta ,en);
    return 0;
}

//  void lv_textarea_set_edge_flash(lv_obj_t* ta, bool en)
int luat_lv_textarea_set_edge_flash(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_edge_flash");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_textarea_set_edge_flash(ta ,en);
    return 0;
}

//  void lv_textarea_set_text_sel(lv_obj_t* ta, bool en)
int luat_lv_textarea_set_text_sel(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_text_sel");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_textarea_set_text_sel(ta ,en);
    return 0;
}

//  void lv_textarea_set_pwd_show_time(lv_obj_t* ta, uint16_t time)
int luat_lv_textarea_set_pwd_show_time(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_pwd_show_time");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t time = (uint16_t)luaL_checkinteger(L, 2);
    lv_textarea_set_pwd_show_time(ta ,time);
    return 0;
}

//  void lv_textarea_set_cursor_blink_time(lv_obj_t* ta, uint16_t time)
int luat_lv_textarea_set_cursor_blink_time(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_cursor_blink_time");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t time = (uint16_t)luaL_checkinteger(L, 2);
    lv_textarea_set_cursor_blink_time(ta ,time);
    return 0;
}

//  char* lv_textarea_get_text(lv_obj_t* ta)
int luat_lv_textarea_get_text(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_text");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_textarea_get_text(ta);
    lua_pushstring(L, ret);
    return 1;
}

//  char* lv_textarea_get_placeholder_text(lv_obj_t* ta)
int luat_lv_textarea_get_placeholder_text(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_placeholder_text");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_textarea_get_placeholder_text(ta);
    lua_pushstring(L, ret);
    return 1;
}

//  lv_obj_t* lv_textarea_get_label(lv_obj_t* ta)
int luat_lv_textarea_get_label(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_label");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_textarea_get_label(ta);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  uint32_t lv_textarea_get_cursor_pos(lv_obj_t* ta)
int luat_lv_textarea_get_cursor_pos(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_cursor_pos");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_textarea_get_cursor_pos(ta);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_textarea_get_cursor_hidden(lv_obj_t* ta)
int luat_lv_textarea_get_cursor_hidden(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_cursor_hidden");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_get_cursor_hidden(ta);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_textarea_get_cursor_click_pos(lv_obj_t* ta)
int luat_lv_textarea_get_cursor_click_pos(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_cursor_click_pos");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_get_cursor_click_pos(ta);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_textarea_get_pwd_mode(lv_obj_t* ta)
int luat_lv_textarea_get_pwd_mode(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_pwd_mode");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_get_pwd_mode(ta);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_textarea_get_one_line(lv_obj_t* ta)
int luat_lv_textarea_get_one_line(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_one_line");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_get_one_line(ta);
    lua_pushboolean(L, ret);
    return 1;
}

//  char* lv_textarea_get_accepted_chars(lv_obj_t* ta)
int luat_lv_textarea_get_accepted_chars(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_accepted_chars");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_textarea_get_accepted_chars(ta);
    lua_pushstring(L, ret);
    return 1;
}

//  uint32_t lv_textarea_get_max_length(lv_obj_t* ta)
int luat_lv_textarea_get_max_length(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_max_length");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_textarea_get_max_length(ta);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_scrollbar_mode_t lv_textarea_get_scrollbar_mode(lv_obj_t* ta)
int luat_lv_textarea_get_scrollbar_mode(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_scrollbar_mode");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    lv_scrollbar_mode_t ret;
    ret = lv_textarea_get_scrollbar_mode(ta);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_textarea_get_scroll_propagation(lv_obj_t* ta)
int luat_lv_textarea_get_scroll_propagation(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_scroll_propagation");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_get_scroll_propagation(ta);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_textarea_get_edge_flash(lv_obj_t* ta)
int luat_lv_textarea_get_edge_flash(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_edge_flash");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_get_edge_flash(ta);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_textarea_text_is_selected(lv_obj_t* ta)
int luat_lv_textarea_text_is_selected(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_text_is_selected");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_text_is_selected(ta);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_textarea_get_text_sel_en(lv_obj_t* ta)
int luat_lv_textarea_get_text_sel_en(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_text_sel_en");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_get_text_sel_en(ta);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint16_t lv_textarea_get_pwd_show_time(lv_obj_t* ta)
int luat_lv_textarea_get_pwd_show_time(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_pwd_show_time");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_textarea_get_pwd_show_time(ta);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_textarea_get_cursor_blink_time(lv_obj_t* ta)
int luat_lv_textarea_get_cursor_blink_time(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_cursor_blink_time");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_textarea_get_cursor_blink_time(ta);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_textarea_clear_selection(lv_obj_t* ta)
int luat_lv_textarea_clear_selection(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_clear_selection");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_clear_selection(ta);
    return 0;
}

//  void lv_textarea_cursor_right(lv_obj_t* ta)
int luat_lv_textarea_cursor_right(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_cursor_right");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_cursor_right(ta);
    return 0;
}

//  void lv_textarea_cursor_left(lv_obj_t* ta)
int luat_lv_textarea_cursor_left(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_cursor_left");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_cursor_left(ta);
    return 0;
}

//  void lv_textarea_cursor_down(lv_obj_t* ta)
int luat_lv_textarea_cursor_down(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_cursor_down");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_cursor_down(ta);
    return 0;
}

//  void lv_textarea_cursor_up(lv_obj_t* ta)
int luat_lv_textarea_cursor_up(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_cursor_up");
    lv_obj_t* ta = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_cursor_up(ta);
    return 0;
}

