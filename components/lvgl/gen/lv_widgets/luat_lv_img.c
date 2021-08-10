
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_img_dsc_t* lv_img_buf_alloc(lv_coord_t w, lv_coord_t h, lv_img_cf_t cf)
int luat_lv_img_buf_alloc(lua_State *L) {
    LV_DEBUG("CALL lv_img_buf_alloc");
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 1);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 2);
    lv_img_cf_t cf = (lv_img_cf_t)luaL_checkinteger(L, 3);
    lv_img_dsc_t* ret = NULL;
    ret = lv_img_buf_alloc(w ,h ,cf);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  lv_color_t lv_img_buf_get_px_color(lv_img_dsc_t* dsc, lv_coord_t x, lv_coord_t y, lv_color_t color)
int luat_lv_img_buf_get_px_color(lua_State *L) {
    LV_DEBUG("CALL lv_img_buf_get_px_color");
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 4);
    lv_color_t ret;
    ret = lv_img_buf_get_px_color(dsc ,x ,y ,color);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_opa_t lv_img_buf_get_px_alpha(lv_img_dsc_t* dsc, lv_coord_t x, lv_coord_t y)
int luat_lv_img_buf_get_px_alpha(lua_State *L) {
    LV_DEBUG("CALL lv_img_buf_get_px_alpha");
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_opa_t ret;
    ret = lv_img_buf_get_px_alpha(dsc ,x ,y);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_img_buf_set_px_color(lv_img_dsc_t* dsc, lv_coord_t x, lv_coord_t y, lv_color_t c)
int luat_lv_img_buf_set_px_color(lua_State *L) {
    LV_DEBUG("CALL lv_img_buf_set_px_color");
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_color_t c = {0};
    c.full = luaL_checkinteger(L, 4);
    lv_img_buf_set_px_color(dsc ,x ,y ,c);
    return 0;
}

//  void lv_img_buf_set_px_alpha(lv_img_dsc_t* dsc, lv_coord_t x, lv_coord_t y, lv_opa_t opa)
int luat_lv_img_buf_set_px_alpha(lua_State *L) {
    LV_DEBUG("CALL lv_img_buf_set_px_alpha");
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_opa_t opa = (lv_opa_t)luaL_checknumber(L, 4);
    lv_img_buf_set_px_alpha(dsc ,x ,y ,opa);
    return 0;
}

//  void lv_img_buf_set_palette(lv_img_dsc_t* dsc, uint8_t id, lv_color_t c)
int luat_lv_img_buf_set_palette(lua_State *L) {
    LV_DEBUG("CALL lv_img_buf_set_palette");
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    uint8_t id = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t c = {0};
    c.full = luaL_checkinteger(L, 3);
    lv_img_buf_set_palette(dsc ,id ,c);
    return 0;
}

//  void lv_img_buf_free(lv_img_dsc_t* dsc)
int luat_lv_img_buf_free(lua_State *L) {
    LV_DEBUG("CALL lv_img_buf_free");
    lv_img_dsc_t* dsc = (lv_img_dsc_t*)lua_touserdata(L, 1);
    lv_img_buf_free(dsc);
    return 0;
}

//  uint32_t lv_img_buf_get_img_size(lv_coord_t w, lv_coord_t h, lv_img_cf_t cf)
int luat_lv_img_buf_get_img_size(lua_State *L) {
    LV_DEBUG("CALL lv_img_buf_get_img_size");
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 1);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 2);
    lv_img_cf_t cf = (lv_img_cf_t)luaL_checkinteger(L, 3);
    uint32_t ret;
    ret = lv_img_buf_get_img_size(w ,h ,cf);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_res_t lv_img_decoder_get_info(char* src, lv_img_header_t* header)
