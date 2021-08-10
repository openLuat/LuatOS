
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  int16_t lv_draw_mask_add(void* param, void* custom_id)
int luat_lv_draw_mask_add(lua_State *L) {
    LV_DEBUG("CALL lv_draw_mask_add");
    void* param = (void*)lua_touserdata(L, 1);
    void* custom_id = (void*)lua_touserdata(L, 2);
    int16_t ret;
    ret = lv_draw_mask_add(param ,custom_id);
    lua_pushinteger(L, ret);
    return 1;
}

//  lv_draw_mask_res_t lv_draw_mask_apply(lv_opa_t* mask_buf, lv_coord_t abs_x, lv_coord_t abs_y, lv_coord_t len)
int luat_lv_draw_mask_apply(lua_State *L) {
    LV_DEBUG("CALL lv_draw_mask_apply");
    lv_opa_t* mask_buf = (lv_opa_t*)lua_touserdata(L, 1);
    lv_coord_t abs_x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t abs_y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t len = (lv_coord_t)luaL_checknumber(L, 4);
    lv_draw_mask_res_t ret;
    ret = lv_draw_mask_apply(mask_buf ,abs_x ,abs_y ,len);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  void* lv_draw_mask_remove_id(int16_t id)
int luat_lv_draw_mask_remove_id(lua_State *L) {
    LV_DEBUG("CALL lv_draw_mask_remove_id");
    int16_t id = (int16_t)luaL_checkinteger(L, 1);
    void* ret = NULL;
    ret = lv_draw_mask_remove_id(id);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  void* lv_draw_mask_remove_custom(void* custom_id)
int luat_lv_draw_mask_remove_custom(lua_State *L) {
    LV_DEBUG("CALL lv_draw_mask_remove_custom");
    void* custom_id = (void*)lua_touserdata(L, 1);
    void* ret = NULL;
    ret = lv_draw_mask_remove_custom(custom_id);
    if (ret) lua_pushlightuserdata(L, ret); else lua_pushnil(L);
    return 1;
}

//  uint8_t lv_draw_mask_get_cnt()
int luat_lv_draw_mask_get_cnt(lua_State *L) {
    LV_DEBUG("CALL lv_draw_mask_get_cnt");
    uint8_t ret;
    ret = lv_draw_mask_get_cnt();
    lua_pushinteger(L, ret);
    return 1;
}

//  void lv_draw_mask_line_points_init(lv_draw_mask_line_param_t* param, lv_coord_t p1x, lv_coord_t p1y, lv_coord_t p2x, lv_coord_t p2y, lv_draw_mask_line_side_t side)
int luat_lv_draw_mask_line_points_init(lua_State *L) {
    LV_DEBUG("CALL lv_draw_mask_line_points_init");
    lv_draw_mask_line_param_t* param = (lv_draw_mask_line_param_t*)lua_touserdata(L, 1);
    lv_coord_t p1x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t p1y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t p2x = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t p2y = (lv_coord_t)luaL_checknumber(L, 5);
    lv_draw_mask_line_side_t side = (lv_draw_mask_line_side_t)luaL_checkinteger(L, 6);
    lv_draw_mask_line_points_init(param ,p1x ,p1y ,p2x ,p2y ,side);
    return 0;
}

//  void lv_draw_mask_line_angle_init(lv_draw_mask_line_param_t* param, lv_coord_t p1x, lv_coord_t py, int16_t angle, lv_draw_mask_line_side_t side)
int luat_lv_draw_mask_line_angle_init(lua_State *L) {
    LV_DEBUG("CALL lv_draw_mask_line_angle_init");
    lv_draw_mask_line_param_t* param = (lv_draw_mask_line_param_t*)lua_touserdata(L, 1);
    lv_coord_t p1x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t py = (lv_coord_t)luaL_checknumber(L, 3);
    int16_t angle = (int16_t)luaL_checkinteger(L, 4);
    lv_draw_mask_line_side_t side = (lv_draw_mask_line_side_t)luaL_checkinteger(L, 5);
    lv_draw_mask_line_angle_init(param ,p1x ,py ,angle ,side);
    return 0;
}

//  void lv_draw_mask_angle_init(lv_draw_mask_angle_param_t* param, lv_coord_t vertex_x, lv_coord_t vertex_y, lv_coord_t start_angle, lv_coord_t end_angle)
int luat_lv_draw_mask_angle_init(lua_State *L) {
    LV_DEBUG("CALL lv_draw_mask_angle_init");
    lv_draw_mask_angle_param_t* param = (lv_draw_mask_angle_param_t*)lua_touserdata(L, 1);
    lv_coord_t vertex_x = (lv_coord_t)luaL_checknumber(L, 2);
    lv_coord_t vertex_y = (lv_coord_t)luaL_checknumber(L, 3);
    lv_coord_t start_angle = (lv_coord_t)luaL_checknumber(L, 4);
    lv_coord_t end_angle = (lv_coord_t)luaL_checknumber(L, 5);
    lv_draw_mask_angle_init(param ,vertex_x ,vertex_y ,start_angle ,end_angle);
    return 0;
}

//  void lv_draw_mask_radius_init(lv_draw_mask_radius_param_t* param, lv_area_t* rect, lv_coord_t radius, bool inv)
int luat_lv_draw_mask_radius_init(lua_State *L) {
    LV_DEBUG("CALL lv_draw_mask_radius_init");
    lv_draw_mask_radius_param_t* param = (lv_draw_mask_radius_param_t*)lua_touserdata(L, 1);
    lv_area_t* rect = (lv_area_t*)lua_touserdata(L, 2);
    lv_coord_t radius = (lv_coord_t)luaL_checknumber(L, 3);
    bool inv = (bool)lua_toboolean(L, 4);
    lv_draw_mask_radius_init(param ,rect ,radius ,inv);
    return 0;
}

//  void lv_draw_mask_fade_init(lv_draw_mask_fade_param_t* param, lv_area_t* coords, lv_opa_t opa_top, lv_coord_t y_top, lv_opa_t opa_bottom, lv_coord_t y_bottom)
int luat_lv_draw_mask_fade_init(lua_State *L) {
    LV_DEBUG("CALL lv_draw_mask_fade_init");
    lv_draw_mask_fade_param_t* param = (lv_draw_mask_fade_param_t*)lua_touserdata(L, 1);
    lv_area_t* coords = (lv_area_t*)lua_touserdata(L, 2);
    lv_opa_t opa_top = (lv_opa_t)luaL_checknumber(L, 3);
    lv_coord_t y_top = (lv_coord_t)luaL_checknumber(L, 4);
    lv_opa_t opa_bottom = (lv_opa_t)luaL_checknumber(L, 5);
    lv_coord_t y_bottom = (lv_coord_t)luaL_checknumber(L, 6);
    lv_draw_mask_fade_init(param ,coords ,opa_top ,y_top ,opa_bottom ,y_bottom);
    return 0;
}

//  void lv_draw_mask_map_init(lv_draw_mask_map_param_t* param, lv_area_t* coords, lv_opa_t* map)
int luat_lv_draw_mask_map_init(lua_State *L) {
    LV_DEBUG("CALL lv_draw_mask_map_init");
    lv_draw_mask_map_param_t* param = (lv_draw_mask_map_param_t*)lua_touserdata(L, 1);
    lv_area_t* coords = (lv_area_t*)lua_touserdata(L, 2);
    lv_opa_t* map = (lv_opa_t*)lua_touserdata(L, 3);
    lv_draw_mask_map_init(param ,coords ,map);
    return 0;
}

//  void lv_draw_rect_dsc_init(lv_draw_rect_dsc_t* dsc)
int luat_lv_draw_rect_dsc_init(lua_State *L) {
    LV_DEBUG("CALL lv_draw_rect_dsc_init");
    lv_draw_rect_dsc_t* dsc = (lv_draw_rect_dsc_t*)lua_touserdata(L, 1);
    lv_draw_rect_dsc_init(dsc);
    return 0;
}

//  void lv_draw_rect(lv_area_t* coords, lv_area_t* mask, lv_draw_rect_dsc_t* dsc)
int luat_lv_draw_rect(lua_State *L) {
    LV_DEBUG("CALL lv_draw_rect");
    lv_area_t* coords = (lv_area_t*)lua_touserdata(L, 1);
    lv_area_t* mask = (lv_area_t*)lua_touserdata(L, 2);
    lv_draw_rect_dsc_t* dsc = (lv_draw_rect_dsc_t*)lua_touserdata(L, 3);
    lv_draw_rect(coords ,mask ,dsc);
    return 0;
}

//  void lv_draw_px(lv_point_t* point, lv_area_t* clip_area, lv_style_t* style)
int luat_lv_draw_px(lua_State *L) {
    LV_DEBUG("CALL lv_draw_px");
    lv_point_t* point = (lv_point_t*)lua_touserdata(L, 1);
    lv_area_t* clip_area = (lv_area_t*)lua_touserdata(L, 2);
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 3);
    lv_draw_px(point ,clip_area ,style);
    return 0;
}

//  void lv_draw_label_dsc_init(lv_draw_label_dsc_t* dsc)
int luat_lv_draw_label_dsc_init(lua_State *L) {
    LV_DEBUG("CALL lv_draw_label_dsc_init");
    lv_draw_label_dsc_t* dsc = (lv_draw_label_dsc_t*)lua_touserdata(L, 1);
    lv_draw_label_dsc_init(dsc);
    return 0;
}

//  void lv_draw_label(lv_area_t* coords, lv_area_t* mask, lv_draw_label_dsc_t* dsc, char* txt, lv_draw_label_hint_t* hint)
int luat_lv_draw_label(lua_State *L) {
    LV_DEBUG("CALL lv_draw_label");
    lv_area_t* coords = (lv_area_t*)lua_touserdata(L, 1);
    lv_area_t* mask = (lv_area_t*)lua_touserdata(L, 2);
    lv_draw_label_dsc_t* dsc = (lv_draw_label_dsc_t*)lua_touserdata(L, 3);
    char* txt = (char*)luaL_checkstring(L, 4);
    lv_draw_label_hint_t* hint = (lv_draw_label_hint_t*)lua_touserdata(L, 5);
    lv_draw_label(coords ,mask ,dsc ,txt ,hint);
    return 0;
}

//  void lv_draw_img_dsc_init(lv_draw_img_dsc_t* dsc)
int luat_lv_draw_img_dsc_init(lua_State *L) {
    LV_DEBUG("CALL lv_draw_img_dsc_init");
    lv_draw_img_dsc_t* dsc = (lv_draw_img_dsc_t*)lua_touserdata(L, 1);
    lv_draw_img_dsc_init(dsc);
    return 0;
}

//  void lv_draw_img(lv_area_t* coords, lv_area_t* mask, void* src, lv_draw_img_dsc_t* dsc)
int luat_lv_draw_img(lua_State *L) {
    LV_DEBUG("CALL lv_draw_img");
    lv_area_t* coords = (lv_area_t*)lua_touserdata(L, 1);
    lv_area_t* mask = (lv_area_t*)lua_touserdata(L, 2);
    void* src = (void*)lua_touserdata(L, 3);
    lv_draw_img_dsc_t* dsc = (lv_draw_img_dsc_t*)lua_touserdata(L, 4);
    lv_draw_img(coords ,mask ,src ,dsc);
    return 0;
}

//  void lv_draw_line(lv_point_t* point1, lv_point_t* point2, lv_area_t* clip, lv_draw_line_dsc_t* dsc)
int luat_lv_draw_line(lua_State *L) {
    LV_DEBUG("CALL lv_draw_line");
    lv_point_t* point1 = (lv_point_t*)lua_touserdata(L, 1);
    lv_point_t* point2 = (lv_point_t*)lua_touserdata(L, 2);
    lv_area_t* clip = (lv_area_t*)lua_touserdata(L, 3);
    lv_draw_line_dsc_t* dsc = (lv_draw_line_dsc_t*)lua_touserdata(L, 4);
    lv_draw_line(point1 ,point2 ,clip ,dsc);
    return 0;
}

//  void lv_draw_line_dsc_init(lv_draw_line_dsc_t* dsc)
int luat_lv_draw_line_dsc_init(lua_State *L) {
    LV_DEBUG("CALL lv_draw_line_dsc_init");
    lv_draw_line_dsc_t* dsc = (lv_draw_line_dsc_t*)lua_touserdata(L, 1);
    lv_draw_line_dsc_init(dsc);
    return 0;
}

//  void lv_draw_arc(lv_coord_t center_x, lv_coord_t center_y, uint16_t radius, uint16_t start_angle, uint16_t end_angle, lv_area_t* clip_area, lv_draw_line_dsc_t* dsc)
int luat_lv_draw_arc(lua_State *L) {
    LV_DEBUG("CALL lv_draw_arc");
    lv_coord_t center_x = (lv_coord_t)luaL_checknumber(L, 1);
    lv_coord_t center_y = (lv_coord_t)luaL_checknumber(L, 2);
    uint16_t radius = (uint16_t)luaL_checkinteger(L, 3);
    uint16_t start_angle = (uint16_t)luaL_checkinteger(L, 4);
    uint16_t end_angle = (uint16_t)luaL_checkinteger(L, 5);
    lv_area_t* clip_area = (lv_area_t*)lua_touserdata(L, 6);
    lv_draw_line_dsc_t* dsc = (lv_draw_line_dsc_t*)lua_touserdata(L, 7);
    lv_draw_arc(center_x ,center_y ,radius ,start_angle ,end_angle ,clip_area ,dsc);
    return 0;
}

