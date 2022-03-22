
#include "luat_base.h"
#ifndef LUAT_LV_GEN
#define LUAT_LV_GEN

// group lv_core
// prefix lv_core lv_disp
int luat_lv_disp_drv_init(lua_State *L);
int luat_lv_disp_buf_init(lua_State *L);
int luat_lv_disp_drv_register(lua_State *L);
int luat_lv_disp_drv_update(lua_State *L);
int luat_lv_disp_remove(lua_State *L);
int luat_lv_disp_set_default(lua_State *L);
int luat_lv_disp_get_default(lua_State *L);
int luat_lv_disp_get_hor_res(lua_State *L);
int luat_lv_disp_get_ver_res(lua_State *L);
int luat_lv_disp_get_antialiasing(lua_State *L);
int luat_lv_disp_get_dpi(lua_State *L);
int luat_lv_disp_get_size_category(lua_State *L);
int luat_lv_disp_set_rotation(lua_State *L);
int luat_lv_disp_get_rotation(lua_State *L);
int luat_lv_disp_flush_ready(lua_State *L);
int luat_lv_disp_flush_is_last(lua_State *L);
int luat_lv_disp_get_next(lua_State *L);
int luat_lv_disp_get_buf(lua_State *L);
int luat_lv_disp_get_inv_buf_size(lua_State *L);
int luat_lv_disp_is_double_buf(lua_State *L);
int luat_lv_disp_is_true_double_buf(lua_State *L);
int luat_lv_disp_get_scr_act(lua_State *L);
int luat_lv_disp_get_scr_prev(lua_State *L);
int luat_lv_disp_load_scr(lua_State *L);
int luat_lv_disp_get_layer_top(lua_State *L);
int luat_lv_disp_get_layer_sys(lua_State *L);
int luat_lv_disp_assign_screen(lua_State *L);
int luat_lv_disp_set_bg_color(lua_State *L);
int luat_lv_disp_set_bg_image(lua_State *L);
int luat_lv_disp_set_bg_opa(lua_State *L);
int luat_lv_disp_get_inactive_time(lua_State *L);
int luat_lv_disp_trig_activity(lua_State *L);
int luat_lv_disp_clean_dcache(lua_State *L);

#define LUAT_LV_DISP_RLT     {"disp_drv_init", ROREG_FUNC(luat_lv_disp_drv_init)},\
    {"disp_buf_init", ROREG_FUNC(luat_lv_disp_buf_init)},\
    {"disp_drv_register", ROREG_FUNC(luat_lv_disp_drv_register)},\
    {"disp_drv_update", ROREG_FUNC(luat_lv_disp_drv_update)},\
    {"disp_remove", ROREG_FUNC(luat_lv_disp_remove)},\
    {"disp_set_default", ROREG_FUNC(luat_lv_disp_set_default)},\
    {"disp_get_default", ROREG_FUNC(luat_lv_disp_get_default)},\
    {"disp_get_hor_res", ROREG_FUNC(luat_lv_disp_get_hor_res)},\
    {"disp_get_ver_res", ROREG_FUNC(luat_lv_disp_get_ver_res)},\
    {"disp_get_antialiasing", ROREG_FUNC(luat_lv_disp_get_antialiasing)},\
    {"disp_get_dpi", ROREG_FUNC(luat_lv_disp_get_dpi)},\
    {"disp_get_size_category", ROREG_FUNC(luat_lv_disp_get_size_category)},\
    {"disp_set_rotation", ROREG_FUNC(luat_lv_disp_set_rotation)},\
    {"disp_get_rotation", ROREG_FUNC(luat_lv_disp_get_rotation)},\
    {"disp_flush_ready", ROREG_FUNC(luat_lv_disp_flush_ready)},\
    {"disp_flush_is_last", ROREG_FUNC(luat_lv_disp_flush_is_last)},\
    {"disp_get_next", ROREG_FUNC(luat_lv_disp_get_next)},\
    {"disp_get_buf", ROREG_FUNC(luat_lv_disp_get_buf)},\
    {"disp_get_inv_buf_size", ROREG_FUNC(luat_lv_disp_get_inv_buf_size)},\
    {"disp_is_double_buf", ROREG_FUNC(luat_lv_disp_is_double_buf)},\
    {"disp_is_true_double_buf", ROREG_FUNC(luat_lv_disp_is_true_double_buf)},\
    {"disp_get_scr_act", ROREG_FUNC(luat_lv_disp_get_scr_act)},\
    {"disp_get_scr_prev", ROREG_FUNC(luat_lv_disp_get_scr_prev)},\
    {"disp_load_scr", ROREG_FUNC(luat_lv_disp_load_scr)},\
    {"disp_get_layer_top", ROREG_FUNC(luat_lv_disp_get_layer_top)},\
    {"disp_get_layer_sys", ROREG_FUNC(luat_lv_disp_get_layer_sys)},\
    {"disp_assign_screen", ROREG_FUNC(luat_lv_disp_assign_screen)},\
    {"disp_set_bg_color", ROREG_FUNC(luat_lv_disp_set_bg_color)},\
    {"disp_set_bg_image", ROREG_FUNC(luat_lv_disp_set_bg_image)},\
    {"disp_set_bg_opa", ROREG_FUNC(luat_lv_disp_set_bg_opa)},\
    {"disp_get_inactive_time", ROREG_FUNC(luat_lv_disp_get_inactive_time)},\
    {"disp_trig_activity", ROREG_FUNC(luat_lv_disp_trig_activity)},\
    {"disp_clean_dcache", ROREG_FUNC(luat_lv_disp_clean_dcache)},\

// prefix lv_core lv_group
int luat_lv_group_create(lua_State *L);
int luat_lv_group_del(lua_State *L);
int luat_lv_group_add_obj(lua_State *L);
int luat_lv_group_remove_obj(lua_State *L);
int luat_lv_group_remove_all_objs(lua_State *L);
int luat_lv_group_focus_obj(lua_State *L);
int luat_lv_group_focus_next(lua_State *L);
int luat_lv_group_focus_prev(lua_State *L);
int luat_lv_group_focus_freeze(lua_State *L);
int luat_lv_group_send_data(lua_State *L);
int luat_lv_group_set_refocus_policy(lua_State *L);
int luat_lv_group_set_editing(lua_State *L);
int luat_lv_group_set_click_focus(lua_State *L);
int luat_lv_group_set_wrap(lua_State *L);
int luat_lv_group_get_focused(lua_State *L);
int luat_lv_group_get_user_data(lua_State *L);
int luat_lv_group_get_editing(lua_State *L);
int luat_lv_group_get_click_focus(lua_State *L);
int luat_lv_group_get_wrap(lua_State *L);

#define LUAT_LV_GROUP_RLT     {"group_create", ROREG_FUNC(luat_lv_group_create)},\
    {"group_del", ROREG_FUNC(luat_lv_group_del)},\
    {"group_add_obj", ROREG_FUNC(luat_lv_group_add_obj)},\
    {"group_remove_obj", ROREG_FUNC(luat_lv_group_remove_obj)},\
    {"group_remove_all_objs", ROREG_FUNC(luat_lv_group_remove_all_objs)},\
    {"group_focus_obj", ROREG_FUNC(luat_lv_group_focus_obj)},\
    {"group_focus_next", ROREG_FUNC(luat_lv_group_focus_next)},\
    {"group_focus_prev", ROREG_FUNC(luat_lv_group_focus_prev)},\
    {"group_focus_freeze", ROREG_FUNC(luat_lv_group_focus_freeze)},\
    {"group_send_data", ROREG_FUNC(luat_lv_group_send_data)},\
    {"group_set_refocus_policy", ROREG_FUNC(luat_lv_group_set_refocus_policy)},\
    {"group_set_editing", ROREG_FUNC(luat_lv_group_set_editing)},\
    {"group_set_click_focus", ROREG_FUNC(luat_lv_group_set_click_focus)},\
    {"group_set_wrap", ROREG_FUNC(luat_lv_group_set_wrap)},\
    {"group_get_focused", ROREG_FUNC(luat_lv_group_get_focused)},\
    {"group_get_user_data", ROREG_FUNC(luat_lv_group_get_user_data)},\
    {"group_get_editing", ROREG_FUNC(luat_lv_group_get_editing)},\
    {"group_get_click_focus", ROREG_FUNC(luat_lv_group_get_click_focus)},\
    {"group_get_wrap", ROREG_FUNC(luat_lv_group_get_wrap)},\

// prefix lv_core lv_obj
int luat_lv_obj_create(lua_State *L);
int luat_lv_obj_del(lua_State *L);
int luat_lv_obj_del_async(lua_State *L);
int luat_lv_obj_clean(lua_State *L);
int luat_lv_obj_invalidate_area(lua_State *L);
int luat_lv_obj_invalidate(lua_State *L);
int luat_lv_obj_area_is_visible(lua_State *L);
int luat_lv_obj_is_visible(lua_State *L);
int luat_lv_obj_set_parent(lua_State *L);
int luat_lv_obj_move_foreground(lua_State *L);
int luat_lv_obj_move_background(lua_State *L);
int luat_lv_obj_set_pos(lua_State *L);
int luat_lv_obj_set_x(lua_State *L);
int luat_lv_obj_set_y(lua_State *L);
int luat_lv_obj_set_size(lua_State *L);
int luat_lv_obj_set_width(lua_State *L);
int luat_lv_obj_set_height(lua_State *L);
int luat_lv_obj_set_width_fit(lua_State *L);
int luat_lv_obj_set_height_fit(lua_State *L);
int luat_lv_obj_set_width_margin(lua_State *L);
int luat_lv_obj_set_height_margin(lua_State *L);
int luat_lv_obj_align(lua_State *L);
int luat_lv_obj_align_x(lua_State *L);
int luat_lv_obj_align_y(lua_State *L);
int luat_lv_obj_align_mid(lua_State *L);
int luat_lv_obj_align_mid_x(lua_State *L);
int luat_lv_obj_align_mid_y(lua_State *L);
int luat_lv_obj_realign(lua_State *L);
int luat_lv_obj_set_auto_realign(lua_State *L);
int luat_lv_obj_set_ext_click_area(lua_State *L);
int luat_lv_obj_add_style(lua_State *L);
int luat_lv_obj_remove_style(lua_State *L);
int luat_lv_obj_clean_style_list(lua_State *L);
int luat_lv_obj_reset_style_list(lua_State *L);
int luat_lv_obj_refresh_style(lua_State *L);
int luat_lv_obj_report_style_mod(lua_State *L);
int luat_lv_obj_remove_style_local_prop(lua_State *L);
int luat_lv_obj_set_hidden(lua_State *L);
int luat_lv_obj_set_adv_hittest(lua_State *L);
int luat_lv_obj_set_click(lua_State *L);
int luat_lv_obj_set_top(lua_State *L);
int luat_lv_obj_set_drag(lua_State *L);
int luat_lv_obj_set_drag_dir(lua_State *L);
int luat_lv_obj_set_drag_throw(lua_State *L);
int luat_lv_obj_set_drag_parent(lua_State *L);
int luat_lv_obj_set_focus_parent(lua_State *L);
int luat_lv_obj_set_gesture_parent(lua_State *L);
int luat_lv_obj_set_parent_event(lua_State *L);
int luat_lv_obj_set_base_dir(lua_State *L);
int luat_lv_obj_add_protect(lua_State *L);
int luat_lv_obj_clear_protect(lua_State *L);
int luat_lv_obj_set_state(lua_State *L);
int luat_lv_obj_add_state(lua_State *L);
int luat_lv_obj_clear_state(lua_State *L);
int luat_lv_obj_finish_transitions(lua_State *L);
int luat_lv_obj_allocate_ext_attr(lua_State *L);
int luat_lv_obj_refresh_ext_draw_pad(lua_State *L);
int luat_lv_obj_get_screen(lua_State *L);
int luat_lv_obj_get_disp(lua_State *L);
int luat_lv_obj_get_parent(lua_State *L);
int luat_lv_obj_get_child(lua_State *L);
int luat_lv_obj_get_child_back(lua_State *L);
int luat_lv_obj_count_children(lua_State *L);
int luat_lv_obj_count_children_recursive(lua_State *L);
int luat_lv_obj_get_coords(lua_State *L);
int luat_lv_obj_get_inner_coords(lua_State *L);
int luat_lv_obj_get_x(lua_State *L);
int luat_lv_obj_get_y(lua_State *L);
int luat_lv_obj_get_width(lua_State *L);
int luat_lv_obj_get_height(lua_State *L);
int luat_lv_obj_get_width_fit(lua_State *L);
int luat_lv_obj_get_height_fit(lua_State *L);
int luat_lv_obj_get_height_margin(lua_State *L);
int luat_lv_obj_get_width_margin(lua_State *L);
int luat_lv_obj_get_width_grid(lua_State *L);
int luat_lv_obj_get_height_grid(lua_State *L);
int luat_lv_obj_get_auto_realign(lua_State *L);
int luat_lv_obj_get_ext_click_pad_left(lua_State *L);
int luat_lv_obj_get_ext_click_pad_right(lua_State *L);
int luat_lv_obj_get_ext_click_pad_top(lua_State *L);
int luat_lv_obj_get_ext_click_pad_bottom(lua_State *L);
int luat_lv_obj_get_ext_draw_pad(lua_State *L);
int luat_lv_obj_get_style_list(lua_State *L);
int luat_lv_obj_get_local_style(lua_State *L);
int luat_lv_obj_get_style_radius(lua_State *L);
int luat_lv_obj_set_style_local_radius(lua_State *L);
int luat_lv_obj_get_style_clip_corner(lua_State *L);
int luat_lv_obj_set_style_local_clip_corner(lua_State *L);
int luat_lv_obj_get_style_size(lua_State *L);
int luat_lv_obj_set_style_local_size(lua_State *L);
int luat_lv_obj_get_style_transform_width(lua_State *L);
int luat_lv_obj_set_style_local_transform_width(lua_State *L);
int luat_lv_obj_get_style_transform_height(lua_State *L);
int luat_lv_obj_set_style_local_transform_height(lua_State *L);
int luat_lv_obj_get_style_transform_angle(lua_State *L);
int luat_lv_obj_set_style_local_transform_angle(lua_State *L);
int luat_lv_obj_get_style_transform_zoom(lua_State *L);
int luat_lv_obj_set_style_local_transform_zoom(lua_State *L);
int luat_lv_obj_get_style_opa_scale(lua_State *L);
int luat_lv_obj_set_style_local_opa_scale(lua_State *L);
int luat_lv_obj_get_style_pad_top(lua_State *L);
int luat_lv_obj_set_style_local_pad_top(lua_State *L);
int luat_lv_obj_get_style_pad_bottom(lua_State *L);
int luat_lv_obj_set_style_local_pad_bottom(lua_State *L);
int luat_lv_obj_get_style_pad_left(lua_State *L);
int luat_lv_obj_set_style_local_pad_left(lua_State *L);
int luat_lv_obj_get_style_pad_right(lua_State *L);
int luat_lv_obj_set_style_local_pad_right(lua_State *L);
int luat_lv_obj_get_style_pad_inner(lua_State *L);
int luat_lv_obj_set_style_local_pad_inner(lua_State *L);
int luat_lv_obj_get_style_margin_top(lua_State *L);
int luat_lv_obj_set_style_local_margin_top(lua_State *L);
int luat_lv_obj_get_style_margin_bottom(lua_State *L);
int luat_lv_obj_set_style_local_margin_bottom(lua_State *L);
int luat_lv_obj_get_style_margin_left(lua_State *L);
int luat_lv_obj_set_style_local_margin_left(lua_State *L);
int luat_lv_obj_get_style_margin_right(lua_State *L);
int luat_lv_obj_set_style_local_margin_right(lua_State *L);
int luat_lv_obj_get_style_bg_blend_mode(lua_State *L);
int luat_lv_obj_set_style_local_bg_blend_mode(lua_State *L);
int luat_lv_obj_get_style_bg_main_stop(lua_State *L);
int luat_lv_obj_set_style_local_bg_main_stop(lua_State *L);
int luat_lv_obj_get_style_bg_grad_stop(lua_State *L);
int luat_lv_obj_set_style_local_bg_grad_stop(lua_State *L);
int luat_lv_obj_get_style_bg_grad_dir(lua_State *L);
int luat_lv_obj_set_style_local_bg_grad_dir(lua_State *L);
int luat_lv_obj_get_style_bg_color(lua_State *L);
int luat_lv_obj_set_style_local_bg_color(lua_State *L);
int luat_lv_obj_get_style_bg_grad_color(lua_State *L);
int luat_lv_obj_set_style_local_bg_grad_color(lua_State *L);
int luat_lv_obj_get_style_bg_opa(lua_State *L);
int luat_lv_obj_set_style_local_bg_opa(lua_State *L);
int luat_lv_obj_get_style_border_width(lua_State *L);
int luat_lv_obj_set_style_local_border_width(lua_State *L);
int luat_lv_obj_get_style_border_side(lua_State *L);
int luat_lv_obj_set_style_local_border_side(lua_State *L);
int luat_lv_obj_get_style_border_blend_mode(lua_State *L);
int luat_lv_obj_set_style_local_border_blend_mode(lua_State *L);
int luat_lv_obj_get_style_border_post(lua_State *L);
int luat_lv_obj_set_style_local_border_post(lua_State *L);
int luat_lv_obj_get_style_border_color(lua_State *L);
int luat_lv_obj_set_style_local_border_color(lua_State *L);
int luat_lv_obj_get_style_border_opa(lua_State *L);
int luat_lv_obj_set_style_local_border_opa(lua_State *L);
int luat_lv_obj_get_style_outline_width(lua_State *L);
int luat_lv_obj_set_style_local_outline_width(lua_State *L);
int luat_lv_obj_get_style_outline_pad(lua_State *L);
int luat_lv_obj_set_style_local_outline_pad(lua_State *L);
int luat_lv_obj_get_style_outline_blend_mode(lua_State *L);
int luat_lv_obj_set_style_local_outline_blend_mode(lua_State *L);
int luat_lv_obj_get_style_outline_color(lua_State *L);
int luat_lv_obj_set_style_local_outline_color(lua_State *L);
int luat_lv_obj_get_style_outline_opa(lua_State *L);
int luat_lv_obj_set_style_local_outline_opa(lua_State *L);
int luat_lv_obj_get_style_shadow_width(lua_State *L);
int luat_lv_obj_set_style_local_shadow_width(lua_State *L);
int luat_lv_obj_get_style_shadow_ofs_x(lua_State *L);
int luat_lv_obj_set_style_local_shadow_ofs_x(lua_State *L);
int luat_lv_obj_get_style_shadow_ofs_y(lua_State *L);
int luat_lv_obj_set_style_local_shadow_ofs_y(lua_State *L);
int luat_lv_obj_get_style_shadow_spread(lua_State *L);
int luat_lv_obj_set_style_local_shadow_spread(lua_State *L);
int luat_lv_obj_get_style_shadow_blend_mode(lua_State *L);
int luat_lv_obj_set_style_local_shadow_blend_mode(lua_State *L);
int luat_lv_obj_get_style_shadow_color(lua_State *L);
int luat_lv_obj_set_style_local_shadow_color(lua_State *L);
int luat_lv_obj_get_style_shadow_opa(lua_State *L);
int luat_lv_obj_set_style_local_shadow_opa(lua_State *L);
int luat_lv_obj_get_style_pattern_repeat(lua_State *L);
int luat_lv_obj_set_style_local_pattern_repeat(lua_State *L);
int luat_lv_obj_get_style_pattern_blend_mode(lua_State *L);
int luat_lv_obj_set_style_local_pattern_blend_mode(lua_State *L);
int luat_lv_obj_get_style_pattern_recolor(lua_State *L);
int luat_lv_obj_set_style_local_pattern_recolor(lua_State *L);
int luat_lv_obj_get_style_pattern_opa(lua_State *L);
int luat_lv_obj_set_style_local_pattern_opa(lua_State *L);
int luat_lv_obj_get_style_pattern_recolor_opa(lua_State *L);
int luat_lv_obj_set_style_local_pattern_recolor_opa(lua_State *L);
int luat_lv_obj_get_style_pattern_image(lua_State *L);
int luat_lv_obj_set_style_local_pattern_image(lua_State *L);
int luat_lv_obj_get_style_value_letter_space(lua_State *L);
int luat_lv_obj_set_style_local_value_letter_space(lua_State *L);
int luat_lv_obj_get_style_value_line_space(lua_State *L);
int luat_lv_obj_set_style_local_value_line_space(lua_State *L);
int luat_lv_obj_get_style_value_blend_mode(lua_State *L);
int luat_lv_obj_set_style_local_value_blend_mode(lua_State *L);
int luat_lv_obj_get_style_value_ofs_x(lua_State *L);
int luat_lv_obj_set_style_local_value_ofs_x(lua_State *L);
int luat_lv_obj_get_style_value_ofs_y(lua_State *L);
int luat_lv_obj_set_style_local_value_ofs_y(lua_State *L);
int luat_lv_obj_get_style_value_align(lua_State *L);
int luat_lv_obj_set_style_local_value_align(lua_State *L);
int luat_lv_obj_get_style_value_color(lua_State *L);
int luat_lv_obj_set_style_local_value_color(lua_State *L);
int luat_lv_obj_get_style_value_opa(lua_State *L);
int luat_lv_obj_set_style_local_value_opa(lua_State *L);
int luat_lv_obj_get_style_value_font(lua_State *L);
int luat_lv_obj_set_style_local_value_font(lua_State *L);
int luat_lv_obj_get_style_value_str(lua_State *L);
int luat_lv_obj_set_style_local_value_str(lua_State *L);
int luat_lv_obj_get_style_text_letter_space(lua_State *L);
int luat_lv_obj_set_style_local_text_letter_space(lua_State *L);
int luat_lv_obj_get_style_text_line_space(lua_State *L);
int luat_lv_obj_set_style_local_text_line_space(lua_State *L);
int luat_lv_obj_get_style_text_decor(lua_State *L);
int luat_lv_obj_set_style_local_text_decor(lua_State *L);
int luat_lv_obj_get_style_text_blend_mode(lua_State *L);
int luat_lv_obj_set_style_local_text_blend_mode(lua_State *L);
int luat_lv_obj_get_style_text_color(lua_State *L);
int luat_lv_obj_set_style_local_text_color(lua_State *L);
int luat_lv_obj_get_style_text_sel_color(lua_State *L);
int luat_lv_obj_set_style_local_text_sel_color(lua_State *L);
int luat_lv_obj_get_style_text_sel_bg_color(lua_State *L);
int luat_lv_obj_set_style_local_text_sel_bg_color(lua_State *L);
int luat_lv_obj_get_style_text_opa(lua_State *L);
int luat_lv_obj_set_style_local_text_opa(lua_State *L);
int luat_lv_obj_get_style_text_font(lua_State *L);
int luat_lv_obj_set_style_local_text_font(lua_State *L);
int luat_lv_obj_get_style_line_width(lua_State *L);
int luat_lv_obj_set_style_local_line_width(lua_State *L);
int luat_lv_obj_get_style_line_blend_mode(lua_State *L);
int luat_lv_obj_set_style_local_line_blend_mode(lua_State *L);
int luat_lv_obj_get_style_line_dash_width(lua_State *L);
int luat_lv_obj_set_style_local_line_dash_width(lua_State *L);
int luat_lv_obj_get_style_line_dash_gap(lua_State *L);
int luat_lv_obj_set_style_local_line_dash_gap(lua_State *L);
int luat_lv_obj_get_style_line_rounded(lua_State *L);
int luat_lv_obj_set_style_local_line_rounded(lua_State *L);
int luat_lv_obj_get_style_line_color(lua_State *L);
int luat_lv_obj_set_style_local_line_color(lua_State *L);
int luat_lv_obj_get_style_line_opa(lua_State *L);
int luat_lv_obj_set_style_local_line_opa(lua_State *L);
int luat_lv_obj_get_style_image_blend_mode(lua_State *L);
int luat_lv_obj_set_style_local_image_blend_mode(lua_State *L);
int luat_lv_obj_get_style_image_recolor(lua_State *L);
int luat_lv_obj_set_style_local_image_recolor(lua_State *L);
int luat_lv_obj_get_style_image_opa(lua_State *L);
int luat_lv_obj_set_style_local_image_opa(lua_State *L);
int luat_lv_obj_get_style_image_recolor_opa(lua_State *L);
int luat_lv_obj_set_style_local_image_recolor_opa(lua_State *L);
int luat_lv_obj_get_style_transition_time(lua_State *L);
int luat_lv_obj_set_style_local_transition_time(lua_State *L);
int luat_lv_obj_get_style_transition_delay(lua_State *L);
int luat_lv_obj_set_style_local_transition_delay(lua_State *L);
int luat_lv_obj_get_style_transition_prop_1(lua_State *L);
int luat_lv_obj_set_style_local_transition_prop_1(lua_State *L);
int luat_lv_obj_get_style_transition_prop_2(lua_State *L);
int luat_lv_obj_set_style_local_transition_prop_2(lua_State *L);
int luat_lv_obj_get_style_transition_prop_3(lua_State *L);
int luat_lv_obj_set_style_local_transition_prop_3(lua_State *L);
int luat_lv_obj_get_style_transition_prop_4(lua_State *L);
int luat_lv_obj_set_style_local_transition_prop_4(lua_State *L);
int luat_lv_obj_get_style_transition_prop_5(lua_State *L);
int luat_lv_obj_set_style_local_transition_prop_5(lua_State *L);
int luat_lv_obj_get_style_transition_prop_6(lua_State *L);
int luat_lv_obj_set_style_local_transition_prop_6(lua_State *L);
int luat_lv_obj_get_style_transition_path(lua_State *L);
int luat_lv_obj_set_style_local_transition_path(lua_State *L);
int luat_lv_obj_get_style_scale_width(lua_State *L);
int luat_lv_obj_set_style_local_scale_width(lua_State *L);
int luat_lv_obj_get_style_scale_border_width(lua_State *L);
int luat_lv_obj_set_style_local_scale_border_width(lua_State *L);
int luat_lv_obj_get_style_scale_end_border_width(lua_State *L);
int luat_lv_obj_set_style_local_scale_end_border_width(lua_State *L);
int luat_lv_obj_get_style_scale_end_line_width(lua_State *L);
int luat_lv_obj_set_style_local_scale_end_line_width(lua_State *L);
int luat_lv_obj_get_style_scale_grad_color(lua_State *L);
int luat_lv_obj_set_style_local_scale_grad_color(lua_State *L);
int luat_lv_obj_get_style_scale_end_color(lua_State *L);
int luat_lv_obj_set_style_local_scale_end_color(lua_State *L);
int luat_lv_obj_set_style_local_pad_all(lua_State *L);
int luat_lv_obj_set_style_local_pad_hor(lua_State *L);
int luat_lv_obj_set_style_local_pad_ver(lua_State *L);
int luat_lv_obj_set_style_local_margin_all(lua_State *L);
int luat_lv_obj_set_style_local_margin_hor(lua_State *L);
int luat_lv_obj_set_style_local_margin_ver(lua_State *L);
int luat_lv_obj_get_hidden(lua_State *L);
int luat_lv_obj_get_adv_hittest(lua_State *L);
int luat_lv_obj_get_click(lua_State *L);
int luat_lv_obj_get_top(lua_State *L);
int luat_lv_obj_get_drag(lua_State *L);
int luat_lv_obj_get_drag_dir(lua_State *L);
int luat_lv_obj_get_drag_throw(lua_State *L);
int luat_lv_obj_get_drag_parent(lua_State *L);
int luat_lv_obj_get_focus_parent(lua_State *L);
int luat_lv_obj_get_parent_event(lua_State *L);
int luat_lv_obj_get_gesture_parent(lua_State *L);
int luat_lv_obj_get_base_dir(lua_State *L);
int luat_lv_obj_get_protect(lua_State *L);
int luat_lv_obj_is_protected(lua_State *L);
int luat_lv_obj_get_state(lua_State *L);
int luat_lv_obj_is_point_on_coords(lua_State *L);
int luat_lv_obj_hittest(lua_State *L);
int luat_lv_obj_get_ext_attr(lua_State *L);
int luat_lv_obj_get_type(lua_State *L);
int luat_lv_obj_get_user_data(lua_State *L);
int luat_lv_obj_get_user_data_ptr(lua_State *L);
int luat_lv_obj_set_user_data(lua_State *L);
int luat_lv_obj_get_group(lua_State *L);
int luat_lv_obj_is_focused(lua_State *L);
int luat_lv_obj_get_focused_obj(lua_State *L);
int luat_lv_obj_handle_get_type_signal(lua_State *L);
int luat_lv_obj_init_draw_rect_dsc(lua_State *L);
int luat_lv_obj_init_draw_label_dsc(lua_State *L);
int luat_lv_obj_init_draw_img_dsc(lua_State *L);
int luat_lv_obj_init_draw_line_dsc(lua_State *L);
int luat_lv_obj_get_draw_rect_ext_pad_size(lua_State *L);
int luat_lv_obj_fade_in(lua_State *L);
int luat_lv_obj_fade_out(lua_State *L);

