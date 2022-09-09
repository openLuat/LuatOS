#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_lvgl.h"
#include "lvgl.h"
        
int luat_lv_style_set_radius(lua_State *L);
int luat_lv_style_get_radius(lua_State *L);
int luat_lv_style_set_clip_corner(lua_State *L);
int luat_lv_style_get_clip_corner(lua_State *L);
int luat_lv_style_set_size(lua_State *L);
int luat_lv_style_get_size(lua_State *L);
int luat_lv_style_set_transform_width(lua_State *L);
int luat_lv_style_get_transform_width(lua_State *L);
int luat_lv_style_set_transform_height(lua_State *L);
int luat_lv_style_get_transform_height(lua_State *L);
int luat_lv_style_set_transform_angle(lua_State *L);
int luat_lv_style_get_transform_angle(lua_State *L);
int luat_lv_style_set_transform_zoom(lua_State *L);
int luat_lv_style_get_transform_zoom(lua_State *L);
int luat_lv_style_set_opa_scale(lua_State *L);
int luat_lv_style_get_opa_scale(lua_State *L);
int luat_lv_style_set_pad_top(lua_State *L);
int luat_lv_style_get_pad_top(lua_State *L);
int luat_lv_style_set_pad_bottom(lua_State *L);
int luat_lv_style_get_pad_bottom(lua_State *L);
int luat_lv_style_set_pad_left(lua_State *L);
int luat_lv_style_get_pad_left(lua_State *L);
int luat_lv_style_set_pad_right(lua_State *L);
int luat_lv_style_get_pad_right(lua_State *L);
int luat_lv_style_set_pad_inner(lua_State *L);
int luat_lv_style_get_pad_inner(lua_State *L);
int luat_lv_style_set_margin_top(lua_State *L);
int luat_lv_style_get_margin_top(lua_State *L);
int luat_lv_style_set_margin_bottom(lua_State *L);
int luat_lv_style_get_margin_bottom(lua_State *L);
int luat_lv_style_set_margin_left(lua_State *L);
int luat_lv_style_get_margin_left(lua_State *L);
int luat_lv_style_set_margin_right(lua_State *L);
int luat_lv_style_get_margin_right(lua_State *L);
int luat_lv_style_set_bg_blend_mode(lua_State *L);
int luat_lv_style_get_bg_blend_mode(lua_State *L);
int luat_lv_style_set_bg_main_stop(lua_State *L);
int luat_lv_style_get_bg_main_stop(lua_State *L);
int luat_lv_style_set_bg_grad_stop(lua_State *L);
int luat_lv_style_get_bg_grad_stop(lua_State *L);
int luat_lv_style_set_bg_grad_dir(lua_State *L);
int luat_lv_style_get_bg_grad_dir(lua_State *L);
int luat_lv_style_set_bg_color(lua_State *L);
int luat_lv_style_get_bg_color(lua_State *L);
int luat_lv_style_set_bg_grad_color(lua_State *L);
int luat_lv_style_get_bg_grad_color(lua_State *L);
int luat_lv_style_set_bg_opa(lua_State *L);
int luat_lv_style_get_bg_opa(lua_State *L);
int luat_lv_style_set_border_width(lua_State *L);
int luat_lv_style_get_border_width(lua_State *L);
int luat_lv_style_set_border_side(lua_State *L);
int luat_lv_style_get_border_side(lua_State *L);
int luat_lv_style_set_border_blend_mode(lua_State *L);
int luat_lv_style_get_border_blend_mode(lua_State *L);
int luat_lv_style_set_border_post(lua_State *L);
int luat_lv_style_get_border_post(lua_State *L);
int luat_lv_style_set_border_color(lua_State *L);
int luat_lv_style_get_border_color(lua_State *L);
int luat_lv_style_set_border_opa(lua_State *L);
int luat_lv_style_get_border_opa(lua_State *L);
int luat_lv_style_set_outline_width(lua_State *L);
int luat_lv_style_get_outline_width(lua_State *L);
int luat_lv_style_set_outline_pad(lua_State *L);
int luat_lv_style_get_outline_pad(lua_State *L);
int luat_lv_style_set_outline_blend_mode(lua_State *L);
int luat_lv_style_get_outline_blend_mode(lua_State *L);
int luat_lv_style_set_outline_color(lua_State *L);
int luat_lv_style_get_outline_color(lua_State *L);
int luat_lv_style_set_outline_opa(lua_State *L);
int luat_lv_style_get_outline_opa(lua_State *L);
int luat_lv_style_set_shadow_width(lua_State *L);
int luat_lv_style_get_shadow_width(lua_State *L);
int luat_lv_style_set_shadow_ofs_x(lua_State *L);
int luat_lv_style_get_shadow_ofs_x(lua_State *L);
int luat_lv_style_set_shadow_ofs_y(lua_State *L);
int luat_lv_style_get_shadow_ofs_y(lua_State *L);
int luat_lv_style_set_shadow_spread(lua_State *L);
int luat_lv_style_get_shadow_spread(lua_State *L);
int luat_lv_style_set_shadow_blend_mode(lua_State *L);
int luat_lv_style_get_shadow_blend_mode(lua_State *L);
int luat_lv_style_set_shadow_color(lua_State *L);
int luat_lv_style_get_shadow_color(lua_State *L);
int luat_lv_style_set_shadow_opa(lua_State *L);
int luat_lv_style_get_shadow_opa(lua_State *L);
int luat_lv_style_set_pattern_repeat(lua_State *L);
int luat_lv_style_get_pattern_repeat(lua_State *L);
int luat_lv_style_set_pattern_blend_mode(lua_State *L);
int luat_lv_style_get_pattern_blend_mode(lua_State *L);
int luat_lv_style_set_pattern_recolor(lua_State *L);
int luat_lv_style_get_pattern_recolor(lua_State *L);
int luat_lv_style_set_pattern_opa(lua_State *L);
int luat_lv_style_get_pattern_opa(lua_State *L);
int luat_lv_style_set_pattern_recolor_opa(lua_State *L);
int luat_lv_style_get_pattern_recolor_opa(lua_State *L);
int luat_lv_style_set_pattern_image(lua_State *L);
int luat_lv_style_get_pattern_image(lua_State *L);
int luat_lv_style_set_value_letter_space(lua_State *L);
int luat_lv_style_get_value_letter_space(lua_State *L);
int luat_lv_style_set_value_line_space(lua_State *L);
int luat_lv_style_get_value_line_space(lua_State *L);
int luat_lv_style_set_value_blend_mode(lua_State *L);
int luat_lv_style_get_value_blend_mode(lua_State *L);
int luat_lv_style_set_value_ofs_x(lua_State *L);
int luat_lv_style_get_value_ofs_x(lua_State *L);
int luat_lv_style_set_value_ofs_y(lua_State *L);
int luat_lv_style_get_value_ofs_y(lua_State *L);
int luat_lv_style_set_value_align(lua_State *L);
int luat_lv_style_get_value_align(lua_State *L);
int luat_lv_style_set_value_color(lua_State *L);
int luat_lv_style_get_value_color(lua_State *L);
int luat_lv_style_set_value_opa(lua_State *L);
int luat_lv_style_get_value_opa(lua_State *L);
int luat_lv_style_set_value_font(lua_State *L);
int luat_lv_style_get_value_font(lua_State *L);
int luat_lv_style_set_value_str(lua_State *L);
int luat_lv_style_get_value_str(lua_State *L);
int luat_lv_style_set_text_letter_space(lua_State *L);
int luat_lv_style_get_text_letter_space(lua_State *L);
int luat_lv_style_set_text_line_space(lua_State *L);
int luat_lv_style_get_text_line_space(lua_State *L);
int luat_lv_style_set_text_decor(lua_State *L);
int luat_lv_style_get_text_decor(lua_State *L);
int luat_lv_style_set_text_blend_mode(lua_State *L);
int luat_lv_style_get_text_blend_mode(lua_State *L);
int luat_lv_style_set_text_color(lua_State *L);
int luat_lv_style_get_text_color(lua_State *L);
int luat_lv_style_set_text_sel_color(lua_State *L);
int luat_lv_style_get_text_sel_color(lua_State *L);
int luat_lv_style_set_text_sel_bg_color(lua_State *L);
int luat_lv_style_get_text_sel_bg_color(lua_State *L);
int luat_lv_style_set_text_opa(lua_State *L);
int luat_lv_style_get_text_opa(lua_State *L);
int luat_lv_style_set_text_font(lua_State *L);
int luat_lv_style_get_text_font(lua_State *L);
int luat_lv_style_set_line_width(lua_State *L);
int luat_lv_style_get_line_width(lua_State *L);
int luat_lv_style_set_line_blend_mode(lua_State *L);
int luat_lv_style_get_line_blend_mode(lua_State *L);
int luat_lv_style_set_line_dash_width(lua_State *L);
int luat_lv_style_get_line_dash_width(lua_State *L);
int luat_lv_style_set_line_dash_gap(lua_State *L);
int luat_lv_style_get_line_dash_gap(lua_State *L);
int luat_lv_style_set_line_rounded(lua_State *L);
int luat_lv_style_get_line_rounded(lua_State *L);
int luat_lv_style_set_line_color(lua_State *L);
int luat_lv_style_get_line_color(lua_State *L);
int luat_lv_style_set_line_opa(lua_State *L);
int luat_lv_style_get_line_opa(lua_State *L);
int luat_lv_style_set_image_blend_mode(lua_State *L);
int luat_lv_style_get_image_blend_mode(lua_State *L);
int luat_lv_style_set_image_recolor(lua_State *L);
int luat_lv_style_get_image_recolor(lua_State *L);
int luat_lv_style_set_image_opa(lua_State *L);
int luat_lv_style_get_image_opa(lua_State *L);
int luat_lv_style_set_image_recolor_opa(lua_State *L);
int luat_lv_style_get_image_recolor_opa(lua_State *L);
int luat_lv_style_set_transition_time(lua_State *L);
int luat_lv_style_get_transition_time(lua_State *L);
int luat_lv_style_set_transition_delay(lua_State *L);
int luat_lv_style_get_transition_delay(lua_State *L);
int luat_lv_style_set_transition_prop_1(lua_State *L);
int luat_lv_style_get_transition_prop_1(lua_State *L);
int luat_lv_style_set_transition_prop_2(lua_State *L);
int luat_lv_style_get_transition_prop_2(lua_State *L);
int luat_lv_style_set_transition_prop_3(lua_State *L);
int luat_lv_style_get_transition_prop_3(lua_State *L);
int luat_lv_style_set_transition_prop_4(lua_State *L);
int luat_lv_style_get_transition_prop_4(lua_State *L);
int luat_lv_style_set_transition_prop_5(lua_State *L);
int luat_lv_style_get_transition_prop_5(lua_State *L);
int luat_lv_style_set_transition_prop_6(lua_State *L);
int luat_lv_style_get_transition_prop_6(lua_State *L);
int luat_lv_style_set_scale_width(lua_State *L);
int luat_lv_style_get_scale_width(lua_State *L);
int luat_lv_style_set_scale_border_width(lua_State *L);
int luat_lv_style_get_scale_border_width(lua_State *L);
int luat_lv_style_set_scale_end_border_width(lua_State *L);
int luat_lv_style_get_scale_end_border_width(lua_State *L);
int luat_lv_style_set_scale_end_line_width(lua_State *L);
int luat_lv_style_get_scale_end_line_width(lua_State *L);
int luat_lv_style_set_scale_grad_color(lua_State *L);
int luat_lv_style_get_scale_grad_color(lua_State *L);
int luat_lv_style_set_scale_end_color(lua_State *L);
int luat_lv_style_get_scale_end_color(lua_State *L);