int luat_lv_img_decoder_get_info(lua_State *L) {
    LV_DEBUG("CALL lv_img_decoder_get_info");
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
    LV_DEBUG("CALL lv_img_decoder_open");
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
    LV_DEBUG("CALL lv_img_decoder_read_line");
    lv_img_decoder_dsc_t* dsc = (lv_img_decoder_dsc_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t len = (lv_coord_t)luaL_checknumber(L, 4);
    uint8_t* buf = (uint8_t*)lua_touserdata(L, 5);
    lv_res_t ret;
    ret = lv_img_decoder_read_line(dsc ,x ,y ,len ,buf);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  void lv_img_decoder_close(lv_img_decoder_dsc_t* dsc)
int luat_lv_img_decoder_close(lua_State *L) {
    LV_DEBUG("CALL lv_img_decoder_close");
    lv_img_decoder_dsc_t* dsc = (lv_img_decoder_dsc_t*)lua_touserdata(L, 1);
    lv_img_decoder_close(dsc);
    return 0;
}

//  lv_img_decoder_t* lv_img_decoder_create()
int luat_lv_img_decoder_create(lua_State *L) {
    LV_DEBUG("CALL lv_img_decoder_create");
    lv_img_decoder_t* ret = NULL;
    ret = lv_img_decoder_create();
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_img_decoder_delete(lv_img_decoder_t* decoder)
int luat_lv_img_decoder_delete(lua_State *L) {
    LV_DEBUG("CALL lv_img_decoder_delete");
    lv_img_decoder_t* decoder = (lv_img_decoder_t*)lua_touserdata(L, 1);
    lv_img_decoder_delete(decoder);
    return 0;
}

//  lv_res_t lv_img_decoder_built_in_info(lv_img_decoder_t* decoder, void* src, lv_img_header_t* header)
int luat_lv_img_decoder_built_in_info(lua_State *L) {
    LV_DEBUG("CALL lv_img_decoder_built_in_info");
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
    LV_DEBUG("CALL lv_img_decoder_built_in_open");
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
    LV_DEBUG("CALL lv_img_decoder_built_in_read_line");
    lv_img_decoder_t* decoder = (lv_img_decoder_t*)lua_touserdata(L, 1);
    lv_img_decoder_dsc_t* dsc = (lv_img_decoder_dsc_t*)lua_touserdata(L, 2);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t len = (lv_coord_t)luaL_checknumber(L, 5);
    uint8_t* buf = (uint8_t*)lua_touserdata(L, 6);
    lv_res_t ret;
    ret = lv_img_decoder_built_in_read_line(decoder ,dsc ,x ,y ,len ,buf);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  void lv_img_decoder_built_in_close(lv_img_decoder_t* decoder, lv_img_decoder_dsc_t* dsc)
int luat_lv_img_decoder_built_in_close(lua_State *L) {
    LV_DEBUG("CALL lv_img_decoder_built_in_close");
    lv_img_decoder_t* decoder = (lv_img_decoder_t*)lua_touserdata(L, 1);
    lv_img_decoder_dsc_t* dsc = (lv_img_decoder_dsc_t*)lua_touserdata(L, 2);
    lv_img_decoder_built_in_close(decoder ,dsc);
    return 0;
}

//  lv_img_src_t lv_img_src_get_type(void* src)
int luat_lv_img_src_get_type(lua_State *L) {
    LV_DEBUG("CALL lv_img_src_get_type");
    void* src = (void*)lua_touserdata(L, 1);
    lv_img_src_t ret;
    ret = lv_img_src_get_type(src);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint8_t lv_img_cf_get_px_size(lv_img_cf_t cf)
int luat_lv_img_cf_get_px_size(lua_State *L) {
    LV_DEBUG("CALL lv_img_cf_get_px_size");
    lv_img_cf_t cf = (lv_img_cf_t)luaL_checkinteger(L, 1);
    uint8_t ret;
    ret = lv_img_cf_get_px_size(cf);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_img_cf_is_chroma_keyed(lv_img_cf_t cf)
int luat_lv_img_cf_is_chroma_keyed(lua_State *L) {
    LV_DEBUG("CALL lv_img_cf_is_chroma_keyed");
    lv_img_cf_t cf = (lv_img_cf_t)luaL_checkinteger(L, 1);
    bool ret;
    ret = lv_img_cf_is_chroma_keyed(cf);
    lua_pushboolean(L, ret);
    return 1;
}

//  bool lv_img_cf_has_alpha(lv_img_cf_t cf)
int luat_lv_img_cf_has_alpha(lua_State *L) {
    LV_DEBUG("CALL lv_img_cf_has_alpha");
    lv_img_cf_t cf = (lv_img_cf_t)luaL_checkinteger(L, 1);
    bool ret;
    ret = lv_img_cf_has_alpha(cf);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_obj_t* lv_img_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_img_create(lua_State *L) {
    LV_DEBUG("CALL lv_img_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_img_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_img_set_auto_size(lv_obj_t* img, bool autosize_en)
int luat_lv_img_set_auto_size(lua_State *L) {
    LV_DEBUG("CALL lv_img_set_auto_size");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    bool autosize_en = (bool)lua_toboolean(L, 2);
    lv_img_set_auto_size(img ,autosize_en);
    return 0;
}

//  void lv_img_set_offset_x(lv_obj_t* img, lv_coord_t x)
int luat_lv_img_set_offset_x(lua_State *L) {
    LV_DEBUG("CALL lv_img_set_offset_x");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_img_set_offset_x(img ,x);
    return 0;
}

//  void lv_img_set_offset_y(lv_obj_t* img, lv_coord_t y)
int luat_lv_img_set_offset_y(lua_State *L) {
    LV_DEBUG("CALL lv_img_set_offset_y");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 2);
    lv_img_set_offset_y(img ,y);
    return 0;
}

//  void lv_img_set_pivot(lv_obj_t* img, lv_coord_t pivot_x, lv_coord_t pivot_y)
int luat_lv_img_set_pivot(lua_State *L) {
    LV_DEBUG("CALL lv_img_set_pivot");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t pivot_x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t pivot_y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_img_set_pivot(img ,pivot_x ,pivot_y);
    return 0;
}

//  void lv_img_set_angle(lv_obj_t* img, int16_t angle)
int luat_lv_img_set_angle(lua_State *L) {
    LV_DEBUG("CALL lv_img_set_angle");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    int16_t angle = (int16_t)luaL_checkinteger(L, 2);
    lv_img_set_angle(img ,angle);
    return 0;
}

//  void lv_img_set_zoom(lv_obj_t* img, uint16_t zoom)
int luat_lv_img_set_zoom(lua_State *L) {
    LV_DEBUG("CALL lv_img_set_zoom");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t zoom = (uint16_t)luaL_checkinteger(L, 2);
    lv_img_set_zoom(img ,zoom);
    return 0;
}

//  void lv_img_set_antialias(lv_obj_t* img, bool antialias)
int luat_lv_img_set_antialias(lua_State *L) {
    LV_DEBUG("CALL lv_img_set_antialias");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    bool antialias = (bool)lua_toboolean(L, 2);
    lv_img_set_antialias(img ,antialias);
    return 0;
}

//  void* lv_img_get_src(lv_obj_t* img)
int luat_lv_img_get_src(lua_State *L) {
    LV_DEBUG("CALL lv_img_get_src");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    void* ret = NULL;
    ret = lv_img_get_src(img);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  char* lv_img_get_file_name(lv_obj_t* img)
int luat_lv_img_get_file_name(lua_State *L) {
    LV_DEBUG("CALL lv_img_get_file_name");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    char* ret = NULL;
    ret = lv_img_get_file_name(img);
    lua_pushstring(L, ret);
    return 1;
}

//  bool lv_img_get_auto_size(lv_obj_t* img)
int luat_lv_img_get_auto_size(lua_State *L) {
    LV_DEBUG("CALL lv_img_get_auto_size");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_img_get_auto_size(img);
    lua_pushboolean(L, ret);
    return 1;
}

//  lv_coord_t lv_img_get_offset_x(lv_obj_t* img)
int luat_lv_img_get_offset_x(lua_State *L) {
    LV_DEBUG("CALL lv_img_get_offset_x");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_img_get_offset_x(img);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_coord_t lv_img_get_offset_y(lv_obj_t* img)
int luat_lv_img_get_offset_y(lua_State *L) {
    LV_DEBUG("CALL lv_img_get_offset_y");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t ret;
    ret = lv_img_get_offset_y(img);
    lua_pushinteger(L, ret);
    return 1;
}

//  uint16_t lv_img_get_angle(lv_obj_t* img)
int luat_lv_img_get_angle(lua_State *L) {
    LV_DEBUG("CALL lv_img_get_angle");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_img_get_angle(img);
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_img_get_pivot(lv_obj_t* img, lv_point_t* center)
int luat_lv_img_get_pivot(lua_State *L) {
    LV_DEBUG("CALL lv_img_get_pivot");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    lv_point_t* center = (lv_point_t*)lua_touserdata(L, 2);
    lv_img_get_pivot(img ,center);
    return 0;
}

//  uint16_t lv_img_get_zoom(lv_obj_t* img)
int luat_lv_img_get_zoom(lua_State *L) {
    LV_DEBUG("CALL lv_img_get_zoom");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    uint16_t ret;
    ret = lv_img_get_zoom(img);
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_img_get_antialias(lv_obj_t* img)
int luat_lv_img_get_antialias(lua_State *L) {
    LV_DEBUG("CALL lv_img_get_antialias");
    lv_obj_t* img = (lv_obj_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_img_get_antialias(img);
    lua_pushboolean(L, ret);
    return 1;
}