#define LUAT_LV_OBJ_RLT     {"obj_create", ROREG_FUNC(luat_lv_obj_create)},\
    {"obj_del", ROREG_FUNC(luat_lv_obj_del)},\
    {"obj_del_async", ROREG_FUNC(luat_lv_obj_del_async)},\
    {"obj_clean", ROREG_FUNC(luat_lv_obj_clean)},\
    {"obj_invalidate_area", ROREG_FUNC(luat_lv_obj_invalidate_area)},\
    {"obj_invalidate", ROREG_FUNC(luat_lv_obj_invalidate)},\
    {"obj_area_is_visible", ROREG_FUNC(luat_lv_obj_area_is_visible)},\
    {"obj_is_visible", ROREG_FUNC(luat_lv_obj_is_visible)},\
    {"obj_set_parent", ROREG_FUNC(luat_lv_obj_set_parent)},\
    {"obj_move_foreground", ROREG_FUNC(luat_lv_obj_move_foreground)},\
    {"obj_move_background", ROREG_FUNC(luat_lv_obj_move_background)},\
    {"obj_set_pos", ROREG_FUNC(luat_lv_obj_set_pos)},\
    {"obj_set_x", ROREG_FUNC(luat_lv_obj_set_x)},\
    {"obj_set_y", ROREG_FUNC(luat_lv_obj_set_y)},\
    {"obj_set_size", ROREG_FUNC(luat_lv_obj_set_size)},\
    {"obj_set_width", ROREG_FUNC(luat_lv_obj_set_width)},\
    {"obj_set_height", ROREG_FUNC(luat_lv_obj_set_height)},\
    {"obj_set_width_fit", ROREG_FUNC(luat_lv_obj_set_width_fit)},\
    {"obj_set_height_fit", ROREG_FUNC(luat_lv_obj_set_height_fit)},\
    {"obj_set_width_margin", ROREG_FUNC(luat_lv_obj_set_width_margin)},\
    {"obj_set_height_margin", ROREG_FUNC(luat_lv_obj_set_height_margin)},\
    {"obj_align", ROREG_FUNC(luat_lv_obj_align)},\
    {"obj_align_x", ROREG_FUNC(luat_lv_obj_align_x)},\
    {"obj_align_y", ROREG_FUNC(luat_lv_obj_align_y)},\
    {"obj_align_mid", ROREG_FUNC(luat_lv_obj_align_mid)},\
    {"obj_align_mid_x", ROREG_FUNC(luat_lv_obj_align_mid_x)},\
    {"obj_align_mid_y", ROREG_FUNC(luat_lv_obj_align_mid_y)},\
    {"obj_realign", ROREG_FUNC(luat_lv_obj_realign)},\
    {"obj_set_auto_realign", ROREG_FUNC(luat_lv_obj_set_auto_realign)},\
    {"obj_set_ext_click_area", ROREG_FUNC(luat_lv_obj_set_ext_click_area)},\
    {"obj_add_style", ROREG_FUNC(luat_lv_obj_add_style)},\
    {"obj_remove_style", ROREG_FUNC(luat_lv_obj_remove_style)},\
    {"obj_clean_style_list", ROREG_FUNC(luat_lv_obj_clean_style_list)},\
    {"obj_reset_style_list", ROREG_FUNC(luat_lv_obj_reset_style_list)},\
    {"obj_refresh_style", ROREG_FUNC(luat_lv_obj_refresh_style)},\
    {"obj_report_style_mod", ROREG_FUNC(luat_lv_obj_report_style_mod)},\
    {"obj_remove_style_local_prop", ROREG_FUNC(luat_lv_obj_remove_style_local_prop)},\
    {"obj_set_hidden", ROREG_FUNC(luat_lv_obj_set_hidden)},\
    {"obj_set_adv_hittest", ROREG_FUNC(luat_lv_obj_set_adv_hittest)},\
    {"obj_set_click", ROREG_FUNC(luat_lv_obj_set_click)},\
    {"obj_set_top", ROREG_FUNC(luat_lv_obj_set_top)},\
    {"obj_set_drag", ROREG_FUNC(luat_lv_obj_set_drag)},\
    {"obj_set_drag_dir", ROREG_FUNC(luat_lv_obj_set_drag_dir)},\
    {"obj_set_drag_throw", ROREG_FUNC(luat_lv_obj_set_drag_throw)},\
    {"obj_set_drag_parent", ROREG_FUNC(luat_lv_obj_set_drag_parent)},\
    {"obj_set_focus_parent", ROREG_FUNC(luat_lv_obj_set_focus_parent)},\
    {"obj_set_gesture_parent", ROREG_FUNC(luat_lv_obj_set_gesture_parent)},\
    {"obj_set_parent_event", ROREG_FUNC(luat_lv_obj_set_parent_event)},\
    {"obj_set_base_dir", ROREG_FUNC(luat_lv_obj_set_base_dir)},\
    {"obj_add_protect", ROREG_FUNC(luat_lv_obj_add_protect)},\
    {"obj_clear_protect", ROREG_FUNC(luat_lv_obj_clear_protect)},\
    {"obj_set_state", ROREG_FUNC(luat_lv_obj_set_state)},\
    {"obj_add_state", ROREG_FUNC(luat_lv_obj_add_state)},\
    {"obj_clear_state", ROREG_FUNC(luat_lv_obj_clear_state)},\
    {"obj_finish_transitions", ROREG_FUNC(luat_lv_obj_finish_transitions)},\
    {"obj_allocate_ext_attr", ROREG_FUNC(luat_lv_obj_allocate_ext_attr)},\
    {"obj_refresh_ext_draw_pad", ROREG_FUNC(luat_lv_obj_refresh_ext_draw_pad)},\
    {"obj_get_screen", ROREG_FUNC(luat_lv_obj_get_screen)},\
    {"obj_get_disp", ROREG_FUNC(luat_lv_obj_get_disp)},\
    {"obj_get_parent", ROREG_FUNC(luat_lv_obj_get_parent)},\
    {"obj_get_child", ROREG_FUNC(luat_lv_obj_get_child)},\
    {"obj_get_child_back", ROREG_FUNC(luat_lv_obj_get_child_back)},\
    {"obj_count_children", ROREG_FUNC(luat_lv_obj_count_children)},\
    {"obj_count_children_recursive", ROREG_FUNC(luat_lv_obj_count_children_recursive)},\
    {"obj_get_coords", ROREG_FUNC(luat_lv_obj_get_coords)},\
    {"obj_get_inner_coords", ROREG_FUNC(luat_lv_obj_get_inner_coords)},\
    {"obj_get_x", ROREG_FUNC(luat_lv_obj_get_x)},\
    {"obj_get_y", ROREG_FUNC(luat_lv_obj_get_y)},\
    {"obj_get_width", ROREG_FUNC(luat_lv_obj_get_width)},\
    {"obj_get_height", ROREG_FUNC(luat_lv_obj_get_height)},\
    {"obj_get_width_fit", ROREG_FUNC(luat_lv_obj_get_width_fit)},\
    {"obj_get_height_fit", ROREG_FUNC(luat_lv_obj_get_height_fit)},\
    {"obj_get_height_margin", ROREG_FUNC(luat_lv_obj_get_height_margin)},\
    {"obj_get_width_margin", ROREG_FUNC(luat_lv_obj_get_width_margin)},\
    {"obj_get_width_grid", ROREG_FUNC(luat_lv_obj_get_width_grid)},\
    {"obj_get_height_grid", ROREG_FUNC(luat_lv_obj_get_height_grid)},\
    {"obj_get_auto_realign", ROREG_FUNC(luat_lv_obj_get_auto_realign)},\
    {"obj_get_ext_click_pad_left", ROREG_FUNC(luat_lv_obj_get_ext_click_pad_left)},\
    {"obj_get_ext_click_pad_right", ROREG_FUNC(luat_lv_obj_get_ext_click_pad_right)},\
    {"obj_get_ext_click_pad_top", ROREG_FUNC(luat_lv_obj_get_ext_click_pad_top)},\
    {"obj_get_ext_click_pad_bottom", ROREG_FUNC(luat_lv_obj_get_ext_click_pad_bottom)},\
    {"obj_get_ext_draw_pad", ROREG_FUNC(luat_lv_obj_get_ext_draw_pad)},\
    {"obj_get_style_list", ROREG_FUNC(luat_lv_obj_get_style_list)},\
    {"obj_get_local_style", ROREG_FUNC(luat_lv_obj_get_local_style)},\
    {"obj_get_style_radius", ROREG_FUNC(luat_lv_obj_get_style_radius)},\
    {"obj_set_style_local_radius", ROREG_FUNC(luat_lv_obj_set_style_local_radius)},\
    {"obj_get_style_clip_corner", ROREG_FUNC(luat_lv_obj_get_style_clip_corner)},\
    {"obj_set_style_local_clip_corner", ROREG_FUNC(luat_lv_obj_set_style_local_clip_corner)},\
    {"obj_get_style_size", ROREG_FUNC(luat_lv_obj_get_style_size)},\
    {"obj_set_style_local_size", ROREG_FUNC(luat_lv_obj_set_style_local_size)},\
    {"obj_get_style_transform_width", ROREG_FUNC(luat_lv_obj_get_style_transform_width)},\
    {"obj_set_style_local_transform_width", ROREG_FUNC(luat_lv_obj_set_style_local_transform_width)},\
    {"obj_get_style_transform_height", ROREG_FUNC(luat_lv_obj_get_style_transform_height)},\
    {"obj_set_style_local_transform_height", ROREG_FUNC(luat_lv_obj_set_style_local_transform_height)},\
    {"obj_get_style_transform_angle", ROREG_FUNC(luat_lv_obj_get_style_transform_angle)},\
    {"obj_set_style_local_transform_angle", ROREG_FUNC(luat_lv_obj_set_style_local_transform_angle)},\
    {"obj_get_style_transform_zoom", ROREG_FUNC(luat_lv_obj_get_style_transform_zoom)},\
    {"obj_set_style_local_transform_zoom", ROREG_FUNC(luat_lv_obj_set_style_local_transform_zoom)},\
    {"obj_get_style_opa_scale", ROREG_FUNC(luat_lv_obj_get_style_opa_scale)},\
    {"obj_set_style_local_opa_scale", ROREG_FUNC(luat_lv_obj_set_style_local_opa_scale)},\
    {"obj_get_style_pad_top", ROREG_FUNC(luat_lv_obj_get_style_pad_top)},\
    {"obj_set_style_local_pad_top", ROREG_FUNC(luat_lv_obj_set_style_local_pad_top)},\
    {"obj_get_style_pad_bottom", ROREG_FUNC(luat_lv_obj_get_style_pad_bottom)},\
    {"obj_set_style_local_pad_bottom", ROREG_FUNC(luat_lv_obj_set_style_local_pad_bottom)},\
    {"obj_get_style_pad_left", ROREG_FUNC(luat_lv_obj_get_style_pad_left)},\
    {"obj_set_style_local_pad_left", ROREG_FUNC(luat_lv_obj_set_style_local_pad_left)},\
    {"obj_get_style_pad_right", ROREG_FUNC(luat_lv_obj_get_style_pad_right)},\
    {"obj_set_style_local_pad_right", ROREG_FUNC(luat_lv_obj_set_style_local_pad_right)},\
    {"obj_get_style_pad_inner", ROREG_FUNC(luat_lv_obj_get_style_pad_inner)},\
    {"obj_set_style_local_pad_inner", ROREG_FUNC(luat_lv_obj_set_style_local_pad_inner)},\
    {"obj_get_style_margin_top", ROREG_FUNC(luat_lv_obj_get_style_margin_top)},\
    {"obj_set_style_local_margin_top", ROREG_FUNC(luat_lv_obj_set_style_local_margin_top)},\
    {"obj_get_style_margin_bottom", ROREG_FUNC(luat_lv_obj_get_style_margin_bottom)},\
    {"obj_set_style_local_margin_bottom", ROREG_FUNC(luat_lv_obj_set_style_local_margin_bottom)},\
    {"obj_get_style_margin_left", ROREG_FUNC(luat_lv_obj_get_style_margin_left)},\
    {"obj_set_style_local_margin_left", ROREG_FUNC(luat_lv_obj_set_style_local_margin_left)},\
    {"obj_get_style_margin_right", ROREG_FUNC(luat_lv_obj_get_style_margin_right)},\
    {"obj_set_style_local_margin_right", ROREG_FUNC(luat_lv_obj_set_style_local_margin_right)},\
    {"obj_get_style_bg_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_bg_blend_mode)},\
    {"obj_set_style_local_bg_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_bg_blend_mode)},\
    {"obj_get_style_bg_main_stop", ROREG_FUNC(luat_lv_obj_get_style_bg_main_stop)},\
    {"obj_set_style_local_bg_main_stop", ROREG_FUNC(luat_lv_obj_set_style_local_bg_main_stop)},\
    {"obj_get_style_bg_grad_stop", ROREG_FUNC(luat_lv_obj_get_style_bg_grad_stop)},\
    {"obj_set_style_local_bg_grad_stop", ROREG_FUNC(luat_lv_obj_set_style_local_bg_grad_stop)},\
    {"obj_get_style_bg_grad_dir", ROREG_FUNC(luat_lv_obj_get_style_bg_grad_dir)},\
    {"obj_set_style_local_bg_grad_dir", ROREG_FUNC(luat_lv_obj_set_style_local_bg_grad_dir)},\
    {"obj_get_style_bg_color", ROREG_FUNC(luat_lv_obj_get_style_bg_color)},\
    {"obj_set_style_local_bg_color", ROREG_FUNC(luat_lv_obj_set_style_local_bg_color)},\
    {"obj_get_style_bg_grad_color", ROREG_FUNC(luat_lv_obj_get_style_bg_grad_color)},\
    {"obj_set_style_local_bg_grad_color", ROREG_FUNC(luat_lv_obj_set_style_local_bg_grad_color)},\
    {"obj_get_style_bg_opa", ROREG_FUNC(luat_lv_obj_get_style_bg_opa)},\
    {"obj_set_style_local_bg_opa", ROREG_FUNC(luat_lv_obj_set_style_local_bg_opa)},\
    {"obj_get_style_border_width", ROREG_FUNC(luat_lv_obj_get_style_border_width)},\
    {"obj_set_style_local_border_width", ROREG_FUNC(luat_lv_obj_set_style_local_border_width)},\
    {"obj_get_style_border_side", ROREG_FUNC(luat_lv_obj_get_style_border_side)},\
    {"obj_set_style_local_border_side", ROREG_FUNC(luat_lv_obj_set_style_local_border_side)},\
    {"obj_get_style_border_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_border_blend_mode)},\
    {"obj_set_style_local_border_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_border_blend_mode)},\
    {"obj_get_style_border_post", ROREG_FUNC(luat_lv_obj_get_style_border_post)},\
    {"obj_set_style_local_border_post", ROREG_FUNC(luat_lv_obj_set_style_local_border_post)},\
    {"obj_get_style_border_color", ROREG_FUNC(luat_lv_obj_get_style_border_color)},\
    {"obj_set_style_local_border_color", ROREG_FUNC(luat_lv_obj_set_style_local_border_color)},\
    {"obj_get_style_border_opa", ROREG_FUNC(luat_lv_obj_get_style_border_opa)},\
    {"obj_set_style_local_border_opa", ROREG_FUNC(luat_lv_obj_set_style_local_border_opa)},\
    {"obj_get_style_outline_width", ROREG_FUNC(luat_lv_obj_get_style_outline_width)},\
    {"obj_set_style_local_outline_width", ROREG_FUNC(luat_lv_obj_set_style_local_outline_width)},\
    {"obj_get_style_outline_pad", ROREG_FUNC(luat_lv_obj_get_style_outline_pad)},\
    {"obj_set_style_local_outline_pad", ROREG_FUNC(luat_lv_obj_set_style_local_outline_pad)},\
    {"obj_get_style_outline_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_outline_blend_mode)},\
    {"obj_set_style_local_outline_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_outline_blend_mode)},\
    {"obj_get_style_outline_color", ROREG_FUNC(luat_lv_obj_get_style_outline_color)},\
    {"obj_set_style_local_outline_color", ROREG_FUNC(luat_lv_obj_set_style_local_outline_color)},\
    {"obj_get_style_outline_opa", ROREG_FUNC(luat_lv_obj_get_style_outline_opa)},\
    {"obj_set_style_local_outline_opa", ROREG_FUNC(luat_lv_obj_set_style_local_outline_opa)},\
    {"obj_get_style_shadow_width", ROREG_FUNC(luat_lv_obj_get_style_shadow_width)},\
    {"obj_set_style_local_shadow_width", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_width)},\
    {"obj_get_style_shadow_ofs_x", ROREG_FUNC(luat_lv_obj_get_style_shadow_ofs_x)},\
    {"obj_set_style_local_shadow_ofs_x", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_ofs_x)},\
    {"obj_get_style_shadow_ofs_y", ROREG_FUNC(luat_lv_obj_get_style_shadow_ofs_y)},\
    {"obj_set_style_local_shadow_ofs_y", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_ofs_y)},\
    {"obj_get_style_shadow_spread", ROREG_FUNC(luat_lv_obj_get_style_shadow_spread)},\
    {"obj_set_style_local_shadow_spread", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_spread)},\
    {"obj_get_style_shadow_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_shadow_blend_mode)},\
    {"obj_set_style_local_shadow_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_blend_mode)},\
    {"obj_get_style_shadow_color", ROREG_FUNC(luat_lv_obj_get_style_shadow_color)},\
    {"obj_set_style_local_shadow_color", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_color)},\
    {"obj_get_style_shadow_opa", ROREG_FUNC(luat_lv_obj_get_style_shadow_opa)},\
    {"obj_set_style_local_shadow_opa", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_opa)},\
    {"obj_get_style_pattern_repeat", ROREG_FUNC(luat_lv_obj_get_style_pattern_repeat)},\
    {"obj_set_style_local_pattern_repeat", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_repeat)},\
    {"obj_get_style_pattern_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_pattern_blend_mode)},\
    {"obj_set_style_local_pattern_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_blend_mode)},\
    {"obj_get_style_pattern_recolor", ROREG_FUNC(luat_lv_obj_get_style_pattern_recolor)},\
    {"obj_set_style_local_pattern_recolor", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_recolor)},\
    {"obj_get_style_pattern_opa", ROREG_FUNC(luat_lv_obj_get_style_pattern_opa)},\
    {"obj_set_style_local_pattern_opa", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_opa)},\
    {"obj_get_style_pattern_recolor_opa", ROREG_FUNC(luat_lv_obj_get_style_pattern_recolor_opa)},\
    {"obj_set_style_local_pattern_recolor_opa", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_recolor_opa)},\
    {"obj_get_style_pattern_image", ROREG_FUNC(luat_lv_obj_get_style_pattern_image)},\
    {"obj_set_style_local_pattern_image", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_image)},\
    {"obj_get_style_value_letter_space", ROREG_FUNC(luat_lv_obj_get_style_value_letter_space)},\
    {"obj_set_style_local_value_letter_space", ROREG_FUNC(luat_lv_obj_set_style_local_value_letter_space)},\
    {"obj_get_style_value_line_space", ROREG_FUNC(luat_lv_obj_get_style_value_line_space)},\
    {"obj_set_style_local_value_line_space", ROREG_FUNC(luat_lv_obj_set_style_local_value_line_space)},\
    {"obj_get_style_value_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_value_blend_mode)},\
    {"obj_set_style_local_value_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_value_blend_mode)},\
    {"obj_get_style_value_ofs_x", ROREG_FUNC(luat_lv_obj_get_style_value_ofs_x)},\
    {"obj_set_style_local_value_ofs_x", ROREG_FUNC(luat_lv_obj_set_style_local_value_ofs_x)},\
    {"obj_get_style_value_ofs_y", ROREG_FUNC(luat_lv_obj_get_style_value_ofs_y)},\
    {"obj_set_style_local_value_ofs_y", ROREG_FUNC(luat_lv_obj_set_style_local_value_ofs_y)},\
    {"obj_get_style_value_align", ROREG_FUNC(luat_lv_obj_get_style_value_align)},\
    {"obj_set_style_local_value_align", ROREG_FUNC(luat_lv_obj_set_style_local_value_align)},\
    {"obj_get_style_value_color", ROREG_FUNC(luat_lv_obj_get_style_value_color)},\
    {"obj_set_style_local_value_color", ROREG_FUNC(luat_lv_obj_set_style_local_value_color)},\
    {"obj_get_style_value_opa", ROREG_FUNC(luat_lv_obj_get_style_value_opa)},\
    {"obj_set_style_local_value_opa", ROREG_FUNC(luat_lv_obj_set_style_local_value_opa)},\
    {"obj_get_style_value_font", ROREG_FUNC(luat_lv_obj_get_style_value_font)},\
    {"obj_set_style_local_value_font", ROREG_FUNC(luat_lv_obj_set_style_local_value_font)},\
    {"obj_get_style_value_str", ROREG_FUNC(luat_lv_obj_get_style_value_str)},\
    {"obj_set_style_local_value_str", ROREG_FUNC(luat_lv_obj_set_style_local_value_str)},\
    {"obj_get_style_text_letter_space", ROREG_FUNC(luat_lv_obj_get_style_text_letter_space)},\
    {"obj_set_style_local_text_letter_space", ROREG_FUNC(luat_lv_obj_set_style_local_text_letter_space)},\
    {"obj_get_style_text_line_space", ROREG_FUNC(luat_lv_obj_get_style_text_line_space)},\
    {"obj_set_style_local_text_line_space", ROREG_FUNC(luat_lv_obj_set_style_local_text_line_space)},\
    {"obj_get_style_text_decor", ROREG_FUNC(luat_lv_obj_get_style_text_decor)},\
    {"obj_set_style_local_text_decor", ROREG_FUNC(luat_lv_obj_set_style_local_text_decor)},\
    {"obj_get_style_text_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_text_blend_mode)},\
    {"obj_set_style_local_text_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_text_blend_mode)},\
    {"obj_get_style_text_color", ROREG_FUNC(luat_lv_obj_get_style_text_color)},\
    {"obj_set_style_local_text_color", ROREG_FUNC(luat_lv_obj_set_style_local_text_color)},\
    {"obj_get_style_text_sel_color", ROREG_FUNC(luat_lv_obj_get_style_text_sel_color)},\
    {"obj_set_style_local_text_sel_color", ROREG_FUNC(luat_lv_obj_set_style_local_text_sel_color)},\
    {"obj_get_style_text_sel_bg_color", ROREG_FUNC(luat_lv_obj_get_style_text_sel_bg_color)},\
    {"obj_set_style_local_text_sel_bg_color", ROREG_FUNC(luat_lv_obj_set_style_local_text_sel_bg_color)},\
    {"obj_get_style_text_opa", ROREG_FUNC(luat_lv_obj_get_style_text_opa)},\
    {"obj_set_style_local_text_opa", ROREG_FUNC(luat_lv_obj_set_style_local_text_opa)},\
    {"obj_get_style_text_font", ROREG_FUNC(luat_lv_obj_get_style_text_font)},\
    {"obj_set_style_local_text_font", ROREG_FUNC(luat_lv_obj_set_style_local_text_font)},\
    {"obj_get_style_line_width", ROREG_FUNC(luat_lv_obj_get_style_line_width)},\
    {"obj_set_style_local_line_width", ROREG_FUNC(luat_lv_obj_set_style_local_line_width)},\
    {"obj_get_style_line_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_line_blend_mode)},\
    {"obj_set_style_local_line_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_line_blend_mode)},\
    {"obj_get_style_line_dash_width", ROREG_FUNC(luat_lv_obj_get_style_line_dash_width)},\
    {"obj_set_style_local_line_dash_width", ROREG_FUNC(luat_lv_obj_set_style_local_line_dash_width)},\
    {"obj_get_style_line_dash_gap", ROREG_FUNC(luat_lv_obj_get_style_line_dash_gap)},\
    {"obj_set_style_local_line_dash_gap", ROREG_FUNC(luat_lv_obj_set_style_local_line_dash_gap)},\
    {"obj_get_style_line_rounded", ROREG_FUNC(luat_lv_obj_get_style_line_rounded)},\
    {"obj_set_style_local_line_rounded", ROREG_FUNC(luat_lv_obj_set_style_local_line_rounded)},\
    {"obj_get_style_line_color", ROREG_FUNC(luat_lv_obj_get_style_line_color)},\
    {"obj_set_style_local_line_color", ROREG_FUNC(luat_lv_obj_set_style_local_line_color)},\
    {"obj_get_style_line_opa", ROREG_FUNC(luat_lv_obj_get_style_line_opa)},\
    {"obj_set_style_local_line_opa", ROREG_FUNC(luat_lv_obj_set_style_local_line_opa)},\
    {"obj_get_style_image_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_image_blend_mode)},\
    {"obj_set_style_local_image_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_image_blend_mode)},\
    {"obj_get_style_image_recolor", ROREG_FUNC(luat_lv_obj_get_style_image_recolor)},\
    {"obj_set_style_local_image_recolor", ROREG_FUNC(luat_lv_obj_set_style_local_image_recolor)},\
    {"obj_get_style_image_opa", ROREG_FUNC(luat_lv_obj_get_style_image_opa)},\
    {"obj_set_style_local_image_opa", ROREG_FUNC(luat_lv_obj_set_style_local_image_opa)},\
    {"obj_get_style_image_recolor_opa", ROREG_FUNC(luat_lv_obj_get_style_image_recolor_opa)},\
    {"obj_set_style_local_image_recolor_opa", ROREG_FUNC(luat_lv_obj_set_style_local_image_recolor_opa)},\
    {"obj_get_style_transition_time", ROREG_FUNC(luat_lv_obj_get_style_transition_time)},\
    {"obj_set_style_local_transition_time", ROREG_FUNC(luat_lv_obj_set_style_local_transition_time)},\
    {"obj_get_style_transition_delay", ROREG_FUNC(luat_lv_obj_get_style_transition_delay)},\
    {"obj_set_style_local_transition_delay", ROREG_FUNC(luat_lv_obj_set_style_local_transition_delay)},\
    {"obj_get_style_transition_prop_1", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_1)},\
    {"obj_set_style_local_transition_prop_1", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_1)},\
    {"obj_get_style_transition_prop_2", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_2)},\
    {"obj_set_style_local_transition_prop_2", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_2)},\
    {"obj_get_style_transition_prop_3", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_3)},\
    {"obj_set_style_local_transition_prop_3", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_3)},\
    {"obj_get_style_transition_prop_4", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_4)},\
    {"obj_set_style_local_transition_prop_4", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_4)},\
    {"obj_get_style_transition_prop_5", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_5)},\
    {"obj_set_style_local_transition_prop_5", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_5)},\
    {"obj_get_style_transition_prop_6", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_6)},\
    {"obj_set_style_local_transition_prop_6", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_6)},\
    {"obj_get_style_transition_path", ROREG_FUNC(luat_lv_obj_get_style_transition_path)},\
    {"obj_set_style_local_transition_path", ROREG_FUNC(luat_lv_obj_set_style_local_transition_path)},\
    {"obj_get_style_scale_width", ROREG_FUNC(luat_lv_obj_get_style_scale_width)},\
    {"obj_set_style_local_scale_width", ROREG_FUNC(luat_lv_obj_set_style_local_scale_width)},\
    {"obj_get_style_scale_border_width", ROREG_FUNC(luat_lv_obj_get_style_scale_border_width)},\
    {"obj_set_style_local_scale_border_width", ROREG_FUNC(luat_lv_obj_set_style_local_scale_border_width)},\
    {"obj_get_style_scale_end_border_width", ROREG_FUNC(luat_lv_obj_get_style_scale_end_border_width)},\
    {"obj_set_style_local_scale_end_border_width", ROREG_FUNC(luat_lv_obj_set_style_local_scale_end_border_width)},\
    {"obj_get_style_scale_end_line_width", ROREG_FUNC(luat_lv_obj_get_style_scale_end_line_width)},\
    {"obj_set_style_local_scale_end_line_width", ROREG_FUNC(luat_lv_obj_set_style_local_scale_end_line_width)},\
    {"obj_get_style_scale_grad_color", ROREG_FUNC(luat_lv_obj_get_style_scale_grad_color)},\
    {"obj_set_style_local_scale_grad_color", ROREG_FUNC(luat_lv_obj_set_style_local_scale_grad_color)},\
    {"obj_get_style_scale_end_color", ROREG_FUNC(luat_lv_obj_get_style_scale_end_color)},\
    {"obj_set_style_local_scale_end_color", ROREG_FUNC(luat_lv_obj_set_style_local_scale_end_color)},\
    {"obj_set_style_local_pad_all", ROREG_FUNC(luat_lv_obj_set_style_local_pad_all)},\
    {"obj_set_style_local_pad_hor", ROREG_FUNC(luat_lv_obj_set_style_local_pad_hor)},\
    {"obj_set_style_local_pad_ver", ROREG_FUNC(luat_lv_obj_set_style_local_pad_ver)},\
    {"obj_set_style_local_margin_all", ROREG_FUNC(luat_lv_obj_set_style_local_margin_all)},\
    {"obj_set_style_local_margin_hor", ROREG_FUNC(luat_lv_obj_set_style_local_margin_hor)},\
    {"obj_set_style_local_margin_ver", ROREG_FUNC(luat_lv_obj_set_style_local_margin_ver)},\
    {"obj_get_hidden", ROREG_FUNC(luat_lv_obj_get_hidden)},\
    {"obj_get_adv_hittest", ROREG_FUNC(luat_lv_obj_get_adv_hittest)},\
    {"obj_get_click", ROREG_FUNC(luat_lv_obj_get_click)},\
    {"obj_get_top", ROREG_FUNC(luat_lv_obj_get_top)},\
    {"obj_get_drag", ROREG_FUNC(luat_lv_obj_get_drag)},\
    {"obj_get_drag_dir", ROREG_FUNC(luat_lv_obj_get_drag_dir)},\
    {"obj_get_drag_throw", ROREG_FUNC(luat_lv_obj_get_drag_throw)},\
    {"obj_get_drag_parent", ROREG_FUNC(luat_lv_obj_get_drag_parent)},\
    {"obj_get_focus_parent", ROREG_FUNC(luat_lv_obj_get_focus_parent)},\
    {"obj_get_parent_event", ROREG_FUNC(luat_lv_obj_get_parent_event)},\
    {"obj_get_gesture_parent", ROREG_FUNC(luat_lv_obj_get_gesture_parent)},\
    {"obj_get_base_dir", ROREG_FUNC(luat_lv_obj_get_base_dir)},\
    {"obj_get_protect", ROREG_FUNC(luat_lv_obj_get_protect)},\
    {"obj_is_protected", ROREG_FUNC(luat_lv_obj_is_protected)},\
    {"obj_get_state", ROREG_FUNC(luat_lv_obj_get_state)},\
    {"obj_is_point_on_coords", ROREG_FUNC(luat_lv_obj_is_point_on_coords)},\
    {"obj_hittest", ROREG_FUNC(luat_lv_obj_hittest)},\
    {"obj_get_ext_attr", ROREG_FUNC(luat_lv_obj_get_ext_attr)},\
    {"obj_get_type", ROREG_FUNC(luat_lv_obj_get_type)},\
    {"obj_get_user_data", ROREG_FUNC(luat_lv_obj_get_user_data)},\
    {"obj_get_user_data_ptr", ROREG_FUNC(luat_lv_obj_get_user_data_ptr)},\
    {"obj_set_user_data", ROREG_FUNC(luat_lv_obj_set_user_data)},\
    {"obj_get_group", ROREG_FUNC(luat_lv_obj_get_group)},\
    {"obj_is_focused", ROREG_FUNC(luat_lv_obj_is_focused)},\
    {"obj_get_focused_obj", ROREG_FUNC(luat_lv_obj_get_focused_obj)},\
    {"obj_handle_get_type_signal", ROREG_FUNC(luat_lv_obj_handle_get_type_signal)},\
    {"obj_init_draw_rect_dsc", ROREG_FUNC(luat_lv_obj_init_draw_rect_dsc)},\
    {"obj_init_draw_label_dsc", ROREG_FUNC(luat_lv_obj_init_draw_label_dsc)},\
    {"obj_init_draw_img_dsc", ROREG_FUNC(luat_lv_obj_init_draw_img_dsc)},\
    {"obj_init_draw_line_dsc", ROREG_FUNC(luat_lv_obj_init_draw_line_dsc)},\
    {"obj_get_draw_rect_ext_pad_size", ROREG_FUNC(luat_lv_obj_get_draw_rect_ext_pad_size)},\
    {"obj_fade_in", ROREG_FUNC(luat_lv_obj_fade_in)},\
    {"obj_fade_out", ROREG_FUNC(luat_lv_obj_fade_out)},\

