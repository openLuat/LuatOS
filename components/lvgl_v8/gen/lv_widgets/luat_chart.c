
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_chart_create(lv_obj_t* parent)
int luat_lv_chart_create(lua_State *L) {
    LV_DEBUG("CALL lv_chart_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_chart_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_chart_set_type(lv_obj_t* obj, lv_chart_type_t type)
int luat_lv_chart_set_type(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_type");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_type_t type = (lv_chart_type_t)luaL_checkinteger(L, 2);
    lv_chart_set_type(obj ,type);
    return 0;
}

//  void lv_chart_set_point_count(lv_obj_t* obj, uint16_t cnt)
int luat_lv_chart_set_point_count(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_point_count");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t cnt = (uint16_t)luaL_checkinteger(L, 2);
    lv_chart_set_point_count(obj ,cnt);
    return 0;
}

//  void lv_chart_set_range(lv_obj_t* obj, lv_chart_axis_t axis, lv_coord_t min, lv_coord_t max)
int luat_lv_chart_set_range(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_range");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_axis_t axis = (lv_chart_axis_t)luaL_checkinteger(L, 2);
    lv_coord_t min = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t max = (lv_coord_t)luaL_checknumber(L, 4);
    lv_chart_set_range(obj ,axis ,min ,max);
    return 0;
}

//  void lv_chart_set_update_mode(lv_obj_t* obj, lv_chart_update_mode_t update_mode)
int luat_lv_chart_set_update_mode(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_update_mode");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_update_mode_t update_mode;
    // miss arg convert
    lv_chart_set_update_mode(obj ,update_mode);
    return 0;
}

//  void lv_chart_set_div_line_count(lv_obj_t* obj, uint8_t hdiv, uint8_t vdiv)
int luat_lv_chart_set_div_line_count(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_div_line_count");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t hdiv = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t vdiv = (uint8_t)luaL_checkinteger(L, 3);
    lv_chart_set_div_line_count(obj ,hdiv ,vdiv);
    return 0;
}

//  void lv_chart_set_zoom_x(lv_obj_t* obj, uint16_t zoom_x)
int luat_lv_chart_set_zoom_x(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_zoom_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t zoom_x = (uint16_t)luaL_checkinteger(L, 2);
    lv_chart_set_zoom_x(obj ,zoom_x);
    return 0;
}

//  void lv_chart_set_zoom_y(lv_obj_t* obj, uint16_t zoom_y)
int luat_lv_chart_set_zoom_y(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_zoom_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t zoom_y = (uint16_t)luaL_checkinteger(L, 2);
    lv_chart_set_zoom_y(obj ,zoom_y);
    return 0;
}

//  uint16_t lv_chart_get_zoom_x(lv_obj_t* obj)
int luat_lv_chart_get_zoom_x(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_zoom_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_chart_get_zoom_x(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_chart_get_zoom_y(lv_obj_t* obj)
int luat_lv_chart_get_zoom_y(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_zoom_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_chart_get_zoom_y(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_chart_set_axis_tick(lv_obj_t* obj, lv_chart_axis_t axis, lv_coord_t major_len, lv_coord_t minor_len, lv_coord_t major_cnt, lv_coord_t minor_cnt, bool label_en, lv_coord_t draw_size)
int luat_lv_chart_set_axis_tick(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_axis_tick");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_axis_t axis = (lv_chart_axis_t)luaL_checkinteger(L, 2);
    lv_coord_t major_len = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t minor_len = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t major_cnt = (lv_coord_t)luaL_checknumber(L, 5);
    lv_coord_t minor_cnt = (lv_coord_t)luaL_checknumber(L, 6);
    bool label_en = (bool)lua_toboolean(L, 7);
    lv_coord_t draw_size = (lv_coord_t)luaL_checknumber(L, 8);
    lv_chart_set_axis_tick(obj ,axis ,major_len ,minor_len ,major_cnt ,minor_cnt ,label_en ,draw_size);
    return 0;
}

//  lv_chart_type_t lv_chart_get_type(lv_obj_t* obj)
int luat_lv_chart_get_type(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_type");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_type_t ret;
    ret = lv_chart_get_type(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_chart_get_point_count(lv_obj_t* obj)
int luat_lv_chart_get_point_count(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_point_count");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_chart_get_point_count(obj);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_chart_get_x_start_point(lv_obj_t* obj, lv_chart_series_t* ser)
int luat_lv_chart_get_x_start_point(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_x_start_point");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    uint16_t ret;
    ret = lv_chart_get_x_start_point(obj ,ser);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_chart_get_point_pos_by_id(lv_obj_t* obj, lv_chart_series_t* ser, uint16_t id, lv_point_t* p_out)
int luat_lv_chart_get_point_pos_by_id(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_point_pos_by_id");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 3);
    lv_point_t* p_out = (lv_point_t*)lua_touserdata(L, 4);
    lv_chart_get_point_pos_by_id(obj ,ser ,id ,p_out);
    return 0;
}

//  void lv_chart_refresh(lv_obj_t* obj)
int luat_lv_chart_refresh(lua_State *L) {
    LV_DEBUG("CALL lv_chart_refresh");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_refresh(obj);
    return 0;
}

//  lv_chart_series_t* lv_chart_add_series(lv_obj_t* obj, lv_color_t color, lv_chart_axis_t axis)
int luat_lv_chart_add_series(lua_State *L) {
    LV_DEBUG("CALL lv_chart_add_series");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 2);
    lv_chart_axis_t axis = (lv_chart_axis_t)luaL_checkinteger(L, 3);
    lv_chart_series_t* ret = NULL;
    ret = lv_chart_add_series(obj ,color ,axis);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_chart_remove_series(lv_obj_t* obj, lv_chart_series_t* series)
int luat_lv_chart_remove_series(lua_State *L) {
    LV_DEBUG("CALL lv_chart_remove_series");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* series = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_chart_remove_series(obj ,series);
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

//  void lv_chart_set_series_color(lv_obj_t* chart, lv_chart_series_t* series, lv_color_t color)
int luat_lv_chart_set_series_color(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_series_color");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* series = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 3);
    lv_chart_set_series_color(chart ,series ,color);
    return 0;
}

//  void lv_chart_set_x_start_point(lv_obj_t* obj, lv_chart_series_t* ser, uint16_t id)
int luat_lv_chart_set_x_start_point(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_x_start_point");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 3);
    lv_chart_set_x_start_point(obj ,ser ,id);
    return 0;
}

//  lv_chart_series_t* lv_chart_get_series_next(lv_obj_t* chart, lv_chart_series_t* ser)
int luat_lv_chart_get_series_next(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_series_next");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_chart_series_t* ret = NULL;
    ret = lv_chart_get_series_next(chart ,ser);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_chart_cursor_t* lv_chart_add_cursor(lv_obj_t* obj, lv_color_t color, lv_dir_t dir)
int luat_lv_chart_add_cursor(lua_State *L) {
    LV_DEBUG("CALL lv_chart_add_cursor");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 2);
    lv_dir_t dir = (lv_dir_t)luaL_checkinteger(L, 3);
    lv_chart_cursor_t* ret = NULL;
    ret = lv_chart_add_cursor(obj ,color ,dir);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_chart_set_cursor_pos(lv_obj_t* chart, lv_chart_cursor_t* cursor, lv_point_t* pos)
int luat_lv_chart_set_cursor_pos(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_cursor_pos");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_cursor_t* cursor = (lv_chart_cursor_t*)lua_touserdata(L, 2);
    lv_point_t* pos = (lv_point_t*)lua_touserdata(L, 3);
    lv_chart_set_cursor_pos(chart ,cursor ,pos);
    return 0;
}

//  void lv_chart_set_cursor_point(lv_obj_t* chart, lv_chart_cursor_t* cursor, lv_chart_series_t* ser, uint16_t point_id)
int luat_lv_chart_set_cursor_point(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_cursor_point");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_cursor_t* cursor = (lv_chart_cursor_t*)lua_touserdata(L, 2);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 3);
    uint16_t point_id = (uint16_t)luaL_checkinteger(L, 4);
    lv_chart_set_cursor_point(chart ,cursor ,ser ,point_id);
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

//  void lv_chart_set_all_value(lv_obj_t* obj, lv_chart_series_t* ser, lv_coord_t value)
int luat_lv_chart_set_all_value(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_all_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 3);
    lv_chart_set_all_value(obj ,ser ,value);
    return 0;
}

//  void lv_chart_set_next_value(lv_obj_t* obj, lv_chart_series_t* ser, lv_coord_t value)
int luat_lv_chart_set_next_value(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_next_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 3);
    lv_chart_set_next_value(obj ,ser ,value);
    return 0;
}

//  void lv_chart_set_next_value2(lv_obj_t* obj, lv_chart_series_t* ser, lv_coord_t x_value, lv_coord_t y_value)
int luat_lv_chart_set_next_value2(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_next_value2");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_coord_t x_value = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t y_value = (lv_coord_t)luaL_checknumber(L, 4);
    lv_chart_set_next_value2(obj ,ser ,x_value ,y_value);
    return 0;
}

//  void lv_chart_set_value_by_id(lv_obj_t* obj, lv_chart_series_t* ser, uint16_t id, lv_coord_t value)
int luat_lv_chart_set_value_by_id(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_value_by_id");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 3);
    lv_coord_t value = (lv_coord_t)luaL_checknumber(L, 4);
    lv_chart_set_value_by_id(obj ,ser ,id ,value);
    return 0;
}

//  void lv_chart_set_value_by_id2(lv_obj_t* obj, lv_chart_series_t* ser, uint16_t id, lv_coord_t x_value, lv_coord_t y_value)
int luat_lv_chart_set_value_by_id2(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_value_by_id2");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    uint16_t id = (uint16_t)luaL_checkinteger(L, 3);
    lv_coord_t x_value = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t y_value = (lv_coord_t)luaL_checknumber(L, 5);
    lv_chart_set_value_by_id2(obj ,ser ,id ,x_value ,y_value);
    return 0;
}

//  lv_coord_t* lv_chart_get_y_array(lv_obj_t* obj, lv_chart_series_t* ser)
int luat_lv_chart_get_y_array(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_y_array");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_coord_t* ret = NULL;
    ret = lv_chart_get_y_array(obj ,ser);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_coord_t* lv_chart_get_x_array(lv_obj_t* obj, lv_chart_series_t* ser)
int luat_lv_chart_get_x_array(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_x_array");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* ser = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_coord_t* ret = NULL;
    ret = lv_chart_get_x_array(obj ,ser);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  uint32_t lv_chart_get_pressed_point(lv_obj_t* obj)
int luat_lv_chart_get_pressed_point(lua_State *L) {
    LV_DEBUG("CALL lv_chart_get_pressed_point");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    uint32_t ret;
    ret = lv_chart_get_pressed_point(obj);
    lua_pushinteger(L, ret);
    return 1;
}

