
#include "luat_base.h"
#include "lvgl.h"
#include "luat_lvgl.h"


//  void lv_style_init(lv_style_t* style)
int luat_lv_style_init(lua_State *L) {
    LV_DEBUG("CALL lv_style_init");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_style_init(style);
    return 0;
}

//  void lv_style_reset(lv_style_t* style)
int luat_lv_style_reset(lua_State *L) {
    LV_DEBUG("CALL lv_style_reset");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_style_reset(style);
    return 0;
}

//  lv_style_prop_t lv_style_register_prop()
int luat_lv_style_register_prop(lua_State *L) {
    LV_DEBUG("CALL lv_style_register_prop");
    lv_style_prop_t ret;
    ret = lv_style_register_prop();
    lua_pushinteger(L, ret);
    return 1;
}

//  bool lv_style_remove_prop(lv_style_t* style, lv_style_prop_t prop)
int luat_lv_style_remove_prop(lua_State *L) {
    LV_DEBUG("CALL lv_style_remove_prop");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_style_prop_t prop = (lv_style_prop_t)luaL_checkinteger(L, 2);
    bool ret;
    ret = lv_style_remove_prop(style ,prop);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_style_set_prop(lv_style_t* style, lv_style_prop_t prop, lv_style_value_t value)
int luat_lv_style_set_prop(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_prop");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_style_prop_t prop = (lv_style_prop_t)luaL_checkinteger(L, 2);
    lv_style_value_t value;
    // miss arg convert
    lv_style_set_prop(style ,prop ,value);
    return 0;
}

//  lv_res_t lv_style_get_prop(lv_style_t* style, lv_style_prop_t prop, lv_style_value_t* value)
int luat_lv_style_get_prop(lua_State *L) {
    LV_DEBUG("CALL lv_style_get_prop");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_style_prop_t prop = (lv_style_prop_t)luaL_checkinteger(L, 2);
    lv_style_value_t* value = (lv_style_value_t*)lua_touserdata(L, 3);
    lv_res_t ret;
    ret = lv_style_get_prop(style ,prop ,value);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_res_t lv_style_get_prop_inlined(lv_style_t* style, lv_style_prop_t prop, lv_style_value_t* value)
int luat_lv_style_get_prop_inlined(lua_State *L) {
    LV_DEBUG("CALL lv_style_get_prop_inlined");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_style_prop_t prop = (lv_style_prop_t)luaL_checkinteger(L, 2);
    lv_style_value_t* value = (lv_style_value_t*)lua_touserdata(L, 3);
    lv_res_t ret;
    ret = lv_style_get_prop_inlined(style ,prop ,value);
    lua_pushboolean(L, ret == LV_RES_OK ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}

//  lv_style_value_t lv_style_prop_get_default(lv_style_prop_t prop)
int luat_lv_style_prop_get_default(lua_State *L) {
    LV_DEBUG("CALL lv_style_prop_get_default");
    lv_style_prop_t prop = (lv_style_prop_t)luaL_checkinteger(L, 1);
    lv_style_value_t ret;
    ret = lv_style_prop_get_default(prop);
    return 0;
}

//  bool lv_style_is_empty(lv_style_t* style)
int luat_lv_style_is_empty(lua_State *L) {
    LV_DEBUG("CALL lv_style_is_empty");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    bool ret;
    ret = lv_style_is_empty(style);
    lua_pushboolean(L, ret);
    return 1;
}

//  void lv_style_set_width(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_width(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_width");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_width(style ,value);
    return 0;
}

//  void lv_style_set_min_width(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_min_width(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_min_width");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_min_width(style ,value);
    return 0;
}

//  void lv_style_set_max_width(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_max_width(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_max_width");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_max_width(style ,value);
    return 0;
}

//  void lv_style_set_height(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_height(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_height");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_height(style ,value);
    return 0;
}