// prefix lv_core lv_refr
int luat_lv_refr_now(lua_State *L);

#define LUAT_LV_REFR_RLT     {"refr_now", ROREG_FUNC(luat_lv_refr_now)},\

// prefix lv_core lv_style
int luat_lv_style_init(lua_State *L);
int luat_lv_style_copy(lua_State *L);
int luat_lv_style_list_init(lua_State *L);
int luat_lv_style_list_copy(lua_State *L);
int luat_lv_style_list_get_style(lua_State *L);
int luat_lv_style_reset(lua_State *L);
int luat_lv_style_remove_prop(lua_State *L);
int luat_lv_style_list_get_local_style(lua_State *L);

#define LUAT_LV_STYLE_RLT     {"style_init", ROREG_FUNC(luat_lv_style_init)},\
    {"style_copy", ROREG_FUNC(luat_lv_style_copy)},\
    {"style_list_init", ROREG_FUNC(luat_lv_style_list_init)},\
    {"style_list_copy", ROREG_FUNC(luat_lv_style_list_copy)},\
    {"style_list_get_style", ROREG_FUNC(luat_lv_style_list_get_style)},\
    {"style_reset", ROREG_FUNC(luat_lv_style_reset)},\
    {"style_remove_prop", ROREG_FUNC(luat_lv_style_remove_prop)},\
    {"style_list_get_local_style", ROREG_FUNC(luat_lv_style_list_get_local_style)},\


