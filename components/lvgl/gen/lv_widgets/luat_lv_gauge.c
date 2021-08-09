
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_gauge_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_gauge_create(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_gauge_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_gauge_set_value(lv_obj_t* gauge, uint8_t needle_id, int32_t value)
int luat_lv_gauge_set_value(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_set_value");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t needle_id = (uint8_t)luaL_checkinteger(L, 2);
    int32_t value = (int32_t)luaL_checkinteger(L, 3);
    lv_gauge_set_value(gauge ,needle_id ,value);
    return 0;
}

//  void lv_gauge_set_range(lv_obj_t* gauge, int32_t min, int32_t max)
int luat_lv_gauge_set_range(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_set_range");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t min = (int32_t)luaL_checkinteger(L, 2);
    int32_t max = (int32_t)luaL_checkinteger(L, 3);
    lv_gauge_set_range(gauge ,min ,max);
    return 0;
}

//  void lv_gauge_set_critical_value(lv_obj_t* gauge, int32_t value)
int luat_lv_gauge_set_critical_value(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_set_critical_value");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t value = (int32_t)luaL_checkinteger(L, 2);
    lv_gauge_set_critical_value(gauge ,value);
    return 0;
}

//  void lv_gauge_set_scale(lv_obj_t* gauge, uint16_t angle, uint8_t line_cnt, uint8_t label_cnt)
int luat_lv_gauge_set_scale(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_set_scale");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t angle = (uint16_t)luaL_checkinteger(L, 2);
    uint8_t line_cnt = (uint8_t)luaL_checkinteger(L, 3);
    uint8_t label_cnt = (uint8_t)luaL_checkinteger(L, 4);
    lv_gauge_set_scale(gauge ,angle ,line_cnt ,label_cnt);
    return 0;
}

//  void lv_gauge_set_angle_offset(lv_obj_t* gauge, uint16_t angle)
int luat_lv_gauge_set_angle_offset(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_set_angle_offset");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t angle = (uint16_t)luaL_checkinteger(L, 2);
    lv_gauge_set_angle_offset(gauge ,angle);
    return 0;
}

//  void lv_gauge_set_needle_img(lv_obj_t* gauge, void* img, lv_coord_t pivot_x, lv_coord_t pivot_y)
int luat_lv_gauge_set_needle_img(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_set_needle_img");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    void* img = (void*)lua_touserdata(L, 2);
    lv_coord_t pivot_x = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t pivot_y = (lv_coord_t)luaL_checknumber(L, 4);
    lv_gauge_set_needle_img(gauge ,img ,pivot_x ,pivot_y);
    return 0;
}

//  int32_t lv_gauge_get_value(lv_obj_t* gauge, uint8_t needle)
int luat_lv_gauge_get_value(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_value");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t needle = (uint8_t)luaL_checkinteger(L, 2);
    int32_t ret;
    ret = lv_gauge_get_value(gauge ,needle);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint8_t lv_gauge_get_needle_count(lv_obj_t* gauge)
int luat_lv_gauge_get_needle_count(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_needle_count");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t ret;
    ret = lv_gauge_get_needle_count(gauge);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_gauge_get_min_value(lv_obj_t* lmeter)
int luat_lv_gauge_get_min_value(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_min_value");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_gauge_get_min_value(lmeter);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_gauge_get_max_value(lv_obj_t* lmeter)
int luat_lv_gauge_get_max_value(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_max_value");
    lv_obj_t* lmeter = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_gauge_get_max_value(lmeter);
    lua_pushinteger(L, ret);
    return 1;
}

//  int32_t lv_gauge_get_critical_value(lv_obj_t* gauge)
int luat_lv_gauge_get_critical_value(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_critical_value");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    int32_t ret;
    ret = lv_gauge_get_critical_value(gauge);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint8_t lv_gauge_get_label_count(lv_obj_t* gauge)
int luat_lv_gauge_get_label_count(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_label_count");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t ret;
    ret = lv_gauge_get_label_count(gauge);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_gauge_get_line_count(lv_obj_t* gauge)
int luat_lv_gauge_get_line_count(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_line_count");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_gauge_get_line_count(gauge);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_gauge_get_scale_angle(lv_obj_t* gauge)
int luat_lv_gauge_get_scale_angle(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_scale_angle");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_gauge_get_scale_angle(gauge);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_gauge_get_angle_offset(lv_obj_t* gauge)
int luat_lv_gauge_get_angle_offset(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_angle_offset");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_gauge_get_angle_offset(gauge);
    lua_pushinteger(L, ret);
    return 1;
}

//  void* lv_gauge_get_needle_img(lv_obj_t* gauge)
int luat_lv_gauge_get_needle_img(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_needle_img");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    void* ret = NULL;
    ret = lv_gauge_get_needle_img(gauge);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_coord_t lv_gauge_get_needle_img_pivot_x(lv_obj_t* gauge)
int luat_lv_gauge_get_needle_img_pivot_x(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_needle_img_pivot_x");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_gauge_get_needle_img_pivot_x(gauge);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_gauge_get_needle_img_pivot_y(lv_obj_t* gauge)
int luat_lv_gauge_get_needle_img_pivot_y(lua_State *L) {
    LV_DEBUG("CALL lv_gauge_get_needle_img_pivot_y");
    lv_obj_t* gauge = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_gauge_get_needle_img_pivot_y(gauge);
    lua_pushinteger(L, ret);
    return 1;
}

