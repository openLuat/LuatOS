#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_lvgl.h"
#include "lvgl.h"
        
int luat_lv_style_set_radius(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_radius(_style, state, _int);
    return 0;
}

int luat_lv_style_set_clip_corner(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    bool _int = (bool)lua_toboolean(L, 3);
    lv_style_set_clip_corner(_style, state, _int);
    return 0;
}

int luat_lv_style_set_size(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_size(_style, state, _int);
    return 0;
}

int luat_lv_style_set_transform_width(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transform_width(_style, state, _int);
    return 0;
}

int luat_lv_style_set_transform_height(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transform_height(_style, state, _int);
    return 0;
}

int luat_lv_style_set_transform_angle(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transform_angle(_style, state, _int);
    return 0;
}

int luat_lv_style_set_transform_zoom(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transform_zoom(_style, state, _int);
    return 0;
}

int luat_lv_style_set_opa_scale(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_opa_scale(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_pad_top(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_pad_top(_style, state, _int);
    return 0;
}

int luat_lv_style_set_pad_bottom(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_pad_bottom(_style, state, _int);
    return 0;
}

int luat_lv_style_set_pad_left(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_pad_left(_style, state, _int);
    return 0;
}

int luat_lv_style_set_pad_right(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_pad_right(_style, state, _int);
    return 0;
}

int luat_lv_style_set_pad_inner(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_pad_inner(_style, state, _int);
    return 0;
}

int luat_lv_style_set_margin_top(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_margin_top(_style, state, _int);
    return 0;
}

int luat_lv_style_set_margin_bottom(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_margin_bottom(_style, state, _int);
    return 0;
}

int luat_lv_style_set_margin_left(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_margin_left(_style, state, _int);
    return 0;
}

int luat_lv_style_set_margin_right(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_margin_right(_style, state, _int);
    return 0;
}

int luat_lv_style_set_bg_blend_mode(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t _int = (lv_blend_mode_t)luaL_checkinteger(L, 3);
    lv_style_set_bg_blend_mode(_style, state, _int);
    return 0;
}

int luat_lv_style_set_bg_main_stop(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_bg_main_stop(_style, state, _int);
    return 0;
}

int luat_lv_style_set_bg_grad_stop(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_bg_grad_stop(_style, state, _int);
    return 0;
}

int luat_lv_style_set_bg_grad_dir(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_grad_dir_t _int = (lv_grad_dir_t)luaL_checkinteger(L, 3);
    lv_style_set_bg_grad_dir(_style, state, _int);
    return 0;
}

int luat_lv_style_set_bg_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_bg_color(_style, state, _color);
    return 0;
}

int luat_lv_style_set_bg_grad_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_bg_grad_color(_style, state, _color);
    return 0;
}

