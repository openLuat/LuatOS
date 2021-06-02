
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_img_dsc_t* lv_img_buf_alloc(lv_coord_t w, lv_coord_t h, lv_img_cf_t cf)
int luat_lv_img_buf_alloc(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_buf_alloc);
    lv_coord_t w = (lv_coord_t)luaL_checkinteger(L, 1);
    lv_coord_t h = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_img_cf_t cf = (lv_img_cf_t)luaL_checkinteger(L, 3);
    lv_img_dsc_t* ret = NULL;
    ret = lv_img_buf_alloc(w ,h ,cf);
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  lv_color_t lv_img_buf_get_px_color(lv_img_dsc_t* dsc, lv_coord_t x, lv_coord_t y, lv_color_t color)
int luat_lv_img_buf_get_px_color(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_buf_get_px_color);
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checkinteger(L, 3);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 4);
    lv_color_t ret;
    ret = lv_img_buf_get_px_color(dsc ,x ,y ,color);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_opa_t lv_img_buf_get_px_alpha(lv_img_dsc_t* dsc, lv_coord_t x, lv_coord_t y)
int luat_lv_img_buf_get_px_alpha(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_buf_get_px_alpha);
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checkinteger(L, 3);
    lv_opa_t ret;
    ret = lv_img_buf_get_px_alpha(dsc ,x ,y);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_img_buf_set_px_color(lv_img_dsc_t* dsc, lv_coord_t x, lv_coord_t y, lv_color_t c)
int luat_lv_img_buf_set_px_color(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_buf_set_px_color);
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checkinteger(L, 3);
    lv_color_t c = {0};
    c.full = luaL_checkinteger(L, 4);
    lv_img_buf_set_px_color(dsc ,x ,y ,c);
    return 0;
}

//  void lv_img_buf_set_px_alpha(lv_img_dsc_t* dsc, lv_coord_t x, lv_coord_t y, lv_opa_t opa)
int luat_lv_img_buf_set_px_alpha(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_buf_set_px_alpha);
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checkinteger(L, 3);
    lv_opa_t opa = (lv_opa_t)luaL_checkinteger(L, 4);
    lv_img_buf_set_px_alpha(dsc ,x ,y ,opa);
    return 0;
}

//  void lv_img_buf_set_palette(lv_img_dsc_t* dsc, uint8_t id, lv_color_t c)
int luat_lv_img_buf_set_palette(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_buf_set_palette);
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    uint8_t id = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t c = {0};
    c.full = luaL_checkinteger(L, 3);
    lv_img_buf_set_palette(dsc ,id ,c);
    return 0;
}

//  void lv_img_buf_free(lv_img_dsc_t* dsc)
int luat_lv_img_buf_free(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_buf_free);
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    lv_img_buf_free(dsc);
    return 0;
}

//  uint32_t lv_img_buf_get_img_size(lv_coord_t w, lv_coord_t h, lv_img_cf_t cf)
int luat_lv_img_buf_get_img_size(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_buf_get_img_size);
    lv_coord_t w = (lv_coord_t)luaL_checkinteger(L, 1);
    lv_coord_t h = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_img_cf_t cf = (lv_img_cf_t)luaL_checkinteger(L, 3);
    uint32_t ret;
    ret = lv_img_buf_get_img_size(w ,h ,cf);
    lua_pushinteger(L, ret);
    return 1;
}

