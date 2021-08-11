/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


#if LV_USE_CHART

int luat_lv_chart_set_range(lua_State *L) {
    LV_DEBUG("CALL lv_chart_set_range");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ymin = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_coord_t ymax = (lv_coord_t)luaL_checkinteger(L, 3);
    lv_chart_set_y_range(chart, LV_CHART_AXIS_PRIMARY_Y, ymin,  ymax);
    return 0;
}

int luat_lv_chart_clear_serie(lua_State *L) {
    LV_DEBUG("CALL lv_chart_clear_serie");
    lv_obj_t* chart = (lv_obj_t*)lua_touserdata(L, 1);
    lv_chart_series_t* series = (lv_chart_series_t*)lua_touserdata(L, 2);
    lv_chart_clear_series(chart, series);
    return 0;
}

#endif

int luat_lv_obj_align_origo(lua_State *L) {
    LV_DEBUG("CALL lv_obj_align_origo");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* base = (lv_obj_t*)lua_touserdata(L, 2);
    lv_align_t align = (lv_align_t)lua_touserdata(L, 3);
    lv_coord_t x_ofs = (lv_coord_t)luaL_checkinteger(L, 4);
    lv_coord_t y_ofs = (lv_coord_t)luaL_checkinteger(L, 5);
    lv_obj_align_mid(obj, base, align, x_ofs, y_ofs);
    return 0;
}

int luat_lv_obj_align_origo_x(lua_State *L) {
    LV_DEBUG("CALL lv_obj_align_origo_x");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* base = (lv_obj_t*)lua_touserdata(L, 2);
    lv_align_t align = (lv_align_t)lua_touserdata(L, 3);
    lv_coord_t x_ofs = (lv_coord_t)luaL_checkinteger(L, 4);
    lv_obj_align_mid_x(obj, base, align, x_ofs);
    return 0;
}

int luat_lv_obj_align_origo_y(lua_State *L) {
    LV_DEBUG("CALL lv_obj_align_origo_y");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* base = (lv_obj_t*)lua_touserdata(L, 2);
    lv_align_t align = (lv_align_t)lua_touserdata(L, 3);
    lv_coord_t y_ofs = (lv_coord_t)luaL_checkinteger(L, 4);
    lv_obj_align_mid_y(obj, base, align, y_ofs);
    return 0;
}

int luat_lv_win_add_btn(lua_State *L) {
    lv_obj_t * win = lua_touserdata(L, 1);
    const char* img_src = luaL_checkstring(L, 2);
    lv_obj_t *btn = lv_win_add_btn(win, img_src);
    lua_pushlightuserdata(L, btn);
    return 1;
}