//  void lv_style_set_min_height(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_min_height(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_min_height");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_min_height(style ,value);
    return 0;
}

//  void lv_style_set_max_height(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_max_height(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_max_height");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_max_height(style ,value);
    return 0;
}

//  void lv_style_set_x(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_x(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_x");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_x(style ,value);
    return 0;
}

//  void lv_style_set_y(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_y(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_y");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_y(style ,value);
    return 0;
}

//  void lv_style_set_align(lv_style_t* style, lv_align_t value)
int luat_lv_style_set_align(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_align");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_align_t value = (lv_align_t)luaL_checkinteger(L, 2);
    lv_style_set_align(style ,value);
    return 0;
}

//  void lv_style_set_transform_width(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_transform_width(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_transform_width");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_transform_width(style ,value);
    return 0;
}

//  void lv_style_set_transform_height(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_transform_height(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_transform_height");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_transform_height(style ,value);
    return 0;
}

//  void lv_style_set_translate_x(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_translate_x(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_translate_x");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_translate_x(style ,value);
    return 0;
}

//  void lv_style_set_translate_y(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_translate_y(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_translate_y");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_translate_y(style ,value);
    return 0;
}

//  void lv_style_set_transform_zoom(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_transform_zoom(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_transform_zoom");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_transform_zoom(style ,value);
    return 0;
}

//  void lv_style_set_transform_angle(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_transform_angle(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_transform_angle");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_transform_angle(style ,value);
    return 0;
}

//  void lv_style_set_pad_top(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_pad_top(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_pad_top");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_pad_top(style ,value);
    return 0;
}

//  void lv_style_set_pad_bottom(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_pad_bottom(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_pad_bottom");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_pad_bottom(style ,value);
    return 0;
}

//  void lv_style_set_pad_left(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_pad_left(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_pad_left");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_pad_left(style ,value);
    return 0;
}

//  void lv_style_set_pad_right(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_pad_right(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_pad_right");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_pad_right(style ,value);
    return 0;
}

//  void lv_style_set_pad_row(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_pad_row(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_pad_row");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_pad_row(style ,value);
    return 0;
}

//  void lv_style_set_pad_column(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_pad_column(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_pad_column");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_pad_column(style ,value);
    return 0;
}

//  void lv_style_set_radius(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_radius(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_radius");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_radius(style ,value);
    return 0;
}

//  void lv_style_set_clip_corner(lv_style_t* style, bool value)
int luat_lv_style_set_clip_corner(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_clip_corner");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    bool value = (bool)lua_toboolean(L, 2);
    lv_style_set_clip_corner(style ,value);
    return 0;
}

//  void lv_style_set_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_opa(style ,value);
    return 0;
}

//  void lv_style_set_color_filter_dsc(lv_style_t* style, lv_color_filter_dsc_t* value)
int luat_lv_style_set_color_filter_dsc(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_color_filter_dsc");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_filter_dsc_t* value = (lv_color_filter_dsc_t*)lua_touserdata(L, 2);
    lv_style_set_color_filter_dsc(style ,value);
    return 0;
}

//  void lv_style_set_color_filter_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_color_filter_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_color_filter_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_color_filter_opa(style ,value);
    return 0;
}

//  void lv_style_set_anim_time(lv_style_t* style, uint32_t value)
int luat_lv_style_set_anim_time(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_anim_time");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    uint32_t value = (uint32_t)luaL_checkinteger(L, 2);
    lv_style_set_anim_time(style ,value);
    return 0;
}

//  void lv_style_set_anim_speed(lv_style_t* style, uint32_t value)
int luat_lv_style_set_anim_speed(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_anim_speed");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    uint32_t value = (uint32_t)luaL_checkinteger(L, 2);
    lv_style_set_anim_speed(style ,value);
    return 0;
}

