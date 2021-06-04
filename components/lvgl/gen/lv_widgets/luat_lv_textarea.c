
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_textarea_create(lv_obj_t* parent)
int luat_lv_textarea_create(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_textarea_create(parent);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  void lv_textarea_add_char(lv_obj_t* obj, uint32_t c)
int luat_lv_textarea_add_char(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_add_char");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t c = (uint32_t)luaL_checkinteger(L, 2);
    lv_textarea_add_char(obj ,c);
    return 0;
}

//  void lv_textarea_add_text(lv_obj_t* obj, char* txt)
int luat_lv_textarea_add_text(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_add_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_textarea_add_text(obj ,txt);
    return 0;
}

//  void lv_textarea_del_char(lv_obj_t* obj)
int luat_lv_textarea_del_char(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_del_char");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_del_char(obj);
    return 0;
}

//  void lv_textarea_del_char_forward(lv_obj_t* obj)
int luat_lv_textarea_del_char_forward(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_del_char_forward");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_del_char_forward(obj);
    return 0;
}

//  void lv_textarea_set_text(lv_obj_t* obj, char* txt)
int luat_lv_textarea_set_text(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_textarea_set_text(obj ,txt);
    return 0;
}

//  void lv_textarea_set_placeholder_text(lv_obj_t* obj, char* txt)
int luat_lv_textarea_set_placeholder_text(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_placeholder_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_textarea_set_placeholder_text(obj ,txt);
    return 0;
}

//  void lv_textarea_set_cursor_pos(lv_obj_t* obj, int32_t pos)
int luat_lv_textarea_set_cursor_pos(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_cursor_pos");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t pos = (int32_t)luaL_checkinteger(L, 2);
    lv_textarea_set_cursor_pos(obj ,pos);
    return 0;
}

//  void lv_textarea_set_cursor_click_pos(lv_obj_t* obj, bool en)
int luat_lv_textarea_set_cursor_click_pos(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_cursor_click_pos");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_textarea_set_cursor_click_pos(obj ,en);
    return 0;
}

//  void lv_textarea_set_password_mode(lv_obj_t* obj, bool en)
int luat_lv_textarea_set_password_mode(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_password_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_textarea_set_password_mode(obj ,en);
    return 0;
}

//  void lv_textarea_set_one_line(lv_obj_t* obj, bool en)
int luat_lv_textarea_set_one_line(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_one_line");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_textarea_set_one_line(obj ,en);
    return 0;
}

//  void lv_textarea_set_accepted_chars(lv_obj_t* obj, char* list)
int luat_lv_textarea_set_accepted_chars(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_accepted_chars");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* list = (char*)luaL_checkstring(L, 2);
    lv_textarea_set_accepted_chars(obj ,list);
    return 0;
}

//  void lv_textarea_set_max_length(lv_obj_t* obj, uint32_t num)
int luat_lv_textarea_set_max_length(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_max_length");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t num = (uint32_t)luaL_checkinteger(L, 2);
    lv_textarea_set_max_length(obj ,num);
    return 0;
}

//  void lv_textarea_set_insert_replace(lv_obj_t* obj, char* txt)
int luat_lv_textarea_set_insert_replace(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_insert_replace");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* txt = (char*)luaL_checkstring(L, 2);
    lv_textarea_set_insert_replace(obj ,txt);
    return 0;
}

//  void lv_textarea_set_text_selection(lv_obj_t* obj, bool en)
int luat_lv_textarea_set_text_selection(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_text_selection");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool en = (bool)lua_toboolean(L, 2);
    lv_textarea_set_text_selection(obj ,en);
    return 0;
}

//  void lv_textarea_set_password_show_time(lv_obj_t* obj, uint16_t time)
int luat_lv_textarea_set_password_show_time(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_password_show_time");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t time = (uint16_t)luaL_checkinteger(L, 2);
    lv_textarea_set_password_show_time(obj ,time);
    return 0;
}

//  void lv_textarea_set_align(lv_obj_t* obj, lv_text_align_t align)
int luat_lv_textarea_set_align(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_set_align");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_text_align_t align = (lv_text_align_t)luaL_checkinteger(L, 2);
    lv_textarea_set_align(obj ,align);
    return 0;
}

//  char* lv_textarea_get_text(lv_obj_t* obj)
int luat_lv_textarea_get_text(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_textarea_get_text(obj);
    lua_pushstring(L, ret);
    return 1;
}

//  char* lv_textarea_get_placeholder_text(lv_obj_t* obj)
int luat_lv_textarea_get_placeholder_text(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_placeholder_text");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_textarea_get_placeholder_text(obj);
    lua_pushstring(L, ret);
    return 1;
}

//  lv_obj_t* lv_textarea_get_label(lv_obj_t* obj)
int luat_lv_textarea_get_label(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_label");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_textarea_get_label(obj);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  uint32_t lv_textarea_get_cursor_pos(lv_obj_t* obj)
int luat_lv_textarea_get_cursor_pos(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_cursor_pos");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_textarea_get_cursor_pos(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_textarea_get_cursor_click_pos(lv_obj_t* obj)
int luat_lv_textarea_get_cursor_click_pos(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_cursor_click_pos");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_get_cursor_click_pos(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_textarea_get_password_mode(lv_obj_t* obj)
int luat_lv_textarea_get_password_mode(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_password_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_get_password_mode(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_textarea_get_one_line(lv_obj_t* obj)
int luat_lv_textarea_get_one_line(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_one_line");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_get_one_line(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  char* lv_textarea_get_accepted_chars(lv_obj_t* obj)
int luat_lv_textarea_get_accepted_chars(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_accepted_chars");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_textarea_get_accepted_chars(obj);
    lua_pushstring(L, ret);
    return 1;
}

//  uint32_t lv_textarea_get_max_length(lv_obj_t* obj)
int luat_lv_textarea_get_max_length(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_max_length");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_textarea_get_max_length(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_textarea_text_is_selected(lv_obj_t* obj)
int luat_lv_textarea_text_is_selected(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_text_is_selected");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_text_is_selected(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_textarea_get_text_selection(lv_obj_t* obj)
int luat_lv_textarea_get_text_selection(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_text_selection");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_textarea_get_text_selection(obj);
    lua_pushboolean(L, ret);
    return 1;
}

//  uint16_t lv_textarea_get_password_show_time(lv_obj_t* obj)
int luat_lv_textarea_get_password_show_time(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_get_password_show_time");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_textarea_get_password_show_time(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_textarea_clear_selection(lv_obj_t* obj)
int luat_lv_textarea_clear_selection(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_clear_selection");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_clear_selection(obj);
    return 0;
}

//  void lv_textarea_cursor_right(lv_obj_t* obj)
int luat_lv_textarea_cursor_right(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_cursor_right");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_cursor_right(obj);
    return 0;
}

//  void lv_textarea_cursor_left(lv_obj_t* obj)
int luat_lv_textarea_cursor_left(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_cursor_left");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_cursor_left(obj);
    return 0;
}

//  void lv_textarea_cursor_down(lv_obj_t* obj)
int luat_lv_textarea_cursor_down(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_cursor_down");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_cursor_down(obj);
    return 0;
}

//  void lv_textarea_cursor_up(lv_obj_t* obj)
int luat_lv_textarea_cursor_up(lua_State *L) {
    LV_DEBUG("CALL lv_textarea_cursor_up");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_textarea_cursor_up(obj);
    return 0;
}