// group lv_draw
// prefix lv_draw lv_draw
int luat_lv_draw_mask_add(lua_State *L);
int luat_lv_draw_mask_apply(lua_State *L);
int luat_lv_draw_mask_remove_id(lua_State *L);
int luat_lv_draw_mask_remove_custom(lua_State *L);
int luat_lv_draw_mask_get_cnt(lua_State *L);
int luat_lv_draw_mask_line_points_init(lua_State *L);
int luat_lv_draw_mask_line_angle_init(lua_State *L);
int luat_lv_draw_mask_angle_init(lua_State *L);
int luat_lv_draw_mask_radius_init(lua_State *L);
int luat_lv_draw_mask_fade_init(lua_State *L);
int luat_lv_draw_mask_map_init(lua_State *L);
int luat_lv_draw_rect_dsc_init(lua_State *L);
int luat_lv_draw_rect(lua_State *L);
int luat_lv_draw_px(lua_State *L);
int luat_lv_draw_label_dsc_init(lua_State *L);
int luat_lv_draw_label(lua_State *L);
int luat_lv_draw_img_dsc_init(lua_State *L);
int luat_lv_draw_img(lua_State *L);
int luat_lv_draw_line(lua_State *L);
int luat_lv_draw_line_dsc_init(lua_State *L);
int luat_lv_draw_arc(lua_State *L);

#define LUAT_LV_DRAW_RLT     {"draw_mask_add", ROREG_FUNC(luat_lv_draw_mask_add)},\
    {"draw_mask_apply", ROREG_FUNC(luat_lv_draw_mask_apply)},\
    {"draw_mask_remove_id", ROREG_FUNC(luat_lv_draw_mask_remove_id)},\
    {"draw_mask_remove_custom", ROREG_FUNC(luat_lv_draw_mask_remove_custom)},\
    {"draw_mask_get_cnt", ROREG_FUNC(luat_lv_draw_mask_get_cnt)},\
    {"draw_mask_line_points_init", ROREG_FUNC(luat_lv_draw_mask_line_points_init)},\
    {"draw_mask_line_angle_init", ROREG_FUNC(luat_lv_draw_mask_line_angle_init)},\
    {"draw_mask_angle_init", ROREG_FUNC(luat_lv_draw_mask_angle_init)},\
    {"draw_mask_radius_init", ROREG_FUNC(luat_lv_draw_mask_radius_init)},\
    {"draw_mask_fade_init", ROREG_FUNC(luat_lv_draw_mask_fade_init)},\
    {"draw_mask_map_init", ROREG_FUNC(luat_lv_draw_mask_map_init)},\
    {"draw_rect_dsc_init", ROREG_FUNC(luat_lv_draw_rect_dsc_init)},\
    {"draw_rect", ROREG_FUNC(luat_lv_draw_rect)},\
    {"draw_px", ROREG_FUNC(luat_lv_draw_px)},\
    {"draw_label_dsc_init", ROREG_FUNC(luat_lv_draw_label_dsc_init)},\
    {"draw_label", ROREG_FUNC(luat_lv_draw_label)},\
    {"draw_img_dsc_init", ROREG_FUNC(luat_lv_draw_img_dsc_init)},\
    {"draw_img", ROREG_FUNC(luat_lv_draw_img)},\
    {"draw_line", ROREG_FUNC(luat_lv_draw_line)},\
    {"draw_line_dsc_init", ROREG_FUNC(luat_lv_draw_line_dsc_init)},\
    {"draw_arc", ROREG_FUNC(luat_lv_draw_arc)},\


// group lv_font
// prefix lv_font lv_font
int luat_lv_font_get_glyph_dsc(lua_State *L);
int luat_lv_font_get_glyph_width(lua_State *L);
int luat_lv_font_get_line_height(lua_State *L);

#define LUAT_LV_FONT_RLT     {"font_get_glyph_dsc", ROREG_FUNC(luat_lv_font_get_glyph_dsc)},\
    {"font_get_glyph_width", ROREG_FUNC(luat_lv_font_get_glyph_width)},\
    {"font_get_line_height", ROREG_FUNC(luat_lv_font_get_line_height)},\


// group lv_misc
// prefix lv_misc lv_anim
int luat_lv_anim_init(lua_State *L);
int luat_lv_anim_set_var(lua_State *L);
int luat_lv_anim_set_time(lua_State *L);
int luat_lv_anim_set_delay(lua_State *L);
int luat_lv_anim_set_values(lua_State *L);
int luat_lv_anim_set_path(lua_State *L);
int luat_lv_anim_set_playback_time(lua_State *L);
int luat_lv_anim_set_playback_delay(lua_State *L);
int luat_lv_anim_set_repeat_count(lua_State *L);
int luat_lv_anim_set_repeat_delay(lua_State *L);
int luat_lv_anim_start(lua_State *L);
int luat_lv_anim_path_init(lua_State *L);
int luat_lv_anim_path_set_user_data(lua_State *L);
int luat_lv_anim_get_delay(lua_State *L);
int luat_lv_anim_del(lua_State *L);
int luat_lv_anim_del_all(lua_State *L);
int luat_lv_anim_get(lua_State *L);
int luat_lv_anim_custom_del(lua_State *L);
int luat_lv_anim_count_running(lua_State *L);
int luat_lv_anim_speed_to_time(lua_State *L);
int luat_lv_anim_refr_now(lua_State *L);
int luat_lv_anim_path_linear(lua_State *L);
int luat_lv_anim_path_ease_in(lua_State *L);
int luat_lv_anim_path_ease_out(lua_State *L);
int luat_lv_anim_path_ease_in_out(lua_State *L);
int luat_lv_anim_path_overshoot(lua_State *L);
int luat_lv_anim_path_bounce(lua_State *L);
int luat_lv_anim_path_step(lua_State *L);

#define LUAT_LV_ANIM_RLT     {"anim_init", ROREG_FUNC(luat_lv_anim_init)},\
    {"anim_set_var", ROREG_FUNC(luat_lv_anim_set_var)},\
    {"anim_set_time", ROREG_FUNC(luat_lv_anim_set_time)},\
    {"anim_set_delay", ROREG_FUNC(luat_lv_anim_set_delay)},\
    {"anim_set_values", ROREG_FUNC(luat_lv_anim_set_values)},\
    {"anim_set_path", ROREG_FUNC(luat_lv_anim_set_path)},\
    {"anim_set_playback_time", ROREG_FUNC(luat_lv_anim_set_playback_time)},\
    {"anim_set_playback_delay", ROREG_FUNC(luat_lv_anim_set_playback_delay)},\
    {"anim_set_repeat_count", ROREG_FUNC(luat_lv_anim_set_repeat_count)},\
    {"anim_set_repeat_delay", ROREG_FUNC(luat_lv_anim_set_repeat_delay)},\
    {"anim_start", ROREG_FUNC(luat_lv_anim_start)},\
    {"anim_path_init", ROREG_FUNC(luat_lv_anim_path_init)},\
    {"anim_path_set_user_data", ROREG_FUNC(luat_lv_anim_path_set_user_data)},\
    {"anim_get_delay", ROREG_FUNC(luat_lv_anim_get_delay)},\
    {"anim_del", ROREG_FUNC(luat_lv_anim_del)},\
    {"anim_del_all", ROREG_FUNC(luat_lv_anim_del_all)},\
    {"anim_get", ROREG_FUNC(luat_lv_anim_get)},\
    {"anim_custom_del", ROREG_FUNC(luat_lv_anim_custom_del)},\
    {"anim_count_running", ROREG_FUNC(luat_lv_anim_count_running)},\
    {"anim_speed_to_time", ROREG_FUNC(luat_lv_anim_speed_to_time)},\
    {"anim_refr_now", ROREG_FUNC(luat_lv_anim_refr_now)},\
    {"anim_path_linear", ROREG_FUNC(luat_lv_anim_path_linear)},\
    {"anim_path_ease_in", ROREG_FUNC(luat_lv_anim_path_ease_in)},\
    {"anim_path_ease_out", ROREG_FUNC(luat_lv_anim_path_ease_out)},\
    {"anim_path_ease_in_out", ROREG_FUNC(luat_lv_anim_path_ease_in_out)},\
    {"anim_path_overshoot", ROREG_FUNC(luat_lv_anim_path_overshoot)},\
    {"anim_path_bounce", ROREG_FUNC(luat_lv_anim_path_bounce)},\
    {"anim_path_step", ROREG_FUNC(luat_lv_anim_path_step)},\

// prefix lv_misc lv_area
int luat_lv_area_set(lua_State *L);
int luat_lv_area_copy(lua_State *L);
int luat_lv_area_get_width(lua_State *L);
int luat_lv_area_get_height(lua_State *L);
int luat_lv_area_set_width(lua_State *L);
int luat_lv_area_set_height(lua_State *L);
int luat_lv_area_get_size(lua_State *L);

#define LUAT_LV_AREA_RLT     {"area_set", ROREG_FUNC(luat_lv_area_set)},\
    {"area_copy", ROREG_FUNC(luat_lv_area_copy)},\
    {"area_get_width", ROREG_FUNC(luat_lv_area_get_width)},\
    {"area_get_height", ROREG_FUNC(luat_lv_area_get_height)},\
    {"area_set_width", ROREG_FUNC(luat_lv_area_set_width)},\
    {"area_set_height", ROREG_FUNC(luat_lv_area_set_height)},\
    {"area_get_size", ROREG_FUNC(luat_lv_area_get_size)},\

// prefix lv_misc lv_color
int luat_lv_color_to1(lua_State *L);
int luat_lv_color_to8(lua_State *L);
int luat_lv_color_to16(lua_State *L);
int luat_lv_color_to32(lua_State *L);
int luat_lv_color_mix(lua_State *L);
int luat_lv_color_premult(lua_State *L);
int luat_lv_color_mix_premult(lua_State *L);
int luat_lv_color_mix_with_alpha(lua_State *L);
int luat_lv_color_brightness(lua_State *L);
int luat_lv_color_make(lua_State *L);
int luat_lv_color_hex(lua_State *L);
int luat_lv_color_hex3(lua_State *L);
int luat_lv_color_fill(lua_State *L);
int luat_lv_color_lighten(lua_State *L);
int luat_lv_color_darken(lua_State *L);
int luat_lv_color_hsv_to_rgb(lua_State *L);
int luat_lv_color_rgb_to_hsv(lua_State *L);
int luat_lv_color_to_hsv(lua_State *L);

#define LUAT_LV_COLOR_RLT     {"color_to1", ROREG_FUNC(luat_lv_color_to1)},\
    {"color_to8", ROREG_FUNC(luat_lv_color_to8)},\
    {"color_to16", ROREG_FUNC(luat_lv_color_to16)},\
    {"color_to32", ROREG_FUNC(luat_lv_color_to32)},\
    {"color_mix", ROREG_FUNC(luat_lv_color_mix)},\
    {"color_premult", ROREG_FUNC(luat_lv_color_premult)},\
    {"color_mix_premult", ROREG_FUNC(luat_lv_color_mix_premult)},\
    {"color_mix_with_alpha", ROREG_FUNC(luat_lv_color_mix_with_alpha)},\
    {"color_brightness", ROREG_FUNC(luat_lv_color_brightness)},\
    {"color_make", ROREG_FUNC(luat_lv_color_make)},\
    {"color_hex", ROREG_FUNC(luat_lv_color_hex)},\
    {"color_hex3", ROREG_FUNC(luat_lv_color_hex3)},\
    {"color_fill", ROREG_FUNC(luat_lv_color_fill)},\
    {"color_lighten", ROREG_FUNC(luat_lv_color_lighten)},\
    {"color_darken", ROREG_FUNC(luat_lv_color_darken)},\
    {"color_hsv_to_rgb", ROREG_FUNC(luat_lv_color_hsv_to_rgb)},\
    {"color_rgb_to_hsv", ROREG_FUNC(luat_lv_color_rgb_to_hsv)},\
    {"color_to_hsv", ROREG_FUNC(luat_lv_color_to_hsv)},\


// group lv_themes
// prefix lv_themes lv_theme
int luat_lv_theme_set_act(lua_State *L);
int luat_lv_theme_get_act(lua_State *L);
int luat_lv_theme_apply(lua_State *L);
int luat_lv_theme_copy(lua_State *L);
int luat_lv_theme_set_base(lua_State *L);
int luat_lv_theme_get_font_small(lua_State *L);
int luat_lv_theme_get_font_normal(lua_State *L);
int luat_lv_theme_get_font_subtitle(lua_State *L);
int luat_lv_theme_get_font_title(lua_State *L);
int luat_lv_theme_get_color_primary(lua_State *L);
int luat_lv_theme_get_color_secondary(lua_State *L);
int luat_lv_theme_get_flags(lua_State *L);
int luat_lv_theme_empty_init(lua_State *L);
int luat_lv_theme_template_init(lua_State *L);
int luat_lv_theme_material_init(lua_State *L);
int luat_lv_theme_mono_init(lua_State *L);

#define LUAT_LV_THEME_RLT     {"theme_set_act", ROREG_FUNC(luat_lv_theme_set_act)},\
    {"theme_get_act", ROREG_FUNC(luat_lv_theme_get_act)},\
    {"theme_apply", ROREG_FUNC(luat_lv_theme_apply)},\
    {"theme_copy", ROREG_FUNC(luat_lv_theme_copy)},\
    {"theme_set_base", ROREG_FUNC(luat_lv_theme_set_base)},\
    {"theme_get_font_small", ROREG_FUNC(luat_lv_theme_get_font_small)},\
    {"theme_get_font_normal", ROREG_FUNC(luat_lv_theme_get_font_normal)},\
    {"theme_get_font_subtitle", ROREG_FUNC(luat_lv_theme_get_font_subtitle)},\
    {"theme_get_font_title", ROREG_FUNC(luat_lv_theme_get_font_title)},\
    {"theme_get_color_primary", ROREG_FUNC(luat_lv_theme_get_color_primary)},\
    {"theme_get_color_secondary", ROREG_FUNC(luat_lv_theme_get_color_secondary)},\
    {"theme_get_flags", ROREG_FUNC(luat_lv_theme_get_flags)},\
    {"theme_empty_init", ROREG_FUNC(luat_lv_theme_empty_init)},\
    {"theme_template_init", ROREG_FUNC(luat_lv_theme_template_init)},\
    {"theme_material_init", ROREG_FUNC(luat_lv_theme_material_init)},\
    {"theme_mono_init", ROREG_FUNC(luat_lv_theme_mono_init)},\


// group lv_widgets
// prefix lv_widgets lv_arc
int luat_lv_arc_create(lua_State *L);
int luat_lv_arc_set_start_angle(lua_State *L);
int luat_lv_arc_set_end_angle(lua_State *L);
int luat_lv_arc_set_angles(lua_State *L);
int luat_lv_arc_set_bg_start_angle(lua_State *L);
int luat_lv_arc_set_bg_end_angle(lua_State *L);
int luat_lv_arc_set_bg_angles(lua_State *L);
int luat_lv_arc_set_rotation(lua_State *L);
int luat_lv_arc_set_type(lua_State *L);
int luat_lv_arc_set_value(lua_State *L);
int luat_lv_arc_set_range(lua_State *L);
int luat_lv_arc_set_chg_rate(lua_State *L);
int luat_lv_arc_set_adjustable(lua_State *L);
int luat_lv_arc_get_angle_start(lua_State *L);
int luat_lv_arc_get_angle_end(lua_State *L);
int luat_lv_arc_get_bg_angle_start(lua_State *L);
int luat_lv_arc_get_bg_angle_end(lua_State *L);
int luat_lv_arc_get_type(lua_State *L);
int luat_lv_arc_get_value(lua_State *L);
int luat_lv_arc_get_min_value(lua_State *L);
int luat_lv_arc_get_max_value(lua_State *L);
int luat_lv_arc_is_dragged(lua_State *L);
int luat_lv_arc_get_adjustable(lua_State *L);

#define LUAT_LV_ARC_RLT     {"arc_create", ROREG_FUNC(luat_lv_arc_create)},\
    {"arc_set_start_angle", ROREG_FUNC(luat_lv_arc_set_start_angle)},\
    {"arc_set_end_angle", ROREG_FUNC(luat_lv_arc_set_end_angle)},\
    {"arc_set_angles", ROREG_FUNC(luat_lv_arc_set_angles)},\
    {"arc_set_bg_start_angle", ROREG_FUNC(luat_lv_arc_set_bg_start_angle)},\
    {"arc_set_bg_end_angle", ROREG_FUNC(luat_lv_arc_set_bg_end_angle)},\
    {"arc_set_bg_angles", ROREG_FUNC(luat_lv_arc_set_bg_angles)},\
    {"arc_set_rotation", ROREG_FUNC(luat_lv_arc_set_rotation)},\
    {"arc_set_type", ROREG_FUNC(luat_lv_arc_set_type)},\
    {"arc_set_value", ROREG_FUNC(luat_lv_arc_set_value)},\
    {"arc_set_range", ROREG_FUNC(luat_lv_arc_set_range)},\
    {"arc_set_chg_rate", ROREG_FUNC(luat_lv_arc_set_chg_rate)},\
    {"arc_set_adjustable", ROREG_FUNC(luat_lv_arc_set_adjustable)},\
    {"arc_get_angle_start", ROREG_FUNC(luat_lv_arc_get_angle_start)},\
    {"arc_get_angle_end", ROREG_FUNC(luat_lv_arc_get_angle_end)},\
    {"arc_get_bg_angle_start", ROREG_FUNC(luat_lv_arc_get_bg_angle_start)},\
    {"arc_get_bg_angle_end", ROREG_FUNC(luat_lv_arc_get_bg_angle_end)},\
    {"arc_get_type", ROREG_FUNC(luat_lv_arc_get_type)},\
    {"arc_get_value", ROREG_FUNC(luat_lv_arc_get_value)},\
    {"arc_get_min_value", ROREG_FUNC(luat_lv_arc_get_min_value)},\
    {"arc_get_max_value", ROREG_FUNC(luat_lv_arc_get_max_value)},\
    {"arc_is_dragged", ROREG_FUNC(luat_lv_arc_is_dragged)},\
    {"arc_get_adjustable", ROREG_FUNC(luat_lv_arc_get_adjustable)},\

// prefix lv_widgets lv_bar
int luat_lv_bar_create(lua_State *L);
int luat_lv_bar_set_value(lua_State *L);
int luat_lv_bar_set_start_value(lua_State *L);
int luat_lv_bar_set_range(lua_State *L);
int luat_lv_bar_set_type(lua_State *L);
int luat_lv_bar_set_anim_time(lua_State *L);
int luat_lv_bar_get_value(lua_State *L);
int luat_lv_bar_get_start_value(lua_State *L);
int luat_lv_bar_get_min_value(lua_State *L);
int luat_lv_bar_get_max_value(lua_State *L);
int luat_lv_bar_get_type(lua_State *L);
int luat_lv_bar_get_anim_time(lua_State *L);

#define LUAT_LV_BAR_RLT     {"bar_create", ROREG_FUNC(luat_lv_bar_create)},\
    {"bar_set_value", ROREG_FUNC(luat_lv_bar_set_value)},\
    {"bar_set_start_value", ROREG_FUNC(luat_lv_bar_set_start_value)},\
    {"bar_set_range", ROREG_FUNC(luat_lv_bar_set_range)},\
    {"bar_set_type", ROREG_FUNC(luat_lv_bar_set_type)},\
    {"bar_set_anim_time", ROREG_FUNC(luat_lv_bar_set_anim_time)},\
    {"bar_get_value", ROREG_FUNC(luat_lv_bar_get_value)},\
    {"bar_get_start_value", ROREG_FUNC(luat_lv_bar_get_start_value)},\
    {"bar_get_min_value", ROREG_FUNC(luat_lv_bar_get_min_value)},\
    {"bar_get_max_value", ROREG_FUNC(luat_lv_bar_get_max_value)},\
    {"bar_get_type", ROREG_FUNC(luat_lv_bar_get_type)},\
    {"bar_get_anim_time", ROREG_FUNC(luat_lv_bar_get_anim_time)},\

// prefix lv_widgets lv_btn
int luat_lv_btn_create(lua_State *L);
int luat_lv_btn_set_checkable(lua_State *L);
int luat_lv_btn_set_state(lua_State *L);
int luat_lv_btn_toggle(lua_State *L);
int luat_lv_btn_set_layout(lua_State *L);
int luat_lv_btn_set_fit4(lua_State *L);
int luat_lv_btn_set_fit2(lua_State *L);
int luat_lv_btn_set_fit(lua_State *L);
int luat_lv_btn_get_state(lua_State *L);
int luat_lv_btn_get_checkable(lua_State *L);
int luat_lv_btn_get_layout(lua_State *L);
int luat_lv_btn_get_fit_left(lua_State *L);
int luat_lv_btn_get_fit_right(lua_State *L);
int luat_lv_btn_get_fit_top(lua_State *L);
int luat_lv_btn_get_fit_bottom(lua_State *L);