//  void lv_style_set_transition(lv_style_t* style, lv_style_transition_dsc_t* value)
int luat_lv_style_set_transition(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_transition");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_style_transition_dsc_t* value = (lv_style_transition_dsc_t*)lua_touserdata(L, 2);
    lv_style_set_transition(style ,value);
    return 0;
}

//  void lv_style_set_blend_mode(lv_style_t* style, lv_blend_mode_t value)
int luat_lv_style_set_blend_mode(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_blend_mode");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_blend_mode_t value = (lv_blend_mode_t)luaL_checkinteger(L, 2);
    lv_style_set_blend_mode(style ,value);
    return 0;
}

//  void lv_style_set_layout(lv_style_t* style, uint16_t value)
int luat_lv_style_set_layout(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_layout");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    uint16_t value = (uint16_t)luaL_checkinteger(L, 2);
    lv_style_set_layout(style ,value);
    return 0;
}

//  void lv_style_set_base_dir(lv_style_t* style, lv_base_dir_t value)
int luat_lv_style_set_base_dir(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_base_dir");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_base_dir_t value = (lv_base_dir_t)luaL_checkinteger(L, 2);
    lv_style_set_base_dir(style ,value);
    return 0;
}

//  void lv_style_set_bg_color(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_bg_color(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_color");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_bg_color(style ,value);
    return 0;
}

//  void lv_style_set_bg_color_filtered(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_bg_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_color_filtered");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_bg_color_filtered(style ,value);
    return 0;
}

//  void lv_style_set_bg_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_bg_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_bg_opa(style ,value);
    return 0;
}

//  void lv_style_set_bg_grad_color(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_bg_grad_color(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_grad_color");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_bg_grad_color(style ,value);
    return 0;
}

//  void lv_style_set_bg_grad_color_filtered(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_bg_grad_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_grad_color_filtered");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_bg_grad_color_filtered(style ,value);
    return 0;
}

//  void lv_style_set_bg_grad_dir(lv_style_t* style, lv_grad_dir_t value)
int luat_lv_style_set_bg_grad_dir(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_grad_dir");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_grad_dir_t value = (lv_grad_dir_t)luaL_checkinteger(L, 2);
    lv_style_set_bg_grad_dir(style ,value);
    return 0;
}

//  void lv_style_set_bg_main_stop(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_bg_main_stop(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_main_stop");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_bg_main_stop(style ,value);
    return 0;
}

//  void lv_style_set_bg_grad_stop(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_bg_grad_stop(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_grad_stop");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_bg_grad_stop(style ,value);
    return 0;
}

//  void lv_style_set_bg_img_src(lv_style_t* style, void* value)
int luat_lv_style_set_bg_img_src(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_img_src");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    void* value = (void*)lua_touserdata(L, 2);
    lv_style_set_bg_img_src(style ,value);
    return 0;
}

//  void lv_style_set_bg_img_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_bg_img_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_img_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_bg_img_opa(style ,value);
    return 0;
}

//  void lv_style_set_bg_img_recolor(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_bg_img_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_img_recolor");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_bg_img_recolor(style ,value);
    return 0;
}

//  void lv_style_set_bg_img_recolor_filtered(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_bg_img_recolor_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_img_recolor_filtered");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_bg_img_recolor_filtered(style ,value);
    return 0;
}

//  void lv_style_set_bg_img_recolor_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_bg_img_recolor_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_img_recolor_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_bg_img_recolor_opa(style ,value);
    return 0;
}

//  void lv_style_set_bg_img_tiled(lv_style_t* style, bool value)
int luat_lv_style_set_bg_img_tiled(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_bg_img_tiled");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    bool value = (bool)lua_toboolean(L, 2);
    lv_style_set_bg_img_tiled(style ,value);
    return 0;
}

//  void lv_style_set_border_color(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_border_color(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_border_color");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_border_color(style ,value);
    return 0;
}

//  void lv_style_set_border_color_filtered(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_border_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_border_color_filtered");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_border_color_filtered(style ,value);
    return 0;
}

