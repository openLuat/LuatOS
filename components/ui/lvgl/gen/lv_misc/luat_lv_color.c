
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  uint8_t lv_color_to1(lv_color_t color)
int luat_lv_color_to1(lua_State *L) {
    LV_DEBUG("CALL lv_color_to1");
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 1);
    uint8_t ret;
    ret = lv_color_to1(color);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint8_t lv_color_to8(lv_color_t color)
int luat_lv_color_to8(lua_State *L) {
    LV_DEBUG("CALL lv_color_to8");
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 1);
    uint8_t ret;
    ret = lv_color_to8(color);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_color_to16(lv_color_t color)
int luat_lv_color_to16(lua_State *L) {
    LV_DEBUG("CALL lv_color_to16");
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 1);
    uint16_t ret;
    ret = lv_color_to16(color);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint32_t lv_color_to32(lv_color_t color)
int luat_lv_color_to32(lua_State *L) {
    LV_DEBUG("CALL lv_color_to32");
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 1);
    uint32_t ret;
    ret = lv_color_to32(color);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_color_t lv_color_mix(lv_color_t c1, lv_color_t c2, uint8_t mix)
int luat_lv_color_mix(lua_State *L) {
    LV_DEBUG("CALL lv_color_mix");
    lv_color_t c1 = {0};
    c1.full = luaL_checkinteger(L, 1);
    lv_color_t c2 = {0};
    c2.full = luaL_checkinteger(L, 2);
    uint8_t mix = (uint8_t)luaL_checkinteger(L, 3);
    lv_color_t ret;
    ret = lv_color_mix(c1 ,c2 ,mix);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_color_premult(lv_color_t c, uint8_t mix, uint16_t* out)
int luat_lv_color_premult(lua_State *L) {
    LV_DEBUG("CALL lv_color_premult");
    lv_color_t c = {0};
    c.full = luaL_checkinteger(L, 1);
    uint8_t mix = (uint8_t)luaL_checkinteger(L, 2);
    uint16_t* out = (uint16_t*)lua_touserdata(L, 3);
    lv_color_premult(c ,mix ,out);
    return 0;
}

//  lv_color_t lv_color_mix_premult(uint16_t* premult_c1, lv_color_t c2, uint8_t mix)
int luat_lv_color_mix_premult(lua_State *L) {
    LV_DEBUG("CALL lv_color_mix_premult");
    uint16_t* premult_c1 = (uint16_t*)lua_touserdata(L, 1);
    lv_color_t c2 = {0};
    c2.full = luaL_checkinteger(L, 2);
    uint8_t mix = (uint8_t)luaL_checkinteger(L, 3);
    lv_color_t ret;
    ret = lv_color_mix_premult(premult_c1 ,c2 ,mix);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_color_mix_with_alpha(lv_color_t bg_color, lv_opa_t bg_opa, lv_color_t fg_color, lv_opa_t fg_opa, lv_color_t* res_color, lv_opa_t* res_opa)
int luat_lv_color_mix_with_alpha(lua_State *L) {
    LV_DEBUG("CALL lv_color_mix_with_alpha");
    lv_color_t bg_color = {0};
    bg_color.full = luaL_checkinteger(L, 1);
    lv_opa_t bg_opa = (lv_opa_t)luaL_checknumber(L, 2);
    lv_color_t fg_color = {0};
    fg_color.full = luaL_checkinteger(L, 3);
    lv_opa_t fg_opa = (lv_opa_t)luaL_checknumber(L, 4);
    lv_color_t* res_color = (lv_color_t*)lua_touserdata(L, 5);
    lv_opa_t* res_opa = (lv_opa_t*)lua_touserdata(L, 6);
    lv_color_mix_with_alpha(bg_color ,bg_opa ,fg_color ,fg_opa ,res_color ,res_opa);
    return 0;
}

//  uint8_t lv_color_brightness(lv_color_t color)
int luat_lv_color_brightness(lua_State *L) {
    LV_DEBUG("CALL lv_color_brightness");
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 1);
    uint8_t ret;
    ret = lv_color_brightness(color);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_color_t lv_color_make(uint8_t r, uint8_t g, uint8_t b)
int luat_lv_color_make(lua_State *L) {
    LV_DEBUG("CALL lv_color_make");
    uint8_t r = (uint8_t)luaL_checkinteger(L, 1);
    uint8_t g = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t b = (uint8_t)luaL_checkinteger(L, 3);
    lv_color_t ret;
    ret = lv_color_make(r ,g ,b);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_color_hex(uint32_t c)
int luat_lv_color_hex(lua_State *L) {
    LV_DEBUG("CALL lv_color_hex");
    uint32_t c = (uint32_t)luaL_checkinteger(L, 1);
    lv_color_t ret;
    ret = lv_color_hex(c);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_color_hex3(uint32_t c)
int luat_lv_color_hex3(lua_State *L) {
    LV_DEBUG("CALL lv_color_hex3");
    uint32_t c = (uint32_t)luaL_checkinteger(L, 1);
    lv_color_t ret;
    ret = lv_color_hex3(c);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  void lv_color_fill(lv_color_t* buf, lv_color_t color, uint32_t px_num)
int luat_lv_color_fill(lua_State *L) {
    LV_DEBUG("CALL lv_color_fill");
    lv_color_t* buf = (lv_color_t*)lua_touserdata(L, 1);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 2);
    uint32_t px_num = (uint32_t)luaL_checkinteger(L, 3);
    lv_color_fill(buf ,color ,px_num);
    return 0;
}

//  lv_color_t lv_color_lighten(lv_color_t c, lv_opa_t lvl)
int luat_lv_color_lighten(lua_State *L) {
    LV_DEBUG("CALL lv_color_lighten");
    lv_color_t c = {0};
    c.full = luaL_checkinteger(L, 1);
    lv_opa_t lvl = (lv_opa_t)luaL_checknumber(L, 2);
    lv_color_t ret;
    ret = lv_color_lighten(c ,lvl);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_color_darken(lv_color_t c, lv_opa_t lvl)
int luat_lv_color_darken(lua_State *L) {
    LV_DEBUG("CALL lv_color_darken");
    lv_color_t c = {0};
    c.full = luaL_checkinteger(L, 1);
    lv_opa_t lvl = (lv_opa_t)luaL_checknumber(L, 2);
    lv_color_t ret;
    ret = lv_color_darken(c ,lvl);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_t lv_color_hsv_to_rgb(uint16_t h, uint8_t s, uint8_t v)
int luat_lv_color_hsv_to_rgb(lua_State *L) {
    LV_DEBUG("CALL lv_color_hsv_to_rgb");
    uint16_t h = (uint16_t)luaL_checkinteger(L, 1);
    uint8_t s = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t v = (uint8_t)luaL_checkinteger(L, 3);
    lv_color_t ret;
    ret = lv_color_hsv_to_rgb(h ,s ,v);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_color_hsv_t lv_color_rgb_to_hsv(uint8_t r8, uint8_t g8, uint8_t b8)
int luat_lv_color_rgb_to_hsv(lua_State *L) {
    LV_DEBUG("CALL lv_color_rgb_to_hsv");
    uint8_t r8 = (uint8_t)luaL_checkinteger(L, 1);
    uint8_t g8 = (uint8_t)luaL_checkinteger(L, 2);
    uint8_t b8 = (uint8_t)luaL_checkinteger(L, 3);
    lv_color_hsv_t ret;
    ret = lv_color_rgb_to_hsv(r8 ,g8 ,b8);
    lua_pushinteger(L, ret.h);
    lua_pushinteger(L, ret.s);
    lua_pushinteger(L, ret.v);
    return 3;
}

//  lv_color_hsv_t lv_color_to_hsv(lv_color_t color)
int luat_lv_color_to_hsv(lua_State *L) {
    LV_DEBUG("CALL lv_color_to_hsv");
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 1);
    lv_color_hsv_t ret;
    ret = lv_color_to_hsv(color);
    lua_pushinteger(L, ret.h);
    lua_pushinteger(L, ret.s);
    lua_pushinteger(L, ret.v);
    return 3;
}