#define LUAT_LV_BTN_RLT     {"btn_create", ROREG_FUNC(luat_lv_btn_create)},\
    {"btn_set_checkable", ROREG_FUNC(luat_lv_btn_set_checkable)},\
    {"btn_set_state", ROREG_FUNC(luat_lv_btn_set_state)},\
    {"btn_toggle", ROREG_FUNC(luat_lv_btn_toggle)},\
    {"btn_set_layout", ROREG_FUNC(luat_lv_btn_set_layout)},\
    {"btn_set_fit4", ROREG_FUNC(luat_lv_btn_set_fit4)},\
    {"btn_set_fit2", ROREG_FUNC(luat_lv_btn_set_fit2)},\
    {"btn_set_fit", ROREG_FUNC(luat_lv_btn_set_fit)},\
    {"btn_get_state", ROREG_FUNC(luat_lv_btn_get_state)},\
    {"btn_get_checkable", ROREG_FUNC(luat_lv_btn_get_checkable)},\
    {"btn_get_layout", ROREG_FUNC(luat_lv_btn_get_layout)},\
    {"btn_get_fit_left", ROREG_FUNC(luat_lv_btn_get_fit_left)},\
    {"btn_get_fit_right", ROREG_FUNC(luat_lv_btn_get_fit_right)},\
    {"btn_get_fit_top", ROREG_FUNC(luat_lv_btn_get_fit_top)},\
    {"btn_get_fit_bottom", ROREG_FUNC(luat_lv_btn_get_fit_bottom)},\

// prefix lv_widgets lv_btnmatrix
int luat_lv_btnmatrix_create(lua_State *L);
int luat_lv_btnmatrix_set_focused_btn(lua_State *L);
int luat_lv_btnmatrix_set_recolor(lua_State *L);
int luat_lv_btnmatrix_set_btn_ctrl(lua_State *L);
int luat_lv_btnmatrix_clear_btn_ctrl(lua_State *L);
int luat_lv_btnmatrix_set_btn_ctrl_all(lua_State *L);
int luat_lv_btnmatrix_clear_btn_ctrl_all(lua_State *L);
int luat_lv_btnmatrix_set_btn_width(lua_State *L);
int luat_lv_btnmatrix_set_one_check(lua_State *L);
int luat_lv_btnmatrix_set_align(lua_State *L);
int luat_lv_btnmatrix_get_recolor(lua_State *L);
int luat_lv_btnmatrix_get_active_btn(lua_State *L);
int luat_lv_btnmatrix_get_active_btn_text(lua_State *L);
int luat_lv_btnmatrix_get_focused_btn(lua_State *L);
int luat_lv_btnmatrix_get_btn_text(lua_State *L);
int luat_lv_btnmatrix_get_btn_ctrl(lua_State *L);
int luat_lv_btnmatrix_get_one_check(lua_State *L);
int luat_lv_btnmatrix_get_align(lua_State *L);

#define LUAT_LV_BTNMATRIX_RLT     {"btnmatrix_create", ROREG_FUNC(luat_lv_btnmatrix_create)},\
    {"btnmatrix_set_focused_btn", ROREG_FUNC(luat_lv_btnmatrix_set_focused_btn)},\
    {"btnmatrix_set_recolor", ROREG_FUNC(luat_lv_btnmatrix_set_recolor)},\
    {"btnmatrix_set_btn_ctrl", ROREG_FUNC(luat_lv_btnmatrix_set_btn_ctrl)},\
    {"btnmatrix_clear_btn_ctrl", ROREG_FUNC(luat_lv_btnmatrix_clear_btn_ctrl)},\
    {"btnmatrix_set_btn_ctrl_all", ROREG_FUNC(luat_lv_btnmatrix_set_btn_ctrl_all)},\
    {"btnmatrix_clear_btn_ctrl_all", ROREG_FUNC(luat_lv_btnmatrix_clear_btn_ctrl_all)},\
    {"btnmatrix_set_btn_width", ROREG_FUNC(luat_lv_btnmatrix_set_btn_width)},\
    {"btnmatrix_set_one_check", ROREG_FUNC(luat_lv_btnmatrix_set_one_check)},\
    {"btnmatrix_set_align", ROREG_FUNC(luat_lv_btnmatrix_set_align)},\
    {"btnmatrix_get_recolor", ROREG_FUNC(luat_lv_btnmatrix_get_recolor)},\
    {"btnmatrix_get_active_btn", ROREG_FUNC(luat_lv_btnmatrix_get_active_btn)},\
    {"btnmatrix_get_active_btn_text", ROREG_FUNC(luat_lv_btnmatrix_get_active_btn_text)},\
    {"btnmatrix_get_focused_btn", ROREG_FUNC(luat_lv_btnmatrix_get_focused_btn)},\
    {"btnmatrix_get_btn_text", ROREG_FUNC(luat_lv_btnmatrix_get_btn_text)},\
    {"btnmatrix_get_btn_ctrl", ROREG_FUNC(luat_lv_btnmatrix_get_btn_ctrl)},\
    {"btnmatrix_get_one_check", ROREG_FUNC(luat_lv_btnmatrix_get_one_check)},\
    {"btnmatrix_get_align", ROREG_FUNC(luat_lv_btnmatrix_get_align)},\

// prefix lv_widgets lv_calendar
int luat_lv_calendar_create(lua_State *L);
int luat_lv_calendar_set_today_date(lua_State *L);
int luat_lv_calendar_set_showed_date(lua_State *L);
int luat_lv_calendar_get_today_date(lua_State *L);
int luat_lv_calendar_get_showed_date(lua_State *L);
int luat_lv_calendar_get_pressed_date(lua_State *L);
int luat_lv_calendar_get_highlighted_dates(lua_State *L);
int luat_lv_calendar_get_highlighted_dates_num(lua_State *L);
int luat_lv_calendar_get_day_of_week(lua_State *L);

#define LUAT_LV_CALENDAR_RLT     {"calendar_create", ROREG_FUNC(luat_lv_calendar_create)},\
    {"calendar_set_today_date", ROREG_FUNC(luat_lv_calendar_set_today_date)},\
    {"calendar_set_showed_date", ROREG_FUNC(luat_lv_calendar_set_showed_date)},\
    {"calendar_get_today_date", ROREG_FUNC(luat_lv_calendar_get_today_date)},\
    {"calendar_get_showed_date", ROREG_FUNC(luat_lv_calendar_get_showed_date)},\
    {"calendar_get_pressed_date", ROREG_FUNC(luat_lv_calendar_get_pressed_date)},\
    {"calendar_get_highlighted_dates", ROREG_FUNC(luat_lv_calendar_get_highlighted_dates)},\
    {"calendar_get_highlighted_dates_num", ROREG_FUNC(luat_lv_calendar_get_highlighted_dates_num)},\
    {"calendar_get_day_of_week", ROREG_FUNC(luat_lv_calendar_get_day_of_week)},\

// prefix lv_widgets lv_canvas
int luat_lv_canvas_create(lua_State *L);
int luat_lv_canvas_set_px(lua_State *L);
int luat_lv_canvas_set_palette(lua_State *L);
int luat_lv_canvas_get_px(lua_State *L);
int luat_lv_canvas_get_img(lua_State *L);
int luat_lv_canvas_copy_buf(lua_State *L);
int luat_lv_canvas_transform(lua_State *L);
int luat_lv_canvas_blur_hor(lua_State *L);
int luat_lv_canvas_blur_ver(lua_State *L);
int luat_lv_canvas_fill_bg(lua_State *L);
int luat_lv_canvas_draw_rect(lua_State *L);
int luat_lv_canvas_draw_text(lua_State *L);
int luat_lv_canvas_draw_img(lua_State *L);
int luat_lv_canvas_draw_arc(lua_State *L);

#define LUAT_LV_CANVAS_RLT     {"canvas_create", ROREG_FUNC(luat_lv_canvas_create)},\
    {"canvas_set_px", ROREG_FUNC(luat_lv_canvas_set_px)},\
    {"canvas_set_palette", ROREG_FUNC(luat_lv_canvas_set_palette)},\
    {"canvas_get_px", ROREG_FUNC(luat_lv_canvas_get_px)},\
    {"canvas_get_img", ROREG_FUNC(luat_lv_canvas_get_img)},\
    {"canvas_copy_buf", ROREG_FUNC(luat_lv_canvas_copy_buf)},\
    {"canvas_transform", ROREG_FUNC(luat_lv_canvas_transform)},\
    {"canvas_blur_hor", ROREG_FUNC(luat_lv_canvas_blur_hor)},\
    {"canvas_blur_ver", ROREG_FUNC(luat_lv_canvas_blur_ver)},\
    {"canvas_fill_bg", ROREG_FUNC(luat_lv_canvas_fill_bg)},\
    {"canvas_draw_rect", ROREG_FUNC(luat_lv_canvas_draw_rect)},\
    {"canvas_draw_text", ROREG_FUNC(luat_lv_canvas_draw_text)},\
    {"canvas_draw_img", ROREG_FUNC(luat_lv_canvas_draw_img)},\
    {"canvas_draw_arc", ROREG_FUNC(luat_lv_canvas_draw_arc)},\

// prefix lv_widgets lv_chart
int luat_lv_chart_create(lua_State *L);
int luat_lv_chart_add_series(lua_State *L);
int luat_lv_chart_remove_series(lua_State *L);
int luat_lv_chart_add_cursor(lua_State *L);
int luat_lv_chart_clear_series(lua_State *L);
int luat_lv_chart_hide_series(lua_State *L);
int luat_lv_chart_set_div_line_count(lua_State *L);
int luat_lv_chart_set_y_range(lua_State *L);
int luat_lv_chart_set_type(lua_State *L);
int luat_lv_chart_set_point_count(lua_State *L);
int luat_lv_chart_init_points(lua_State *L);
int luat_lv_chart_set_next(lua_State *L);
int luat_lv_chart_set_update_mode(lua_State *L);
int luat_lv_chart_set_x_tick_length(lua_State *L);
int luat_lv_chart_set_y_tick_length(lua_State *L);
int luat_lv_chart_set_secondary_y_tick_length(lua_State *L);
int luat_lv_chart_set_x_tick_texts(lua_State *L);
int luat_lv_chart_set_secondary_y_tick_texts(lua_State *L);
int luat_lv_chart_set_y_tick_texts(lua_State *L);
int luat_lv_chart_set_x_start_point(lua_State *L);
int luat_lv_chart_set_point_id(lua_State *L);
int luat_lv_chart_set_series_axis(lua_State *L);
int luat_lv_chart_set_cursor_point(lua_State *L);
int luat_lv_chart_get_type(lua_State *L);
int luat_lv_chart_get_point_count(lua_State *L);
int luat_lv_chart_get_x_start_point(lua_State *L);
int luat_lv_chart_get_point_id(lua_State *L);
int luat_lv_chart_get_series_axis(lua_State *L);
int luat_lv_chart_get_series_area(lua_State *L);
int luat_lv_chart_get_cursor_point(lua_State *L);
int luat_lv_chart_get_nearest_index_from_coord(lua_State *L);
int luat_lv_chart_get_x_from_index(lua_State *L);
int luat_lv_chart_get_y_from_index(lua_State *L);
int luat_lv_chart_refresh(lua_State *L);

#define LUAT_LV_CHART_RLT     {"chart_create", ROREG_FUNC(luat_lv_chart_create)},\
    {"chart_add_series", ROREG_FUNC(luat_lv_chart_add_series)},\
    {"chart_remove_series", ROREG_FUNC(luat_lv_chart_remove_series)},\
    {"chart_add_cursor", ROREG_FUNC(luat_lv_chart_add_cursor)},\
    {"chart_clear_series", ROREG_FUNC(luat_lv_chart_clear_series)},\
    {"chart_hide_series", ROREG_FUNC(luat_lv_chart_hide_series)},\
    {"chart_set_div_line_count", ROREG_FUNC(luat_lv_chart_set_div_line_count)},\
    {"chart_set_y_range", ROREG_FUNC(luat_lv_chart_set_y_range)},\
    {"chart_set_type", ROREG_FUNC(luat_lv_chart_set_type)},\
    {"chart_set_point_count", ROREG_FUNC(luat_lv_chart_set_point_count)},\
    {"chart_init_points", ROREG_FUNC(luat_lv_chart_init_points)},\
    {"chart_set_next", ROREG_FUNC(luat_lv_chart_set_next)},\
    {"chart_set_update_mode", ROREG_FUNC(luat_lv_chart_set_update_mode)},\
    {"chart_set_x_tick_length", ROREG_FUNC(luat_lv_chart_set_x_tick_length)},\
    {"chart_set_y_tick_length", ROREG_FUNC(luat_lv_chart_set_y_tick_length)},\
    {"chart_set_secondary_y_tick_length", ROREG_FUNC(luat_lv_chart_set_secondary_y_tick_length)},\
    {"chart_set_x_tick_texts", ROREG_FUNC(luat_lv_chart_set_x_tick_texts)},\
    {"chart_set_secondary_y_tick_texts", ROREG_FUNC(luat_lv_chart_set_secondary_y_tick_texts)},\
    {"chart_set_y_tick_texts", ROREG_FUNC(luat_lv_chart_set_y_tick_texts)},\
    {"chart_set_x_start_point", ROREG_FUNC(luat_lv_chart_set_x_start_point)},\
    {"chart_set_point_id", ROREG_FUNC(luat_lv_chart_set_point_id)},\
    {"chart_set_series_axis", ROREG_FUNC(luat_lv_chart_set_series_axis)},\
    {"chart_set_cursor_point", ROREG_FUNC(luat_lv_chart_set_cursor_point)},\
    {"chart_get_type", ROREG_FUNC(luat_lv_chart_get_type)},\
    {"chart_get_point_count", ROREG_FUNC(luat_lv_chart_get_point_count)},\
    {"chart_get_x_start_point", ROREG_FUNC(luat_lv_chart_get_x_start_point)},\
    {"chart_get_point_id", ROREG_FUNC(luat_lv_chart_get_point_id)},\
    {"chart_get_series_axis", ROREG_FUNC(luat_lv_chart_get_series_axis)},\
    {"chart_get_series_area", ROREG_FUNC(luat_lv_chart_get_series_area)},\
    {"chart_get_cursor_point", ROREG_FUNC(luat_lv_chart_get_cursor_point)},\
    {"chart_get_nearest_index_from_coord", ROREG_FUNC(luat_lv_chart_get_nearest_index_from_coord)},\
    {"chart_get_x_from_index", ROREG_FUNC(luat_lv_chart_get_x_from_index)},\
    {"chart_get_y_from_index", ROREG_FUNC(luat_lv_chart_get_y_from_index)},\
    {"chart_refresh", ROREG_FUNC(luat_lv_chart_refresh)},\

// prefix lv_widgets lv_checkbox
int luat_lv_checkbox_create(lua_State *L);
int luat_lv_checkbox_set_text(lua_State *L);
int luat_lv_checkbox_set_text_static(lua_State *L);
int luat_lv_checkbox_set_checked(lua_State *L);
int luat_lv_checkbox_set_disabled(lua_State *L);
int luat_lv_checkbox_set_state(lua_State *L);
int luat_lv_checkbox_get_text(lua_State *L);
int luat_lv_checkbox_is_checked(lua_State *L);
int luat_lv_checkbox_is_inactive(lua_State *L);
int luat_lv_checkbox_get_state(lua_State *L);

#define LUAT_LV_CHECKBOX_RLT     {"checkbox_create", ROREG_FUNC(luat_lv_checkbox_create)},\
    {"checkbox_set_text", ROREG_FUNC(luat_lv_checkbox_set_text)},\
    {"checkbox_set_text_static", ROREG_FUNC(luat_lv_checkbox_set_text_static)},\
    {"checkbox_set_checked", ROREG_FUNC(luat_lv_checkbox_set_checked)},\
    {"checkbox_set_disabled", ROREG_FUNC(luat_lv_checkbox_set_disabled)},\
    {"checkbox_set_state", ROREG_FUNC(luat_lv_checkbox_set_state)},\
    {"checkbox_get_text", ROREG_FUNC(luat_lv_checkbox_get_text)},\
    {"checkbox_is_checked", ROREG_FUNC(luat_lv_checkbox_is_checked)},\
    {"checkbox_is_inactive", ROREG_FUNC(luat_lv_checkbox_is_inactive)},\
    {"checkbox_get_state", ROREG_FUNC(luat_lv_checkbox_get_state)},\

// prefix lv_widgets lv_cont
int luat_lv_cont_create(lua_State *L);
int luat_lv_cont_set_layout(lua_State *L);
int luat_lv_cont_set_fit4(lua_State *L);
int luat_lv_cont_set_fit2(lua_State *L);
int luat_lv_cont_set_fit(lua_State *L);
int luat_lv_cont_get_layout(lua_State *L);
int luat_lv_cont_get_fit_left(lua_State *L);
int luat_lv_cont_get_fit_right(lua_State *L);
int luat_lv_cont_get_fit_top(lua_State *L);
int luat_lv_cont_get_fit_bottom(lua_State *L);

#define LUAT_LV_CONT_RLT     {"cont_create", ROREG_FUNC(luat_lv_cont_create)},\
    {"cont_set_layout", ROREG_FUNC(luat_lv_cont_set_layout)},\
    {"cont_set_fit4", ROREG_FUNC(luat_lv_cont_set_fit4)},\
    {"cont_set_fit2", ROREG_FUNC(luat_lv_cont_set_fit2)},\
    {"cont_set_fit", ROREG_FUNC(luat_lv_cont_set_fit)},\
    {"cont_get_layout", ROREG_FUNC(luat_lv_cont_get_layout)},\
    {"cont_get_fit_left", ROREG_FUNC(luat_lv_cont_get_fit_left)},\
    {"cont_get_fit_right", ROREG_FUNC(luat_lv_cont_get_fit_right)},\
    {"cont_get_fit_top", ROREG_FUNC(luat_lv_cont_get_fit_top)},\
    {"cont_get_fit_bottom", ROREG_FUNC(luat_lv_cont_get_fit_bottom)},\

// prefix lv_widgets lv_cpicker
int luat_lv_cpicker_create(lua_State *L);
int luat_lv_cpicker_set_type(lua_State *L);
int luat_lv_cpicker_set_hue(lua_State *L);
int luat_lv_cpicker_set_saturation(lua_State *L);
int luat_lv_cpicker_set_value(lua_State *L);
int luat_lv_cpicker_set_hsv(lua_State *L);
int luat_lv_cpicker_set_color(lua_State *L);
int luat_lv_cpicker_set_color_mode(lua_State *L);
int luat_lv_cpicker_set_color_mode_fixed(lua_State *L);
int luat_lv_cpicker_set_knob_colored(lua_State *L);
int luat_lv_cpicker_get_color_mode(lua_State *L);
int luat_lv_cpicker_get_color_mode_fixed(lua_State *L);
int luat_lv_cpicker_get_hue(lua_State *L);
int luat_lv_cpicker_get_saturation(lua_State *L);
int luat_lv_cpicker_get_value(lua_State *L);
int luat_lv_cpicker_get_hsv(lua_State *L);
int luat_lv_cpicker_get_color(lua_State *L);
int luat_lv_cpicker_get_knob_colored(lua_State *L);

#define LUAT_LV_CPICKER_RLT     {"cpicker_create", ROREG_FUNC(luat_lv_cpicker_create)},\
    {"cpicker_set_type", ROREG_FUNC(luat_lv_cpicker_set_type)},\
    {"cpicker_set_hue", ROREG_FUNC(luat_lv_cpicker_set_hue)},\
    {"cpicker_set_saturation", ROREG_FUNC(luat_lv_cpicker_set_saturation)},\
    {"cpicker_set_value", ROREG_FUNC(luat_lv_cpicker_set_value)},\
    {"cpicker_set_hsv", ROREG_FUNC(luat_lv_cpicker_set_hsv)},\
    {"cpicker_set_color", ROREG_FUNC(luat_lv_cpicker_set_color)},\
    {"cpicker_set_color_mode", ROREG_FUNC(luat_lv_cpicker_set_color_mode)},\
    {"cpicker_set_color_mode_fixed", ROREG_FUNC(luat_lv_cpicker_set_color_mode_fixed)},\
    {"cpicker_set_knob_colored", ROREG_FUNC(luat_lv_cpicker_set_knob_colored)},\
    {"cpicker_get_color_mode", ROREG_FUNC(luat_lv_cpicker_get_color_mode)},\
    {"cpicker_get_color_mode_fixed", ROREG_FUNC(luat_lv_cpicker_get_color_mode_fixed)},\
    {"cpicker_get_hue", ROREG_FUNC(luat_lv_cpicker_get_hue)},\
    {"cpicker_get_saturation", ROREG_FUNC(luat_lv_cpicker_get_saturation)},\
    {"cpicker_get_value", ROREG_FUNC(luat_lv_cpicker_get_value)},\
    {"cpicker_get_hsv", ROREG_FUNC(luat_lv_cpicker_get_hsv)},\
    {"cpicker_get_color", ROREG_FUNC(luat_lv_cpicker_get_color)},\
    {"cpicker_get_knob_colored", ROREG_FUNC(luat_lv_cpicker_get_knob_colored)},\

