
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_meter_create(lv_obj_t* parent)
int luat_lv_meter_create(lua_State *L) {
    LV_DEBUG("CALL lv_meter_create");
    lv_obj_t* parent = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* ret = NULL;
    ret = lv_meter_create(parent);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_meter_scale_t* lv_meter_add_scale(lv_obj_t* obj)
int luat_lv_meter_add_scale(lua_State *L) {
    LV_DEBUG("CALL lv_meter_add_scale");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_meter_scale_t* ret = NULL;
    ret = lv_meter_add_scale(obj);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_meter_set_scale_ticks(lv_obj_t* obj, lv_meter_scale_t* scale, uint16_t cnt, uint16_t width, uint16_t len, lv_color_t color)
int luat_lv_meter_set_scale_ticks(lua_State *L) {
    LV_DEBUG("CALL lv_meter_set_scale_ticks");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_meter_scale_t* scale = (lv_meter_scale_t*)lua_touserdata(L, 2);
    uint16_t cnt = (uint16_t)luaL_checkinteger(L, 3);
    uint16_t width = (uint16_t)luaL_checkinteger(L, 4);
    uint16_t len = (uint16_t)luaL_checkinteger(L, 5);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 6);
    lv_meter_set_scale_ticks(obj ,scale ,cnt ,width ,len ,color);
    return 0;
}

//  void lv_meter_set_scale_major_ticks(lv_obj_t* obj, lv_meter_scale_t* scale, uint16_t nth, uint16_t width, uint16_t len, lv_color_t color, int16_t label_gap)
int luat_lv_meter_set_scale_major_ticks(lua_State *L) {
    LV_DEBUG("CALL lv_meter_set_scale_major_ticks");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_meter_scale_t* scale = (lv_meter_scale_t*)lua_touserdata(L, 2);
    uint16_t nth = (uint16_t)luaL_checkinteger(L, 3);
    uint16_t width = (uint16_t)luaL_checkinteger(L, 4);
    uint16_t len = (uint16_t)luaL_checkinteger(L, 5);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 6);
    int16_t label_gap = (int16_t)luaL_checkinteger(L, 7);
    lv_meter_set_scale_major_ticks(obj ,scale ,nth ,width ,len ,color ,label_gap);
    return 0;
}

//  void lv_meter_set_scale_range(lv_obj_t* obj, lv_meter_scale_t* scale, int32_t min, int32_t max, uint32_t angle_range, uint32_t rotation)
int luat_lv_meter_set_scale_range(lua_State *L) {
    LV_DEBUG("CALL lv_meter_set_scale_range");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_meter_scale_t* scale = (lv_meter_scale_t*)lua_touserdata(L, 2);
    int32_t min = (int32_t)luaL_checkinteger(L, 3);
    int32_t max = (int32_t)luaL_checkinteger(L, 4);
    uint32_t angle_range = (uint32_t)luaL_checkinteger(L, 5);
    uint32_t rotation = (uint32_t)luaL_checkinteger(L, 6);
    lv_meter_set_scale_range(obj ,scale ,min ,max ,angle_range ,rotation);
    return 0;
}

//  lv_meter_indicator_t* lv_meter_add_needle_line(lv_obj_t* obj, lv_meter_scale_t* scale, uint16_t width, lv_color_t color, int16_t r_mod)
int luat_lv_meter_add_needle_line(lua_State *L) {
    LV_DEBUG("CALL lv_meter_add_needle_line");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_meter_scale_t* scale = (lv_meter_scale_t*)lua_touserdata(L, 2);
    uint16_t width = (uint16_t)luaL_checkinteger(L, 3);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 4);
    int16_t r_mod = (int16_t)luaL_checkinteger(L, 5);
    lv_meter_indicator_t* ret = NULL;
    ret = lv_meter_add_needle_line(obj ,scale ,width ,color ,r_mod);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_meter_indicator_t* lv_meter_add_needle_img(lv_obj_t* obj, lv_meter_scale_t* scale, void* src, lv_coord_t pivot_x, lv_coord_t pivot_y)
