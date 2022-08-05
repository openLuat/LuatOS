

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

#define LUAT_LV_DISP_RLT     

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

#define LUAT_LV_GROUP_RLT     

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

#define LUAT_LV_OBJ_RLT  
// prefix lv_core lv_refr
int luat_lv_refr_now(lua_State *L);

#define LUAT_LV_REFR_RLT     

// prefix lv_core lv_style
int luat_lv_style_init(lua_State *L);
int luat_lv_style_copy(lua_State *L);
int luat_lv_style_list_init(lua_State *L);
int luat_lv_style_list_copy(lua_State *L);
int luat_lv_style_list_get_style(lua_State *L);
int luat_lv_style_reset(lua_State *L);
int luat_lv_style_remove_prop(lua_State *L);
int luat_lv_style_list_get_local_style(lua_State *L);

#define LUAT_LV_STYLE_RLT 

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

#define LUAT_LV_DRAW_RLT  

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

#define LUAT_LV_ANIM_RLT  

// prefix lv_misc lv_area
int luat_lv_area_set(lua_State *L);
int luat_lv_area_copy(lua_State *L);
int luat_lv_area_get_width(lua_State *L);
int luat_lv_area_get_height(lua_State *L);
int luat_lv_area_set_width(lua_State *L);
int luat_lv_area_set_height(lua_State *L);
int luat_lv_area_get_size(lua_State *L);

#define LUAT_LV_AREA_RLT     

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

#define LUAT_LV_COLOR_RLT  

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

#define LUAT_LV_THEME_RLT  


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

#define LUAT_LV_ARC_RLT     

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

#define LUAT_LV_BAR_RLT     

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

#define LUAT_LV_BTN_RLT     

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

#define LUAT_LV_BTNMATRIX_RLT  

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

#define LUAT_LV_CALENDAR_RLT  

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

#define LUAT_LV_CANVAS_RLT     

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

#define LUAT_LV_CHART_RLT     

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

#define LUAT_LV_CHECKBOX_RLT   

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

#define LUAT_LV_CONT_RLT  

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

#define LUAT_LV_CPICKER_RLT   
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

#define LUAT_LV_DROPDOWN_RLT  
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

#define LUAT_LV_GAUGE_RLT  
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

#define LUAT_LV_IMG_RLT   

// prefix lv_widgets lv_imgbtn
int luat_lv_imgbtn_create(lua_State *L);
int luat_lv_imgbtn_set_state(lua_State *L);
int luat_lv_imgbtn_toggle(lua_State *L);
int luat_lv_imgbtn_set_checkable(lua_State *L);
int luat_lv_imgbtn_get_src(lua_State *L);
int luat_lv_imgbtn_get_state(lua_State *L);
int luat_lv_imgbtn_get_checkable(lua_State *L);

#define LUAT_LV_IMGBTN_RLT  

// prefix lv_widgets lv_keyboard
int luat_lv_keyboard_create(lua_State *L);
int luat_lv_keyboard_set_textarea(lua_State *L);
int luat_lv_keyboard_set_mode(lua_State *L);
int luat_lv_keyboard_set_cursor_manage(lua_State *L);
int luat_lv_keyboard_get_textarea(lua_State *L);
int luat_lv_keyboard_get_mode(lua_State *L);
int luat_lv_keyboard_get_cursor_manage(lua_State *L);

#define LUAT_LV_KEYBOARD_RLT  
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

#define LUAT_LV_LABEL_RLT  
// prefix lv_widgets lv_led
int luat_lv_led_create(lua_State *L);
int luat_lv_led_set_bright(lua_State *L);
int luat_lv_led_on(lua_State *L);
int luat_lv_led_off(lua_State *L);
int luat_lv_led_toggle(lua_State *L);
int luat_lv_led_get_bright(lua_State *L);

#define LUAT_LV_LED_RLT  

// prefix lv_widgets lv_line
int luat_lv_line_create(lua_State *L);
int luat_lv_line_set_auto_size(lua_State *L);
int luat_lv_line_set_y_invert(lua_State *L);
int luat_lv_line_get_auto_size(lua_State *L);
int luat_lv_line_get_y_invert(lua_State *L);

#define LUAT_LV_LINE_RLT  

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

#define LUAT_LV_LINEMETER_RLT  

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

#define LUAT_LV_LIST_RLT  
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

#define LUAT_LV_MSGBOX_RLT 
// prefix lv_widgets lv_objmask
int luat_lv_objmask_create(lua_State *L);
int luat_lv_objmask_add_mask(lua_State *L);
int luat_lv_objmask_update_mask(lua_State *L);
int luat_lv_objmask_remove_mask(lua_State *L);

#define LUAT_LV_OBJMASK_RLT  

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

#define LUAT_LV_PAGE_RLT  

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

#define LUAT_LV_ROLLER_RLT 

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

#define LUAT_LV_SLIDER_RLT  
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

#define LUAT_LV_SPINBOX_RLT  
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

#define LUAT_LV_SPINNER_RLT  

// prefix lv_widgets lv_switch
int luat_lv_switch_create(lua_State *L);
int luat_lv_switch_on(lua_State *L);
int luat_lv_switch_off(lua_State *L);
int luat_lv_switch_toggle(lua_State *L);
int luat_lv_switch_set_anim_time(lua_State *L);
int luat_lv_switch_get_state(lua_State *L);
int luat_lv_switch_get_anim_time(lua_State *L);

#define LUAT_LV_SWITCH_RLT  

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

#define LUAT_LV_TABLE_RLT 

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

#define LUAT_LV_TABVIEW_RLT  
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

#define LUAT_LV_TEXTAREA_RLT 
// prefix lv_widgets lv_tileview
int luat_lv_tileview_create(lua_State *L);
int luat_lv_tileview_add_element(lua_State *L);
int luat_lv_tileview_set_tile_act(lua_State *L);
int luat_lv_tileview_set_edge_flash(lua_State *L);
int luat_lv_tileview_set_anim_time(lua_State *L);
int luat_lv_tileview_get_tile_act(lua_State *L);
int luat_lv_tileview_get_edge_flash(lua_State *L);
int luat_lv_tileview_get_anim_time(lua_State *L);

#define LUAT_LV_TILEVIEW_RLT  
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

#define LUAT_LV_WIN_RLT 
#endif