// prefix lv_widgets lv_dropdown
int luat_lv_dropdown_create(lua_State *L);
int luat_lv_dropdown_set_text(lua_State *L);
int luat_lv_dropdown_clear_options(lua_State *L);
int luat_lv_dropdown_set_options(lua_State *L);
int luat_lv_dropdown_set_options_static(lua_State *L);
int luat_lv_dropdown_add_option(lua_State *L);
int luat_lv_dropdown_set_selected(lua_State *L);
int luat_lv_dropdown_set_dir(lua_State *L);
int luat_lv_dropdown_set_max_height(lua_State *L);
int luat_lv_dropdown_set_show_selected(lua_State *L);
int luat_lv_dropdown_get_text(lua_State *L);
int luat_lv_dropdown_get_options(lua_State *L);
int luat_lv_dropdown_get_selected(lua_State *L);
int luat_lv_dropdown_get_option_cnt(lua_State *L);
int luat_lv_dropdown_get_max_height(lua_State *L);
int luat_lv_dropdown_get_symbol(lua_State *L);
int luat_lv_dropdown_get_dir(lua_State *L);
int luat_lv_dropdown_get_show_selected(lua_State *L);
int luat_lv_dropdown_open(lua_State *L);
int luat_lv_dropdown_close(lua_State *L);

#define LUAT_LV_DROPDOWN_RLT     {"dropdown_create", ROREG_FUNC(luat_lv_dropdown_create)},\
    {"dropdown_set_text", ROREG_FUNC(luat_lv_dropdown_set_text)},\
    {"dropdown_clear_options", ROREG_FUNC(luat_lv_dropdown_clear_options)},\
    {"dropdown_set_options", ROREG_FUNC(luat_lv_dropdown_set_options)},\
    {"dropdown_set_options_static", ROREG_FUNC(luat_lv_dropdown_set_options_static)},\
    {"dropdown_add_option", ROREG_FUNC(luat_lv_dropdown_add_option)},\
    {"dropdown_set_selected", ROREG_FUNC(luat_lv_dropdown_set_selected)},\
    {"dropdown_set_dir", ROREG_FUNC(luat_lv_dropdown_set_dir)},\
    {"dropdown_set_max_height", ROREG_FUNC(luat_lv_dropdown_set_max_height)},\
    {"dropdown_set_show_selected", ROREG_FUNC(luat_lv_dropdown_set_show_selected)},\
    {"dropdown_get_text", ROREG_FUNC(luat_lv_dropdown_get_text)},\
    {"dropdown_get_options", ROREG_FUNC(luat_lv_dropdown_get_options)},\
    {"dropdown_get_selected", ROREG_FUNC(luat_lv_dropdown_get_selected)},\
    {"dropdown_get_option_cnt", ROREG_FUNC(luat_lv_dropdown_get_option_cnt)},\
    {"dropdown_get_max_height", ROREG_FUNC(luat_lv_dropdown_get_max_height)},\
    {"dropdown_get_symbol", ROREG_FUNC(luat_lv_dropdown_get_symbol)},\
    {"dropdown_get_dir", ROREG_FUNC(luat_lv_dropdown_get_dir)},\
    {"dropdown_get_show_selected", ROREG_FUNC(luat_lv_dropdown_get_show_selected)},\
    {"dropdown_open", ROREG_FUNC(luat_lv_dropdown_open)},\
    {"dropdown_close", ROREG_FUNC(luat_lv_dropdown_close)},\

// prefix lv_widgets lv_gauge
int luat_lv_gauge_create(lua_State *L);
int luat_lv_gauge_set_value(lua_State *L);
int luat_lv_gauge_set_range(lua_State *L);
int luat_lv_gauge_set_critical_value(lua_State *L);
int luat_lv_gauge_set_scale(lua_State *L);
int luat_lv_gauge_set_angle_offset(lua_State *L);
int luat_lv_gauge_set_needle_img(lua_State *L);
int luat_lv_gauge_get_value(lua_State *L);
int luat_lv_gauge_get_needle_count(lua_State *L);
int luat_lv_gauge_get_min_value(lua_State *L);
int luat_lv_gauge_get_max_value(lua_State *L);
int luat_lv_gauge_get_critical_value(lua_State *L);
int luat_lv_gauge_get_label_count(lua_State *L);
int luat_lv_gauge_get_line_count(lua_State *L);
int luat_lv_gauge_get_scale_angle(lua_State *L);
int luat_lv_gauge_get_angle_offset(lua_State *L);
int luat_lv_gauge_get_needle_img(lua_State *L);
int luat_lv_gauge_get_needle_img_pivot_x(lua_State *L);
int luat_lv_gauge_get_needle_img_pivot_y(lua_State *L);

#define LUAT_LV_GAUGE_RLT     {"gauge_create", ROREG_FUNC(luat_lv_gauge_create)},\
    {"gauge_set_value", ROREG_FUNC(luat_lv_gauge_set_value)},\
    {"gauge_set_range", ROREG_FUNC(luat_lv_gauge_set_range)},\
    {"gauge_set_critical_value", ROREG_FUNC(luat_lv_gauge_set_critical_value)},\
    {"gauge_set_scale", ROREG_FUNC(luat_lv_gauge_set_scale)},\
    {"gauge_set_angle_offset", ROREG_FUNC(luat_lv_gauge_set_angle_offset)},\
    {"gauge_set_needle_img", ROREG_FUNC(luat_lv_gauge_set_needle_img)},\
    {"gauge_get_value", ROREG_FUNC(luat_lv_gauge_get_value)},\
    {"gauge_get_needle_count", ROREG_FUNC(luat_lv_gauge_get_needle_count)},\
    {"gauge_get_min_value", ROREG_FUNC(luat_lv_gauge_get_min_value)},\
    {"gauge_get_max_value", ROREG_FUNC(luat_lv_gauge_get_max_value)},\
    {"gauge_get_critical_value", ROREG_FUNC(luat_lv_gauge_get_critical_value)},\
    {"gauge_get_label_count", ROREG_FUNC(luat_lv_gauge_get_label_count)},\
    {"gauge_get_line_count", ROREG_FUNC(luat_lv_gauge_get_line_count)},\
    {"gauge_get_scale_angle", ROREG_FUNC(luat_lv_gauge_get_scale_angle)},\
    {"gauge_get_angle_offset", ROREG_FUNC(luat_lv_gauge_get_angle_offset)},\
    {"gauge_get_needle_img", ROREG_FUNC(luat_lv_gauge_get_needle_img)},\
    {"gauge_get_needle_img_pivot_x", ROREG_FUNC(luat_lv_gauge_get_needle_img_pivot_x)},\
    {"gauge_get_needle_img_pivot_y", ROREG_FUNC(luat_lv_gauge_get_needle_img_pivot_y)},\

// prefix lv_widgets lv_img
int luat_lv_img_buf_alloc(lua_State *L);
int luat_lv_img_buf_get_px_color(lua_State *L);
int luat_lv_img_buf_get_px_alpha(lua_State *L);
int luat_lv_img_buf_set_px_color(lua_State *L);
int luat_lv_img_buf_set_px_alpha(lua_State *L);
int luat_lv_img_buf_set_palette(lua_State *L);
int luat_lv_img_buf_free(lua_State *L);
int luat_lv_img_buf_get_img_size(lua_State *L);
int luat_lv_img_decoder_get_info(lua_State *L);
int luat_lv_img_decoder_open(lua_State *L);
int luat_lv_img_decoder_read_line(lua_State *L);
int luat_lv_img_decoder_close(lua_State *L);
int luat_lv_img_decoder_create(lua_State *L);
int luat_lv_img_decoder_delete(lua_State *L);
int luat_lv_img_decoder_built_in_info(lua_State *L);
int luat_lv_img_decoder_built_in_open(lua_State *L);
int luat_lv_img_decoder_built_in_read_line(lua_State *L);
int luat_lv_img_decoder_built_in_close(lua_State *L);
int luat_lv_img_src_get_type(lua_State *L);
int luat_lv_img_cf_get_px_size(lua_State *L);
int luat_lv_img_cf_is_chroma_keyed(lua_State *L);
int luat_lv_img_cf_has_alpha(lua_State *L);
int luat_lv_img_create(lua_State *L);
int luat_lv_img_set_auto_size(lua_State *L);
int luat_lv_img_set_offset_x(lua_State *L);
int luat_lv_img_set_offset_y(lua_State *L);
int luat_lv_img_set_pivot(lua_State *L);
int luat_lv_img_set_angle(lua_State *L);
int luat_lv_img_set_zoom(lua_State *L);
int luat_lv_img_set_antialias(lua_State *L);
int luat_lv_img_get_src(lua_State *L);
int luat_lv_img_get_file_name(lua_State *L);
int luat_lv_img_get_auto_size(lua_State *L);
int luat_lv_img_get_offset_x(lua_State *L);
int luat_lv_img_get_offset_y(lua_State *L);
int luat_lv_img_get_angle(lua_State *L);
int luat_lv_img_get_pivot(lua_State *L);
int luat_lv_img_get_zoom(lua_State *L);
int luat_lv_img_get_antialias(lua_State *L);

#define LUAT_LV_IMG_RLT     {"img_buf_alloc", ROREG_FUNC(luat_lv_img_buf_alloc)},\
    {"img_buf_get_px_color", ROREG_FUNC(luat_lv_img_buf_get_px_color)},\
    {"img_buf_get_px_alpha", ROREG_FUNC(luat_lv_img_buf_get_px_alpha)},\
    {"img_buf_set_px_color", ROREG_FUNC(luat_lv_img_buf_set_px_color)},\
    {"img_buf_set_px_alpha", ROREG_FUNC(luat_lv_img_buf_set_px_alpha)},\
    {"img_buf_set_palette", ROREG_FUNC(luat_lv_img_buf_set_palette)},\
    {"img_buf_free", ROREG_FUNC(luat_lv_img_buf_free)},\
    {"img_buf_get_img_size", ROREG_FUNC(luat_lv_img_buf_get_img_size)},\
    {"img_decoder_get_info", ROREG_FUNC(luat_lv_img_decoder_get_info)},\
    {"img_decoder_open", ROREG_FUNC(luat_lv_img_decoder_open)},\
    {"img_decoder_read_line", ROREG_FUNC(luat_lv_img_decoder_read_line)},\
    {"img_decoder_close", ROREG_FUNC(luat_lv_img_decoder_close)},\
    {"img_decoder_create", ROREG_FUNC(luat_lv_img_decoder_create)},\
    {"img_decoder_delete", ROREG_FUNC(luat_lv_img_decoder_delete)},\
    {"img_decoder_built_in_info", ROREG_FUNC(luat_lv_img_decoder_built_in_info)},\
    {"img_decoder_built_in_open", ROREG_FUNC(luat_lv_img_decoder_built_in_open)},\
    {"img_decoder_built_in_read_line", ROREG_FUNC(luat_lv_img_decoder_built_in_read_line)},\
    {"img_decoder_built_in_close", ROREG_FUNC(luat_lv_img_decoder_built_in_close)},\
    {"img_src_get_type", ROREG_FUNC(luat_lv_img_src_get_type)},\
    {"img_cf_get_px_size", ROREG_FUNC(luat_lv_img_cf_get_px_size)},\
    {"img_cf_is_chroma_keyed", ROREG_FUNC(luat_lv_img_cf_is_chroma_keyed)},\
    {"img_cf_has_alpha", ROREG_FUNC(luat_lv_img_cf_has_alpha)},\
    {"img_create", ROREG_FUNC(luat_lv_img_create)},\
    {"img_set_auto_size", ROREG_FUNC(luat_lv_img_set_auto_size)},\
    {"img_set_offset_x", ROREG_FUNC(luat_lv_img_set_offset_x)},\
    {"img_set_offset_y", ROREG_FUNC(luat_lv_img_set_offset_y)},\
    {"img_set_pivot", ROREG_FUNC(luat_lv_img_set_pivot)},\
    {"img_set_angle", ROREG_FUNC(luat_lv_img_set_angle)},\
    {"img_set_zoom", ROREG_FUNC(luat_lv_img_set_zoom)},\
    {"img_set_antialias", ROREG_FUNC(luat_lv_img_set_antialias)},\
    {"img_get_src", ROREG_FUNC(luat_lv_img_get_src)},\
    {"img_get_file_name", ROREG_FUNC(luat_lv_img_get_file_name)},\
    {"img_get_auto_size", ROREG_FUNC(luat_lv_img_get_auto_size)},\
    {"img_get_offset_x", ROREG_FUNC(luat_lv_img_get_offset_x)},\
    {"img_get_offset_y", ROREG_FUNC(luat_lv_img_get_offset_y)},\
    {"img_get_angle", ROREG_FUNC(luat_lv_img_get_angle)},\
    {"img_get_pivot", ROREG_FUNC(luat_lv_img_get_pivot)},\
    {"img_get_zoom", ROREG_FUNC(luat_lv_img_get_zoom)},\
    {"img_get_antialias", ROREG_FUNC(luat_lv_img_get_antialias)},\

// prefix lv_widgets lv_imgbtn
int luat_lv_imgbtn_create(lua_State *L);
int luat_lv_imgbtn_set_state(lua_State *L);
int luat_lv_imgbtn_toggle(lua_State *L);
int luat_lv_imgbtn_set_checkable(lua_State *L);
int luat_lv_imgbtn_get_src(lua_State *L);
int luat_lv_imgbtn_get_state(lua_State *L);
int luat_lv_imgbtn_get_checkable(lua_State *L);

#define LUAT_LV_IMGBTN_RLT     {"imgbtn_create", ROREG_FUNC(luat_lv_imgbtn_create)},\
    {"imgbtn_set_state", ROREG_FUNC(luat_lv_imgbtn_set_state)},\
    {"imgbtn_toggle", ROREG_FUNC(luat_lv_imgbtn_toggle)},\
    {"imgbtn_set_checkable", ROREG_FUNC(luat_lv_imgbtn_set_checkable)},\
    {"imgbtn_get_src", ROREG_FUNC(luat_lv_imgbtn_get_src)},\
    {"imgbtn_get_state", ROREG_FUNC(luat_lv_imgbtn_get_state)},\
    {"imgbtn_get_checkable", ROREG_FUNC(luat_lv_imgbtn_get_checkable)},\

// prefix lv_widgets lv_keyboard
int luat_lv_keyboard_create(lua_State *L);
int luat_lv_keyboard_set_textarea(lua_State *L);
int luat_lv_keyboard_set_mode(lua_State *L);
int luat_lv_keyboard_set_cursor_manage(lua_State *L);
int luat_lv_keyboard_get_textarea(lua_State *L);
int luat_lv_keyboard_get_mode(lua_State *L);
int luat_lv_keyboard_get_cursor_manage(lua_State *L);

#define LUAT_LV_KEYBOARD_RLT     {"keyboard_create", ROREG_FUNC(luat_lv_keyboard_create)},\
    {"keyboard_set_textarea", ROREG_FUNC(luat_lv_keyboard_set_textarea)},\
    {"keyboard_set_mode", ROREG_FUNC(luat_lv_keyboard_set_mode)},\
    {"keyboard_set_cursor_manage", ROREG_FUNC(luat_lv_keyboard_set_cursor_manage)},\
    {"keyboard_get_textarea", ROREG_FUNC(luat_lv_keyboard_get_textarea)},\
    {"keyboard_get_mode", ROREG_FUNC(luat_lv_keyboard_get_mode)},\
    {"keyboard_get_cursor_manage", ROREG_FUNC(luat_lv_keyboard_get_cursor_manage)},\

// prefix lv_widgets lv_label
int luat_lv_label_create(lua_State *L);
int luat_lv_label_set_text(lua_State *L);
int luat_lv_label_set_text_static(lua_State *L);
int luat_lv_label_set_long_mode(lua_State *L);
int luat_lv_label_set_align(lua_State *L);
int luat_lv_label_set_recolor(lua_State *L);
int luat_lv_label_set_anim_speed(lua_State *L);
int luat_lv_label_set_text_sel_start(lua_State *L);
int luat_lv_label_set_text_sel_end(lua_State *L);
int luat_lv_label_get_text(lua_State *L);
int luat_lv_label_get_long_mode(lua_State *L);
int luat_lv_label_get_align(lua_State *L);
int luat_lv_label_get_recolor(lua_State *L);
int luat_lv_label_get_anim_speed(lua_State *L);
int luat_lv_label_get_letter_pos(lua_State *L);
int luat_lv_label_get_letter_on(lua_State *L);
int luat_lv_label_is_char_under_pos(lua_State *L);
int luat_lv_label_get_text_sel_start(lua_State *L);
int luat_lv_label_get_text_sel_end(lua_State *L);
int luat_lv_label_get_style(lua_State *L);
int luat_lv_label_ins_text(lua_State *L);
int luat_lv_label_cut_text(lua_State *L);
int luat_lv_label_refr_text(lua_State *L);

#define LUAT_LV_LABEL_RLT     {"label_create", ROREG_FUNC(luat_lv_label_create)},\
    {"label_set_text", ROREG_FUNC(luat_lv_label_set_text)},\
    {"label_set_text_static", ROREG_FUNC(luat_lv_label_set_text_static)},\
    {"label_set_long_mode", ROREG_FUNC(luat_lv_label_set_long_mode)},\
    {"label_set_align", ROREG_FUNC(luat_lv_label_set_align)},\
    {"label_set_recolor", ROREG_FUNC(luat_lv_label_set_recolor)},\
    {"label_set_anim_speed", ROREG_FUNC(luat_lv_label_set_anim_speed)},\
    {"label_set_text_sel_start", ROREG_FUNC(luat_lv_label_set_text_sel_start)},\
    {"label_set_text_sel_end", ROREG_FUNC(luat_lv_label_set_text_sel_end)},\
    {"label_get_text", ROREG_FUNC(luat_lv_label_get_text)},\
    {"label_get_long_mode", ROREG_FUNC(luat_lv_label_get_long_mode)},\
    {"label_get_align", ROREG_FUNC(luat_lv_label_get_align)},\
    {"label_get_recolor", ROREG_FUNC(luat_lv_label_get_recolor)},\
    {"label_get_anim_speed", ROREG_FUNC(luat_lv_label_get_anim_speed)},\
    {"label_get_letter_pos", ROREG_FUNC(luat_lv_label_get_letter_pos)},\
    {"label_get_letter_on", ROREG_FUNC(luat_lv_label_get_letter_on)},\
    {"label_is_char_under_pos", ROREG_FUNC(luat_lv_label_is_char_under_pos)},\
    {"label_get_text_sel_start", ROREG_FUNC(luat_lv_label_get_text_sel_start)},\
    {"label_get_text_sel_end", ROREG_FUNC(luat_lv_label_get_text_sel_end)},\
    {"label_get_style", ROREG_FUNC(luat_lv_label_get_style)},\
    {"label_ins_text", ROREG_FUNC(luat_lv_label_ins_text)},\
    {"label_cut_text", ROREG_FUNC(luat_lv_label_cut_text)},\
    {"label_refr_text", ROREG_FUNC(luat_lv_label_refr_text)},\

// prefix lv_widgets lv_led
int luat_lv_led_create(lua_State *L);
int luat_lv_led_set_bright(lua_State *L);
int luat_lv_led_on(lua_State *L);
int luat_lv_led_off(lua_State *L);
int luat_lv_led_toggle(lua_State *L);
int luat_lv_led_get_bright(lua_State *L);

#define LUAT_LV_LED_RLT     {"led_create", ROREG_FUNC(luat_lv_led_create)},\
    {"led_set_bright", ROREG_FUNC(luat_lv_led_set_bright)},\
    {"led_on", ROREG_FUNC(luat_lv_led_on)},\
    {"led_off", ROREG_FUNC(luat_lv_led_off)},\
    {"led_toggle", ROREG_FUNC(luat_lv_led_toggle)},\
    {"led_get_bright", ROREG_FUNC(luat_lv_led_get_bright)},\

// prefix lv_widgets lv_line
int luat_lv_line_create(lua_State *L);
int luat_lv_line_set_auto_size(lua_State *L);
int luat_lv_line_set_y_invert(lua_State *L);
int luat_lv_line_get_auto_size(lua_State *L);
int luat_lv_line_get_y_invert(lua_State *L);

#define LUAT_LV_LINE_RLT     {"line_create", ROREG_FUNC(luat_lv_line_create)},\
    {"line_set_auto_size", ROREG_FUNC(luat_lv_line_set_auto_size)},\
    {"line_set_y_invert", ROREG_FUNC(luat_lv_line_set_y_invert)},\
    {"line_get_auto_size", ROREG_FUNC(luat_lv_line_get_auto_size)},\
    {"line_get_y_invert", ROREG_FUNC(luat_lv_line_get_y_invert)},\