int luat_lv_style_set_bg_opa(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_bg_opa(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_border_width(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_border_width(_style, state, _int);
    return 0;
}

int luat_lv_style_set_border_side(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_border_side_t _int = (lv_border_side_t)luaL_checkinteger(L, 3);
    lv_style_set_border_side(_style, state, _int);
    return 0;
}

int luat_lv_style_set_border_blend_mode(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t _int = (lv_blend_mode_t)luaL_checkinteger(L, 3);
    lv_style_set_border_blend_mode(_style, state, _int);
    return 0;
}

int luat_lv_style_set_border_post(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    bool _int = (bool)lua_toboolean(L, 3);
    lv_style_set_border_post(_style, state, _int);
    return 0;
}

int luat_lv_style_set_border_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_border_color(_style, state, _color);
    return 0;
}

int luat_lv_style_set_border_opa(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_border_opa(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_outline_width(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_outline_width(_style, state, _int);
    return 0;
}

int luat_lv_style_set_outline_pad(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_outline_pad(_style, state, _int);
    return 0;
}

int luat_lv_style_set_outline_blend_mode(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t _int = (lv_blend_mode_t)luaL_checkinteger(L, 3);
    lv_style_set_outline_blend_mode(_style, state, _int);
    return 0;
}

int luat_lv_style_set_outline_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_outline_color(_style, state, _color);
    return 0;
}

int luat_lv_style_set_outline_opa(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_outline_opa(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_shadow_width(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_shadow_width(_style, state, _int);
    return 0;
}

int luat_lv_style_set_shadow_ofs_x(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_shadow_ofs_x(_style, state, _int);
    return 0;
}

int luat_lv_style_set_shadow_ofs_y(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_shadow_ofs_y(_style, state, _int);
    return 0;
}

int luat_lv_style_set_shadow_spread(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_shadow_spread(_style, state, _int);
    return 0;
}

int luat_lv_style_set_shadow_blend_mode(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t _int = (lv_blend_mode_t)luaL_checkinteger(L, 3);
    lv_style_set_shadow_blend_mode(_style, state, _int);
    return 0;
}

int luat_lv_style_set_shadow_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_shadow_color(_style, state, _color);
    return 0;
}

int luat_lv_style_set_shadow_opa(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_shadow_opa(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_pattern_repeat(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    bool _int = (bool)lua_toboolean(L, 3);
    lv_style_set_pattern_repeat(_style, state, _int);
    return 0;
}

int luat_lv_style_set_pattern_blend_mode(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t _int = (lv_blend_mode_t)luaL_checkinteger(L, 3);
    lv_style_set_pattern_blend_mode(_style, state, _int);
    return 0;
}

int luat_lv_style_set_pattern_recolor(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_pattern_recolor(_style, state, _color);
    return 0;
}

int luat_lv_style_set_pattern_opa(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_pattern_opa(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_pattern_recolor_opa(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_pattern_recolor_opa(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_pattern_image(lua_State *L){
    // lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    // lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    // const void * _ptr;
    // TODO const void * _ptr
    // lv_style_set_pattern_image(_style, state, _ptr);
    return 0;
}

int luat_lv_style_set_value_letter_space(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_value_letter_space(_style, state, _int);
    return 0;
}

int luat_lv_style_set_value_line_space(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_value_line_space(_style, state, _int);
    return 0;
}

int luat_lv_style_set_value_blend_mode(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t _int = (lv_blend_mode_t)luaL_checkinteger(L, 3);
    lv_style_set_value_blend_mode(_style, state, _int);
    return 0;
}

int luat_lv_style_set_value_ofs_x(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_value_ofs_x(_style, state, _int);
    return 0;
}

int luat_lv_style_set_value_ofs_y(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_value_ofs_y(_style, state, _int);
    return 0;
}

int luat_lv_style_set_value_align(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_align_t _int = (lv_align_t)luaL_checkinteger(L, 3);
    lv_style_set_value_align(_style, state, _int);
    return 0;
}

int luat_lv_style_set_value_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_value_color(_style, state, _color);
    return 0;
}

int luat_lv_style_set_value_opa(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_value_opa(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_value_font(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    const lv_font_t * _ptr = (const lv_font_t *)lua_touserdata(L, 3);
    lv_style_set_value_font(_style, state, _ptr);
    return 0;
}

int luat_lv_style_set_value_str(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    const char * _ptr = (const char *)luaL_checkstring(L, 3);
    lv_style_set_value_str(_style, state, _ptr);
    return 0;
}

int luat_lv_style_set_text_letter_space(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_text_letter_space(_style, state, _int);
    return 0;
}

int luat_lv_style_set_text_line_space(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_text_line_space(_style, state, _int);
    return 0;
}

int luat_lv_style_set_text_decor(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_text_decor_t _int = (lv_text_decor_t)luaL_checkinteger(L, 3);
    lv_style_set_text_decor(_style, state, _int);
    return 0;
}

int luat_lv_style_set_text_blend_mode(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t _int = (lv_blend_mode_t)luaL_checkinteger(L, 3);
    lv_style_set_text_blend_mode(_style, state, _int);
    return 0;
}

int luat_lv_style_set_text_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_text_color(_style, state, _color);
    return 0;
}

int luat_lv_style_set_text_sel_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_text_sel_color(_style, state, _color);
    return 0;
}

int luat_lv_style_set_text_sel_bg_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_text_sel_bg_color(_style, state, _color);
    return 0;
}

int luat_lv_style_set_text_opa(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_text_opa(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_text_font(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    const lv_font_t * _ptr = (const lv_font_t *)lua_touserdata(L, 3);
    lv_style_set_text_font(_style, state, _ptr);
    return 0;
}

int luat_lv_style_set_line_width(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_line_width(_style, state, _int);
    return 0;
}

int luat_lv_style_set_line_blend_mode(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t _int = (lv_blend_mode_t)luaL_checkinteger(L, 3);
    lv_style_set_line_blend_mode(_style, state, _int);
    return 0;
}

int luat_lv_style_set_line_dash_width(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_line_dash_width(_style, state, _int);
    return 0;
}

int luat_lv_style_set_line_dash_gap(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_line_dash_gap(_style, state, _int);
    return 0;
}

int luat_lv_style_set_line_rounded(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    bool _int = (bool)lua_toboolean(L, 3);
    lv_style_set_line_rounded(_style, state, _int);
    return 0;
}

int luat_lv_style_set_line_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_line_color(_style, state, _color);
    return 0;
}

int luat_lv_style_set_line_opa(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_line_opa(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_image_blend_mode(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_blend_mode_t _int = (lv_blend_mode_t)luaL_checkinteger(L, 3);
    lv_style_set_image_blend_mode(_style, state, _int);
    return 0;
}

int luat_lv_style_set_image_recolor(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_image_recolor(_style, state, _color);
    return 0;
}

int luat_lv_style_set_image_opa(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_image_opa(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_image_recolor_opa(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_opa_t _opa = (lv_opa_t)luaL_checkinteger(L, 3);
    lv_style_set_image_recolor_opa(_style, state, _opa);
    return 0;
}

int luat_lv_style_set_transition_time(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transition_time(_style, state, _int);
    return 0;
}

int luat_lv_style_set_transition_delay(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transition_delay(_style, state, _int);
    return 0;
}

int luat_lv_style_set_transition_prop_1(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transition_prop_1(_style, state, _int);
    return 0;
}

int luat_lv_style_set_transition_prop_2(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transition_prop_2(_style, state, _int);
    return 0;
}

int luat_lv_style_set_transition_prop_3(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transition_prop_3(_style, state, _int);
    return 0;
}

int luat_lv_style_set_transition_prop_4(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transition_prop_4(_style, state, _int);
    return 0;
}

int luat_lv_style_set_transition_prop_5(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transition_prop_5(_style, state, _int);
    return 0;
}

int luat_lv_style_set_transition_prop_6(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_transition_prop_6(_style, state, _int);
    return 0;
}

int luat_lv_style_set_scale_width(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_scale_width(_style, state, _int);
    return 0;
}

int luat_lv_style_set_scale_border_width(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_scale_border_width(_style, state, _int);
    return 0;
}

int luat_lv_style_set_scale_end_border_width(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_scale_end_border_width(_style, state, _int);
    return 0;
}

int luat_lv_style_set_scale_end_line_width(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_style_int_t _int = (lv_style_int_t)luaL_checkinteger(L, 3);
    lv_style_set_scale_end_line_width(_style, state, _int);
    return 0;
}

int luat_lv_style_set_scale_grad_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_scale_grad_color(_style, state, _color);
    return 0;
}

int luat_lv_style_set_scale_end_color(lua_State *L){
    lv_style_t* _style = (lv_style_t*)lua_touserdata(L, 1);
    lv_state_t state = (lv_state_t)luaL_checkinteger(L, 2);
    lv_color_t _color;
    _color.full = luaL_checkinteger(L, 3);
    lv_style_set_scale_end_color(_style, state, _color);
    return 0;
}

