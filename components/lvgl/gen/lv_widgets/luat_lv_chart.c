

#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_chart_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_chart_create(lua_State *L) {
    LV_DEBUG("CALL lv_chart_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_chart_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_chart_series_t* lv_chart_add_series(lv_obj_t* chart, lv_color_t color)
int luat_lv_chart_add_series(lua_State *L) {
    LV_DEBUG("CALL lv_chart_add_series");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 2);
    lv_chart_series_t* ret = NULL;
    ret = lv_chart_add_series(chart ,color);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_chart_remove_series(lv_obj_t* chart, lv_chart_series_t* series)
int luat_lv_chart_remove_series(lua_State *L) {
    LV_DEBUG("CALL lv_chart_remove_series");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* series = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_chart_remove_series(chart ,series);
    return 0;
}

//  lv_chart_cursor_t* lv_chart_add_cursor(lv_obj_t* chart, lv_color_t color, lv_cursor_direction_t dir)
int luat_lv_chart_add_cursor(lua_State *L) {
    LV_DEBUG("CALL lv_chart_add_cursor");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 2);
    lv_cursor_direction_t dir = luaL_checkinteger(L, 3);
    // miss arg convert
    lv_chart_cursor_t* ret = NULL;
    ret = lv_chart_add_cursor(chart ,color ,dir);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_chart_clear_series(lv_obj_t* chart, lv_chart_series_t* series)
int luat_lv_chart_clear_series(lua_State *L) {
    LV_DEBUG("CALL lv_chart_clear_series");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* series = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_chart_clear_series(chart ,series);
    return 0;
}

//  void lv_chart_hide_series(lv_obj_t* chart, lv_chart_series_t* series, bool hide)
int luat_lv_chart_hide_series(lua_State *L) {
    LV_DEBUG("CALL lv_chart_hide_series");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* series = (lv_chart_series_t*)lua_touserdata(L, 2);
    bool hide = (bool)lua_toboolean(L, 3);
    lv_chart_hide_series(chart ,series ,hide);
    return 0;
}

//  void lv_chart_set_div_line_count(lv_obj_t* chart, uint8_t hdiv, uint8_t vdiv)
int luat_lv_chart_set_div_line_count(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_div_line_count");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t hdiv = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t vdiv = (uint8_t)luaL_checkinteger(L, 3);
    lv_chart_set_div_line_count(chart ,hdiv ,vdiv);
    return 0;
}

//  void lv_chart_set_y_range(lv_obj_t* chart, lv_chart_axis_t axis, lv_coord_t ymin, lv_coord_t ymax)
int luat_lv_chart_set_y_range(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_y_range");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_axis_t axis = (lv_chart_axis_t)luaL_checkinteger(L, 2);
    lv_coord_t ymin = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t ymax = (lv_coord_t)luaL_checknumber(L, 4);
    lv_chart_set_y_range(chart ,axis ,ymin ,ymax);
    return 0;
}

//  void lv_chart_set_type(lv_obj_t* chart, lv_chart_type_t type)
int luat_lv_chart_set_type(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_type");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_type_t type = (lv_chart_type_t)luaL_checkinteger(L, 2);
    lv_chart_set_type(chart ,type);
    return 0;
}

//  void lv_chart_set_point_count(lv_obj_t* chart, uint16_t point_cnt)
int luat_lv_chart_set_point_count(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_point_count");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t point_cnt = (uint16_t)luaL_checkinteger(L, 2);
    lv_chart_set_point_count(chart ,point_cnt);
    return 0;
}

//  void lv_chart_init_points(lv_obj_t* chart, lv_chart_series_t* ser, lv_coord_t y)
int luat_lv_chart_init_points(lua_State *L) {
    LV_DEBUG("CALL lv_chart_init_points");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_chart_init_points(chart ,ser ,y);
    return 0;
}

//  void lv_chart_set_next(lv_obj_t* chart, lv_chart_series_t* ser, lv_coord_t y)
int luat_lv_chart_set_next(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_next");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_chart_set_next(chart ,ser ,y);
    return 0;
}

//  void lv_chart_set_update_mode(lv_obj_t* chart, lv_chart_update_mode_t update_mode)
int luat_lv_chart_set_update_mode(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_update_mode");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_update_mode_t update_mode = luaL_checkinteger(L, 2);
    // miss arg convert
    lv_chart_set_update_mode(chart ,update_mode);
    return 0;
}

//  void lv_chart_set_x_tick_length(lv_obj_t* chart, uint8_t major_tick_len, uint8_t minor_tick_len)
int luat_lv_chart_set_x_tick_length(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_x_tick_length");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t major_tick_len = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t minor_tick_len = (uint8_t)luaL_checkinteger(L, 3);
    lv_chart_set_x_tick_length(chart ,major_tick_len ,minor_tick_len);
    return 0;
}

//  void lv_chart_set_y_tick_length(lv_obj_t* chart, uint8_t major_tick_len, uint8_t minor_tick_len)
int luat_lv_chart_set_y_tick_length(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_y_tick_length");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t major_tick_len = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t minor_tick_len = (uint8_t)luaL_checkinteger(L, 3);
    lv_chart_set_y_tick_length(chart ,major_tick_len ,minor_tick_len);
    return 0;
}

//  void lv_chart_set_secondary_y_tick_length(lv_obj_t* chart, uint8_t major_tick_len, uint8_t minor_tick_len)
int luat_lv_chart_set_secondary_y_tick_length(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_secondary_y_tick_length");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t major_tick_len = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t minor_tick_len = (uint8_t)luaL_checkinteger(L, 3);
    lv_chart_set_secondary_y_tick_length(chart ,major_tick_len ,minor_tick_len);
    return 0;
}

//  void lv_chart_set_x_tick_texts(lv_obj_t* chart, char* list_of_values, uint8_t num_tick_marks, lv_chart_axis_options_t options)
int luat_lv_chart_set_x_tick_texts(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_x_tick_texts");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    char* list_of_values = (char*)luaL_checkstring(L, 2);
    uint8_t num_tick_marks = (uint8_t)luaL_checkinteger(L, 3);
    lv_chart_axis_options_t options = luaL_checkinteger(L, 4);
    // miss arg convert
    lv_chart_set_x_tick_texts(chart ,list_of_values ,num_tick_marks ,options);
    return 0;
}

//  void lv_chart_set_secondary_y_tick_texts(lv_obj_t* chart, char* list_of_values, uint8_t num_tick_marks, lv_chart_axis_options_t options)
int luat_lv_chart_set_secondary_y_tick_texts(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_secondary_y_tick_texts");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    char* list_of_values = (char*)luaL_checkstring(L, 2);
    uint8_t num_tick_marks = (uint8_t)luaL_checkinteger(L, 3);
    lv_chart_axis_options_t options  = luaL_checkinteger(L, 4);
    // miss arg convert
    lv_chart_set_secondary_y_tick_texts(chart ,list_of_values ,num_tick_marks ,options);
    return 0;
}

//  void lv_chart_set_y_tick_texts(lv_obj_t* chart, char* list_of_values, uint8_t num_tick_marks, lv_chart_axis_options_t options)
int luat_lv_chart_set_y_tick_texts(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_y_tick_texts");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    char* list_of_values = (char*)luaL_checkstring(L, 2);
    uint8_t num_tick_marks = (uint8_t)luaL_checkinteger(L, 3);
    lv_chart_axis_options_t options  = luaL_checkinteger(L, 4);
    // miss arg convert
    lv_chart_set_y_tick_texts(chart ,list_of_values ,num_tick_marks ,options);
    return 0;
}

//  void lv_chart_set_x_start_point(lv_obj_t* chart, lv_chart_series_t* ser, uint16_t id)
int luat_lv_chart_set_x_start_point(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_x_start_point");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 3);
    lv_chart_set_x_start_point(chart ,ser ,id);
    return 0;
}

//  void lv_chart_set_point_id(lv_obj_t* chart, lv_chart_series_t* ser, lv_coord_t value, uint16_t id)
int luat_lv_chart_set_point_id(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_point_id");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 3);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 4);
    lv_chart_set_point_id(chart ,ser ,value ,id);
    return 0;
}

//  void lv_chart_set_series_axis(lv_obj_t* chart, lv_chart_series_t* ser, lv_chart_axis_t axis)
int luat_lv_chart_set_series_axis(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_series_axis");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_chart_axis_t axis = (lv_chart_axis_t)luaL_checkinteger(L, 3);
    lv_chart_set_series_axis(chart ,ser ,axis);
    return 0;
}

//  void lv_chart_set_cursor_point(lv_obj_t* chart, lv_chart_cursor_t* cursor, lv_point_t* point)
int luat_lv_chart_set_cursor_point(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_cursor_point");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_cursor_t* cursor = (lv_chart_cursor_t*)lua_touserdata(L, 2);
    lv_point_t* point = (lv_point_t*)lua_touserdata(L, 3);
    lv_chart_set_cursor_point(chart ,cursor ,point);
    return 0;
}

//  lv_chart_type_t lv_chart_get_type(lv_obj_t* chart)
int luat_lv_chart_get_type(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_type");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_type_t ret;
    ret = lv_chart_get_type(chart);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_chart_get_point_count(lv_obj_t* chart)
int luat_lv_chart_get_point_count(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_point_count");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_chart_get_point_count(chart);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_chart_get_x_start_point(lv_chart_series_t* ser)
int luat_lv_chart_get_x_start_point(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_x_start_point");
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_chart_get_x_start_point(ser);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_chart_get_point_id(lv_obj_t* chart, lv_chart_series_t* ser, uint16_t id)
int luat_lv_chart_get_point_id(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_point_id");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 3);
    lv_coord_t ret;
    ret = lv_chart_get_point_id(chart ,ser ,id);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_chart_axis_t lv_chart_get_series_axis(lv_obj_t* chart, lv_chart_series_t* ser)
int luat_lv_chart_get_series_axis(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_series_axis");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_chart_axis_t ret;
    ret = lv_chart_get_series_axis(chart ,ser);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_chart_get_series_area(lv_obj_t* chart, lv_area_t* series_area)
int luat_lv_chart_get_series_area(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_series_area");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* series_area = (lv_area_t*)lua_touserdata(L, 2);
    lv_chart_get_series_area(chart ,series_area);
    return 0;
}

//  lv_point_t lv_chart_get_cursor_point(lv_obj_t* chart, lv_chart_cursor_t* cursor)
int luat_lv_chart_get_cursor_point(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_cursor_point");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_cursor_t* cursor = (lv_chart_cursor_t*)lua_touserdata(L, 2);
    lv_point_t ret;
    ret = lv_chart_get_cursor_point(chart ,cursor);
    lua_pushinteger(L, ret.x);
    lua_pushinteger(L, ret.y);
    return 2;
}

//  uint16_t lv_chart_get_nearest_index_from_coord(lv_obj_t* chart, lv_coord_t x)
int luat_lv_chart_get_nearest_index_from_coord(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_nearest_index_from_coord");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    uint16_t ret;
    ret = lv_chart_get_nearest_index_from_coord(chart ,x);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_chart_get_x_from_index(lv_obj_t* chart, lv_chart_series_t* ser, uint16_t id)
int luat_lv_chart_get_x_from_index(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_x_from_index");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 3);
    lv_coord_t ret;
    ret = lv_chart_get_x_from_index(chart ,ser ,id);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_chart_get_y_from_index(lv_obj_t* chart, lv_chart_series_t* ser, uint16_t id)
int luat_lv_chart_get_y_from_index(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_y_from_index");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 3);
    lv_coord_t ret;
    ret = lv_chart_get_y_from_index(chart ,ser ,id);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_chart_refresh(lv_obj_t* chart)
int luat_lv_chart_refresh(lua_State *L) {
    LV_DEBUG("CALL lv_chart_refresh");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_refresh(chart);
    return 0;
}