// prefix lv_widgets lv_linemeter
int luat_lv_linemeter_create(lua_State *L);
int luat_lv_linemeter_set_value(lua_State *L);
int luat_lv_linemeter_set_range(lua_State *L);
int luat_lv_linemeter_set_scale(lua_State *L);
int luat_lv_linemeter_set_angle_offset(lua_State *L);
int luat_lv_linemeter_set_mirror(lua_State *L);
int luat_lv_linemeter_get_value(lua_State *L);
int luat_lv_linemeter_get_min_value(lua_State *L);
int luat_lv_linemeter_get_max_value(lua_State *L);
int luat_lv_linemeter_get_line_count(lua_State *L);
int luat_lv_linemeter_get_scale_angle(lua_State *L);
int luat_lv_linemeter_get_angle_offset(lua_State *L);
int luat_lv_linemeter_draw_scale(lua_State *L);
int luat_lv_linemeter_get_mirror(lua_State *L);

#define LUAT_LV_LINEMETER_RLT     {"linemeter_create", ROREG_FUNC(luat_lv_linemeter_create)},\
    {"linemeter_set_value", ROREG_FUNC(luat_lv_linemeter_set_value)},\
    {"linemeter_set_range", ROREG_FUNC(luat_lv_linemeter_set_range)},\
    {"linemeter_set_scale", ROREG_FUNC(luat_lv_linemeter_set_scale)},\
    {"linemeter_set_angle_offset", ROREG_FUNC(luat_lv_linemeter_set_angle_offset)},\
    {"linemeter_set_mirror", ROREG_FUNC(luat_lv_linemeter_set_mirror)},\
    {"linemeter_get_value", ROREG_FUNC(luat_lv_linemeter_get_value)},\
    {"linemeter_get_min_value", ROREG_FUNC(luat_lv_linemeter_get_min_value)},\
    {"linemeter_get_max_value", ROREG_FUNC(luat_lv_linemeter_get_max_value)},\
    {"linemeter_get_line_count", ROREG_FUNC(luat_lv_linemeter_get_line_count)},\
    {"linemeter_get_scale_angle", ROREG_FUNC(luat_lv_linemeter_get_scale_angle)},\
    {"linemeter_get_angle_offset", ROREG_FUNC(luat_lv_linemeter_get_angle_offset)},\
    {"linemeter_draw_scale", ROREG_FUNC(luat_lv_linemeter_draw_scale)},\
    {"linemeter_get_mirror", ROREG_FUNC(luat_lv_linemeter_get_mirror)},\

// prefix lv_widgets lv_list
int luat_lv_list_create(lua_State *L);
int luat_lv_list_clean(lua_State *L);
int luat_lv_list_add_btn(lua_State *L);
int luat_lv_list_remove(lua_State *L);
int luat_lv_list_focus_btn(lua_State *L);
int luat_lv_list_set_scrollbar_mode(lua_State *L);
int luat_lv_list_set_scroll_propagation(lua_State *L);
int luat_lv_list_set_edge_flash(lua_State *L);
int luat_lv_list_set_anim_time(lua_State *L);
int luat_lv_list_set_layout(lua_State *L);
int luat_lv_list_get_btn_text(lua_State *L);
int luat_lv_list_get_btn_label(lua_State *L);
int luat_lv_list_get_btn_img(lua_State *L);
int luat_lv_list_get_prev_btn(lua_State *L);
int luat_lv_list_get_next_btn(lua_State *L);
int luat_lv_list_get_btn_index(lua_State *L);
int luat_lv_list_get_size(lua_State *L);
int luat_lv_list_get_btn_selected(lua_State *L);
int luat_lv_list_get_layout(lua_State *L);
int luat_lv_list_get_scrollbar_mode(lua_State *L);
int luat_lv_list_get_scroll_propagation(lua_State *L);
int luat_lv_list_get_edge_flash(lua_State *L);
int luat_lv_list_get_anim_time(lua_State *L);
int luat_lv_list_up(lua_State *L);
int luat_lv_list_down(lua_State *L);
int luat_lv_list_focus(lua_State *L);

#define LUAT_LV_LIST_RLT     {"list_create", ROREG_FUNC(luat_lv_list_create)},\
    {"list_clean", ROREG_FUNC(luat_lv_list_clean)},\
    {"list_add_btn", ROREG_FUNC(luat_lv_list_add_btn)},\
    {"list_remove", ROREG_FUNC(luat_lv_list_remove)},\
    {"list_focus_btn", ROREG_FUNC(luat_lv_list_focus_btn)},\
    {"list_set_scrollbar_mode", ROREG_FUNC(luat_lv_list_set_scrollbar_mode)},\
    {"list_set_scroll_propagation", ROREG_FUNC(luat_lv_list_set_scroll_propagation)},\
    {"list_set_edge_flash", ROREG_FUNC(luat_lv_list_set_edge_flash)},\
    {"list_set_anim_time", ROREG_FUNC(luat_lv_list_set_anim_time)},\
    {"list_set_layout", ROREG_FUNC(luat_lv_list_set_layout)},\
    {"list_get_btn_text", ROREG_FUNC(luat_lv_list_get_btn_text)},\
    {"list_get_btn_label", ROREG_FUNC(luat_lv_list_get_btn_label)},\
    {"list_get_btn_img", ROREG_FUNC(luat_lv_list_get_btn_img)},\
    {"list_get_prev_btn", ROREG_FUNC(luat_lv_list_get_prev_btn)},\
    {"list_get_next_btn", ROREG_FUNC(luat_lv_list_get_next_btn)},\
    {"list_get_btn_index", ROREG_FUNC(luat_lv_list_get_btn_index)},\
    {"list_get_size", ROREG_FUNC(luat_lv_list_get_size)},\
    {"list_get_btn_selected", ROREG_FUNC(luat_lv_list_get_btn_selected)},\
    {"list_get_layout", ROREG_FUNC(luat_lv_list_get_layout)},\
    {"list_get_scrollbar_mode", ROREG_FUNC(luat_lv_list_get_scrollbar_mode)},\
    {"list_get_scroll_propagation", ROREG_FUNC(luat_lv_list_get_scroll_propagation)},\
    {"list_get_edge_flash", ROREG_FUNC(luat_lv_list_get_edge_flash)},\
    {"list_get_anim_time", ROREG_FUNC(luat_lv_list_get_anim_time)},\
    {"list_up", ROREG_FUNC(luat_lv_list_up)},\
    {"list_down", ROREG_FUNC(luat_lv_list_down)},\
    {"list_focus", ROREG_FUNC(luat_lv_list_focus)},\

// prefix lv_widgets lv_msgbox
int luat_lv_msgbox_create(lua_State *L);
int luat_lv_msgbox_set_text(lua_State *L);
int luat_lv_msgbox_set_anim_time(lua_State *L);
int luat_lv_msgbox_start_auto_close(lua_State *L);
int luat_lv_msgbox_stop_auto_close(lua_State *L);
int luat_lv_msgbox_set_recolor(lua_State *L);
int luat_lv_msgbox_get_text(lua_State *L);
int luat_lv_msgbox_get_active_btn(lua_State *L);
int luat_lv_msgbox_get_active_btn_text(lua_State *L);
int luat_lv_msgbox_get_anim_time(lua_State *L);
int luat_lv_msgbox_get_recolor(lua_State *L);
int luat_lv_msgbox_get_btnmatrix(lua_State *L);

#define LUAT_LV_MSGBOX_RLT     {"msgbox_create", ROREG_FUNC(luat_lv_msgbox_create)},\
    {"msgbox_set_text", ROREG_FUNC(luat_lv_msgbox_set_text)},\
    {"msgbox_set_anim_time", ROREG_FUNC(luat_lv_msgbox_set_anim_time)},\
    {"msgbox_start_auto_close", ROREG_FUNC(luat_lv_msgbox_start_auto_close)},\
    {"msgbox_stop_auto_close", ROREG_FUNC(luat_lv_msgbox_stop_auto_close)},\
    {"msgbox_set_recolor", ROREG_FUNC(luat_lv_msgbox_set_recolor)},\
    {"msgbox_get_text", ROREG_FUNC(luat_lv_msgbox_get_text)},\
    {"msgbox_get_active_btn", ROREG_FUNC(luat_lv_msgbox_get_active_btn)},\
    {"msgbox_get_active_btn_text", ROREG_FUNC(luat_lv_msgbox_get_active_btn_text)},\
    {"msgbox_get_anim_time", ROREG_FUNC(luat_lv_msgbox_get_anim_time)},\
    {"msgbox_get_recolor", ROREG_FUNC(luat_lv_msgbox_get_recolor)},\
    {"msgbox_get_btnmatrix", ROREG_FUNC(luat_lv_msgbox_get_btnmatrix)},\

// prefix lv_widgets lv_objmask
int luat_lv_objmask_create(lua_State *L);
int luat_lv_objmask_add_mask(lua_State *L);
int luat_lv_objmask_update_mask(lua_State *L);
int luat_lv_objmask_remove_mask(lua_State *L);

#define LUAT_LV_OBJMASK_RLT     {"objmask_create", ROREG_FUNC(luat_lv_objmask_create)},\
    {"objmask_add_mask", ROREG_FUNC(luat_lv_objmask_add_mask)},\
    {"objmask_update_mask", ROREG_FUNC(luat_lv_objmask_update_mask)},\
    {"objmask_remove_mask", ROREG_FUNC(luat_lv_objmask_remove_mask)},\

// prefix lv_widgets lv_page
int luat_lv_page_create(lua_State *L);
int luat_lv_page_clean(lua_State *L);
int luat_lv_page_get_scrollable(lua_State *L);
int luat_lv_page_get_anim_time(lua_State *L);
int luat_lv_page_set_scrollbar_mode(lua_State *L);
int luat_lv_page_set_anim_time(lua_State *L);
int luat_lv_page_set_scroll_propagation(lua_State *L);
int luat_lv_page_set_edge_flash(lua_State *L);
int luat_lv_page_set_scrollable_fit4(lua_State *L);
int luat_lv_page_set_scrollable_fit2(lua_State *L);
int luat_lv_page_set_scrollable_fit(lua_State *L);
int luat_lv_page_set_scrl_width(lua_State *L);
int luat_lv_page_set_scrl_height(lua_State *L);
int luat_lv_page_set_scrl_layout(lua_State *L);
int luat_lv_page_get_scrollbar_mode(lua_State *L);
int luat_lv_page_get_scroll_propagation(lua_State *L);
int luat_lv_page_get_edge_flash(lua_State *L);
int luat_lv_page_get_width_fit(lua_State *L);
int luat_lv_page_get_height_fit(lua_State *L);
int luat_lv_page_get_width_grid(lua_State *L);
int luat_lv_page_get_height_grid(lua_State *L);
int luat_lv_page_get_scrl_width(lua_State *L);
int luat_lv_page_get_scrl_height(lua_State *L);
int luat_lv_page_get_scrl_layout(lua_State *L);
int luat_lv_page_get_scrl_fit_left(lua_State *L);
int luat_lv_page_get_scrl_fit_right(lua_State *L);
int luat_lv_page_get_scrl_fit_top(lua_State *L);
int luat_lv_page_get_scrl_fit_bottom(lua_State *L);
int luat_lv_page_on_edge(lua_State *L);
int luat_lv_page_glue_obj(lua_State *L);
int luat_lv_page_focus(lua_State *L);
int luat_lv_page_scroll_hor(lua_State *L);
int luat_lv_page_scroll_ver(lua_State *L);
int luat_lv_page_start_edge_flash(lua_State *L);

#define LUAT_LV_PAGE_RLT     {"page_create", ROREG_FUNC(luat_lv_page_create)},\
    {"page_clean", ROREG_FUNC(luat_lv_page_clean)},\
    {"page_get_scrollable", ROREG_FUNC(luat_lv_page_get_scrollable)},\
    {"page_get_anim_time", ROREG_FUNC(luat_lv_page_get_anim_time)},\
    {"page_set_scrollbar_mode", ROREG_FUNC(luat_lv_page_set_scrollbar_mode)},\
    {"page_set_anim_time", ROREG_FUNC(luat_lv_page_set_anim_time)},\
    {"page_set_scroll_propagation", ROREG_FUNC(luat_lv_page_set_scroll_propagation)},\
    {"page_set_edge_flash", ROREG_FUNC(luat_lv_page_set_edge_flash)},\
    {"page_set_scrollable_fit4", ROREG_FUNC(luat_lv_page_set_scrollable_fit4)},\
    {"page_set_scrollable_fit2", ROREG_FUNC(luat_lv_page_set_scrollable_fit2)},\
    {"page_set_scrollable_fit", ROREG_FUNC(luat_lv_page_set_scrollable_fit)},\
    {"page_set_scrl_width", ROREG_FUNC(luat_lv_page_set_scrl_width)},\
    {"page_set_scrl_height", ROREG_FUNC(luat_lv_page_set_scrl_height)},\
    {"page_set_scrl_layout", ROREG_FUNC(luat_lv_page_set_scrl_layout)},\
    {"page_get_scrollbar_mode", ROREG_FUNC(luat_lv_page_get_scrollbar_mode)},\
    {"page_get_scroll_propagation", ROREG_FUNC(luat_lv_page_get_scroll_propagation)},\
    {"page_get_edge_flash", ROREG_FUNC(luat_lv_page_get_edge_flash)},\
    {"page_get_width_fit", ROREG_FUNC(luat_lv_page_get_width_fit)},\
    {"page_get_height_fit", ROREG_FUNC(luat_lv_page_get_height_fit)},\
    {"page_get_width_grid", ROREG_FUNC(luat_lv_page_get_width_grid)},\
    {"page_get_height_grid", ROREG_FUNC(luat_lv_page_get_height_grid)},\
    {"page_get_scrl_width", ROREG_FUNC(luat_lv_page_get_scrl_width)},\
    {"page_get_scrl_height", ROREG_FUNC(luat_lv_page_get_scrl_height)},\
    {"page_get_scrl_layout", ROREG_FUNC(luat_lv_page_get_scrl_layout)},\
    {"page_get_scrl_fit_left", ROREG_FUNC(luat_lv_page_get_scrl_fit_left)},\
    {"page_get_scrl_fit_right", ROREG_FUNC(luat_lv_page_get_scrl_fit_right)},\
    {"page_get_scrl_fit_top", ROREG_FUNC(luat_lv_page_get_scrl_fit_top)},\
    {"page_get_scrl_fit_bottom", ROREG_FUNC(luat_lv_page_get_scrl_fit_bottom)},\
    {"page_on_edge", ROREG_FUNC(luat_lv_page_on_edge)},\
    {"page_glue_obj", ROREG_FUNC(luat_lv_page_glue_obj)},\
    {"page_focus", ROREG_FUNC(luat_lv_page_focus)},\
    {"page_scroll_hor", ROREG_FUNC(luat_lv_page_scroll_hor)},\
    {"page_scroll_ver", ROREG_FUNC(luat_lv_page_scroll_ver)},\
    {"page_start_edge_flash", ROREG_FUNC(luat_lv_page_start_edge_flash)},\

// prefix lv_widgets lv_roller
int luat_lv_roller_create(lua_State *L);
int luat_lv_roller_set_options(lua_State *L);
int luat_lv_roller_set_align(lua_State *L);
int luat_lv_roller_set_selected(lua_State *L);
int luat_lv_roller_set_visible_row_count(lua_State *L);
int luat_lv_roller_set_auto_fit(lua_State *L);
int luat_lv_roller_set_anim_time(lua_State *L);
int luat_lv_roller_get_selected(lua_State *L);
int luat_lv_roller_get_option_cnt(lua_State *L);
int luat_lv_roller_get_align(lua_State *L);
int luat_lv_roller_get_auto_fit(lua_State *L);
int luat_lv_roller_get_options(lua_State *L);
int luat_lv_roller_get_anim_time(lua_State *L);

#define LUAT_LV_ROLLER_RLT     {"roller_create", ROREG_FUNC(luat_lv_roller_create)},\
    {"roller_set_options", ROREG_FUNC(luat_lv_roller_set_options)},\
    {"roller_set_align", ROREG_FUNC(luat_lv_roller_set_align)},\
    {"roller_set_selected", ROREG_FUNC(luat_lv_roller_set_selected)},\
    {"roller_set_visible_row_count", ROREG_FUNC(luat_lv_roller_set_visible_row_count)},\
    {"roller_set_auto_fit", ROREG_FUNC(luat_lv_roller_set_auto_fit)},\
    {"roller_set_anim_time", ROREG_FUNC(luat_lv_roller_set_anim_time)},\
    {"roller_get_selected", ROREG_FUNC(luat_lv_roller_get_selected)},\
    {"roller_get_option_cnt", ROREG_FUNC(luat_lv_roller_get_option_cnt)},\
    {"roller_get_align", ROREG_FUNC(luat_lv_roller_get_align)},\
    {"roller_get_auto_fit", ROREG_FUNC(luat_lv_roller_get_auto_fit)},\
    {"roller_get_options", ROREG_FUNC(luat_lv_roller_get_options)},\
    {"roller_get_anim_time", ROREG_FUNC(luat_lv_roller_get_anim_time)},\

// prefix lv_widgets lv_slider
int luat_lv_slider_create(lua_State *L);
int luat_lv_slider_set_value(lua_State *L);
int luat_lv_slider_set_left_value(lua_State *L);
int luat_lv_slider_set_range(lua_State *L);
int luat_lv_slider_set_anim_time(lua_State *L);
int luat_lv_slider_set_type(lua_State *L);
int luat_lv_slider_get_value(lua_State *L);
int luat_lv_slider_get_left_value(lua_State *L);
int luat_lv_slider_get_min_value(lua_State *L);
int luat_lv_slider_get_max_value(lua_State *L);
int luat_lv_slider_is_dragged(lua_State *L);
int luat_lv_slider_get_anim_time(lua_State *L);
int luat_lv_slider_get_type(lua_State *L);

#define LUAT_LV_SLIDER_RLT     {"slider_create", ROREG_FUNC(luat_lv_slider_create)},\
    {"slider_set_value", ROREG_FUNC(luat_lv_slider_set_value)},\
    {"slider_set_left_value", ROREG_FUNC(luat_lv_slider_set_left_value)},\
    {"slider_set_range", ROREG_FUNC(luat_lv_slider_set_range)},\
    {"slider_set_anim_time", ROREG_FUNC(luat_lv_slider_set_anim_time)},\
    {"slider_set_type", ROREG_FUNC(luat_lv_slider_set_type)},\
    {"slider_get_value", ROREG_FUNC(luat_lv_slider_get_value)},\
    {"slider_get_left_value", ROREG_FUNC(luat_lv_slider_get_left_value)},\
    {"slider_get_min_value", ROREG_FUNC(luat_lv_slider_get_min_value)},\
    {"slider_get_max_value", ROREG_FUNC(luat_lv_slider_get_max_value)},\
    {"slider_is_dragged", ROREG_FUNC(luat_lv_slider_is_dragged)},\
    {"slider_get_anim_time", ROREG_FUNC(luat_lv_slider_get_anim_time)},\
    {"slider_get_type", ROREG_FUNC(luat_lv_slider_get_type)},\

// prefix lv_widgets lv_spinbox
int luat_lv_spinbox_create(lua_State *L);
int luat_lv_spinbox_set_rollover(lua_State *L);
int luat_lv_spinbox_set_value(lua_State *L);
int luat_lv_spinbox_set_digit_format(lua_State *L);
int luat_lv_spinbox_set_step(lua_State *L);
int luat_lv_spinbox_set_range(lua_State *L);
int luat_lv_spinbox_set_padding_left(lua_State *L);
int luat_lv_spinbox_get_rollover(lua_State *L);
int luat_lv_spinbox_get_value(lua_State *L);
int luat_lv_spinbox_get_step(lua_State *L);
int luat_lv_spinbox_step_next(lua_State *L);
int luat_lv_spinbox_step_prev(lua_State *L);
int luat_lv_spinbox_increment(lua_State *L);
int luat_lv_spinbox_decrement(lua_State *L);

#define LUAT_LV_SPINBOX_RLT     {"spinbox_create", ROREG_FUNC(luat_lv_spinbox_create)},\
    {"spinbox_set_rollover", ROREG_FUNC(luat_lv_spinbox_set_rollover)},\
    {"spinbox_set_value", ROREG_FUNC(luat_lv_spinbox_set_value)},\
    {"spinbox_set_digit_format", ROREG_FUNC(luat_lv_spinbox_set_digit_format)},\
    {"spinbox_set_step", ROREG_FUNC(luat_lv_spinbox_set_step)},\
    {"spinbox_set_range", ROREG_FUNC(luat_lv_spinbox_set_range)},\
    {"spinbox_set_padding_left", ROREG_FUNC(luat_lv_spinbox_set_padding_left)},\
    {"spinbox_get_rollover", ROREG_FUNC(luat_lv_spinbox_get_rollover)},\
    {"spinbox_get_value", ROREG_FUNC(luat_lv_spinbox_get_value)},\
    {"spinbox_get_step", ROREG_FUNC(luat_lv_spinbox_get_step)},\
    {"spinbox_step_next", ROREG_FUNC(luat_lv_spinbox_step_next)},\
    {"spinbox_step_prev", ROREG_FUNC(luat_lv_spinbox_step_prev)},\
    {"spinbox_increment", ROREG_FUNC(luat_lv_spinbox_increment)},\
    {"spinbox_decrement", ROREG_FUNC(luat_lv_spinbox_decrement)},\