//  void lv_style_set_border_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_border_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_border_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_border_opa(style ,value);
    return 0;
}

//  void lv_style_set_border_width(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_border_width(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_border_width");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_border_width(style ,value);
    return 0;
}

//  void lv_style_set_border_side(lv_style_t* style, lv_border_side_t value)
int luat_lv_style_set_border_side(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_border_side");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_border_side_t value = (lv_border_side_t)luaL_checkinteger(L, 2);
    lv_style_set_border_side(style ,value);
    return 0;
}

//  void lv_style_set_border_post(lv_style_t* style, bool value)
int luat_lv_style_set_border_post(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_border_post");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    bool value = (bool)lua_toboolean(L, 2);
    lv_style_set_border_post(style ,value);
    return 0;
}

//  void lv_style_set_text_color(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_text_color(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_text_color");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_text_color(style ,value);
    return 0;
}

//  void lv_style_set_text_color_filtered(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_text_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_text_color_filtered");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_text_color_filtered(style ,value);
    return 0;
}

//  void lv_style_set_text_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_text_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_text_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_text_opa(style ,value);
    return 0;
}

//  void lv_style_set_text_font(lv_style_t* style, lv_font_t* value)
int luat_lv_style_set_text_font(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_text_font");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_font_t* value = (lv_font_t*)lua_touserdata(L, 2);
    lv_style_set_text_font(style ,value);
    return 0;
}

//  void lv_style_set_text_letter_space(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_text_letter_space(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_text_letter_space");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_text_letter_space(style ,value);
    return 0;
}

//  void lv_style_set_text_line_space(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_text_line_space(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_text_line_space");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_text_line_space(style ,value);
    return 0;
}

//  void lv_style_set_text_decor(lv_style_t* style, lv_text_decor_t value)
int luat_lv_style_set_text_decor(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_text_decor");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_text_decor_t value = (lv_text_decor_t)luaL_checkinteger(L, 2);
    lv_style_set_text_decor(style ,value);
    return 0;
}

//  void lv_style_set_text_align(lv_style_t* style, lv_text_align_t value)
int luat_lv_style_set_text_align(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_text_align");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_text_align_t value = (lv_text_align_t)luaL_checkinteger(L, 2);
    lv_style_set_text_align(style ,value);
    return 0;
}

//  void lv_style_set_img_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_img_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_img_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_img_opa(style ,value);
    return 0;
}

//  void lv_style_set_img_recolor(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_img_recolor(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_img_recolor");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_img_recolor(style ,value);
    return 0;
}

//  void lv_style_set_img_recolor_filtered(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_img_recolor_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_img_recolor_filtered");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_img_recolor_filtered(style ,value);
    return 0;
}

//  void lv_style_set_img_recolor_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_img_recolor_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_img_recolor_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_img_recolor_opa(style ,value);
    return 0;
}

//  void lv_style_set_outline_width(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_outline_width(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_outline_width");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_outline_width(style ,value);
    return 0;
}

//  void lv_style_set_outline_color(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_outline_color(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_outline_color");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_outline_color(style ,value);
    return 0;
}

//  void lv_style_set_outline_color_filtered(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_outline_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_outline_color_filtered");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_outline_color_filtered(style ,value);
    return 0;
}

//  void lv_style_set_outline_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_outline_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_outline_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_outline_opa(style ,value);
    return 0;
}

//  void lv_style_set_outline_pad(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_outline_pad(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_outline_pad");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_outline_pad(style ,value);
    return 0;
}

//  void lv_style_set_shadow_width(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_shadow_width(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_shadow_width");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_shadow_width(style ,value);
    return 0;
}

//  void lv_style_set_shadow_ofs_x(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_shadow_ofs_x(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_shadow_ofs_x");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_shadow_ofs_x(style ,value);
    return 0;
}

