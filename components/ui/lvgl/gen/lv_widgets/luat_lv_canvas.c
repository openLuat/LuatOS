
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  lv_obj_t* lv_canvas_create(lv_obj_t* par, lv_obj_t* copy)
int luat_lv_canvas_create(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_create");
    lv_obj_t* par = (lv_obj_t*)lua_touserdata(L, 1);
    lv_obj_t* copy = (lv_obj_t*)lua_touserdata(L, 2);
    lv_obj_t* ret = NULL;
    ret = lv_canvas_create(par ,copy);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_canvas_set_px(lv_obj_t* canvas, lv_coord_t x, lv_coord_t y, lv_color_t c)
int luat_lv_canvas_set_px(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_set_px");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_color_t c = {0};
    c.full = luaL_checkinteger(L, 4);
    lv_canvas_set_px(canvas ,x ,y ,c);
    return 0;
}

//  void lv_canvas_set_palette(lv_obj_t* canvas, uint8_t id, lv_color_t c)
int luat_lv_canvas_set_palette(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_set_palette");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    uint8_t id = (uint8_t)luaL_checkinteger(L, 2);
    lv_color_t c = {0};
    c.full = luaL_checkinteger(L, 3);
    lv_canvas_set_palette(canvas ,id ,c);
    return 0;
}

//  lv_color_t lv_canvas_get_px(lv_obj_t* canvas, lv_coord_t x, lv_coord_t y)
int luat_lv_canvas_get_px(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_get_px");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_color_t ret;
    ret = lv_canvas_get_px(canvas ,x ,y);
    lua_pushinteger(L, ret.full);
    return 1;
}

//  lv_img_dsc_t* lv_canvas_get_img(lv_obj_t* canvas)
int luat_lv_canvas_get_img(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_get_img");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    lv_img_dsc_t* ret = NULL;
    ret = lv_canvas_get_img(canvas);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void lv_canvas_copy_buf(lv_obj_t* canvas, void* to_copy, lv_coord_t x, lv_coord_t y, lv_coord_t w, lv_coord_t h)
int luat_lv_canvas_copy_buf(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_copy_buf");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    void* to_copy = (void*)lua_touserdata(L, 2);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 5);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 6);
    lv_canvas_copy_buf(canvas ,to_copy ,x ,y ,w ,h);
    return 0;
}

//  void lv_canvas_transform(lv_obj_t* canvas, lv_img_dsc_t* img, int16_t angle, uint16_t zoom, lv_coord_t offset_x, lv_coord_t offset_y, int32_t pivot_x, int32_t pivot_y, bool antialias)
int luat_lv_canvas_transform(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_transform");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    lv_img_dsc_t* img = (lv_img_dsc_t*)lua_touserdata(L, 2);
    int16_t angle = (int16_t)luaL_checkinteger(L, 3);
    uint16_t zoom = (uint16_t)luaL_checkinteger(L, 4);
    lv_coord_t offset_x = (lv_coord_t)luaL_checknumber(L, 5);
    lv_coord_t offset_y = (lv_coord_t)luaL_checknumber(L, 6);
    int32_t pivot_x = (int32_t)luaL_checkinteger(L, 7);
    int32_t pivot_y = (int32_t)luaL_checkinteger(L, 8);
    bool antialias = (bool)lua_toboolean(L, 9);
    lv_canvas_transform(canvas ,img ,angle ,zoom ,offset_x ,offset_y ,pivot_x ,pivot_y ,antialias);
    return 0;
}

//  void lv_canvas_blur_hor(lv_obj_t* canvas, lv_area_t* area, uint16_t r)
int luat_lv_canvas_blur_hor(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_blur_hor");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* area = (lv_area_t*)lua_touserdata(L, 2);
    uint16_t r = (uint16_t)luaL_checkinteger(L, 3);
    lv_canvas_blur_hor(canvas ,area ,r);
    return 0;
}

//  void lv_canvas_blur_ver(lv_obj_t* canvas, lv_area_t* area, uint16_t r)
int luat_lv_canvas_blur_ver(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_blur_ver");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    lv_area_t* area = (lv_area_t*)lua_touserdata(L, 2);
    uint16_t r = (uint16_t)luaL_checkinteger(L, 3);
    lv_canvas_blur_ver(canvas ,area ,r);
    return 0;
}

//  void lv_canvas_fill_bg(lv_obj_t* canvas, lv_color_t color, lv_opa_t opa)
int luat_lv_canvas_fill_bg(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_fill_bg");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    lv_color_t color = {0};
    color.full = luaL_checkinteger(L, 2);
    lv_opa_t opa = (lv_opa_t)luaL_checknumber(L, 3);
    lv_canvas_fill_bg(canvas ,color ,opa);
    return 0;
}

//  void lv_canvas_draw_rect(lv_obj_t* canvas, lv_coord_t x, lv_coord_t y, lv_coord_t w, lv_coord_t h, lv_draw_rect_dsc_t* rect_dsc)
int luat_lv_canvas_draw_rect(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_draw_rect");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t w = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t h = (lv_coord_t)luaL_checknumber(L, 5);
    lv_draw_rect_dsc_t* rect_dsc = (lv_draw_rect_dsc_t*)lua_touserdata(L, 6);
    lv_canvas_draw_rect(canvas ,x ,y ,w ,h ,rect_dsc);
    return 0;
}

//  void lv_canvas_draw_text(lv_obj_t* canvas, lv_coord_t x, lv_coord_t y, lv_coord_t max_w, lv_draw_label_dsc_t* label_draw_dsc, char* txt, lv_label_align_t align)
int luat_lv_canvas_draw_text(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_draw_text");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t max_w = (lv_coord_t)luaL_checknumber(L, 4);
    lv_draw_label_dsc_t* label_draw_dsc = (lv_draw_label_dsc_t*)lua_touserdata(L, 5);
    char* txt = (char*)luaL_checkstring(L, 6);
    lv_label_align_t align = (lv_label_align_t)luaL_checkinteger(L, 7);
    lv_canvas_draw_text(canvas ,x ,y ,max_w ,label_draw_dsc ,txt ,align);
    return 0;
}

//  void lv_canvas_draw_img(lv_obj_t* canvas, lv_coord_t x, lv_coord_t y, void* src, lv_draw_img_dsc_t* img_draw_dsc)
int luat_lv_canvas_draw_img(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_draw_img");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    void* src = (void*)lua_touserdata(L, 4);
    lv_draw_img_dsc_t* img_draw_dsc = (lv_draw_img_dsc_t*)lua_touserdata(L, 5);
    lv_canvas_draw_img(canvas ,x ,y ,src ,img_draw_dsc);
    return 0;
}

//  void lv_canvas_draw_arc(lv_obj_t* canvas, lv_coord_t x, lv_coord_t y, lv_coord_t r, int32_t start_angle, int32_t end_angle, lv_draw_line_dsc_t* arc_draw_dsc)
int luat_lv_canvas_draw_arc(lua_State *L) {
    LV_DEBUG("CALL lv_canvas_draw_arc");
    lv_obj_t* canvas = (lv_obj_t*)lua_touserdata(L, 1);
    lv_coord_t x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t r = (lv_coord_t)luaL_checknumber(L, 4);
    int32_t start_angle = (int32_t)luaL_checkinteger(L, 5);
    int32_t end_angle = (int32_t)luaL_checkinteger(L, 6);
    lv_draw_line_dsc_t* arc_draw_dsc = (lv_draw_line_dsc_t*)lua_touserdata(L, 7);
    lv_canvas_draw_arc(canvas ,x ,y ,r ,start_angle ,end_angle ,arc_draw_dsc);
    return 0;
}