// prefix lv_widgets lv_spinner
int luat_lv_spinner_create(lua_State *L);
int luat_lv_spinner_set_arc_length(lua_State *L);
int luat_lv_spinner_set_spin_time(lua_State *L);
int luat_lv_spinner_set_type(lua_State *L);
int luat_lv_spinner_set_dir(lua_State *L);
int luat_lv_spinner_get_arc_length(lua_State *L);
int luat_lv_spinner_get_spin_time(lua_State *L);
int luat_lv_spinner_get_type(lua_State *L);
int luat_lv_spinner_get_dir(lua_State *L);

#define LUAT_LV_SPINNER_RLT     {"spinner_create", ROREG_FUNC(luat_lv_spinner_create)},\
    {"spinner_set_arc_length", ROREG_FUNC(luat_lv_spinner_set_arc_length)},\
    {"spinner_set_spin_time", ROREG_FUNC(luat_lv_spinner_set_spin_time)},\
    {"spinner_set_type", ROREG_FUNC(luat_lv_spinner_set_type)},\
    {"spinner_set_dir", ROREG_FUNC(luat_lv_spinner_set_dir)},\
    {"spinner_get_arc_length", ROREG_FUNC(luat_lv_spinner_get_arc_length)},\
    {"spinner_get_spin_time", ROREG_FUNC(luat_lv_spinner_get_spin_time)},\
    {"spinner_get_type", ROREG_FUNC(luat_lv_spinner_get_type)},\
    {"spinner_get_dir", ROREG_FUNC(luat_lv_spinner_get_dir)},\

// prefix lv_widgets lv_switch
int luat_lv_switch_create(lua_State *L);
int luat_lv_switch_on(lua_State *L);
int luat_lv_switch_off(lua_State *L);
int luat_lv_switch_toggle(lua_State *L);
int luat_lv_switch_set_anim_time(lua_State *L);
int luat_lv_switch_get_state(lua_State *L);
int luat_lv_switch_get_anim_time(lua_State *L);

#define LUAT_LV_SWITCH_RLT     {"switch_create", ROREG_FUNC(luat_lv_switch_create)},\
    {"switch_on", ROREG_FUNC(luat_lv_switch_on)},\
    {"switch_off", ROREG_FUNC(luat_lv_switch_off)},\
    {"switch_toggle", ROREG_FUNC(luat_lv_switch_toggle)},\
    {"switch_set_anim_time", ROREG_FUNC(luat_lv_switch_set_anim_time)},\
    {"switch_get_state", ROREG_FUNC(luat_lv_switch_get_state)},\
    {"switch_get_anim_time", ROREG_FUNC(luat_lv_switch_get_anim_time)},\

// prefix lv_widgets lv_table
int luat_lv_table_create(lua_State *L);
int luat_lv_table_set_cell_value(lua_State *L);
int luat_lv_table_set_row_cnt(lua_State *L);
int luat_lv_table_set_col_cnt(lua_State *L);
int luat_lv_table_set_col_width(lua_State *L);
int luat_lv_table_set_cell_align(lua_State *L);
int luat_lv_table_set_cell_type(lua_State *L);
int luat_lv_table_set_cell_crop(lua_State *L);
int luat_lv_table_set_cell_merge_right(lua_State *L);
int luat_lv_table_get_cell_value(lua_State *L);
int luat_lv_table_get_row_cnt(lua_State *L);
int luat_lv_table_get_col_cnt(lua_State *L);
int luat_lv_table_get_col_width(lua_State *L);
int luat_lv_table_get_cell_align(lua_State *L);
int luat_lv_table_get_cell_type(lua_State *L);
int luat_lv_table_get_cell_crop(lua_State *L);
int luat_lv_table_get_cell_merge_right(lua_State *L);
int luat_lv_table_get_pressed_cell(lua_State *L);

#define LUAT_LV_TABLE_RLT     {"table_create", ROREG_FUNC(luat_lv_table_create)},\
    {"table_set_cell_value", ROREG_FUNC(luat_lv_table_set_cell_value)},\
    {"table_set_row_cnt", ROREG_FUNC(luat_lv_table_set_row_cnt)},\
    {"table_set_col_cnt", ROREG_FUNC(luat_lv_table_set_col_cnt)},\
    {"table_set_col_width", ROREG_FUNC(luat_lv_table_set_col_width)},\
    {"table_set_cell_align", ROREG_FUNC(luat_lv_table_set_cell_align)},\
    {"table_set_cell_type", ROREG_FUNC(luat_lv_table_set_cell_type)},\
    {"table_set_cell_crop", ROREG_FUNC(luat_lv_table_set_cell_crop)},\
    {"table_set_cell_merge_right", ROREG_FUNC(luat_lv_table_set_cell_merge_right)},\
    {"table_get_cell_value", ROREG_FUNC(luat_lv_table_get_cell_value)},\
    {"table_get_row_cnt", ROREG_FUNC(luat_lv_table_get_row_cnt)},\
    {"table_get_col_cnt", ROREG_FUNC(luat_lv_table_get_col_cnt)},\
    {"table_get_col_width", ROREG_FUNC(luat_lv_table_get_col_width)},\
    {"table_get_cell_align", ROREG_FUNC(luat_lv_table_get_cell_align)},\
    {"table_get_cell_type", ROREG_FUNC(luat_lv_table_get_cell_type)},\
    {"table_get_cell_crop", ROREG_FUNC(luat_lv_table_get_cell_crop)},\
    {"table_get_cell_merge_right", ROREG_FUNC(luat_lv_table_get_cell_merge_right)},\
    {"table_get_pressed_cell", ROREG_FUNC(luat_lv_table_get_pressed_cell)},\

// prefix lv_widgets lv_tabview
int luat_lv_tabview_create(lua_State *L);
int luat_lv_tabview_add_tab(lua_State *L);
int luat_lv_tabview_clean_tab(lua_State *L);
int luat_lv_tabview_set_tab_act(lua_State *L);
int luat_lv_tabview_set_tab_name(lua_State *L);
int luat_lv_tabview_set_anim_time(lua_State *L);
int luat_lv_tabview_set_btns_pos(lua_State *L);
int luat_lv_tabview_get_tab_act(lua_State *L);
int luat_lv_tabview_get_tab_count(lua_State *L);
int luat_lv_tabview_get_tab(lua_State *L);
int luat_lv_tabview_get_anim_time(lua_State *L);
int luat_lv_tabview_get_btns_pos(lua_State *L);

#define LUAT_LV_TABVIEW_RLT     {"tabview_create", ROREG_FUNC(luat_lv_tabview_create)},\
    {"tabview_add_tab", ROREG_FUNC(luat_lv_tabview_add_tab)},\
    {"tabview_clean_tab", ROREG_FUNC(luat_lv_tabview_clean_tab)},\
    {"tabview_set_tab_act", ROREG_FUNC(luat_lv_tabview_set_tab_act)},\
    {"tabview_set_tab_name", ROREG_FUNC(luat_lv_tabview_set_tab_name)},\
    {"tabview_set_anim_time", ROREG_FUNC(luat_lv_tabview_set_anim_time)},\
    {"tabview_set_btns_pos", ROREG_FUNC(luat_lv_tabview_set_btns_pos)},\
    {"tabview_get_tab_act", ROREG_FUNC(luat_lv_tabview_get_tab_act)},\
    {"tabview_get_tab_count", ROREG_FUNC(luat_lv_tabview_get_tab_count)},\
    {"tabview_get_tab", ROREG_FUNC(luat_lv_tabview_get_tab)},\
    {"tabview_get_anim_time", ROREG_FUNC(luat_lv_tabview_get_anim_time)},\
    {"tabview_get_btns_pos", ROREG_FUNC(luat_lv_tabview_get_btns_pos)},\

// prefix lv_widgets lv_textarea
int luat_lv_textarea_create(lua_State *L);
int luat_lv_textarea_add_char(lua_State *L);
int luat_lv_textarea_add_text(lua_State *L);
int luat_lv_textarea_del_char(lua_State *L);
int luat_lv_textarea_del_char_forward(lua_State *L);
int luat_lv_textarea_set_text(lua_State *L);
int luat_lv_textarea_set_placeholder_text(lua_State *L);
int luat_lv_textarea_set_cursor_pos(lua_State *L);
int luat_lv_textarea_set_cursor_hidden(lua_State *L);
int luat_lv_textarea_set_cursor_click_pos(lua_State *L);
int luat_lv_textarea_set_pwd_mode(lua_State *L);
int luat_lv_textarea_set_one_line(lua_State *L);
int luat_lv_textarea_set_text_align(lua_State *L);
int luat_lv_textarea_set_accepted_chars(lua_State *L);
int luat_lv_textarea_set_max_length(lua_State *L);
int luat_lv_textarea_set_insert_replace(lua_State *L);
int luat_lv_textarea_set_scrollbar_mode(lua_State *L);
int luat_lv_textarea_set_scroll_propagation(lua_State *L);
int luat_lv_textarea_set_edge_flash(lua_State *L);
int luat_lv_textarea_set_text_sel(lua_State *L);
int luat_lv_textarea_set_pwd_show_time(lua_State *L);
int luat_lv_textarea_set_cursor_blink_time(lua_State *L);
int luat_lv_textarea_get_text(lua_State *L);
int luat_lv_textarea_get_placeholder_text(lua_State *L);
int luat_lv_textarea_get_label(lua_State *L);
int luat_lv_textarea_get_cursor_pos(lua_State *L);
int luat_lv_textarea_get_cursor_hidden(lua_State *L);
int luat_lv_textarea_get_cursor_click_pos(lua_State *L);
int luat_lv_textarea_get_pwd_mode(lua_State *L);
int luat_lv_textarea_get_one_line(lua_State *L);
int luat_lv_textarea_get_accepted_chars(lua_State *L);
int luat_lv_textarea_get_max_length(lua_State *L);
int luat_lv_textarea_get_scrollbar_mode(lua_State *L);
int luat_lv_textarea_get_scroll_propagation(lua_State *L);
int luat_lv_textarea_get_edge_flash(lua_State *L);
int luat_lv_textarea_text_is_selected(lua_State *L);
int luat_lv_textarea_get_text_sel_en(lua_State *L);
int luat_lv_textarea_get_pwd_show_time(lua_State *L);
int luat_lv_textarea_get_cursor_blink_time(lua_State *L);
int luat_lv_textarea_clear_selection(lua_State *L);
int luat_lv_textarea_cursor_right(lua_State *L);
int luat_lv_textarea_cursor_left(lua_State *L);
int luat_lv_textarea_cursor_down(lua_State *L);
int luat_lv_textarea_cursor_up(lua_State *L);

#define LUAT_LV_TEXTAREA_RLT     {"textarea_create", ROREG_FUNC(luat_lv_textarea_create)},\
    {"textarea_add_char", ROREG_FUNC(luat_lv_textarea_add_char)},\
    {"textarea_add_text", ROREG_FUNC(luat_lv_textarea_add_text)},\
    {"textarea_del_char", ROREG_FUNC(luat_lv_textarea_del_char)},\
    {"textarea_del_char_forward", ROREG_FUNC(luat_lv_textarea_del_char_forward)},\
    {"textarea_set_text", ROREG_FUNC(luat_lv_textarea_set_text)},\
    {"textarea_set_placeholder_text", ROREG_FUNC(luat_lv_textarea_set_placeholder_text)},\
    {"textarea_set_cursor_pos", ROREG_FUNC(luat_lv_textarea_set_cursor_pos)},\
    {"textarea_set_cursor_hidden", ROREG_FUNC(luat_lv_textarea_set_cursor_hidden)},\
    {"textarea_set_cursor_click_pos", ROREG_FUNC(luat_lv_textarea_set_cursor_click_pos)},\
    {"textarea_set_pwd_mode", ROREG_FUNC(luat_lv_textarea_set_pwd_mode)},\
    {"textarea_set_one_line", ROREG_FUNC(luat_lv_textarea_set_one_line)},\
    {"textarea_set_text_align", ROREG_FUNC(luat_lv_textarea_set_text_align)},\
    {"textarea_set_accepted_chars", ROREG_FUNC(luat_lv_textarea_set_accepted_chars)},\
    {"textarea_set_max_length", ROREG_FUNC(luat_lv_textarea_set_max_length)},\
    {"textarea_set_insert_replace", ROREG_FUNC(luat_lv_textarea_set_insert_replace)},\
    {"textarea_set_scrollbar_mode", ROREG_FUNC(luat_lv_textarea_set_scrollbar_mode)},\
    {"textarea_set_scroll_propagation", ROREG_FUNC(luat_lv_textarea_set_scroll_propagation)},\
    {"textarea_set_edge_flash", ROREG_FUNC(luat_lv_textarea_set_edge_flash)},\
    {"textarea_set_text_sel", ROREG_FUNC(luat_lv_textarea_set_text_sel)},\
    {"textarea_set_pwd_show_time", ROREG_FUNC(luat_lv_textarea_set_pwd_show_time)},\
    {"textarea_set_cursor_blink_time", ROREG_FUNC(luat_lv_textarea_set_cursor_blink_time)},\
    {"textarea_get_text", ROREG_FUNC(luat_lv_textarea_get_text)},\
    {"textarea_get_placeholder_text", ROREG_FUNC(luat_lv_textarea_get_placeholder_text)},\
    {"textarea_get_label", ROREG_FUNC(luat_lv_textarea_get_label)},\
    {"textarea_get_cursor_pos", ROREG_FUNC(luat_lv_textarea_get_cursor_pos)},\
    {"textarea_get_cursor_hidden", ROREG_FUNC(luat_lv_textarea_get_cursor_hidden)},\
    {"textarea_get_cursor_click_pos", ROREG_FUNC(luat_lv_textarea_get_cursor_click_pos)},\
    {"textarea_get_pwd_mode", ROREG_FUNC(luat_lv_textarea_get_pwd_mode)},\
    {"textarea_get_one_line", ROREG_FUNC(luat_lv_textarea_get_one_line)},\
    {"textarea_get_accepted_chars", ROREG_FUNC(luat_lv_textarea_get_accepted_chars)},\
    {"textarea_get_max_length", ROREG_FUNC(luat_lv_textarea_get_max_length)},\
    {"textarea_get_scrollbar_mode", ROREG_FUNC(luat_lv_textarea_get_scrollbar_mode)},\
    {"textarea_get_scroll_propagation", ROREG_FUNC(luat_lv_textarea_get_scroll_propagation)},\
    {"textarea_get_edge_flash", ROREG_FUNC(luat_lv_textarea_get_edge_flash)},\
    {"textarea_text_is_selected", ROREG_FUNC(luat_lv_textarea_text_is_selected)},\
    {"textarea_get_text_sel_en", ROREG_FUNC(luat_lv_textarea_get_text_sel_en)},\
    {"textarea_get_pwd_show_time", ROREG_FUNC(luat_lv_textarea_get_pwd_show_time)},\
    {"textarea_get_cursor_blink_time", ROREG_FUNC(luat_lv_textarea_get_cursor_blink_time)},\
    {"textarea_clear_selection", ROREG_FUNC(luat_lv_textarea_clear_selection)},\
    {"textarea_cursor_right", ROREG_FUNC(luat_lv_textarea_cursor_right)},\
    {"textarea_cursor_left", ROREG_FUNC(luat_lv_textarea_cursor_left)},\
    {"textarea_cursor_down", ROREG_FUNC(luat_lv_textarea_cursor_down)},\
    {"textarea_cursor_up", ROREG_FUNC(luat_lv_textarea_cursor_up)},\

// prefix lv_widgets lv_tileview
int luat_lv_tileview_create(lua_State *L);
int luat_lv_tileview_add_element(lua_State *L);
int luat_lv_tileview_set_tile_act(lua_State *L);
int luat_lv_tileview_set_edge_flash(lua_State *L);
int luat_lv_tileview_set_anim_time(lua_State *L);
int luat_lv_tileview_get_tile_act(lua_State *L);
int luat_lv_tileview_get_edge_flash(lua_State *L);
int luat_lv_tileview_get_anim_time(lua_State *L);

#define LUAT_LV_TILEVIEW_RLT     {"tileview_create", ROREG_FUNC(luat_lv_tileview_create)},\
    {"tileview_add_element", ROREG_FUNC(luat_lv_tileview_add_element)},\
    {"tileview_set_tile_act", ROREG_FUNC(luat_lv_tileview_set_tile_act)},\
    {"tileview_set_edge_flash", ROREG_FUNC(luat_lv_tileview_set_edge_flash)},\
    {"tileview_set_anim_time", ROREG_FUNC(luat_lv_tileview_set_anim_time)},\
    {"tileview_get_tile_act", ROREG_FUNC(luat_lv_tileview_get_tile_act)},\
    {"tileview_get_edge_flash", ROREG_FUNC(luat_lv_tileview_get_edge_flash)},\
    {"tileview_get_anim_time", ROREG_FUNC(luat_lv_tileview_get_anim_time)},\

// prefix lv_widgets lv_win
int luat_lv_win_create(lua_State *L);
int luat_lv_win_clean(lua_State *L);
int luat_lv_win_add_btn_right(lua_State *L);
int luat_lv_win_add_btn_left(lua_State *L);
int luat_lv_win_set_title(lua_State *L);
int luat_lv_win_set_header_height(lua_State *L);
int luat_lv_win_set_btn_width(lua_State *L);
int luat_lv_win_set_content_size(lua_State *L);
int luat_lv_win_set_layout(lua_State *L);
int luat_lv_win_set_scrollbar_mode(lua_State *L);
int luat_lv_win_set_anim_time(lua_State *L);
int luat_lv_win_set_drag(lua_State *L);
int luat_lv_win_title_set_alignment(lua_State *L);
int luat_lv_win_get_title(lua_State *L);
int luat_lv_win_get_content(lua_State *L);
int luat_lv_win_get_header_height(lua_State *L);
int luat_lv_win_get_btn_width(lua_State *L);
int luat_lv_win_get_from_btn(lua_State *L);
int luat_lv_win_get_layout(lua_State *L);
int luat_lv_win_get_sb_mode(lua_State *L);
int luat_lv_win_get_anim_time(lua_State *L);
int luat_lv_win_get_width(lua_State *L);
int luat_lv_win_get_drag(lua_State *L);
int luat_lv_win_title_get_alignment(lua_State *L);
int luat_lv_win_focus(lua_State *L);
int luat_lv_win_scroll_hor(lua_State *L);
int luat_lv_win_scroll_ver(lua_State *L);

#define LUAT_LV_WIN_RLT     {"win_create", ROREG_FUNC(luat_lv_win_create)},\
    {"win_clean", ROREG_FUNC(luat_lv_win_clean)},\
    {"win_add_btn_right", ROREG_FUNC(luat_lv_win_add_btn_right)},\
    {"win_add_btn_left", ROREG_FUNC(luat_lv_win_add_btn_left)},\
    {"win_set_title", ROREG_FUNC(luat_lv_win_set_title)},\
    {"win_set_header_height", ROREG_FUNC(luat_lv_win_set_header_height)},\
    {"win_set_btn_width", ROREG_FUNC(luat_lv_win_set_btn_width)},\
    {"win_set_content_size", ROREG_FUNC(luat_lv_win_set_content_size)},\
    {"win_set_layout", ROREG_FUNC(luat_lv_win_set_layout)},\
    {"win_set_scrollbar_mode", ROREG_FUNC(luat_lv_win_set_scrollbar_mode)},\
    {"win_set_anim_time", ROREG_FUNC(luat_lv_win_set_anim_time)},\
    {"win_set_drag", ROREG_FUNC(luat_lv_win_set_drag)},\
    {"win_title_set_alignment", ROREG_FUNC(luat_lv_win_title_set_alignment)},\
    {"win_get_title", ROREG_FUNC(luat_lv_win_get_title)},\
    {"win_get_content", ROREG_FUNC(luat_lv_win_get_content)},\
    {"win_get_header_height", ROREG_FUNC(luat_lv_win_get_header_height)},\
    {"win_get_btn_width", ROREG_FUNC(luat_lv_win_get_btn_width)},\
    {"win_get_from_btn", ROREG_FUNC(luat_lv_win_get_from_btn)},\
    {"win_get_layout", ROREG_FUNC(luat_lv_win_get_layout)},\
    {"win_get_sb_mode", ROREG_FUNC(luat_lv_win_get_sb_mode)},\
    {"win_get_anim_time", ROREG_FUNC(luat_lv_win_get_anim_time)},\
    {"win_get_width", ROREG_FUNC(luat_lv_win_get_width)},\
    {"win_get_drag", ROREG_FUNC(luat_lv_win_get_drag)},\
    {"win_title_get_alignment", ROREG_FUNC(luat_lv_win_title_get_alignment)},\
    {"win_focus", ROREG_FUNC(luat_lv_win_focus)},\
    {"win_scroll_hor", ROREG_FUNC(luat_lv_win_scroll_hor)},\
    {"win_scroll_ver", ROREG_FUNC(luat_lv_win_scroll_ver)},\

#endif