//  void lv_style_set_shadow_ofs_y(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_shadow_ofs_y(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_shadow_ofs_y");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_shadow_ofs_y(style ,value);
    return 0;
}

//  void lv_style_set_shadow_spread(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_shadow_spread(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_shadow_spread");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_shadow_spread(style ,value);
    return 0;
}

//  void lv_style_set_shadow_color(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_shadow_color(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_shadow_color");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_shadow_color(style ,value);
    return 0;
}

//  void lv_style_set_shadow_color_filtered(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_shadow_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_shadow_color_filtered");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_shadow_color_filtered(style ,value);
    return 0;
}

//  void lv_style_set_shadow_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_shadow_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_shadow_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_shadow_opa(style ,value);
    return 0;
}

//  void lv_style_set_line_width(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_line_width(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_line_width");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_line_width(style ,value);
    return 0;
}

//  void lv_style_set_line_dash_width(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_line_dash_width(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_line_dash_width");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_line_dash_width(style ,value);
    return 0;
}

//  void lv_style_set_line_dash_gap(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_line_dash_gap(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_line_dash_gap");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_line_dash_gap(style ,value);
    return 0;
}

//  void lv_style_set_line_rounded(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_line_rounded(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_line_rounded");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_line_rounded(style ,value);
    return 0;
}

//  void lv_style_set_line_color(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_line_color(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_line_color");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_line_color(style ,value);
    return 0;
}

//  void lv_style_set_line_color_filtered(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_line_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_line_color_filtered");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_line_color_filtered(style ,value);
    return 0;
}

//  void lv_style_set_line_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_line_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_line_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_line_opa(style ,value);
    return 0;
}

//  void lv_style_set_arc_width(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_arc_width(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_arc_width");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_arc_width(style ,value);
    return 0;
}

//  void lv_style_set_arc_rounded(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_arc_rounded(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_arc_rounded");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_arc_rounded(style ,value);
    return 0;
}

//  void lv_style_set_arc_color(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_arc_color(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_arc_color");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_arc_color(style ,value);
    return 0;
}

//  void lv_style_set_arc_color_filtered(lv_style_t* style, lv_color_t value)
int luat_lv_style_set_arc_color_filtered(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_arc_color_filtered");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_color_t value = {0};
    value.full = luaL_checkinteger(L, 2);
    lv_style_set_arc_color_filtered(style ,value);
    return 0;
}

//  void lv_style_set_arc_opa(lv_style_t* style, lv_opa_t value)
int luat_lv_style_set_arc_opa(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_arc_opa");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_opa_t value = (lv_opa_t)luaL_checkinteger(L, 2);
    lv_style_set_arc_opa(style ,value);
    return 0;
}

//  void lv_style_set_arc_img_src(lv_style_t* style, void* value)
int luat_lv_style_set_arc_img_src(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_arc_img_src");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    void* value = (void*)lua_touserdata(L, 2);
    lv_style_set_arc_img_src(style ,value);
    return 0;
}

//  void lv_style_set_pad_all(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_pad_all(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_pad_all");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_pad_all(style ,value);
    return 0;
}

//  void lv_style_set_pad_hor(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_pad_hor(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_pad_hor");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_pad_hor(style ,value);
    return 0;
}

//  void lv_style_set_pad_ver(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_pad_ver(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_pad_ver");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_pad_ver(style ,value);
    return 0;
}

//  void lv_style_set_pad_gap(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_pad_gap(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_pad_gap");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_pad_gap(style ,value);
    return 0;
}

//  void lv_style_set_size(lv_style_t* style, lv_coord_t value)
int luat_lv_style_set_size(lua_State *L) {
    LV_DEBUG("CALL lv_style_set_size");
    lv_style_t* style = (lv_style_t*)lua_touserdata(L, 1);
    lv_coord_t value = (lv_coord_t)luaL_checkinteger(L, 2);
    lv_style_set_size(style ,value);
    return 0;
}