#define LUAT_LV_STYLE_DEC_RLT {"style_set_radius", ROREG_FUNC(luat_lv_style_set_radius)},\
{"style_set_clip_corner", ROREG_FUNC(luat_lv_style_set_clip_corner)},\
{"style_set_size", ROREG_FUNC(luat_lv_style_set_size)},\
{"style_set_transform_width", ROREG_FUNC(luat_lv_style_set_transform_width)},\
{"style_set_transform_height", ROREG_FUNC(luat_lv_style_set_transform_height)},\
{"style_set_transform_angle", ROREG_FUNC(luat_lv_style_set_transform_angle)},\
{"style_set_transform_zoom", ROREG_FUNC(luat_lv_style_set_transform_zoom)},\
{"style_set_opa_scale", ROREG_FUNC(luat_lv_style_set_opa_scale)},\
{"style_set_pad_top", ROREG_FUNC(luat_lv_style_set_pad_top)},\
{"style_set_pad_bottom", ROREG_FUNC(luat_lv_style_set_pad_bottom)},\
{"style_set_pad_left", ROREG_FUNC(luat_lv_style_set_pad_left)},\
{"style_set_pad_right", ROREG_FUNC(luat_lv_style_set_pad_right)},\
{"style_set_pad_inner", ROREG_FUNC(luat_lv_style_set_pad_inner)},\
{"style_set_margin_top", ROREG_FUNC(luat_lv_style_set_margin_top)},\
{"style_set_margin_bottom", ROREG_FUNC(luat_lv_style_set_margin_bottom)},\
{"style_set_margin_left", ROREG_FUNC(luat_lv_style_set_margin_left)},\
{"style_set_margin_right", ROREG_FUNC(luat_lv_style_set_margin_right)},\
{"style_set_bg_blend_mode", ROREG_FUNC(luat_lv_style_set_bg_blend_mode)},\
{"style_set_bg_main_stop", ROREG_FUNC(luat_lv_style_set_bg_main_stop)},\
{"style_set_bg_grad_stop", ROREG_FUNC(luat_lv_style_set_bg_grad_stop)},\
{"style_set_bg_grad_dir", ROREG_FUNC(luat_lv_style_set_bg_grad_dir)},\
{"style_set_bg_color", ROREG_FUNC(luat_lv_style_set_bg_color)},\
{"style_set_bg_grad_color", ROREG_FUNC(luat_lv_style_set_bg_grad_color)},\
{"style_set_bg_opa", ROREG_FUNC(luat_lv_style_set_bg_opa)},\
{"style_set_border_width", ROREG_FUNC(luat_lv_style_set_border_width)},\
{"style_set_border_side", ROREG_FUNC(luat_lv_style_set_border_side)},\
{"style_set_border_blend_mode", ROREG_FUNC(luat_lv_style_set_border_blend_mode)},\
{"style_set_border_post", ROREG_FUNC(luat_lv_style_set_border_post)},\
{"style_set_border_color", ROREG_FUNC(luat_lv_style_set_border_color)},\
{"style_set_border_opa", ROREG_FUNC(luat_lv_style_set_border_opa)},\
{"style_set_outline_width", ROREG_FUNC(luat_lv_style_set_outline_width)},\
{"style_set_outline_pad", ROREG_FUNC(luat_lv_style_set_outline_pad)},\
{"style_set_outline_blend_mode", ROREG_FUNC(luat_lv_style_set_outline_blend_mode)},\
{"style_set_outline_color", ROREG_FUNC(luat_lv_style_set_outline_color)},\
{"style_set_outline_opa", ROREG_FUNC(luat_lv_style_set_outline_opa)},\
{"style_set_shadow_width", ROREG_FUNC(luat_lv_style_set_shadow_width)},\
{"style_set_shadow_ofs_x", ROREG_FUNC(luat_lv_style_set_shadow_ofs_x)},\
{"style_set_shadow_ofs_y", ROREG_FUNC(luat_lv_style_set_shadow_ofs_y)},\
{"style_set_shadow_spread", ROREG_FUNC(luat_lv_style_set_shadow_spread)},\
{"style_set_shadow_blend_mode", ROREG_FUNC(luat_lv_style_set_shadow_blend_mode)},\
{"style_set_shadow_color", ROREG_FUNC(luat_lv_style_set_shadow_color)},\
{"style_set_shadow_opa", ROREG_FUNC(luat_lv_style_set_shadow_opa)},\
{"style_set_pattern_repeat", ROREG_FUNC(luat_lv_style_set_pattern_repeat)},\
{"style_set_pattern_blend_mode", ROREG_FUNC(luat_lv_style_set_pattern_blend_mode)},\
{"style_set_pattern_recolor", ROREG_FUNC(luat_lv_style_set_pattern_recolor)},\
{"style_set_pattern_opa", ROREG_FUNC(luat_lv_style_set_pattern_opa)},\
{"style_set_pattern_recolor_opa", ROREG_FUNC(luat_lv_style_set_pattern_recolor_opa)},\
{"style_set_pattern_image", ROREG_FUNC(luat_lv_style_set_pattern_image)},\
{"style_set_value_letter_space", ROREG_FUNC(luat_lv_style_set_value_letter_space)},\
{"style_set_value_line_space", ROREG_FUNC(luat_lv_style_set_value_line_space)},\
{"style_set_value_blend_mode", ROREG_FUNC(luat_lv_style_set_value_blend_mode)},\
{"style_set_value_ofs_x", ROREG_FUNC(luat_lv_style_set_value_ofs_x)},\
{"style_set_value_ofs_y", ROREG_FUNC(luat_lv_style_set_value_ofs_y)},\
{"style_set_value_align", ROREG_FUNC(luat_lv_style_set_value_align)},\
{"style_set_value_color", ROREG_FUNC(luat_lv_style_set_value_color)},\
{"style_set_value_opa", ROREG_FUNC(luat_lv_style_set_value_opa)},\
{"style_set_value_font", ROREG_FUNC(luat_lv_style_set_value_font)},\
{"style_set_value_str", ROREG_FUNC(luat_lv_style_set_value_str)},\
{"style_set_text_letter_space", ROREG_FUNC(luat_lv_style_set_text_letter_space)},\
{"style_set_text_line_space", ROREG_FUNC(luat_lv_style_set_text_line_space)},\
{"style_set_text_decor", ROREG_FUNC(luat_lv_style_set_text_decor)},\
{"style_set_text_blend_mode", ROREG_FUNC(luat_lv_style_set_text_blend_mode)},\
{"style_set_text_color", ROREG_FUNC(luat_lv_style_set_text_color)},\
{"style_set_text_sel_color", ROREG_FUNC(luat_lv_style_set_text_sel_color)},\
{"style_set_text_sel_bg_color", ROREG_FUNC(luat_lv_style_set_text_sel_bg_color)},\
{"style_set_text_opa", ROREG_FUNC(luat_lv_style_set_text_opa)},\
{"style_set_text_font", ROREG_FUNC(luat_lv_style_set_text_font)},\
{"style_set_line_width", ROREG_FUNC(luat_lv_style_set_line_width)},\
{"style_set_line_blend_mode", ROREG_FUNC(luat_lv_style_set_line_blend_mode)},\
{"style_set_line_dash_width", ROREG_FUNC(luat_lv_style_set_line_dash_width)},\
{"style_set_line_dash_gap", ROREG_FUNC(luat_lv_style_set_line_dash_gap)},\
{"style_set_line_rounded", ROREG_FUNC(luat_lv_style_set_line_rounded)},\
{"style_set_line_color", ROREG_FUNC(luat_lv_style_set_line_color)},\
{"style_set_line_opa", ROREG_FUNC(luat_lv_style_set_line_opa)},\
{"style_set_image_blend_mode", ROREG_FUNC(luat_lv_style_set_image_blend_mode)},\
{"style_set_image_recolor", ROREG_FUNC(luat_lv_style_set_image_recolor)},\
{"style_set_image_opa", ROREG_FUNC(luat_lv_style_set_image_opa)},\
{"style_set_image_recolor_opa", ROREG_FUNC(luat_lv_style_set_image_recolor_opa)},\
{"style_set_transition_time", ROREG_FUNC(luat_lv_style_set_transition_time)},\
{"style_set_transition_delay", ROREG_FUNC(luat_lv_style_set_transition_delay)},\
{"style_set_transition_prop_1", ROREG_FUNC(luat_lv_style_set_transition_prop_1)},\
{"style_set_transition_prop_2", ROREG_FUNC(luat_lv_style_set_transition_prop_2)},\
{"style_set_transition_prop_3", ROREG_FUNC(luat_lv_style_set_transition_prop_3)},\
{"style_set_transition_prop_4", ROREG_FUNC(luat_lv_style_set_transition_prop_4)},\
{"style_set_transition_prop_5", ROREG_FUNC(luat_lv_style_set_transition_prop_5)},\
{"style_set_transition_prop_6", ROREG_FUNC(luat_lv_style_set_transition_prop_6)},\
{"style_set_scale_width", ROREG_FUNC(luat_lv_style_set_scale_width)},\
{"style_set_scale_border_width", ROREG_FUNC(luat_lv_style_set_scale_border_width)},\
{"style_set_scale_end_border_width", ROREG_FUNC(luat_lv_style_set_scale_end_border_width)},\
{"style_set_scale_end_line_width", ROREG_FUNC(luat_lv_style_set_scale_end_line_width)},\
{"style_set_scale_grad_color", ROREG_FUNC(luat_lv_style_set_scale_grad_color)},\
{"style_set_scale_end_color", ROREG_FUNC(luat_lv_style_set_scale_end_color)},