int luat_lv_meter_add_needle_img(lua_State *L) {
    LV_DEBUG("CALL lv_meter_add_needle_img");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_meter_scale_t* scale = (lv_meter_scale_t*)lua_touserdata(L, 2);
    void* src = (void*)lua_touserdata(L, 3);
    lv_coord_t pivot_x = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t pivot_y = (lv_coord_t)luaL_checknumber(L, 5);
    lv_meter_indicator_t* ret = NULL;
    ret = lv_meter_add_needle_img(obj ,scale ,src ,pivot_x ,pivot_y);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_meter_indicator_t* lv_meter_add_arc(lv_obj_t* obj, lv_meter_scale_t* scale, uint16_t width, lv_color_t color, int16_t r_mod)
int luat_lv_meter_add_arc(lua_State *L) {
    LV_DEBUG("CALL lv_meter_add_arc");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_meter_scale_t* scale = (lv_meter_scale_t*)lua_touserdata(L, 2);
    uint16_t width = (uint16_t)luaL_checkinteger(L, 3);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 4);
    int16_t r_mod = (int16_t)luaL_checkinteger(L, 5);
    lv_meter_indicator_t* ret = NULL;
    ret = lv_meter_add_arc(obj ,scale ,width ,color ,r_mod);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_meter_indicator_t* lv_meter_add_scale_lines(lv_obj_t* obj, lv_meter_scale_t* scale, lv_color_t color_start, lv_color_t color_end, bool local, int16_t width_mod)
int luat_lv_meter_add_scale_lines(lua_State *L) {
    LV_DEBUG("CALL lv_meter_add_scale_lines");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_meter_scale_t* scale = (lv_meter_scale_t*)lua_touserdata(L, 2);
    lv_color_t color_start = {0};
    color_start.full = luaL_checkinteger(L, 3);
    lv_color_t color_end = {0};
    color_end.full = luaL_checkinteger(L, 4);
    bool local = (bool)lua_toboolean(L, 5);
    int16_t width_mod = (int16_t)luaL_checkinteger(L, 6);
    lv_meter_indicator_t* ret = NULL;
    ret = lv_meter_add_scale_lines(obj ,scale ,color_start ,color_end ,local ,width_mod);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_meter_set_indicator_value(lv_obj_t* obj, lv_meter_indicator_t* indic, int32_t value)
int luat_lv_meter_set_indicator_value(lua_State *L) {
    LV_DEBUG("CALL lv_meter_set_indicator_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_meter_indicator_t* indic = (lv_meter_indicator_t*)lua_touserdata(L, 2);
    int32_t value = (int32_t)luaL_checkinteger(L, 3);
    lv_meter_set_indicator_value(obj ,indic ,value);
    return 0;
}

//  void lv_meter_set_indicator_start_value(lv_obj_t* obj, lv_meter_indicator_t* indic, int32_t value)
int luat_lv_meter_set_indicator_start_value(lua_State *L) {
    LV_DEBUG("CALL lv_meter_set_indicator_start_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_meter_indicator_t* indic = (lv_meter_indicator_t*)lua_touserdata(L, 2);
    int32_t value = (int32_t)luaL_checkinteger(L, 3);
    lv_meter_set_indicator_start_value(obj ,indic ,value);
    return 0;
}

//  void lv_meter_set_indicator_end_value(lv_obj_t* obj, lv_meter_indicator_t* indic, int32_t value)
int luat_lv_meter_set_indicator_end_value(lua_State *L) {
    LV_DEBUG("CALL lv_meter_set_indicator_end_value");
    lv_obj_t* obj = (lv_obj_t*)lua_touserdata(L, 1);
    lv_meter_indicator_t* indic = (lv_meter_indicator_t*)lua_touserdata(L, 2);
    int32_t value = (int32_t)luaL_checkinteger(L, 3);
    lv_meter_set_indicator_end_value(obj ,indic ,value);
    return 0;
}

