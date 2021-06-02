
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_res_t lv_img_decoder_get_info(char* src, lv_img_header_t* header)
int luat_lv_img_decoder_get_info(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_decoder_get_info);
    char* src = (char*)luaL_checkstring(L, 1);
    lv_img_header_t* header = (lv_img_header_t*)lua_touserdata(L, 2);
    lv_res_t ret;
    ret = lv_img_decoder_get_info(src ,header);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_res_t lv_img_decoder_open(lv_img_decoder_dsc_t* dsc, void* src, lv_color_t color)
int luat_lv_img_decoder_open(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_decoder_open);
    lv_img_decoder_dsc_t* dsc = (lv_img_decoder_dsc_t*)lua_touserdata(L, 1);
    void* src = (void*)lua_touserdata(L, 2);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 3);
    lv_res_t ret;
    ret = lv_img_decoder_open(dsc ,src ,color);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_res_t lv_img_decoder_read_line(lv_img_decoder_dsc_t* dsc, lv_coord_t x, lv_coord_t y, lv_coord_t len, uint8_t* buf)
int luat_lv_img_decoder_read_line(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_decoder_read_line);
    lv_img_decoder_dsc_t* dsc = (lv_img_decoder_dsc_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checkinteger(L, 3);
    lv_coord_t len = (lv_coord_t)luaL_checkinteger(L, 4);
    uint8_t* buf = (uint8_t*)lua_touserdata(L, 5);
    lv_res_t ret;
    ret = lv_img_decoder_read_line(dsc ,x ,y ,len ,buf);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  void lv_img_decoder_close(lv_img_decoder_dsc_t* dsc)
int luat_lv_img_decoder_close(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_decoder_close);
    lv_img_decoder_dsc_t* dsc = (lv_img_decoder_dsc_t*)lua_touserdata(L, 1);
    lv_img_decoder_close(dsc);
    return 0;
}

//  lv_img_decoder_t* lv_img_decoder_create()
int luat_lv_img_decoder_create(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_decoder_create);
    lv_img_decoder_t* ret = NULL;
    ret = lv_img_decoder_create();
    lua_pushlightuserdata(L, ret);
    return 1;
}

//  void lv_img_decoder_delete(lv_img_decoder_t* decoder)
int luat_lv_img_decoder_delete(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_decoder_delete);
    lv_img_decoder_t* decoder = (lv_img_decoder_t*)lua_touserdata(L, 1);
    lv_img_decoder_delete(decoder);
    return 0;
}

//  lv_res_t lv_img_decoder_built_in_info(lv_img_decoder_t* decoder, void* src, lv_img_header_t* header)
int luat_lv_img_decoder_built_in_info(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_decoder_built_in_info);
    lv_img_decoder_t* decoder = (lv_img_decoder_t*)lua_touserdata(L, 1);
    void* src = (void*)lua_touserdata(L, 2);
    lv_img_header_t* header = (lv_img_header_t*)lua_touserdata(L, 3);
    lv_res_t ret;
    ret = lv_img_decoder_built_in_info(decoder ,src ,header);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_res_t lv_img_decoder_built_in_open(lv_img_decoder_t* decoder, lv_img_decoder_dsc_t* dsc)
int luat_lv_img_decoder_built_in_open(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_decoder_built_in_open);
    lv_img_decoder_t* decoder = (lv_img_decoder_t*)lua_touserdata(L, 1);
    lv_img_decoder_dsc_t* dsc = (lv_img_decoder_dsc_t*)lua_touserdata(L, 2);
    lv_res_t ret;
    ret = lv_img_decoder_built_in_open(decoder ,dsc);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_res_t lv_img_decoder_built_in_read_line(lv_img_decoder_t* decoder, lv_img_decoder_dsc_t* dsc, lv_coord_t x, lv_coord_t y, lv_coord_t len, uint8_t* buf)
int luat_lv_img_decoder_built_in_read_line(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_decoder_built_in_read_line);
    lv_img_decoder_t* decoder = (lv_img_decoder_t*)lua_touserdata(L, 1);
    lv_img_decoder_dsc_t* dsc = (lv_img_decoder_dsc_t*)lua_touserdata(L, 2);
    lv_coord_t x = (lv_coord_t)luaL_checkinteger(L, 3);
    lv_coord_t y = (lv_coord_t)luaL_checkinteger(L, 4);
    lv_coord_t len = (lv_coord_t)luaL_checkinteger(L, 5);
    uint8_t* buf = (uint8_t*)lua_touserdata(L, 6);
    lv_res_t ret;
    ret = lv_img_decoder_built_in_read_line(decoder ,dsc ,x ,y ,len ,buf);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  void lv_img_decoder_built_in_close(lv_img_decoder_t* decoder, lv_img_decoder_dsc_t* dsc)
int luat_lv_img_decoder_built_in_close(lua_State *L) {
    LV_DEBUG("CALL %s", lv_img_decoder_built_in_close);
    lv_img_decoder_t* decoder = (lv_img_decoder_t*)lua_touserdata(L, 1);
    lv_img_decoder_dsc_t* dsc = (lv_img_decoder_dsc_t*)lua_touserdata(L, 2);
    lv_img_decoder_built_in_close(decoder ,dsc);
    return 0;
}

