
#ifndef LUAT_LVGL_WIDGETS_EX
#define LUAT_LVGL_WIDGETS_EX

#include "luat_base.h"
#include "lvgl.h"

int luat_lv_msgbox_add_btns(lua_State *L);
int luat_lv_tileview_set_valid_positions(lua_State *L);
int luat_lv_calendar_set_highlighted_dates(lua_State *L);
/*line*/
int luat_lv_line_set_points(lua_State *L);
/*gauge*/
int luat_lv_gauge_set_needle_count(lua_State *L);
/*btnmatrix*/
int luat_lv_btnmatrix_set_map(lua_State *L);
/*dropdown*/
int luat_lv_dropdown_get_selected_str(lua_State *L);
/*roller*/
int luat_lv_roller_get_selected_str(lua_State *L);
/*canvas*/
int luat_lv_canvas_set_buffer(lua_State *L);

#define LUAT_LV_WIDGETS_EX_RLT {"msgbox_add_btns", luat_lv_msgbox_add_btns, 0},\
{"tileview_set_valid_positions", luat_lv_tileview_set_valid_positions, 0},\
{"calendar_set_highlighted_dates", luat_lv_calendar_set_highlighted_dates, 0},\
{"line_set_points", luat_lv_line_set_points, 0},\
{"gauge_set_needle_count", luat_lv_gauge_set_needle_count, 0},\
{"btnmatrix_set_map", luat_lv_btnmatrix_set_map, 0},\
{"dropdown_get_selected_str", luat_lv_dropdown_get_selected_str, 0},\
{"roller_get_selected_str", luat_lv_roller_get_selected_str, 0},\
{"canvas_set_buffer", luat_lv_canvas_set_buffer, 0},\

#endif