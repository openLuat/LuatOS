
#include "luat_base.h"
#ifndef LUAT_LV_GEN
#define LUAT_LV_GEN

// group lv_core
// prefix lv_core disp
int luat_lv_disp_drv_init(lua_State *L);
int luat_lv_disp_draw_buf_init(lua_State *L);
int luat_lv_disp_drv_register(lua_State *L);
int luat_lv_disp_drv_update(lua_State *L);
int luat_lv_disp_remove(lua_State *L);
int luat_lv_disp_set_default(lua_State *L);
int luat_lv_disp_get_default(lua_State *L);
int luat_lv_disp_get_hor_res(lua_State *L);
int luat_lv_disp_get_ver_res(lua_State *L);
int luat_lv_disp_get_physical_hor_res(lua_State *L);
int luat_lv_disp_get_physical_ver_res(lua_State *L);
int luat_lv_disp_get_offset_x(lua_State *L);
int luat_lv_disp_get_offset_y(lua_State *L);
int luat_lv_disp_get_antialiasing(lua_State *L);
int luat_lv_disp_get_dpi(lua_State *L);
int luat_lv_disp_set_rotation(lua_State *L);
int luat_lv_disp_get_rotation(lua_State *L);
int luat_lv_disp_flush_ready(lua_State *L);
int luat_lv_disp_flush_is_last(lua_State *L);
int luat_lv_disp_get_next(lua_State *L);
int luat_lv_disp_get_draw_buf(lua_State *L);
int luat_lv_disp_get_scr_act(lua_State *L);
int luat_lv_disp_get_scr_prev(lua_State *L);
int luat_lv_disp_load_scr(lua_State *L);
int luat_lv_disp_get_layer_top(lua_State *L);
int luat_lv_disp_get_layer_sys(lua_State *L);
int luat_lv_disp_set_theme(lua_State *L);
int luat_lv_disp_get_theme(lua_State *L);
int luat_lv_disp_set_bg_color(lua_State *L);
int luat_lv_disp_set_bg_image(lua_State *L);
int luat_lv_disp_set_bg_opa(lua_State *L);
int luat_lv_disp_get_inactive_time(lua_State *L);
int luat_lv_disp_trig_activity(lua_State *L);
int luat_lv_disp_clean_dcache(lua_State *L);
int luat_lv_disp_dpx(lua_State *L);

#define LUAT_LV_DISP_RLT     {"disp_drv_init", luat_lv_disp_drv_init, 0},\
    {"disp_draw_buf_init", luat_lv_disp_draw_buf_init, 0},\
    {"disp_drv_register", luat_lv_disp_drv_register, 0},\
    {"disp_drv_update", luat_lv_disp_drv_update, 0},\
    {"disp_remove", luat_lv_disp_remove, 0},\
    {"disp_set_default", luat_lv_disp_set_default, 0},\
    {"disp_get_default", luat_lv_disp_get_default, 0},\
    {"disp_get_hor_res", luat_lv_disp_get_hor_res, 0},\
    {"disp_get_ver_res", luat_lv_disp_get_ver_res, 0},\
    {"disp_get_physical_hor_res", luat_lv_disp_get_physical_hor_res, 0},\
    {"disp_get_physical_ver_res", luat_lv_disp_get_physical_ver_res, 0},\
    {"disp_get_offset_x", luat_lv_disp_get_offset_x, 0},\
    {"disp_get_offset_y", luat_lv_disp_get_offset_y, 0},\
    {"disp_get_antialiasing", luat_lv_disp_get_antialiasing, 0},\
    {"disp_get_dpi", luat_lv_disp_get_dpi, 0},\
    {"disp_set_rotation", luat_lv_disp_set_rotation, 0},\
    {"disp_get_rotation", luat_lv_disp_get_rotation, 0},\
    {"disp_flush_ready", luat_lv_disp_flush_ready, 0},\
    {"disp_flush_is_last", luat_lv_disp_flush_is_last, 0},\
    {"disp_get_next", luat_lv_disp_get_next, 0},\
    {"disp_get_draw_buf", luat_lv_disp_get_draw_buf, 0},\
    {"disp_get_scr_act", luat_lv_disp_get_scr_act, 0},\
    {"disp_get_scr_prev", luat_lv_disp_get_scr_prev, 0},\
    {"disp_load_scr", luat_lv_disp_load_scr, 0},\
    {"disp_get_layer_top", luat_lv_disp_get_layer_top, 0},\
    {"disp_get_layer_sys", luat_lv_disp_get_layer_sys, 0},\
    {"disp_set_theme", luat_lv_disp_set_theme, 0},\
    {"disp_get_theme", luat_lv_disp_get_theme, 0},\
    {"disp_set_bg_color", luat_lv_disp_set_bg_color, 0},\
    {"disp_set_bg_image", luat_lv_disp_set_bg_image, 0},\
    {"disp_set_bg_opa", luat_lv_disp_set_bg_opa, 0},\
    {"disp_get_inactive_time", luat_lv_disp_get_inactive_time, 0},\
    {"disp_trig_activity", luat_lv_disp_trig_activity, 0},\
    {"disp_clean_dcache", luat_lv_disp_clean_dcache, 0},\
    {"disp_dpx", luat_lv_disp_dpx, 0},\

// prefix lv_core group
int luat_lv_group_create(lua_State *L);
int luat_lv_group_del(lua_State *L);
int luat_lv_group_set_default(lua_State *L);
int luat_lv_group_get_default(lua_State *L);
int luat_lv_group_add_obj(lua_State *L);
int luat_lv_group_swap_obj(lua_State *L);
int luat_lv_group_remove_obj(lua_State *L);
int luat_lv_group_remove_all_objs(lua_State *L);
int luat_lv_group_focus_obj(lua_State *L);
int luat_lv_group_focus_next(lua_State *L);
int luat_lv_group_focus_prev(lua_State *L);
int luat_lv_group_focus_freeze(lua_State *L);
int luat_lv_group_send_data(lua_State *L);
int luat_lv_group_set_refocus_policy(lua_State *L);
int luat_lv_group_set_editing(lua_State *L);
int luat_lv_group_set_wrap(lua_State *L);
int luat_lv_group_get_focused(lua_State *L);
int luat_lv_group_get_editing(lua_State *L);
int luat_lv_group_get_wrap(lua_State *L);
int luat_lv_group_get_obj_count(lua_State *L);

#define LUAT_LV_GROUP_RLT     {"group_create", luat_lv_group_create, 0},\
    {"group_del", luat_lv_group_del, 0},\
    {"group_set_default", luat_lv_group_set_default, 0},\
    {"group_get_default", luat_lv_group_get_default, 0},\
    {"group_add_obj", luat_lv_group_add_obj, 0},\
    {"group_swap_obj", luat_lv_group_swap_obj, 0},\
    {"group_remove_obj", luat_lv_group_remove_obj, 0},\
    {"group_remove_all_objs", luat_lv_group_remove_all_objs, 0},\
    {"group_focus_obj", luat_lv_group_focus_obj, 0},\
    {"group_focus_next", luat_lv_group_focus_next, 0},\
    {"group_focus_prev", luat_lv_group_focus_prev, 0},\
    {"group_focus_freeze", luat_lv_group_focus_freeze, 0},\
    {"group_send_data", luat_lv_group_send_data, 0},\
    {"group_set_refocus_policy", luat_lv_group_set_refocus_policy, 0},\
    {"group_set_editing", luat_lv_group_set_editing, 0},\
    {"group_set_wrap", luat_lv_group_set_wrap, 0},\
    {"group_get_focused", luat_lv_group_get_focused, 0},\
    {"group_get_editing", luat_lv_group_get_editing, 0},\
    {"group_get_wrap", luat_lv_group_get_wrap, 0},\
    {"group_get_obj_count", luat_lv_group_get_obj_count, 0},\

// prefix lv_core obj
int luat_lv_obj_del(lua_State *L);
int luat_lv_obj_clean(lua_State *L);
int luat_lv_obj_del_delayed(lua_State *L);
int luat_lv_obj_del_async(lua_State *L);
int luat_lv_obj_set_parent(lua_State *L);
int luat_lv_obj_swap(lua_State *L);
int luat_lv_obj_move_to_index(lua_State *L);
int luat_lv_obj_get_screen(lua_State *L);
int luat_lv_obj_get_disp(lua_State *L);
int luat_lv_obj_get_parent(lua_State *L);
int luat_lv_obj_get_child(lua_State *L);
int luat_lv_obj_get_child_cnt(lua_State *L);
int luat_lv_obj_get_index(lua_State *L);
int luat_lv_obj_tree_walk(lua_State *L);
int luat_lv_obj_set_pos(lua_State *L);
int luat_lv_obj_set_x(lua_State *L);
int luat_lv_obj_set_y(lua_State *L);
int luat_lv_obj_set_size(lua_State *L);
int luat_lv_obj_refr_size(lua_State *L);
int luat_lv_obj_set_width(lua_State *L);
int luat_lv_obj_set_height(lua_State *L);
int luat_lv_obj_set_content_width(lua_State *L);
int luat_lv_obj_set_content_height(lua_State *L);
int luat_lv_obj_set_layout(lua_State *L);
int luat_lv_obj_is_layout_positioned(lua_State *L);
int luat_lv_obj_mark_layout_as_dirty(lua_State *L);
int luat_lv_obj_update_layout(lua_State *L);
int luat_lv_obj_set_align(lua_State *L);
int luat_lv_obj_align(lua_State *L);
int luat_lv_obj_align_to(lua_State *L);
int luat_lv_obj_center(lua_State *L);
int luat_lv_obj_get_coords(lua_State *L);
int luat_lv_obj_get_x(lua_State *L);
int luat_lv_obj_get_x2(lua_State *L);
int luat_lv_obj_get_y(lua_State *L);
int luat_lv_obj_get_y2(lua_State *L);
int luat_lv_obj_get_width(lua_State *L);
int luat_lv_obj_get_height(lua_State *L);
int luat_lv_obj_get_content_width(lua_State *L);
int luat_lv_obj_get_content_height(lua_State *L);
int luat_lv_obj_get_content_coords(lua_State *L);
int luat_lv_obj_get_self_width(lua_State *L);
int luat_lv_obj_get_self_height(lua_State *L);
int luat_lv_obj_refresh_self_size(lua_State *L);
int luat_lv_obj_refr_pos(lua_State *L);
int luat_lv_obj_move_to(lua_State *L);
int luat_lv_obj_move_children_by(lua_State *L);
int luat_lv_obj_invalidate_area(lua_State *L);
int luat_lv_obj_invalidate(lua_State *L);
int luat_lv_obj_area_is_visible(lua_State *L);
int luat_lv_obj_is_visible(lua_State *L);
int luat_lv_obj_set_ext_click_area(lua_State *L);
int luat_lv_obj_get_click_area(lua_State *L);
int luat_lv_obj_hit_test(lua_State *L);
int luat_lv_obj_set_scrollbar_mode(lua_State *L);
int luat_lv_obj_set_scroll_dir(lua_State *L);
int luat_lv_obj_set_scroll_snap_x(lua_State *L);
int luat_lv_obj_set_scroll_snap_y(lua_State *L);
int luat_lv_obj_get_scrollbar_mode(lua_State *L);
int luat_lv_obj_get_scroll_dir(lua_State *L);
int luat_lv_obj_get_scroll_snap_x(lua_State *L);
int luat_lv_obj_get_scroll_snap_y(lua_State *L);
int luat_lv_obj_get_scroll_x(lua_State *L);
int luat_lv_obj_get_scroll_y(lua_State *L);
int luat_lv_obj_get_scroll_top(lua_State *L);
int luat_lv_obj_get_scroll_bottom(lua_State *L);
int luat_lv_obj_get_scroll_left(lua_State *L);
int luat_lv_obj_get_scroll_right(lua_State *L);
int luat_lv_obj_get_scroll_end(lua_State *L);
int luat_lv_obj_scroll_by(lua_State *L);
int luat_lv_obj_scroll_to(lua_State *L);
int luat_lv_obj_scroll_to_x(lua_State *L);
int luat_lv_obj_scroll_to_y(lua_State *L);
int luat_lv_obj_scroll_to_view(lua_State *L);
int luat_lv_obj_scroll_to_view_recursive(lua_State *L);
int luat_lv_obj_is_scrolling(lua_State *L);
int luat_lv_obj_update_snap(lua_State *L);
int luat_lv_obj_get_scrollbar_area(lua_State *L);
int luat_lv_obj_scrollbar_invalidate(lua_State *L);
int luat_lv_obj_readjust_scroll(lua_State *L);
int luat_lv_obj_add_style(lua_State *L);
int luat_lv_obj_remove_style(lua_State *L);
int luat_lv_obj_remove_style_all(lua_State *L);
int luat_lv_obj_report_style_change(lua_State *L);
int luat_lv_obj_refresh_style(lua_State *L);
int luat_lv_obj_enable_style_refresh(lua_State *L);
int luat_lv_obj_get_style_prop(lua_State *L);
int luat_lv_obj_set_local_style_prop(lua_State *L);
int luat_lv_obj_get_local_style_prop(lua_State *L);
int luat_lv_obj_remove_local_style_prop(lua_State *L);
int luat_lv_obj_fade_in(lua_State *L);
int luat_lv_obj_fade_out(lua_State *L);
int luat_lv_obj_style_get_selector_state(lua_State *L);
int luat_lv_obj_style_get_selector_part(lua_State *L);
int luat_lv_obj_get_style_width(lua_State *L);
int luat_lv_obj_get_style_min_width(lua_State *L);
int luat_lv_obj_get_style_max_width(lua_State *L);
int luat_lv_obj_get_style_height(lua_State *L);
int luat_lv_obj_get_style_min_height(lua_State *L);
int luat_lv_obj_get_style_max_height(lua_State *L);
int luat_lv_obj_get_style_x(lua_State *L);
int luat_lv_obj_get_style_y(lua_State *L);
int luat_lv_obj_get_style_align(lua_State *L);
int luat_lv_obj_get_style_transform_width(lua_State *L);
int luat_lv_obj_get_style_transform_height(lua_State *L);
int luat_lv_obj_get_style_translate_x(lua_State *L);
int luat_lv_obj_get_style_translate_y(lua_State *L);
int luat_lv_obj_get_style_transform_zoom(lua_State *L);
int luat_lv_obj_get_style_transform_angle(lua_State *L);
int luat_lv_obj_get_style_pad_top(lua_State *L);
int luat_lv_obj_get_style_pad_bottom(lua_State *L);
int luat_lv_obj_get_style_pad_left(lua_State *L);
int luat_lv_obj_get_style_pad_right(lua_State *L);
int luat_lv_obj_get_style_pad_row(lua_State *L);
int luat_lv_obj_get_style_pad_column(lua_State *L);
int luat_lv_obj_get_style_radius(lua_State *L);
int luat_lv_obj_get_style_clip_corner(lua_State *L);
int luat_lv_obj_get_style_opa(lua_State *L);
int luat_lv_obj_get_style_color_filter_dsc(lua_State *L);
int luat_lv_obj_get_style_color_filter_opa(lua_State *L);
int luat_lv_obj_get_style_anim_time(lua_State *L);
int luat_lv_obj_get_style_anim_speed(lua_State *L);
int luat_lv_obj_get_style_transition(lua_State *L);
int luat_lv_obj_get_style_blend_mode(lua_State *L);
int luat_lv_obj_get_style_layout(lua_State *L);
int luat_lv_obj_get_style_base_dir(lua_State *L);
int luat_lv_obj_get_style_bg_color(lua_State *L);
int luat_lv_obj_get_style_bg_color_filtered(lua_State *L);
int luat_lv_obj_get_style_bg_opa(lua_State *L);
int luat_lv_obj_get_style_bg_grad_color(lua_State *L);
int luat_lv_obj_get_style_bg_grad_color_filtered(lua_State *L);
int luat_lv_obj_get_style_bg_grad_dir(lua_State *L);
int luat_lv_obj_get_style_bg_main_stop(lua_State *L);
int luat_lv_obj_get_style_bg_grad_stop(lua_State *L);
int luat_lv_obj_get_style_bg_img_src(lua_State *L);
int luat_lv_obj_get_style_bg_img_opa(lua_State *L);
int luat_lv_obj_get_style_bg_img_recolor(lua_State *L);
int luat_lv_obj_get_style_bg_img_recolor_filtered(lua_State *L);
int luat_lv_obj_get_style_bg_img_recolor_opa(lua_State *L);
int luat_lv_obj_get_style_bg_img_tiled(lua_State *L);
int luat_lv_obj_get_style_border_color(lua_State *L);
int luat_lv_obj_get_style_border_color_filtered(lua_State *L);
int luat_lv_obj_get_style_border_opa(lua_State *L);
int luat_lv_obj_get_style_border_width(lua_State *L);
int luat_lv_obj_get_style_border_side(lua_State *L);
int luat_lv_obj_get_style_border_post(lua_State *L);
int luat_lv_obj_get_style_text_color(lua_State *L);
int luat_lv_obj_get_style_text_color_filtered(lua_State *L);
int luat_lv_obj_get_style_text_opa(lua_State *L);
int luat_lv_obj_get_style_text_font(lua_State *L);
int luat_lv_obj_get_style_text_letter_space(lua_State *L);
int luat_lv_obj_get_style_text_line_space(lua_State *L);
int luat_lv_obj_get_style_text_decor(lua_State *L);
int luat_lv_obj_get_style_text_align(lua_State *L);
int luat_lv_obj_get_style_img_opa(lua_State *L);
int luat_lv_obj_get_style_img_recolor(lua_State *L);
int luat_lv_obj_get_style_img_recolor_filtered(lua_State *L);
int luat_lv_obj_get_style_img_recolor_opa(lua_State *L);
int luat_lv_obj_get_style_outline_width(lua_State *L);
int luat_lv_obj_get_style_outline_color(lua_State *L);
int luat_lv_obj_get_style_outline_color_filtered(lua_State *L);
int luat_lv_obj_get_style_outline_opa(lua_State *L);
int luat_lv_obj_get_style_outline_pad(lua_State *L);
int luat_lv_obj_get_style_shadow_width(lua_State *L);
int luat_lv_obj_get_style_shadow_ofs_x(lua_State *L);
int luat_lv_obj_get_style_shadow_ofs_y(lua_State *L);
int luat_lv_obj_get_style_shadow_spread(lua_State *L);
int luat_lv_obj_get_style_shadow_color(lua_State *L);
int luat_lv_obj_get_style_shadow_color_filtered(lua_State *L);
int luat_lv_obj_get_style_shadow_opa(lua_State *L);
int luat_lv_obj_get_style_line_width(lua_State *L);
int luat_lv_obj_get_style_line_dash_width(lua_State *L);
int luat_lv_obj_get_style_line_dash_gap(lua_State *L);
int luat_lv_obj_get_style_line_rounded(lua_State *L);
int luat_lv_obj_get_style_line_color(lua_State *L);
int luat_lv_obj_get_style_line_color_filtered(lua_State *L);
int luat_lv_obj_get_style_line_opa(lua_State *L);
int luat_lv_obj_get_style_arc_width(lua_State *L);
int luat_lv_obj_get_style_arc_rounded(lua_State *L);
int luat_lv_obj_get_style_arc_color(lua_State *L);
int luat_lv_obj_get_style_arc_color_filtered(lua_State *L);
int luat_lv_obj_get_style_arc_opa(lua_State *L);
int luat_lv_obj_get_style_arc_img_src(lua_State *L);
int luat_lv_obj_set_style_width(lua_State *L);
int luat_lv_obj_set_style_min_width(lua_State *L);
int luat_lv_obj_set_style_max_width(lua_State *L);
int luat_lv_obj_set_style_height(lua_State *L);
int luat_lv_obj_set_style_min_height(lua_State *L);
int luat_lv_obj_set_style_max_height(lua_State *L);
int luat_lv_obj_set_style_x(lua_State *L);
int luat_lv_obj_set_style_y(lua_State *L);
int luat_lv_obj_set_style_align(lua_State *L);
int luat_lv_obj_set_style_transform_width(lua_State *L);
int luat_lv_obj_set_style_transform_height(lua_State *L);
int luat_lv_obj_set_style_translate_x(lua_State *L);
int luat_lv_obj_set_style_translate_y(lua_State *L);
int luat_lv_obj_set_style_transform_zoom(lua_State *L);
int luat_lv_obj_set_style_transform_angle(lua_State *L);
int luat_lv_obj_set_style_pad_top(lua_State *L);
int luat_lv_obj_set_style_pad_bottom(lua_State *L);
int luat_lv_obj_set_style_pad_left(lua_State *L);
int luat_lv_obj_set_style_pad_right(lua_State *L);
int luat_lv_obj_set_style_pad_row(lua_State *L);
int luat_lv_obj_set_style_pad_column(lua_State *L);
int luat_lv_obj_set_style_radius(lua_State *L);
int luat_lv_obj_set_style_clip_corner(lua_State *L);
int luat_lv_obj_set_style_opa(lua_State *L);
int luat_lv_obj_set_style_color_filter_dsc(lua_State *L);
int luat_lv_obj_set_style_color_filter_opa(lua_State *L);
int luat_lv_obj_set_style_anim_time(lua_State *L);
int luat_lv_obj_set_style_anim_speed(lua_State *L);
int luat_lv_obj_set_style_transition(lua_State *L);
int luat_lv_obj_set_style_blend_mode(lua_State *L);
int luat_lv_obj_set_style_layout(lua_State *L);
int luat_lv_obj_set_style_base_dir(lua_State *L);
int luat_lv_obj_set_style_bg_color(lua_State *L);
int luat_lv_obj_set_style_bg_color_filtered(lua_State *L);
int luat_lv_obj_set_style_bg_opa(lua_State *L);
int luat_lv_obj_set_style_bg_grad_color(lua_State *L);
int luat_lv_obj_set_style_bg_grad_color_filtered(lua_State *L);
int luat_lv_obj_set_style_bg_grad_dir(lua_State *L);
int luat_lv_obj_set_style_bg_main_stop(lua_State *L);
int luat_lv_obj_set_style_bg_grad_stop(lua_State *L);
int luat_lv_obj_set_style_bg_img_src(lua_State *L);
int luat_lv_obj_set_style_bg_img_opa(lua_State *L);
int luat_lv_obj_set_style_bg_img_recolor(lua_State *L);
int luat_lv_obj_set_style_bg_img_recolor_filtered(lua_State *L);
int luat_lv_obj_set_style_bg_img_recolor_opa(lua_State *L);
int luat_lv_obj_set_style_bg_img_tiled(lua_State *L);
int luat_lv_obj_set_style_border_color(lua_State *L);
int luat_lv_obj_set_style_border_color_filtered(lua_State *L);
int luat_lv_obj_set_style_border_opa(lua_State *L);
int luat_lv_obj_set_style_border_width(lua_State *L);
int luat_lv_obj_set_style_border_side(lua_State *L);
int luat_lv_obj_set_style_border_post(lua_State *L);
int luat_lv_obj_set_style_text_color(lua_State *L);
int luat_lv_obj_set_style_text_color_filtered(lua_State *L);
int luat_lv_obj_set_style_text_opa(lua_State *L);
int luat_lv_obj_set_style_text_font(lua_State *L);
int luat_lv_obj_set_style_text_letter_space(lua_State *L);
int luat_lv_obj_set_style_text_line_space(lua_State *L);
int luat_lv_obj_set_style_text_decor(lua_State *L);
int luat_lv_obj_set_style_text_align(lua_State *L);
int luat_lv_obj_set_style_img_opa(lua_State *L);
int luat_lv_obj_set_style_img_recolor(lua_State *L);
int luat_lv_obj_set_style_img_recolor_filtered(lua_State *L);
int luat_lv_obj_set_style_img_recolor_opa(lua_State *L);
int luat_lv_obj_set_style_outline_width(lua_State *L);
int luat_lv_obj_set_style_outline_color(lua_State *L);
int luat_lv_obj_set_style_outline_color_filtered(lua_State *L);
int luat_lv_obj_set_style_outline_opa(lua_State *L);
int luat_lv_obj_set_style_outline_pad(lua_State *L);
int luat_lv_obj_set_style_shadow_width(lua_State *L);
int luat_lv_obj_set_style_shadow_ofs_x(lua_State *L);
int luat_lv_obj_set_style_shadow_ofs_y(lua_State *L);
int luat_lv_obj_set_style_shadow_spread(lua_State *L);
int luat_lv_obj_set_style_shadow_color(lua_State *L);
int luat_lv_obj_set_style_shadow_color_filtered(lua_State *L);
int luat_lv_obj_set_style_shadow_opa(lua_State *L);
int luat_lv_obj_set_style_line_width(lua_State *L);
int luat_lv_obj_set_style_line_dash_width(lua_State *L);
int luat_lv_obj_set_style_line_dash_gap(lua_State *L);
int luat_lv_obj_set_style_line_rounded(lua_State *L);
int luat_lv_obj_set_style_line_color(lua_State *L);
int luat_lv_obj_set_style_line_color_filtered(lua_State *L);
int luat_lv_obj_set_style_line_opa(lua_State *L);
int luat_lv_obj_set_style_arc_width(lua_State *L);
int luat_lv_obj_set_style_arc_rounded(lua_State *L);
int luat_lv_obj_set_style_arc_color(lua_State *L);
int luat_lv_obj_set_style_arc_color_filtered(lua_State *L);
int luat_lv_obj_set_style_arc_opa(lua_State *L);
int luat_lv_obj_set_style_arc_img_src(lua_State *L);
int luat_lv_obj_set_style_pad_all(lua_State *L);
int luat_lv_obj_set_style_pad_hor(lua_State *L);
int luat_lv_obj_set_style_pad_ver(lua_State *L);
int luat_lv_obj_set_style_pad_gap(lua_State *L);
int luat_lv_obj_set_style_size(lua_State *L);
int luat_lv_obj_calculate_style_text_align(lua_State *L);
int luat_lv_obj_get_x_aligned(lua_State *L);
int luat_lv_obj_get_y_aligned(lua_State *L);
int luat_lv_obj_init_draw_rect_dsc(lua_State *L);
int luat_lv_obj_init_draw_label_dsc(lua_State *L);
int luat_lv_obj_init_draw_img_dsc(lua_State *L);
int luat_lv_obj_init_draw_line_dsc(lua_State *L);
int luat_lv_obj_init_draw_arc_dsc(lua_State *L);
int luat_lv_obj_calculate_ext_draw_size(lua_State *L);
int luat_lv_obj_draw_dsc_init(lua_State *L);
int luat_lv_obj_draw_part_check_type(lua_State *L);
int luat_lv_obj_refresh_ext_draw_size(lua_State *L);
int luat_lv_obj_class_create_obj(lua_State *L);
int luat_lv_obj_class_init_obj(lua_State *L);
int luat_lv_obj_is_editable(lua_State *L);
int luat_lv_obj_is_group_def(lua_State *L);
int luat_lv_obj_event_base(lua_State *L);
int luat_lv_obj_remove_event_dsc(lua_State *L);
int luat_lv_obj_create(lua_State *L);
int luat_lv_obj_add_flag(lua_State *L);
int luat_lv_obj_clear_flag(lua_State *L);
int luat_lv_obj_add_state(lua_State *L);
int luat_lv_obj_clear_state(lua_State *L);
int luat_lv_obj_set_user_data(lua_State *L);
int luat_lv_obj_has_flag(lua_State *L);
int luat_lv_obj_has_flag_any(lua_State *L);
int luat_lv_obj_get_state(lua_State *L);
int luat_lv_obj_has_state(lua_State *L);
int luat_lv_obj_get_group(lua_State *L);
int luat_lv_obj_get_user_data(lua_State *L);
int luat_lv_obj_allocate_spec_attr(lua_State *L);
int luat_lv_obj_check_type(lua_State *L);
int luat_lv_obj_has_class(lua_State *L);
int luat_lv_obj_get_class(lua_State *L);
int luat_lv_obj_is_valid(lua_State *L);
int luat_lv_obj_dpx(lua_State *L);

#define LUAT_LV_OBJ_RLT     {"obj_del", luat_lv_obj_del, 0},\
    {"obj_clean", luat_lv_obj_clean, 0},\
    {"obj_del_delayed", luat_lv_obj_del_delayed, 0},\
    {"obj_del_async", luat_lv_obj_del_async, 0},\
    {"obj_set_parent", luat_lv_obj_set_parent, 0},\
    {"obj_swap", luat_lv_obj_swap, 0},\
    {"obj_move_to_index", luat_lv_obj_move_to_index, 0},\
    {"obj_get_screen", luat_lv_obj_get_screen, 0},\
    {"obj_get_disp", luat_lv_obj_get_disp, 0},\
    {"obj_get_parent", luat_lv_obj_get_parent, 0},\
    {"obj_get_child", luat_lv_obj_get_child, 0},\
    {"obj_get_child_cnt", luat_lv_obj_get_child_cnt, 0},\
    {"obj_get_index", luat_lv_obj_get_index, 0},\
    {"obj_tree_walk", luat_lv_obj_tree_walk, 0},\
    {"obj_set_pos", luat_lv_obj_set_pos, 0},\
    {"obj_set_x", luat_lv_obj_set_x, 0},\
    {"obj_set_y", luat_lv_obj_set_y, 0},\
    {"obj_set_size", luat_lv_obj_set_size, 0},\
    {"obj_refr_size", luat_lv_obj_refr_size, 0},\
    {"obj_set_width", luat_lv_obj_set_width, 0},\
    {"obj_set_height", luat_lv_obj_set_height, 0},\
    {"obj_set_content_width", luat_lv_obj_set_content_width, 0},\
    {"obj_set_content_height", luat_lv_obj_set_content_height, 0},\
    {"obj_set_layout", luat_lv_obj_set_layout, 0},\
    {"obj_is_layout_positioned", luat_lv_obj_is_layout_positioned, 0},\
    {"obj_mark_layout_as_dirty", luat_lv_obj_mark_layout_as_dirty, 0},\
    {"obj_update_layout", luat_lv_obj_update_layout, 0},\
    {"obj_set_align", luat_lv_obj_set_align, 0},\
    {"obj_align", luat_lv_obj_align, 0},\
    {"obj_align_to", luat_lv_obj_align_to, 0},\
    {"obj_center", luat_lv_obj_center, 0},\
    {"obj_get_coords", luat_lv_obj_get_coords, 0},\
    {"obj_get_x", luat_lv_obj_get_x, 0},\
    {"obj_get_x2", luat_lv_obj_get_x2, 0},\
    {"obj_get_y", luat_lv_obj_get_y, 0},\
    {"obj_get_y2", luat_lv_obj_get_y2, 0},\
    {"obj_get_width", luat_lv_obj_get_width, 0},\
    {"obj_get_height", luat_lv_obj_get_height, 0},\
    {"obj_get_content_width", luat_lv_obj_get_content_width, 0},\
    {"obj_get_content_height", luat_lv_obj_get_content_height, 0},\
    {"obj_get_content_coords", luat_lv_obj_get_content_coords, 0},\
    {"obj_get_self_width", luat_lv_obj_get_self_width, 0},\
    {"obj_get_self_height", luat_lv_obj_get_self_height, 0},\
    {"obj_refresh_self_size", luat_lv_obj_refresh_self_size, 0},\
    {"obj_refr_pos", luat_lv_obj_refr_pos, 0},\
    {"obj_move_to", luat_lv_obj_move_to, 0},\
    {"obj_move_children_by", luat_lv_obj_move_children_by, 0},\
    {"obj_invalidate_area", luat_lv_obj_invalidate_area, 0},\
    {"obj_invalidate", luat_lv_obj_invalidate, 0},\
    {"obj_area_is_visible", luat_lv_obj_area_is_visible, 0},\
    {"obj_is_visible", luat_lv_obj_is_visible, 0},\
    {"obj_set_ext_click_area", luat_lv_obj_set_ext_click_area, 0},\
    {"obj_get_click_area", luat_lv_obj_get_click_area, 0},\
    {"obj_hit_test", luat_lv_obj_hit_test, 0},\
    {"obj_set_scrollbar_mode", luat_lv_obj_set_scrollbar_mode, 0},\
    {"obj_set_scroll_dir", luat_lv_obj_set_scroll_dir, 0},\
    {"obj_set_scroll_snap_x", luat_lv_obj_set_scroll_snap_x, 0},\
    {"obj_set_scroll_snap_y", luat_lv_obj_set_scroll_snap_y, 0},\
    {"obj_get_scrollbar_mode", luat_lv_obj_get_scrollbar_mode, 0},\
    {"obj_get_scroll_dir", luat_lv_obj_get_scroll_dir, 0},\
    {"obj_get_scroll_snap_x", luat_lv_obj_get_scroll_snap_x, 0},\
    {"obj_get_scroll_snap_y", luat_lv_obj_get_scroll_snap_y, 0},\
    {"obj_get_scroll_x", luat_lv_obj_get_scroll_x, 0},\
    {"obj_get_scroll_y", luat_lv_obj_get_scroll_y, 0},\
    {"obj_get_scroll_top", luat_lv_obj_get_scroll_top, 0},\
    {"obj_get_scroll_bottom", luat_lv_obj_get_scroll_bottom, 0},\
    {"obj_get_scroll_left", luat_lv_obj_get_scroll_left, 0},\
    {"obj_get_scroll_right", luat_lv_obj_get_scroll_right, 0},\
    {"obj_get_scroll_end", luat_lv_obj_get_scroll_end, 0},\
    {"obj_scroll_by", luat_lv_obj_scroll_by, 0},\
    {"obj_scroll_to", luat_lv_obj_scroll_to, 0},\
    {"obj_scroll_to_x", luat_lv_obj_scroll_to_x, 0},\
    {"obj_scroll_to_y", luat_lv_obj_scroll_to_y, 0},\
    {"obj_scroll_to_view", luat_lv_obj_scroll_to_view, 0},\
    {"obj_scroll_to_view_recursive", luat_lv_obj_scroll_to_view_recursive, 0},\
    {"obj_is_scrolling", luat_lv_obj_is_scrolling, 0},\
    {"obj_update_snap", luat_lv_obj_update_snap, 0},\
    {"obj_get_scrollbar_area", luat_lv_obj_get_scrollbar_area, 0},\
    {"obj_scrollbar_invalidate", luat_lv_obj_scrollbar_invalidate, 0},\
    {"obj_readjust_scroll", luat_lv_obj_readjust_scroll, 0},\
    {"obj_add_style", luat_lv_obj_add_style, 0},\
    {"obj_remove_style", luat_lv_obj_remove_style, 0},\
    {"obj_remove_style_all", luat_lv_obj_remove_style_all, 0},\
    {"obj_report_style_change", luat_lv_obj_report_style_change, 0},\
    {"obj_refresh_style", luat_lv_obj_refresh_style, 0},\
    {"obj_enable_style_refresh", luat_lv_obj_enable_style_refresh, 0},\
    {"obj_get_style_prop", luat_lv_obj_get_style_prop, 0},\
    {"obj_set_local_style_prop", luat_lv_obj_set_local_style_prop, 0},\
    {"obj_get_local_style_prop", luat_lv_obj_get_local_style_prop, 0},\
    {"obj_remove_local_style_prop", luat_lv_obj_remove_local_style_prop, 0},\
    {"obj_fade_in", luat_lv_obj_fade_in, 0},\
    {"obj_fade_out", luat_lv_obj_fade_out, 0},\
    {"obj_style_get_selector_state", luat_lv_obj_style_get_selector_state, 0},\
    {"obj_style_get_selector_part", luat_lv_obj_style_get_selector_part, 0},\
    {"obj_get_style_width", luat_lv_obj_get_style_width, 0},\
    {"obj_get_style_min_width", luat_lv_obj_get_style_min_width, 0},\
    {"obj_get_style_max_width", luat_lv_obj_get_style_max_width, 0},\
    {"obj_get_style_height", luat_lv_obj_get_style_height, 0},\
    {"obj_get_style_min_height", luat_lv_obj_get_style_min_height, 0},\
    {"obj_get_style_max_height", luat_lv_obj_get_style_max_height, 0},\
    {"obj_get_style_x", luat_lv_obj_get_style_x, 0},\
    {"obj_get_style_y", luat_lv_obj_get_style_y, 0},\
    {"obj_get_style_align", luat_lv_obj_get_style_align, 0},\
    {"obj_get_style_transform_width", luat_lv_obj_get_style_transform_width, 0},\
    {"obj_get_style_transform_height", luat_lv_obj_get_style_transform_height, 0},\
    {"obj_get_style_translate_x", luat_lv_obj_get_style_translate_x, 0},\
    {"obj_get_style_translate_y", luat_lv_obj_get_style_translate_y, 0},\
    {"obj_get_style_transform_zoom", luat_lv_obj_get_style_transform_zoom, 0},\
    {"obj_get_style_transform_angle", luat_lv_obj_get_style_transform_angle, 0},\
    {"obj_get_style_pad_top", luat_lv_obj_get_style_pad_top, 0},\
    {"obj_get_style_pad_bottom", luat_lv_obj_get_style_pad_bottom, 0},\
    {"obj_get_style_pad_left", luat_lv_obj_get_style_pad_left, 0},\
    {"obj_get_style_pad_right", luat_lv_obj_get_style_pad_right, 0},\
    {"obj_get_style_pad_row", luat_lv_obj_get_style_pad_row, 0},\
    {"obj_get_style_pad_column", luat_lv_obj_get_style_pad_column, 0},\
    {"obj_get_style_radius", luat_lv_obj_get_style_radius, 0},\
    {"obj_get_style_clip_corner", luat_lv_obj_get_style_clip_corner, 0},\
    {"obj_get_style_opa", luat_lv_obj_get_style_opa, 0},\
    {"obj_get_style_color_filter_dsc", luat_lv_obj_get_style_color_filter_dsc, 0},\
    {"obj_get_style_color_filter_opa", luat_lv_obj_get_style_color_filter_opa, 0},\
    {"obj_get_style_anim_time", luat_lv_obj_get_style_anim_time, 0},\
    {"obj_get_style_anim_speed", luat_lv_obj_get_style_anim_speed, 0},\
    {"obj_get_style_transition", luat_lv_obj_get_style_transition, 0},\
    {"obj_get_style_blend_mode", luat_lv_obj_get_style_blend_mode, 0},\
    {"obj_get_style_layout", luat_lv_obj_get_style_layout, 0},\
    {"obj_get_style_base_dir", luat_lv_obj_get_style_base_dir, 0},\
    {"obj_get_style_bg_color", luat_lv_obj_get_style_bg_color, 0},\
    {"obj_get_style_bg_color_filtered", luat_lv_obj_get_style_bg_color_filtered, 0},\
    {"obj_get_style_bg_opa", luat_lv_obj_get_style_bg_opa, 0},\
    {"obj_get_style_bg_grad_color", luat_lv_obj_get_style_bg_grad_color, 0},\
    {"obj_get_style_bg_grad_color_filtered", luat_lv_obj_get_style_bg_grad_color_filtered, 0},\
    {"obj_get_style_bg_grad_dir", luat_lv_obj_get_style_bg_grad_dir, 0},\
    {"obj_get_style_bg_main_stop", luat_lv_obj_get_style_bg_main_stop, 0},\
    {"obj_get_style_bg_grad_stop", luat_lv_obj_get_style_bg_grad_stop, 0},\
    {"obj_get_style_bg_img_src", luat_lv_obj_get_style_bg_img_src, 0},\
    {"obj_get_style_bg_img_opa", luat_lv_obj_get_style_bg_img_opa, 0},\
    {"obj_get_style_bg_img_recolor", luat_lv_obj_get_style_bg_img_recolor, 0},\
    {"obj_get_style_bg_img_recolor_filtered", luat_lv_obj_get_style_bg_img_recolor_filtered, 0},\
    {"obj_get_style_bg_img_recolor_opa", luat_lv_obj_get_style_bg_img_recolor_opa, 0},\
    {"obj_get_style_bg_img_tiled", luat_lv_obj_get_style_bg_img_tiled, 0},\
    {"obj_get_style_border_color", luat_lv_obj_get_style_border_color, 0},\
    {"obj_get_style_border_color_filtered", luat_lv_obj_get_style_border_color_filtered, 0},\
    {"obj_get_style_border_opa", luat_lv_obj_get_style_border_opa, 0},\
    {"obj_get_style_border_width", luat_lv_obj_get_style_border_width, 0},\
    {"obj_get_style_border_side", luat_lv_obj_get_style_border_side, 0},\
    {"obj_get_style_border_post", luat_lv_obj_get_style_border_post, 0},\
    {"obj_get_style_text_color", luat_lv_obj_get_style_text_color, 0},\
    {"obj_get_style_text_color_filtered", luat_lv_obj_get_style_text_color_filtered, 0},\
    {"obj_get_style_text_opa", luat_lv_obj_get_style_text_opa, 0},\
    {"obj_get_style_text_font", luat_lv_obj_get_style_text_font, 0},\
    {"obj_get_style_text_letter_space", luat_lv_obj_get_style_text_letter_space, 0},\
    {"obj_get_style_text_line_space", luat_lv_obj_get_style_text_line_space, 0},\
    {"obj_get_style_text_decor", luat_lv_obj_get_style_text_decor, 0},\
    {"obj_get_style_text_align", luat_lv_obj_get_style_text_align, 0},\
    {"obj_get_style_img_opa", luat_lv_obj_get_style_img_opa, 0},\
    {"obj_get_style_img_recolor", luat_lv_obj_get_style_img_recolor, 0},\
    {"obj_get_style_img_recolor_filtered", luat_lv_obj_get_style_img_recolor_filtered, 0},\
    {"obj_get_style_img_recolor_opa", luat_lv_obj_get_style_img_recolor_opa, 0},\
    {"obj_get_style_outline_width", luat_lv_obj_get_style_outline_width, 0},\
    {"obj_get_style_outline_color", luat_lv_obj_get_style_outline_color, 0},\
    {"obj_get_style_outline_color_filtered", luat_lv_obj_get_style_outline_color_filtered, 0},\
    {"obj_get_style_outline_opa", luat_lv_obj_get_style_outline_opa, 0},\
    {"obj_get_style_outline_pad", luat_lv_obj_get_style_outline_pad, 0},\
    {"obj_get_style_shadow_width", luat_lv_obj_get_style_shadow_width, 0},\
    {"obj_get_style_shadow_ofs_x", luat_lv_obj_get_style_shadow_ofs_x, 0},\
    {"obj_get_style_shadow_ofs_y", luat_lv_obj_get_style_shadow_ofs_y, 0},\
    {"obj_get_style_shadow_spread", luat_lv_obj_get_style_shadow_spread, 0},\
    {"obj_get_style_shadow_color", luat_lv_obj_get_style_shadow_color, 0},\
    {"obj_get_style_shadow_color_filtered", luat_lv_obj_get_style_shadow_color_filtered, 0},\
    {"obj_get_style_shadow_opa", luat_lv_obj_get_style_shadow_opa, 0},\
    {"obj_get_style_line_width", luat_lv_obj_get_style_line_width, 0},\
    {"obj_get_style_line_dash_width", luat_lv_obj_get_style_line_dash_width, 0},\
    {"obj_get_style_line_dash_gap", luat_lv_obj_get_style_line_dash_gap, 0},\
    {"obj_get_style_line_rounded", luat_lv_obj_get_style_line_rounded, 0},\
    {"obj_get_style_line_color", luat_lv_obj_get_style_line_color, 0},\
    {"obj_get_style_line_color_filtered", luat_lv_obj_get_style_line_color_filtered, 0},\
    {"obj_get_style_line_opa", luat_lv_obj_get_style_line_opa, 0},\
    {"obj_get_style_arc_width", luat_lv_obj_get_style_arc_width, 0},\
    {"obj_get_style_arc_rounded", luat_lv_obj_get_style_arc_rounded, 0},\
    {"obj_get_style_arc_color", luat_lv_obj_get_style_arc_color, 0},\
    {"obj_get_style_arc_color_filtered", luat_lv_obj_get_style_arc_color_filtered, 0},\
    {"obj_get_style_arc_opa", luat_lv_obj_get_style_arc_opa, 0},\
    {"obj_get_style_arc_img_src", luat_lv_obj_get_style_arc_img_src, 0},\
    {"obj_set_style_width", luat_lv_obj_set_style_width, 0},\
    {"obj_set_style_min_width", luat_lv_obj_set_style_min_width, 0},\
    {"obj_set_style_max_width", luat_lv_obj_set_style_max_width, 0},\
    {"obj_set_style_height", luat_lv_obj_set_style_height, 0},\
    {"obj_set_style_min_height", luat_lv_obj_set_style_min_height, 0},\
    {"obj_set_style_max_height", luat_lv_obj_set_style_max_height, 0},\
    {"obj_set_style_x", luat_lv_obj_set_style_x, 0},\
    {"obj_set_style_y", luat_lv_obj_set_style_y, 0},\
    {"obj_set_style_align", luat_lv_obj_set_style_align, 0},\
    {"obj_set_style_transform_width", luat_lv_obj_set_style_transform_width, 0},\
    {"obj_set_style_transform_height", luat_lv_obj_set_style_transform_height, 0},\
    {"obj_set_style_translate_x", luat_lv_obj_set_style_translate_x, 0},\
    {"obj_set_style_translate_y", luat_lv_obj_set_style_translate_y, 0},\
    {"obj_set_style_transform_zoom", luat_lv_obj_set_style_transform_zoom, 0},\
    {"obj_set_style_transform_angle", luat_lv_obj_set_style_transform_angle, 0},\
    {"obj_set_style_pad_top", luat_lv_obj_set_style_pad_top, 0},\
    {"obj_set_style_pad_bottom", luat_lv_obj_set_style_pad_bottom, 0},\
    {"obj_set_style_pad_left", luat_lv_obj_set_style_pad_left, 0},\
    {"obj_set_style_pad_right", luat_lv_obj_set_style_pad_right, 0},\
    {"obj_set_style_pad_row", luat_lv_obj_set_style_pad_row, 0},\
    {"obj_set_style_pad_column", luat_lv_obj_set_style_pad_column, 0},\
    {"obj_set_style_radius", luat_lv_obj_set_style_radius, 0},\
    {"obj_set_style_clip_corner", luat_lv_obj_set_style_clip_corner, 0},\
    {"obj_set_style_opa", luat_lv_obj_set_style_opa, 0},\
    {"obj_set_style_color_filter_dsc", luat_lv_obj_set_style_color_filter_dsc, 0},\
    {"obj_set_style_color_filter_opa", luat_lv_obj_set_style_color_filter_opa, 0},\
    {"obj_set_style_anim_time", luat_lv_obj_set_style_anim_time, 0},\
    {"obj_set_style_anim_speed", luat_lv_obj_set_style_anim_speed, 0},\
    {"obj_set_style_transition", luat_lv_obj_set_style_transition, 0},\
    {"obj_set_style_blend_mode", luat_lv_obj_set_style_blend_mode, 0},\
    {"obj_set_style_layout", luat_lv_obj_set_style_layout, 0},\
    {"obj_set_style_base_dir", luat_lv_obj_set_style_base_dir, 0},\
    {"obj_set_style_bg_color", luat_lv_obj_set_style_bg_color, 0},\
    {"obj_set_style_bg_color_filtered", luat_lv_obj_set_style_bg_color_filtered, 0},\
    {"obj_set_style_bg_opa", luat_lv_obj_set_style_bg_opa, 0},\
    {"obj_set_style_bg_grad_color", luat_lv_obj_set_style_bg_grad_color, 0},\
    {"obj_set_style_bg_grad_color_filtered", luat_lv_obj_set_style_bg_grad_color_filtered, 0},\
    {"obj_set_style_bg_grad_dir", luat_lv_obj_set_style_bg_grad_dir, 0},\
    {"obj_set_style_bg_main_stop", luat_lv_obj_set_style_bg_main_stop, 0},\
    {"obj_set_style_bg_grad_stop", luat_lv_obj_set_style_bg_grad_stop, 0},\
    {"obj_set_style_bg_img_src", luat_lv_obj_set_style_bg_img_src, 0},\
    {"obj_set_style_bg_img_opa", luat_lv_obj_set_style_bg_img_opa, 0},\
    {"obj_set_style_bg_img_recolor", luat_lv_obj_set_style_bg_img_recolor, 0},\
    {"obj_set_style_bg_img_recolor_filtered", luat_lv_obj_set_style_bg_img_recolor_filtered, 0},\
    {"obj_set_style_bg_img_recolor_opa", luat_lv_obj_set_style_bg_img_recolor_opa, 0},\
    {"obj_set_style_bg_img_tiled", luat_lv_obj_set_style_bg_img_tiled, 0},\
    {"obj_set_style_border_color", luat_lv_obj_set_style_border_color, 0},\
    {"obj_set_style_border_color_filtered", luat_lv_obj_set_style_border_color_filtered, 0},\
    {"obj_set_style_border_opa", luat_lv_obj_set_style_border_opa, 0},\
    {"obj_set_style_border_width", luat_lv_obj_set_style_border_width, 0},\
    {"obj_set_style_border_side", luat_lv_obj_set_style_border_side, 0},\
    {"obj_set_style_border_post", luat_lv_obj_set_style_border_post, 0},\
    {"obj_set_style_text_color", luat_lv_obj_set_style_text_color, 0},\
    {"obj_set_style_text_color_filtered", luat_lv_obj_set_style_text_color_filtered, 0},\
    {"obj_set_style_text_opa", luat_lv_obj_set_style_text_opa, 0},\
    {"obj_set_style_text_font", luat_lv_obj_set_style_text_font, 0},\
    {"obj_set_style_text_letter_space", luat_lv_obj_set_style_text_letter_space, 0},\
    {"obj_set_style_text_line_space", luat_lv_obj_set_style_text_line_space, 0},\
    {"obj_set_style_text_decor", luat_lv_obj_set_style_text_decor, 0},\
    {"obj_set_style_text_align", luat_lv_obj_set_style_text_align, 0},\
    {"obj_set_style_img_opa", luat_lv_obj_set_style_img_opa, 0},\
    {"obj_set_style_img_recolor", luat_lv_obj_set_style_img_recolor, 0},\
    {"obj_set_style_img_recolor_filtered", luat_lv_obj_set_style_img_recolor_filtered, 0},\
    {"obj_set_style_img_recolor_opa", luat_lv_obj_set_style_img_recolor_opa, 0},\
    {"obj_set_style_outline_width", luat_lv_obj_set_style_outline_width, 0},\
    {"obj_set_style_outline_color", luat_lv_obj_set_style_outline_color, 0},\
    {"obj_set_style_outline_color_filtered", luat_lv_obj_set_style_outline_color_filtered, 0},\
    {"obj_set_style_outline_opa", luat_lv_obj_set_style_outline_opa, 0},\
    {"obj_set_style_outline_pad", luat_lv_obj_set_style_outline_pad, 0},\
    {"obj_set_style_shadow_width", luat_lv_obj_set_style_shadow_width, 0},\
    {"obj_set_style_shadow_ofs_x", luat_lv_obj_set_style_shadow_ofs_x, 0},\
    {"obj_set_style_shadow_ofs_y", luat_lv_obj_set_style_shadow_ofs_y, 0},\
    {"obj_set_style_shadow_spread", luat_lv_obj_set_style_shadow_spread, 0},\
    {"obj_set_style_shadow_color", luat_lv_obj_set_style_shadow_color, 0},\
    {"obj_set_style_shadow_color_filtered", luat_lv_obj_set_style_shadow_color_filtered, 0},\
    {"obj_set_style_shadow_opa", luat_lv_obj_set_style_shadow_opa, 0},\
    {"obj_set_style_line_width", luat_lv_obj_set_style_line_width, 0},\
    {"obj_set_style_line_dash_width", luat_lv_obj_set_style_line_dash_width, 0},\
    {"obj_set_style_line_dash_gap", luat_lv_obj_set_style_line_dash_gap, 0},\
    {"obj_set_style_line_rounded", luat_lv_obj_set_style_line_rounded, 0},\
    {"obj_set_style_line_color", luat_lv_obj_set_style_line_color, 0},\
    {"obj_set_style_line_color_filtered", luat_lv_obj_set_style_line_color_filtered, 0},\
    {"obj_set_style_line_opa", luat_lv_obj_set_style_line_opa, 0},\
    {"obj_set_style_arc_width", luat_lv_obj_set_style_arc_width, 0},\
    {"obj_set_style_arc_rounded", luat_lv_obj_set_style_arc_rounded, 0},\
    {"obj_set_style_arc_color", luat_lv_obj_set_style_arc_color, 0},\
    {"obj_set_style_arc_color_filtered", luat_lv_obj_set_style_arc_color_filtered, 0},\
    {"obj_set_style_arc_opa", luat_lv_obj_set_style_arc_opa, 0},\
    {"obj_set_style_arc_img_src", luat_lv_obj_set_style_arc_img_src, 0},\
    {"obj_set_style_pad_all", luat_lv_obj_set_style_pad_all, 0},\
    {"obj_set_style_pad_hor", luat_lv_obj_set_style_pad_hor, 0},\
    {"obj_set_style_pad_ver", luat_lv_obj_set_style_pad_ver, 0},\
    {"obj_set_style_pad_gap", luat_lv_obj_set_style_pad_gap, 0},\
    {"obj_set_style_size", luat_lv_obj_set_style_size, 0},\
    {"obj_calculate_style_text_align", luat_lv_obj_calculate_style_text_align, 0},\
    {"obj_get_x_aligned", luat_lv_obj_get_x_aligned, 0},\
    {"obj_get_y_aligned", luat_lv_obj_get_y_aligned, 0},\
    {"obj_init_draw_rect_dsc", luat_lv_obj_init_draw_rect_dsc, 0},\
    {"obj_init_draw_label_dsc", luat_lv_obj_init_draw_label_dsc, 0},\
    {"obj_init_draw_img_dsc", luat_lv_obj_init_draw_img_dsc, 0},\
    {"obj_init_draw_line_dsc", luat_lv_obj_init_draw_line_dsc, 0},\
    {"obj_init_draw_arc_dsc", luat_lv_obj_init_draw_arc_dsc, 0},\
    {"obj_calculate_ext_draw_size", luat_lv_obj_calculate_ext_draw_size, 0},\
    {"obj_draw_dsc_init", luat_lv_obj_draw_dsc_init, 0},\
    {"obj_draw_part_check_type", luat_lv_obj_draw_part_check_type, 0},\
    {"obj_refresh_ext_draw_size", luat_lv_obj_refresh_ext_draw_size, 0},\
    {"obj_class_create_obj", luat_lv_obj_class_create_obj, 0},\
    {"obj_class_init_obj", luat_lv_obj_class_init_obj, 0},\
    {"obj_is_editable", luat_lv_obj_is_editable, 0},\
    {"obj_is_group_def", luat_lv_obj_is_group_def, 0},\
    {"obj_event_base", luat_lv_obj_event_base, 0},\
    {"obj_remove_event_dsc", luat_lv_obj_remove_event_dsc, 0},\
    {"obj_create", luat_lv_obj_create, 0},\
    {"obj_add_flag", luat_lv_obj_add_flag, 0},\
    {"obj_clear_flag", luat_lv_obj_clear_flag, 0},\
    {"obj_add_state", luat_lv_obj_add_state, 0},\
    {"obj_clear_state", luat_lv_obj_clear_state, 0},\
    {"obj_set_user_data", luat_lv_obj_set_user_data, 0},\
    {"obj_has_flag", luat_lv_obj_has_flag, 0},\
    {"obj_has_flag_any", luat_lv_obj_has_flag_any, 0},\
    {"obj_get_state", luat_lv_obj_get_state, 0},\
    {"obj_has_state", luat_lv_obj_has_state, 0},\
    {"obj_get_group", luat_lv_obj_get_group, 0},\
    {"obj_get_user_data", luat_lv_obj_get_user_data, 0},\
    {"obj_allocate_spec_attr", luat_lv_obj_allocate_spec_attr, 0},\
    {"obj_check_type", luat_lv_obj_check_type, 0},\
    {"obj_has_class", luat_lv_obj_has_class, 0},\
    {"obj_get_class", luat_lv_obj_get_class, 0},\
    {"obj_is_valid", luat_lv_obj_is_valid, 0},\
    {"obj_dpx", luat_lv_obj_dpx, 0},\

// prefix lv_core refr
int luat_lv_refr_now(lua_State *L);

#define LUAT_LV_REFR_RLT     {"refr_now", luat_lv_refr_now, 0},\

// prefix lv_core theme
int luat_lv_theme_get_from_obj(lua_State *L);
int luat_lv_theme_apply(lua_State *L);
int luat_lv_theme_set_parent(lua_State *L);
int luat_lv_theme_get_font_small(lua_State *L);
int luat_lv_theme_get_font_normal(lua_State *L);
int luat_lv_theme_get_font_large(lua_State *L);
int luat_lv_theme_get_color_primary(lua_State *L);
int luat_lv_theme_get_color_secondary(lua_State *L);

#define LUAT_LV_THEME_RLT     {"theme_get_from_obj", luat_lv_theme_get_from_obj, 0},\
    {"theme_apply", luat_lv_theme_apply, 0},\
    {"theme_set_parent", luat_lv_theme_set_parent, 0},\
    {"theme_get_font_small", luat_lv_theme_get_font_small, 0},\
    {"theme_get_font_normal", luat_lv_theme_get_font_normal, 0},\
    {"theme_get_font_large", luat_lv_theme_get_font_large, 0},\
    {"theme_get_color_primary", luat_lv_theme_get_color_primary, 0},\
    {"theme_get_color_secondary", luat_lv_theme_get_color_secondary, 0},\


// group lv_draw
// prefix lv_draw draw
int luat_lv_draw_mask_add(lua_State *L);
int luat_lv_draw_mask_apply(lua_State *L);
int luat_lv_draw_mask_apply_ids(lua_State *L);
int luat_lv_draw_mask_remove_id(lua_State *L);
int luat_lv_draw_mask_remove_custom(lua_State *L);
int luat_lv_draw_mask_free_param(lua_State *L);
int luat_lv_draw_mask_get_cnt(lua_State *L);
int luat_lv_draw_mask_is_any(lua_State *L);
int luat_lv_draw_mask_line_points_init(lua_State *L);
int luat_lv_draw_mask_line_angle_init(lua_State *L);
int luat_lv_draw_mask_angle_init(lua_State *L);
int luat_lv_draw_mask_radius_init(lua_State *L);
int luat_lv_draw_mask_fade_init(lua_State *L);
int luat_lv_draw_mask_map_init(lua_State *L);
int luat_lv_draw_rect_dsc_init(lua_State *L);
int luat_lv_draw_rect(lua_State *L);
int luat_lv_draw_label_dsc_init(lua_State *L);
int luat_lv_draw_label(lua_State *L);
int luat_lv_draw_letter(lua_State *L);
int luat_lv_draw_img_dsc_init(lua_State *L);
int luat_lv_draw_img(lua_State *L);
int luat_lv_draw_line(lua_State *L);
int luat_lv_draw_line_dsc_init(lua_State *L);
int luat_lv_draw_arc_dsc_init(lua_State *L);
int luat_lv_draw_arc(lua_State *L);
int luat_lv_draw_arc_get_area(lua_State *L);

#define LUAT_LV_DRAW_RLT     {"draw_mask_add", luat_lv_draw_mask_add, 0},\
    {"draw_mask_apply", luat_lv_draw_mask_apply, 0},\
    {"draw_mask_apply_ids", luat_lv_draw_mask_apply_ids, 0},\
    {"draw_mask_remove_id", luat_lv_draw_mask_remove_id, 0},\
    {"draw_mask_remove_custom", luat_lv_draw_mask_remove_custom, 0},\
    {"draw_mask_free_param", luat_lv_draw_mask_free_param, 0},\
    {"draw_mask_get_cnt", luat_lv_draw_mask_get_cnt, 0},\
    {"draw_mask_is_any", luat_lv_draw_mask_is_any, 0},\
    {"draw_mask_line_points_init", luat_lv_draw_mask_line_points_init, 0},\
    {"draw_mask_line_angle_init", luat_lv_draw_mask_line_angle_init, 0},\
    {"draw_mask_angle_init", luat_lv_draw_mask_angle_init, 0},\
    {"draw_mask_radius_init", luat_lv_draw_mask_radius_init, 0},\
    {"draw_mask_fade_init", luat_lv_draw_mask_fade_init, 0},\
    {"draw_mask_map_init", luat_lv_draw_mask_map_init, 0},\
    {"draw_rect_dsc_init", luat_lv_draw_rect_dsc_init, 0},\
    {"draw_rect", luat_lv_draw_rect, 0},\
    {"draw_label_dsc_init", luat_lv_draw_label_dsc_init, 0},\
    {"draw_label", luat_lv_draw_label, 0},\
    {"draw_letter", luat_lv_draw_letter, 0},\
    {"draw_img_dsc_init", luat_lv_draw_img_dsc_init, 0},\
    {"draw_img", luat_lv_draw_img, 0},\
    {"draw_line", luat_lv_draw_line, 0},\
    {"draw_line_dsc_init", luat_lv_draw_line_dsc_init, 0},\
    {"draw_arc_dsc_init", luat_lv_draw_arc_dsc_init, 0},\
    {"draw_arc", luat_lv_draw_arc, 0},\
    {"draw_arc_get_area", luat_lv_draw_arc_get_area, 0},\


// group lv_font
// prefix lv_font font
int luat_lv_font_get_glyph_dsc(lua_State *L);
int luat_lv_font_get_glyph_width(lua_State *L);
int luat_lv_font_get_line_height(lua_State *L);
int luat_lv_font_default(lua_State *L);

#define LUAT_LV_FONT_RLT     {"font_get_glyph_dsc", luat_lv_font_get_glyph_dsc, 0},\
    {"font_get_glyph_width", luat_lv_font_get_glyph_width, 0},\
    {"font_get_line_height", luat_lv_font_get_line_height, 0},\
    {"font_default", luat_lv_font_default, 0},\


// group lv_misc
// prefix lv_misc anim
int luat_lv_anim_init(lua_State *L);
int luat_lv_anim_set_var(lua_State *L);
int luat_lv_anim_set_time(lua_State *L);
int luat_lv_anim_set_delay(lua_State *L);
int luat_lv_anim_set_values(lua_State *L);
int luat_lv_anim_set_playback_time(lua_State *L);
int luat_lv_anim_set_playback_delay(lua_State *L);
int luat_lv_anim_set_repeat_count(lua_State *L);
int luat_lv_anim_set_repeat_delay(lua_State *L);
int luat_lv_anim_set_early_apply(lua_State *L);
int luat_lv_anim_set_user_data(lua_State *L);
int luat_lv_anim_start(lua_State *L);
int luat_lv_anim_get_delay(lua_State *L);
int luat_lv_anim_get_playtime(lua_State *L);
int luat_lv_anim_get_user_data(lua_State *L);
int luat_lv_anim_del(lua_State *L);
int luat_lv_anim_del_all(lua_State *L);
int luat_lv_anim_get(lua_State *L);
int luat_lv_anim_custom_del(lua_State *L);
int luat_lv_anim_custom_get(lua_State *L);
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

#define LUAT_LV_ANIM_RLT     {"anim_init", luat_lv_anim_init, 0},\
    {"anim_set_var", luat_lv_anim_set_var, 0},\
    {"anim_set_time", luat_lv_anim_set_time, 0},\
    {"anim_set_delay", luat_lv_anim_set_delay, 0},\
    {"anim_set_values", luat_lv_anim_set_values, 0},\
    {"anim_set_playback_time", luat_lv_anim_set_playback_time, 0},\
    {"anim_set_playback_delay", luat_lv_anim_set_playback_delay, 0},\
    {"anim_set_repeat_count", luat_lv_anim_set_repeat_count, 0},\
    {"anim_set_repeat_delay", luat_lv_anim_set_repeat_delay, 0},\
    {"anim_set_early_apply", luat_lv_anim_set_early_apply, 0},\
    {"anim_set_user_data", luat_lv_anim_set_user_data, 0},\
    {"anim_start", luat_lv_anim_start, 0},\
    {"anim_get_delay", luat_lv_anim_get_delay, 0},\
    {"anim_get_playtime", luat_lv_anim_get_playtime, 0},\
    {"anim_get_user_data", luat_lv_anim_get_user_data, 0},\
    {"anim_del", luat_lv_anim_del, 0},\
    {"anim_del_all", luat_lv_anim_del_all, 0},\
    {"anim_get", luat_lv_anim_get, 0},\
    {"anim_custom_del", luat_lv_anim_custom_del, 0},\
    {"anim_custom_get", luat_lv_anim_custom_get, 0},\
    {"anim_count_running", luat_lv_anim_count_running, 0},\
    {"anim_speed_to_time", luat_lv_anim_speed_to_time, 0},\
    {"anim_refr_now", luat_lv_anim_refr_now, 0},\
    {"anim_path_linear", luat_lv_anim_path_linear, 0},\
    {"anim_path_ease_in", luat_lv_anim_path_ease_in, 0},\
    {"anim_path_ease_out", luat_lv_anim_path_ease_out, 0},\
    {"anim_path_ease_in_out", luat_lv_anim_path_ease_in_out, 0},\
    {"anim_path_overshoot", luat_lv_anim_path_overshoot, 0},\
    {"anim_path_bounce", luat_lv_anim_path_bounce, 0},\
    {"anim_path_step", luat_lv_anim_path_step, 0},\

// prefix lv_misc anim_timeline
int luat_lv_anim_timeline_create(lua_State *L);
int luat_lv_anim_timeline_del(lua_State *L);
int luat_lv_anim_timeline_add(lua_State *L);
int luat_lv_anim_timeline_start(lua_State *L);
int luat_lv_anim_timeline_stop(lua_State *L);
int luat_lv_anim_timeline_set_reverse(lua_State *L);
int luat_lv_anim_timeline_set_progress(lua_State *L);
int luat_lv_anim_timeline_get_playtime(lua_State *L);
int luat_lv_anim_timeline_get_reverse(lua_State *L);

#define LUAT_LV_ANIM_TIMELINE_RLT     {"anim_timeline_create", luat_lv_anim_timeline_create, 0},\
    {"anim_timeline_del", luat_lv_anim_timeline_del, 0},\
    {"anim_timeline_add", luat_lv_anim_timeline_add, 0},\
    {"anim_timeline_start", luat_lv_anim_timeline_start, 0},\
    {"anim_timeline_stop", luat_lv_anim_timeline_stop, 0},\
    {"anim_timeline_set_reverse", luat_lv_anim_timeline_set_reverse, 0},\
    {"anim_timeline_set_progress", luat_lv_anim_timeline_set_progress, 0},\
    {"anim_timeline_get_playtime", luat_lv_anim_timeline_get_playtime, 0},\
    {"anim_timeline_get_reverse", luat_lv_anim_timeline_get_reverse, 0},\

// prefix lv_misc area
int luat_lv_area_set(lua_State *L);
int luat_lv_area_copy(lua_State *L);
int luat_lv_area_get_width(lua_State *L);
int luat_lv_area_get_height(lua_State *L);
int luat_lv_area_set_width(lua_State *L);
int luat_lv_area_set_height(lua_State *L);
int luat_lv_area_get_size(lua_State *L);
int luat_lv_area_increase(lua_State *L);
int luat_lv_area_move(lua_State *L);
int luat_lv_area_align(lua_State *L);

#define LUAT_LV_AREA_RLT     {"area_set", luat_lv_area_set, 0},\
    {"area_copy", luat_lv_area_copy, 0},\
    {"area_get_width", luat_lv_area_get_width, 0},\
    {"area_get_height", luat_lv_area_get_height, 0},\
    {"area_set_width", luat_lv_area_set_width, 0},\
    {"area_set_height", luat_lv_area_set_height, 0},\
    {"area_get_size", luat_lv_area_get_size, 0},\
    {"area_increase", luat_lv_area_increase, 0},\
    {"area_move", luat_lv_area_move, 0},\
    {"area_align", luat_lv_area_align, 0},\

// prefix lv_misc bidi
int luat_lv_bidi_calculate_align(lua_State *L);

#define LUAT_LV_BIDI_RLT     {"bidi_calculate_align", luat_lv_bidi_calculate_align, 0},\

// prefix lv_misc color
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
int luat_lv_color_filter_dsc_init(lua_State *L);
int luat_lv_color_fill(lua_State *L);
int luat_lv_color_lighten(lua_State *L);
int luat_lv_color_darken(lua_State *L);
int luat_lv_color_change_lightness(lua_State *L);
int luat_lv_color_hsv_to_rgb(lua_State *L);
int luat_lv_color_rgb_to_hsv(lua_State *L);
int luat_lv_color_to_hsv(lua_State *L);
int luat_lv_color_chroma_key(lua_State *L);
int luat_lv_color_white(lua_State *L);
int luat_lv_color_black(lua_State *L);

#define LUAT_LV_COLOR_RLT     {"color_to1", luat_lv_color_to1, 0},\
    {"color_to8", luat_lv_color_to8, 0},\
    {"color_to16", luat_lv_color_to16, 0},\
    {"color_to32", luat_lv_color_to32, 0},\
    {"color_mix", luat_lv_color_mix, 0},\
    {"color_premult", luat_lv_color_premult, 0},\
    {"color_mix_premult", luat_lv_color_mix_premult, 0},\
    {"color_mix_with_alpha", luat_lv_color_mix_with_alpha, 0},\
    {"color_brightness", luat_lv_color_brightness, 0},\
    {"color_make", luat_lv_color_make, 0},\
    {"color_hex", luat_lv_color_hex, 0},\
    {"color_hex3", luat_lv_color_hex3, 0},\
    {"color_filter_dsc_init", luat_lv_color_filter_dsc_init, 0},\
    {"color_fill", luat_lv_color_fill, 0},\
    {"color_lighten", luat_lv_color_lighten, 0},\
    {"color_darken", luat_lv_color_darken, 0},\
    {"color_change_lightness", luat_lv_color_change_lightness, 0},\
    {"color_hsv_to_rgb", luat_lv_color_hsv_to_rgb, 0},\
    {"color_rgb_to_hsv", luat_lv_color_rgb_to_hsv, 0},\
    {"color_to_hsv", luat_lv_color_to_hsv, 0},\
    {"color_chroma_key", luat_lv_color_chroma_key, 0},\
    {"color_white", luat_lv_color_white, 0},\
    {"color_black", luat_lv_color_black, 0},\

// prefix lv_misc style
int luat_lv_style_init(lua_State *L);
int luat_lv_style_reset(lua_State *L);
int luat_lv_style_register_prop(lua_State *L);
int luat_lv_style_remove_prop(lua_State *L);
int luat_lv_style_set_prop(lua_State *L);
int luat_lv_style_get_prop(lua_State *L);
int luat_lv_style_get_prop_inlined(lua_State *L);
int luat_lv_style_prop_get_default(lua_State *L);
int luat_lv_style_is_empty(lua_State *L);
int luat_lv_style_set_width(lua_State *L);
int luat_lv_style_set_min_width(lua_State *L);
int luat_lv_style_set_max_width(lua_State *L);
int luat_lv_style_set_height(lua_State *L);
int luat_lv_style_set_min_height(lua_State *L);
int luat_lv_style_set_max_height(lua_State *L);
int luat_lv_style_set_x(lua_State *L);
int luat_lv_style_set_y(lua_State *L);
int luat_lv_style_set_align(lua_State *L);
int luat_lv_style_set_transform_width(lua_State *L);
int luat_lv_style_set_transform_height(lua_State *L);
int luat_lv_style_set_translate_x(lua_State *L);
int luat_lv_style_set_translate_y(lua_State *L);
int luat_lv_style_set_transform_zoom(lua_State *L);
int luat_lv_style_set_transform_angle(lua_State *L);
int luat_lv_style_set_pad_top(lua_State *L);
int luat_lv_style_set_pad_bottom(lua_State *L);
int luat_lv_style_set_pad_left(lua_State *L);
int luat_lv_style_set_pad_right(lua_State *L);
int luat_lv_style_set_pad_row(lua_State *L);
int luat_lv_style_set_pad_column(lua_State *L);
int luat_lv_style_set_radius(lua_State *L);
int luat_lv_style_set_clip_corner(lua_State *L);
int luat_lv_style_set_opa(lua_State *L);
int luat_lv_style_set_color_filter_dsc(lua_State *L);
int luat_lv_style_set_color_filter_opa(lua_State *L);
int luat_lv_style_set_anim_time(lua_State *L);
int luat_lv_style_set_anim_speed(lua_State *L);
int luat_lv_style_set_transition(lua_State *L);
int luat_lv_style_set_blend_mode(lua_State *L);
int luat_lv_style_set_layout(lua_State *L);
int luat_lv_style_set_base_dir(lua_State *L);
int luat_lv_style_set_bg_color(lua_State *L);
int luat_lv_style_set_bg_color_filtered(lua_State *L);
int luat_lv_style_set_bg_opa(lua_State *L);
int luat_lv_style_set_bg_grad_color(lua_State *L);
int luat_lv_style_set_bg_grad_color_filtered(lua_State *L);
int luat_lv_style_set_bg_grad_dir(lua_State *L);
int luat_lv_style_set_bg_main_stop(lua_State *L);
int luat_lv_style_set_bg_grad_stop(lua_State *L);
int luat_lv_style_set_bg_img_src(lua_State *L);
int luat_lv_style_set_bg_img_opa(lua_State *L);
int luat_lv_style_set_bg_img_recolor(lua_State *L);
int luat_lv_style_set_bg_img_recolor_filtered(lua_State *L);
int luat_lv_style_set_bg_img_recolor_opa(lua_State *L);
int luat_lv_style_set_bg_img_tiled(lua_State *L);
int luat_lv_style_set_border_color(lua_State *L);
int luat_lv_style_set_border_color_filtered(lua_State *L);
int luat_lv_style_set_border_opa(lua_State *L);
int luat_lv_style_set_border_width(lua_State *L);
int luat_lv_style_set_border_side(lua_State *L);
int luat_lv_style_set_border_post(lua_State *L);
int luat_lv_style_set_text_color(lua_State *L);
int luat_lv_style_set_text_color_filtered(lua_State *L);
int luat_lv_style_set_text_opa(lua_State *L);
int luat_lv_style_set_text_font(lua_State *L);
int luat_lv_style_set_text_letter_space(lua_State *L);
int luat_lv_style_set_text_line_space(lua_State *L);
int luat_lv_style_set_text_decor(lua_State *L);
int luat_lv_style_set_text_align(lua_State *L);
int luat_lv_style_set_img_opa(lua_State *L);
int luat_lv_style_set_img_recolor(lua_State *L);
int luat_lv_style_set_img_recolor_filtered(lua_State *L);
int luat_lv_style_set_img_recolor_opa(lua_State *L);
int luat_lv_style_set_outline_width(lua_State *L);
int luat_lv_style_set_outline_color(lua_State *L);
int luat_lv_style_set_outline_color_filtered(lua_State *L);
int luat_lv_style_set_outline_opa(lua_State *L);
int luat_lv_style_set_outline_pad(lua_State *L);
int luat_lv_style_set_shadow_width(lua_State *L);
int luat_lv_style_set_shadow_ofs_x(lua_State *L);
int luat_lv_style_set_shadow_ofs_y(lua_State *L);
int luat_lv_style_set_shadow_spread(lua_State *L);
int luat_lv_style_set_shadow_color(lua_State *L);
int luat_lv_style_set_shadow_color_filtered(lua_State *L);
int luat_lv_style_set_shadow_opa(lua_State *L);
int luat_lv_style_set_line_width(lua_State *L);
int luat_lv_style_set_line_dash_width(lua_State *L);
int luat_lv_style_set_line_dash_gap(lua_State *L);
int luat_lv_style_set_line_rounded(lua_State *L);
int luat_lv_style_set_line_color(lua_State *L);
int luat_lv_style_set_line_color_filtered(lua_State *L);
int luat_lv_style_set_line_opa(lua_State *L);
int luat_lv_style_set_arc_width(lua_State *L);
int luat_lv_style_set_arc_rounded(lua_State *L);
int luat_lv_style_set_arc_color(lua_State *L);
int luat_lv_style_set_arc_color_filtered(lua_State *L);
int luat_lv_style_set_arc_opa(lua_State *L);
int luat_lv_style_set_arc_img_src(lua_State *L);
int luat_lv_style_set_pad_all(lua_State *L);
int luat_lv_style_set_pad_hor(lua_State *L);
int luat_lv_style_set_pad_ver(lua_State *L);
int luat_lv_style_set_pad_gap(lua_State *L);
int luat_lv_style_set_size(lua_State *L);

#define LUAT_LV_STYLE_RLT     {"style_init", luat_lv_style_init, 0},\
    {"style_reset", luat_lv_style_reset, 0},\
    {"style_register_prop", luat_lv_style_register_prop, 0},\
    {"style_remove_prop", luat_lv_style_remove_prop, 0},\
    {"style_set_prop", luat_lv_style_set_prop, 0},\
    {"style_get_prop", luat_lv_style_get_prop, 0},\
    {"style_get_prop_inlined", luat_lv_style_get_prop_inlined, 0},\
    {"style_prop_get_default", luat_lv_style_prop_get_default, 0},\
    {"style_is_empty", luat_lv_style_is_empty, 0},\
    {"style_set_width", luat_lv_style_set_width, 0},\
    {"style_set_min_width", luat_lv_style_set_min_width, 0},\
    {"style_set_max_width", luat_lv_style_set_max_width, 0},\
    {"style_set_height", luat_lv_style_set_height, 0},\
    {"style_set_min_height", luat_lv_style_set_min_height, 0},\
    {"style_set_max_height", luat_lv_style_set_max_height, 0},\
    {"style_set_x", luat_lv_style_set_x, 0},\
    {"style_set_y", luat_lv_style_set_y, 0},\
    {"style_set_align", luat_lv_style_set_align, 0},\
    {"style_set_transform_width", luat_lv_style_set_transform_width, 0},\
    {"style_set_transform_height", luat_lv_style_set_transform_height, 0},\
    {"style_set_translate_x", luat_lv_style_set_translate_x, 0},\
    {"style_set_translate_y", luat_lv_style_set_translate_y, 0},\
    {"style_set_transform_zoom", luat_lv_style_set_transform_zoom, 0},\
    {"style_set_transform_angle", luat_lv_style_set_transform_angle, 0},\
    {"style_set_pad_top", luat_lv_style_set_pad_top, 0},\
    {"style_set_pad_bottom", luat_lv_style_set_pad_bottom, 0},\
    {"style_set_pad_left", luat_lv_style_set_pad_left, 0},\
    {"style_set_pad_right", luat_lv_style_set_pad_right, 0},\
    {"style_set_pad_row", luat_lv_style_set_pad_row, 0},\
    {"style_set_pad_column", luat_lv_style_set_pad_column, 0},\
    {"style_set_radius", luat_lv_style_set_radius, 0},\
    {"style_set_clip_corner", luat_lv_style_set_clip_corner, 0},\
    {"style_set_opa", luat_lv_style_set_opa, 0},\
    {"style_set_color_filter_dsc", luat_lv_style_set_color_filter_dsc, 0},\
    {"style_set_color_filter_opa", luat_lv_style_set_color_filter_opa, 0},\
    {"style_set_anim_time", luat_lv_style_set_anim_time, 0},\
    {"style_set_anim_speed", luat_lv_style_set_anim_speed, 0},\
    {"style_set_transition", luat_lv_style_set_transition, 0},\
    {"style_set_blend_mode", luat_lv_style_set_blend_mode, 0},\
    {"style_set_layout", luat_lv_style_set_layout, 0},\
    {"style_set_base_dir", luat_lv_style_set_base_dir, 0},\
    {"style_set_bg_color", luat_lv_style_set_bg_color, 0},\
    {"style_set_bg_color_filtered", luat_lv_style_set_bg_color_filtered, 0},\
    {"style_set_bg_opa", luat_lv_style_set_bg_opa, 0},\
    {"style_set_bg_grad_color", luat_lv_style_set_bg_grad_color, 0},\
    {"style_set_bg_grad_color_filtered", luat_lv_style_set_bg_grad_color_filtered, 0},\
    {"style_set_bg_grad_dir", luat_lv_style_set_bg_grad_dir, 0},\
    {"style_set_bg_main_stop", luat_lv_style_set_bg_main_stop, 0},\
    {"style_set_bg_grad_stop", luat_lv_style_set_bg_grad_stop, 0},\
    {"style_set_bg_img_src", luat_lv_style_set_bg_img_src, 0},\
    {"style_set_bg_img_opa", luat_lv_style_set_bg_img_opa, 0},\
    {"style_set_bg_img_recolor", luat_lv_style_set_bg_img_recolor, 0},\
    {"style_set_bg_img_recolor_filtered", luat_lv_style_set_bg_img_recolor_filtered, 0},\
    {"style_set_bg_img_recolor_opa", luat_lv_style_set_bg_img_recolor_opa, 0},\
    {"style_set_bg_img_tiled", luat_lv_style_set_bg_img_tiled, 0},\
    {"style_set_border_color", luat_lv_style_set_border_color, 0},\
    {"style_set_border_color_filtered", luat_lv_style_set_border_color_filtered, 0},\
    {"style_set_border_opa", luat_lv_style_set_border_opa, 0},\
    {"style_set_border_width", luat_lv_style_set_border_width, 0},\
    {"style_set_border_side", luat_lv_style_set_border_side, 0},\
    {"style_set_border_post", luat_lv_style_set_border_post, 0},\
    {"style_set_text_color", luat_lv_style_set_text_color, 0},\
    {"style_set_text_color_filtered", luat_lv_style_set_text_color_filtered, 0},\
    {"style_set_text_opa", luat_lv_style_set_text_opa, 0},\
    {"style_set_text_font", luat_lv_style_set_text_font, 0},\
    {"style_set_text_letter_space", luat_lv_style_set_text_letter_space, 0},\
    {"style_set_text_line_space", luat_lv_style_set_text_line_space, 0},\
    {"style_set_text_decor", luat_lv_style_set_text_decor, 0},\
    {"style_set_text_align", luat_lv_style_set_text_align, 0},\
    {"style_set_img_opa", luat_lv_style_set_img_opa, 0},\
    {"style_set_img_recolor", luat_lv_style_set_img_recolor, 0},\
    {"style_set_img_recolor_filtered", luat_lv_style_set_img_recolor_filtered, 0},\
    {"style_set_img_recolor_opa", luat_lv_style_set_img_recolor_opa, 0},\
    {"style_set_outline_width", luat_lv_style_set_outline_width, 0},\
    {"style_set_outline_color", luat_lv_style_set_outline_color, 0},\
    {"style_set_outline_color_filtered", luat_lv_style_set_outline_color_filtered, 0},\
    {"style_set_outline_opa", luat_lv_style_set_outline_opa, 0},\
    {"style_set_outline_pad", luat_lv_style_set_outline_pad, 0},\
    {"style_set_shadow_width", luat_lv_style_set_shadow_width, 0},\
    {"style_set_shadow_ofs_x", luat_lv_style_set_shadow_ofs_x, 0},\
    {"style_set_shadow_ofs_y", luat_lv_style_set_shadow_ofs_y, 0},\
    {"style_set_shadow_spread", luat_lv_style_set_shadow_spread, 0},\
    {"style_set_shadow_color", luat_lv_style_set_shadow_color, 0},\
    {"style_set_shadow_color_filtered", luat_lv_style_set_shadow_color_filtered, 0},\
    {"style_set_shadow_opa", luat_lv_style_set_shadow_opa, 0},\
    {"style_set_line_width", luat_lv_style_set_line_width, 0},\
    {"style_set_line_dash_width", luat_lv_style_set_line_dash_width, 0},\
    {"style_set_line_dash_gap", luat_lv_style_set_line_dash_gap, 0},\
    {"style_set_line_rounded", luat_lv_style_set_line_rounded, 0},\
    {"style_set_line_color", luat_lv_style_set_line_color, 0},\
    {"style_set_line_color_filtered", luat_lv_style_set_line_color_filtered, 0},\
    {"style_set_line_opa", luat_lv_style_set_line_opa, 0},\
    {"style_set_arc_width", luat_lv_style_set_arc_width, 0},\
    {"style_set_arc_rounded", luat_lv_style_set_arc_rounded, 0},\
    {"style_set_arc_color", luat_lv_style_set_arc_color, 0},\
    {"style_set_arc_color_filtered", luat_lv_style_set_arc_color_filtered, 0},\
    {"style_set_arc_opa", luat_lv_style_set_arc_opa, 0},\
    {"style_set_arc_img_src", luat_lv_style_set_arc_img_src, 0},\
    {"style_set_pad_all", luat_lv_style_set_pad_all, 0},\
    {"style_set_pad_hor", luat_lv_style_set_pad_hor, 0},\
    {"style_set_pad_ver", luat_lv_style_set_pad_ver, 0},\
    {"style_set_pad_gap", luat_lv_style_set_pad_gap, 0},\
    {"style_set_size", luat_lv_style_set_size, 0},\

// prefix lv_misc txt
int luat_lv_txt_get_size(lua_State *L);
int luat_lv_txt_get_width(lua_State *L);

#define LUAT_LV_TXT_RLT     {"txt_get_size", luat_lv_txt_get_size, 0},\
    {"txt_get_width", luat_lv_txt_get_width, 0},\


// group lv_widgets
// prefix lv_widgets arc
int luat_lv_arc_create(lua_State *L);
int luat_lv_arc_set_start_angle(lua_State *L);
int luat_lv_arc_set_end_angle(lua_State *L);
int luat_lv_arc_set_angles(lua_State *L);
int luat_lv_arc_set_bg_start_angle(lua_State *L);
int luat_lv_arc_set_bg_end_angle(lua_State *L);
int luat_lv_arc_set_bg_angles(lua_State *L);
int luat_lv_arc_set_rotation(lua_State *L);
int luat_lv_arc_set_mode(lua_State *L);
int luat_lv_arc_set_value(lua_State *L);
int luat_lv_arc_set_range(lua_State *L);
int luat_lv_arc_set_change_rate(lua_State *L);
int luat_lv_arc_get_angle_start(lua_State *L);
int luat_lv_arc_get_angle_end(lua_State *L);
int luat_lv_arc_get_bg_angle_start(lua_State *L);
int luat_lv_arc_get_bg_angle_end(lua_State *L);
int luat_lv_arc_get_value(lua_State *L);
int luat_lv_arc_get_min_value(lua_State *L);
int luat_lv_arc_get_max_value(lua_State *L);
int luat_lv_arc_get_mode(lua_State *L);

#define LUAT_LV_ARC_RLT     {"arc_create", luat_lv_arc_create, 0},\
    {"arc_set_start_angle", luat_lv_arc_set_start_angle, 0},\
    {"arc_set_end_angle", luat_lv_arc_set_end_angle, 0},\
    {"arc_set_angles", luat_lv_arc_set_angles, 0},\
    {"arc_set_bg_start_angle", luat_lv_arc_set_bg_start_angle, 0},\
    {"arc_set_bg_end_angle", luat_lv_arc_set_bg_end_angle, 0},\
    {"arc_set_bg_angles", luat_lv_arc_set_bg_angles, 0},\
    {"arc_set_rotation", luat_lv_arc_set_rotation, 0},\
    {"arc_set_mode", luat_lv_arc_set_mode, 0},\
    {"arc_set_value", luat_lv_arc_set_value, 0},\
    {"arc_set_range", luat_lv_arc_set_range, 0},\
    {"arc_set_change_rate", luat_lv_arc_set_change_rate, 0},\
    {"arc_get_angle_start", luat_lv_arc_get_angle_start, 0},\
    {"arc_get_angle_end", luat_lv_arc_get_angle_end, 0},\
    {"arc_get_bg_angle_start", luat_lv_arc_get_bg_angle_start, 0},\
    {"arc_get_bg_angle_end", luat_lv_arc_get_bg_angle_end, 0},\
    {"arc_get_value", luat_lv_arc_get_value, 0},\
    {"arc_get_min_value", luat_lv_arc_get_min_value, 0},\
    {"arc_get_max_value", luat_lv_arc_get_max_value, 0},\
    {"arc_get_mode", luat_lv_arc_get_mode, 0},\

// prefix lv_widgets bar
int luat_lv_bar_create(lua_State *L);
int luat_lv_bar_set_value(lua_State *L);
int luat_lv_bar_set_start_value(lua_State *L);
int luat_lv_bar_set_range(lua_State *L);
int luat_lv_bar_set_mode(lua_State *L);
int luat_lv_bar_get_value(lua_State *L);
int luat_lv_bar_get_start_value(lua_State *L);
int luat_lv_bar_get_min_value(lua_State *L);
int luat_lv_bar_get_max_value(lua_State *L);
int luat_lv_bar_get_mode(lua_State *L);

#define LUAT_LV_BAR_RLT     {"bar_create", luat_lv_bar_create, 0},\
    {"bar_set_value", luat_lv_bar_set_value, 0},\
    {"bar_set_start_value", luat_lv_bar_set_start_value, 0},\
    {"bar_set_range", luat_lv_bar_set_range, 0},\
    {"bar_set_mode", luat_lv_bar_set_mode, 0},\
    {"bar_get_value", luat_lv_bar_get_value, 0},\
    {"bar_get_start_value", luat_lv_bar_get_start_value, 0},\
    {"bar_get_min_value", luat_lv_bar_get_min_value, 0},\
    {"bar_get_max_value", luat_lv_bar_get_max_value, 0},\
    {"bar_get_mode", luat_lv_bar_get_mode, 0},\

// prefix lv_widgets btn
int luat_lv_btn_create(lua_State *L);

#define LUAT_LV_BTN_RLT     {"btn_create", luat_lv_btn_create, 0},\

// prefix lv_widgets btnmatrix
int luat_lv_btnmatrix_create(lua_State *L);
int luat_lv_btnmatrix_set_selected_btn(lua_State *L);
int luat_lv_btnmatrix_set_btn_ctrl(lua_State *L);
int luat_lv_btnmatrix_clear_btn_ctrl(lua_State *L);
int luat_lv_btnmatrix_set_btn_ctrl_all(lua_State *L);
int luat_lv_btnmatrix_clear_btn_ctrl_all(lua_State *L);
int luat_lv_btnmatrix_set_btn_width(lua_State *L);
int luat_lv_btnmatrix_set_one_checked(lua_State *L);
int luat_lv_btnmatrix_get_selected_btn(lua_State *L);
int luat_lv_btnmatrix_get_btn_text(lua_State *L);
int luat_lv_btnmatrix_has_btn_ctrl(lua_State *L);
int luat_lv_btnmatrix_get_one_checked(lua_State *L);

#define LUAT_LV_BTNMATRIX_RLT     {"btnmatrix_create", luat_lv_btnmatrix_create, 0},\
    {"btnmatrix_set_selected_btn", luat_lv_btnmatrix_set_selected_btn, 0},\
    {"btnmatrix_set_btn_ctrl", luat_lv_btnmatrix_set_btn_ctrl, 0},\
    {"btnmatrix_clear_btn_ctrl", luat_lv_btnmatrix_clear_btn_ctrl, 0},\
    {"btnmatrix_set_btn_ctrl_all", luat_lv_btnmatrix_set_btn_ctrl_all, 0},\
    {"btnmatrix_clear_btn_ctrl_all", luat_lv_btnmatrix_clear_btn_ctrl_all, 0},\
    {"btnmatrix_set_btn_width", luat_lv_btnmatrix_set_btn_width, 0},\
    {"btnmatrix_set_one_checked", luat_lv_btnmatrix_set_one_checked, 0},\
    {"btnmatrix_get_selected_btn", luat_lv_btnmatrix_get_selected_btn, 0},\
    {"btnmatrix_get_btn_text", luat_lv_btnmatrix_get_btn_text, 0},\
    {"btnmatrix_has_btn_ctrl", luat_lv_btnmatrix_has_btn_ctrl, 0},\
    {"btnmatrix_get_one_checked", luat_lv_btnmatrix_get_one_checked, 0},\

// prefix lv_widgets canvas
int luat_lv_canvas_create(lua_State *L);
int luat_lv_canvas_set_px_color(lua_State *L);
int luat_lv_canvas_set_px(lua_State *L);
int luat_lv_canvas_set_px_opa(lua_State *L);
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

#define LUAT_LV_CANVAS_RLT     {"canvas_create", luat_lv_canvas_create, 0},\
    {"canvas_set_px_color", luat_lv_canvas_set_px_color, 0},\
    {"canvas_set_px", luat_lv_canvas_set_px, 0},\
    {"canvas_set_px_opa", luat_lv_canvas_set_px_opa, 0},\
    {"canvas_set_palette", luat_lv_canvas_set_palette, 0},\
    {"canvas_get_px", luat_lv_canvas_get_px, 0},\
    {"canvas_get_img", luat_lv_canvas_get_img, 0},\
    {"canvas_copy_buf", luat_lv_canvas_copy_buf, 0},\
    {"canvas_transform", luat_lv_canvas_transform, 0},\
    {"canvas_blur_hor", luat_lv_canvas_blur_hor, 0},\
    {"canvas_blur_ver", luat_lv_canvas_blur_ver, 0},\
    {"canvas_fill_bg", luat_lv_canvas_fill_bg, 0},\
    {"canvas_draw_rect", luat_lv_canvas_draw_rect, 0},\
    {"canvas_draw_text", luat_lv_canvas_draw_text, 0},\
    {"canvas_draw_img", luat_lv_canvas_draw_img, 0},\
    {"canvas_draw_arc", luat_lv_canvas_draw_arc, 0},\

// prefix lv_widgets checkbox
int luat_lv_checkbox_create(lua_State *L);
int luat_lv_checkbox_set_text(lua_State *L);
int luat_lv_checkbox_set_text_static(lua_State *L);
int luat_lv_checkbox_get_text(lua_State *L);

#define LUAT_LV_CHECKBOX_RLT     {"checkbox_create", luat_lv_checkbox_create, 0},\
    {"checkbox_set_text", luat_lv_checkbox_set_text, 0},\
    {"checkbox_set_text_static", luat_lv_checkbox_set_text_static, 0},\
    {"checkbox_get_text", luat_lv_checkbox_get_text, 0},\

// prefix lv_widgets dropdown
int luat_lv_dropdown_create(lua_State *L);
int luat_lv_dropdown_set_text(lua_State *L);
int luat_lv_dropdown_set_options(lua_State *L);
int luat_lv_dropdown_set_options_static(lua_State *L);
int luat_lv_dropdown_add_option(lua_State *L);
int luat_lv_dropdown_clear_options(lua_State *L);
int luat_lv_dropdown_set_selected(lua_State *L);
int luat_lv_dropdown_set_dir(lua_State *L);
int luat_lv_dropdown_set_selected_highlight(lua_State *L);
int luat_lv_dropdown_get_list(lua_State *L);
int luat_lv_dropdown_get_text(lua_State *L);
int luat_lv_dropdown_get_options(lua_State *L);
int luat_lv_dropdown_get_selected(lua_State *L);
int luat_lv_dropdown_get_option_cnt(lua_State *L);
int luat_lv_dropdown_get_symbol(lua_State *L);
int luat_lv_dropdown_get_selected_highlight(lua_State *L);
int luat_lv_dropdown_get_dir(lua_State *L);
int luat_lv_dropdown_open(lua_State *L);
int luat_lv_dropdown_close(lua_State *L);

#define LUAT_LV_DROPDOWN_RLT     {"dropdown_create", luat_lv_dropdown_create, 0},\
    {"dropdown_set_text", luat_lv_dropdown_set_text, 0},\
    {"dropdown_set_options", luat_lv_dropdown_set_options, 0},\
    {"dropdown_set_options_static", luat_lv_dropdown_set_options_static, 0},\
    {"dropdown_add_option", luat_lv_dropdown_add_option, 0},\
    {"dropdown_clear_options", luat_lv_dropdown_clear_options, 0},\
    {"dropdown_set_selected", luat_lv_dropdown_set_selected, 0},\
    {"dropdown_set_dir", luat_lv_dropdown_set_dir, 0},\
    {"dropdown_set_selected_highlight", luat_lv_dropdown_set_selected_highlight, 0},\
    {"dropdown_get_list", luat_lv_dropdown_get_list, 0},\
    {"dropdown_get_text", luat_lv_dropdown_get_text, 0},\
    {"dropdown_get_options", luat_lv_dropdown_get_options, 0},\
    {"dropdown_get_selected", luat_lv_dropdown_get_selected, 0},\
    {"dropdown_get_option_cnt", luat_lv_dropdown_get_option_cnt, 0},\
    {"dropdown_get_symbol", luat_lv_dropdown_get_symbol, 0},\
    {"dropdown_get_selected_highlight", luat_lv_dropdown_get_selected_highlight, 0},\
    {"dropdown_get_dir", luat_lv_dropdown_get_dir, 0},\
    {"dropdown_open", luat_lv_dropdown_open, 0},\
    {"dropdown_close", luat_lv_dropdown_close, 0},\

// prefix lv_widgets img
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
int luat_lv_img_cache_set_size(lua_State *L);
int luat_lv_img_cache_invalidate_src(lua_State *L);
int luat_lv_img_src_get_type(lua_State *L);
int luat_lv_img_cf_get_px_size(lua_State *L);
int luat_lv_img_cf_is_chroma_keyed(lua_State *L);
int luat_lv_img_cf_has_alpha(lua_State *L);
int luat_lv_img_create(lua_State *L);
int luat_lv_img_set_offset_x(lua_State *L);
int luat_lv_img_set_offset_y(lua_State *L);
int luat_lv_img_set_angle(lua_State *L);
int luat_lv_img_set_pivot(lua_State *L);
int luat_lv_img_set_zoom(lua_State *L);
int luat_lv_img_set_antialias(lua_State *L);
int luat_lv_img_set_size_mode(lua_State *L);
int luat_lv_img_get_src(lua_State *L);
int luat_lv_img_get_offset_x(lua_State *L);
int luat_lv_img_get_offset_y(lua_State *L);
int luat_lv_img_get_angle(lua_State *L);
int luat_lv_img_get_pivot(lua_State *L);
int luat_lv_img_get_zoom(lua_State *L);
int luat_lv_img_get_antialias(lua_State *L);
int luat_lv_img_get_size_mode(lua_State *L);

#define LUAT_LV_IMG_RLT     {"img_buf_alloc", luat_lv_img_buf_alloc, 0},\
    {"img_buf_get_px_color", luat_lv_img_buf_get_px_color, 0},\
    {"img_buf_get_px_alpha", luat_lv_img_buf_get_px_alpha, 0},\
    {"img_buf_set_px_color", luat_lv_img_buf_set_px_color, 0},\
    {"img_buf_set_px_alpha", luat_lv_img_buf_set_px_alpha, 0},\
    {"img_buf_set_palette", luat_lv_img_buf_set_palette, 0},\
    {"img_buf_free", luat_lv_img_buf_free, 0},\
    {"img_buf_get_img_size", luat_lv_img_buf_get_img_size, 0},\
    {"img_decoder_get_info", luat_lv_img_decoder_get_info, 0},\
    {"img_decoder_open", luat_lv_img_decoder_open, 0},\
    {"img_decoder_read_line", luat_lv_img_decoder_read_line, 0},\
    {"img_decoder_close", luat_lv_img_decoder_close, 0},\
    {"img_decoder_create", luat_lv_img_decoder_create, 0},\
    {"img_decoder_delete", luat_lv_img_decoder_delete, 0},\
    {"img_decoder_built_in_info", luat_lv_img_decoder_built_in_info, 0},\
    {"img_decoder_built_in_open", luat_lv_img_decoder_built_in_open, 0},\
    {"img_decoder_built_in_read_line", luat_lv_img_decoder_built_in_read_line, 0},\
    {"img_decoder_built_in_close", luat_lv_img_decoder_built_in_close, 0},\
    {"img_cache_set_size", luat_lv_img_cache_set_size, 0},\
    {"img_cache_invalidate_src", luat_lv_img_cache_invalidate_src, 0},\
    {"img_src_get_type", luat_lv_img_src_get_type, 0},\
    {"img_cf_get_px_size", luat_lv_img_cf_get_px_size, 0},\
    {"img_cf_is_chroma_keyed", luat_lv_img_cf_is_chroma_keyed, 0},\
    {"img_cf_has_alpha", luat_lv_img_cf_has_alpha, 0},\
    {"img_create", luat_lv_img_create, 0},\
    {"img_set_offset_x", luat_lv_img_set_offset_x, 0},\
    {"img_set_offset_y", luat_lv_img_set_offset_y, 0},\
    {"img_set_angle", luat_lv_img_set_angle, 0},\
    {"img_set_pivot", luat_lv_img_set_pivot, 0},\
    {"img_set_zoom", luat_lv_img_set_zoom, 0},\
    {"img_set_antialias", luat_lv_img_set_antialias, 0},\
    {"img_set_size_mode", luat_lv_img_set_size_mode, 0},\
    {"img_get_src", luat_lv_img_get_src, 0},\
    {"img_get_offset_x", luat_lv_img_get_offset_x, 0},\
    {"img_get_offset_y", luat_lv_img_get_offset_y, 0},\
    {"img_get_angle", luat_lv_img_get_angle, 0},\
    {"img_get_pivot", luat_lv_img_get_pivot, 0},\
    {"img_get_zoom", luat_lv_img_get_zoom, 0},\
    {"img_get_antialias", luat_lv_img_get_antialias, 0},\
    {"img_get_size_mode", luat_lv_img_get_size_mode, 0},\

// prefix lv_widgets label
int luat_lv_label_create(lua_State *L);
int luat_lv_label_set_text(lua_State *L);
int luat_lv_label_set_text_static(lua_State *L);
int luat_lv_label_set_long_mode(lua_State *L);
int luat_lv_label_set_recolor(lua_State *L);
int luat_lv_label_set_text_sel_start(lua_State *L);
int luat_lv_label_set_text_sel_end(lua_State *L);
int luat_lv_label_get_text(lua_State *L);
int luat_lv_label_get_long_mode(lua_State *L);
int luat_lv_label_get_recolor(lua_State *L);
int luat_lv_label_get_letter_pos(lua_State *L);
int luat_lv_label_get_letter_on(lua_State *L);
int luat_lv_label_is_char_under_pos(lua_State *L);
int luat_lv_label_get_text_selection_start(lua_State *L);
int luat_lv_label_get_text_selection_end(lua_State *L);
int luat_lv_label_ins_text(lua_State *L);
int luat_lv_label_cut_text(lua_State *L);

#define LUAT_LV_LABEL_RLT     {"label_create", luat_lv_label_create, 0},\
    {"label_set_text", luat_lv_label_set_text, 0},\
    {"label_set_text_static", luat_lv_label_set_text_static, 0},\
    {"label_set_long_mode", luat_lv_label_set_long_mode, 0},\
    {"label_set_recolor", luat_lv_label_set_recolor, 0},\
    {"label_set_text_sel_start", luat_lv_label_set_text_sel_start, 0},\
    {"label_set_text_sel_end", luat_lv_label_set_text_sel_end, 0},\
    {"label_get_text", luat_lv_label_get_text, 0},\
    {"label_get_long_mode", luat_lv_label_get_long_mode, 0},\
    {"label_get_recolor", luat_lv_label_get_recolor, 0},\
    {"label_get_letter_pos", luat_lv_label_get_letter_pos, 0},\
    {"label_get_letter_on", luat_lv_label_get_letter_on, 0},\
    {"label_is_char_under_pos", luat_lv_label_is_char_under_pos, 0},\
    {"label_get_text_selection_start", luat_lv_label_get_text_selection_start, 0},\
    {"label_get_text_selection_end", luat_lv_label_get_text_selection_end, 0},\
    {"label_ins_text", luat_lv_label_ins_text, 0},\
    {"label_cut_text", luat_lv_label_cut_text, 0},\

// prefix lv_widgets line
int luat_lv_line_create(lua_State *L);
int luat_lv_line_set_y_invert(lua_State *L);
int luat_lv_line_get_y_invert(lua_State *L);

#define LUAT_LV_LINE_RLT     {"line_create", luat_lv_line_create, 0},\
    {"line_set_y_invert", luat_lv_line_set_y_invert, 0},\
    {"line_get_y_invert", luat_lv_line_get_y_invert, 0},\

// prefix lv_widgets roller
int luat_lv_roller_create(lua_State *L);
int luat_lv_roller_set_options(lua_State *L);
int luat_lv_roller_set_selected(lua_State *L);
int luat_lv_roller_set_visible_row_count(lua_State *L);
int luat_lv_roller_get_selected(lua_State *L);
int luat_lv_roller_get_options(lua_State *L);
int luat_lv_roller_get_option_cnt(lua_State *L);

#define LUAT_LV_ROLLER_RLT     {"roller_create", luat_lv_roller_create, 0},\
    {"roller_set_options", luat_lv_roller_set_options, 0},\
    {"roller_set_selected", luat_lv_roller_set_selected, 0},\
    {"roller_set_visible_row_count", luat_lv_roller_set_visible_row_count, 0},\
    {"roller_get_selected", luat_lv_roller_get_selected, 0},\
    {"roller_get_options", luat_lv_roller_get_options, 0},\
    {"roller_get_option_cnt", luat_lv_roller_get_option_cnt, 0},\

// prefix lv_widgets slider
int luat_lv_slider_create(lua_State *L);
int luat_lv_slider_set_value(lua_State *L);
int luat_lv_slider_set_left_value(lua_State *L);
int luat_lv_slider_set_range(lua_State *L);
int luat_lv_slider_set_mode(lua_State *L);
int luat_lv_slider_get_value(lua_State *L);
int luat_lv_slider_get_left_value(lua_State *L);
int luat_lv_slider_get_min_value(lua_State *L);
int luat_lv_slider_get_max_value(lua_State *L);
int luat_lv_slider_is_dragged(lua_State *L);
int luat_lv_slider_get_mode(lua_State *L);

#define LUAT_LV_SLIDER_RLT     {"slider_create", luat_lv_slider_create, 0},\
    {"slider_set_value", luat_lv_slider_set_value, 0},\
    {"slider_set_left_value", luat_lv_slider_set_left_value, 0},\
    {"slider_set_range", luat_lv_slider_set_range, 0},\
    {"slider_set_mode", luat_lv_slider_set_mode, 0},\
    {"slider_get_value", luat_lv_slider_get_value, 0},\
    {"slider_get_left_value", luat_lv_slider_get_left_value, 0},\
    {"slider_get_min_value", luat_lv_slider_get_min_value, 0},\
    {"slider_get_max_value", luat_lv_slider_get_max_value, 0},\
    {"slider_is_dragged", luat_lv_slider_is_dragged, 0},\
    {"slider_get_mode", luat_lv_slider_get_mode, 0},\

// prefix lv_widgets switch
int luat_lv_switch_create(lua_State *L);

#define LUAT_LV_SWITCH_RLT     {"switch_create", luat_lv_switch_create, 0},\

// prefix lv_widgets table
int luat_lv_table_create(lua_State *L);
int luat_lv_table_set_cell_value(lua_State *L);
int luat_lv_table_set_row_cnt(lua_State *L);
int luat_lv_table_set_col_cnt(lua_State *L);
int luat_lv_table_set_col_width(lua_State *L);
int luat_lv_table_add_cell_ctrl(lua_State *L);
int luat_lv_table_clear_cell_ctrl(lua_State *L);
int luat_lv_table_get_cell_value(lua_State *L);
int luat_lv_table_get_row_cnt(lua_State *L);
int luat_lv_table_get_col_cnt(lua_State *L);
int luat_lv_table_get_col_width(lua_State *L);
int luat_lv_table_has_cell_ctrl(lua_State *L);
int luat_lv_table_get_selected_cell(lua_State *L);

#define LUAT_LV_TABLE_RLT     {"table_create", luat_lv_table_create, 0},\
    {"table_set_cell_value", luat_lv_table_set_cell_value, 0},\
    {"table_set_row_cnt", luat_lv_table_set_row_cnt, 0},\
    {"table_set_col_cnt", luat_lv_table_set_col_cnt, 0},\
    {"table_set_col_width", luat_lv_table_set_col_width, 0},\
    {"table_add_cell_ctrl", luat_lv_table_add_cell_ctrl, 0},\
    {"table_clear_cell_ctrl", luat_lv_table_clear_cell_ctrl, 0},\
    {"table_get_cell_value", luat_lv_table_get_cell_value, 0},\
    {"table_get_row_cnt", luat_lv_table_get_row_cnt, 0},\
    {"table_get_col_cnt", luat_lv_table_get_col_cnt, 0},\
    {"table_get_col_width", luat_lv_table_get_col_width, 0},\
    {"table_has_cell_ctrl", luat_lv_table_has_cell_ctrl, 0},\
    {"table_get_selected_cell", luat_lv_table_get_selected_cell, 0},\

// prefix lv_widgets textarea
int luat_lv_textarea_create(lua_State *L);
int luat_lv_textarea_add_char(lua_State *L);
int luat_lv_textarea_add_text(lua_State *L);
int luat_lv_textarea_del_char(lua_State *L);
int luat_lv_textarea_del_char_forward(lua_State *L);
int luat_lv_textarea_set_text(lua_State *L);
int luat_lv_textarea_set_placeholder_text(lua_State *L);
int luat_lv_textarea_set_cursor_pos(lua_State *L);
int luat_lv_textarea_set_cursor_click_pos(lua_State *L);
int luat_lv_textarea_set_password_mode(lua_State *L);
int luat_lv_textarea_set_one_line(lua_State *L);
int luat_lv_textarea_set_accepted_chars(lua_State *L);
int luat_lv_textarea_set_max_length(lua_State *L);
int luat_lv_textarea_set_insert_replace(lua_State *L);
int luat_lv_textarea_set_text_selection(lua_State *L);
int luat_lv_textarea_set_password_show_time(lua_State *L);
int luat_lv_textarea_set_align(lua_State *L);
int luat_lv_textarea_get_text(lua_State *L);
int luat_lv_textarea_get_placeholder_text(lua_State *L);
int luat_lv_textarea_get_label(lua_State *L);
int luat_lv_textarea_get_cursor_pos(lua_State *L);
int luat_lv_textarea_get_cursor_click_pos(lua_State *L);
int luat_lv_textarea_get_password_mode(lua_State *L);
int luat_lv_textarea_get_one_line(lua_State *L);
int luat_lv_textarea_get_accepted_chars(lua_State *L);
int luat_lv_textarea_get_max_length(lua_State *L);
int luat_lv_textarea_text_is_selected(lua_State *L);
int luat_lv_textarea_get_text_selection(lua_State *L);
int luat_lv_textarea_get_password_show_time(lua_State *L);
int luat_lv_textarea_clear_selection(lua_State *L);
int luat_lv_textarea_cursor_right(lua_State *L);
int luat_lv_textarea_cursor_left(lua_State *L);
int luat_lv_textarea_cursor_down(lua_State *L);
int luat_lv_textarea_cursor_up(lua_State *L);

#define LUAT_LV_TEXTAREA_RLT     {"textarea_create", luat_lv_textarea_create, 0},\
    {"textarea_add_char", luat_lv_textarea_add_char, 0},\
    {"textarea_add_text", luat_lv_textarea_add_text, 0},\
    {"textarea_del_char", luat_lv_textarea_del_char, 0},\
    {"textarea_del_char_forward", luat_lv_textarea_del_char_forward, 0},\
    {"textarea_set_text", luat_lv_textarea_set_text, 0},\
    {"textarea_set_placeholder_text", luat_lv_textarea_set_placeholder_text, 0},\
    {"textarea_set_cursor_pos", luat_lv_textarea_set_cursor_pos, 0},\
    {"textarea_set_cursor_click_pos", luat_lv_textarea_set_cursor_click_pos, 0},\
    {"textarea_set_password_mode", luat_lv_textarea_set_password_mode, 0},\
    {"textarea_set_one_line", luat_lv_textarea_set_one_line, 0},\
    {"textarea_set_accepted_chars", luat_lv_textarea_set_accepted_chars, 0},\
    {"textarea_set_max_length", luat_lv_textarea_set_max_length, 0},\
    {"textarea_set_insert_replace", luat_lv_textarea_set_insert_replace, 0},\
    {"textarea_set_text_selection", luat_lv_textarea_set_text_selection, 0},\
    {"textarea_set_password_show_time", luat_lv_textarea_set_password_show_time, 0},\
    {"textarea_set_align", luat_lv_textarea_set_align, 0},\
    {"textarea_get_text", luat_lv_textarea_get_text, 0},\
    {"textarea_get_placeholder_text", luat_lv_textarea_get_placeholder_text, 0},\
    {"textarea_get_label", luat_lv_textarea_get_label, 0},\
    {"textarea_get_cursor_pos", luat_lv_textarea_get_cursor_pos, 0},\
    {"textarea_get_cursor_click_pos", luat_lv_textarea_get_cursor_click_pos, 0},\
    {"textarea_get_password_mode", luat_lv_textarea_get_password_mode, 0},\
    {"textarea_get_one_line", luat_lv_textarea_get_one_line, 0},\
    {"textarea_get_accepted_chars", luat_lv_textarea_get_accepted_chars, 0},\
    {"textarea_get_max_length", luat_lv_textarea_get_max_length, 0},\
    {"textarea_text_is_selected", luat_lv_textarea_text_is_selected, 0},\
    {"textarea_get_text_selection", luat_lv_textarea_get_text_selection, 0},\
    {"textarea_get_password_show_time", luat_lv_textarea_get_password_show_time, 0},\
    {"textarea_clear_selection", luat_lv_textarea_clear_selection, 0},\
    {"textarea_cursor_right", luat_lv_textarea_cursor_right, 0},\
    {"textarea_cursor_left", luat_lv_textarea_cursor_left, 0},\
    {"textarea_cursor_down", luat_lv_textarea_cursor_down, 0},\
    {"textarea_cursor_up", luat_lv_textarea_cursor_up, 0},\

// prefix lv_widgets animimg
int luat_lv_animimg_create(lua_State *L);
int luat_lv_animimg_start(lua_State *L);
int luat_lv_animimg_set_duration(lua_State *L);
int luat_lv_animimg_set_repeat_count(lua_State *L);

#define LUAT_LV_ANIMIMG_RLT     {"animimg_create", luat_lv_animimg_create, 0},\
    {"animimg_start", luat_lv_animimg_start, 0},\
    {"animimg_set_duration", luat_lv_animimg_set_duration, 0},\
    {"animimg_set_repeat_count", luat_lv_animimg_set_repeat_count, 0},\

// prefix lv_widgets calendar
int luat_lv_calendar_create(lua_State *L);
int luat_lv_calendar_set_today_date(lua_State *L);
int luat_lv_calendar_set_showed_date(lua_State *L);
int luat_lv_calendar_get_btnmatrix(lua_State *L);
int luat_lv_calendar_get_today_date(lua_State *L);
int luat_lv_calendar_get_showed_date(lua_State *L);
int luat_lv_calendar_get_highlighted_dates(lua_State *L);
int luat_lv_calendar_get_highlighted_dates_num(lua_State *L);
int luat_lv_calendar_get_pressed_date(lua_State *L);

#define LUAT_LV_CALENDAR_RLT     {"calendar_create", luat_lv_calendar_create, 0},\
    {"calendar_set_today_date", luat_lv_calendar_set_today_date, 0},\
    {"calendar_set_showed_date", luat_lv_calendar_set_showed_date, 0},\
    {"calendar_get_btnmatrix", luat_lv_calendar_get_btnmatrix, 0},\
    {"calendar_get_today_date", luat_lv_calendar_get_today_date, 0},\
    {"calendar_get_showed_date", luat_lv_calendar_get_showed_date, 0},\
    {"calendar_get_highlighted_dates", luat_lv_calendar_get_highlighted_dates, 0},\
    {"calendar_get_highlighted_dates_num", luat_lv_calendar_get_highlighted_dates_num, 0},\
    {"calendar_get_pressed_date", luat_lv_calendar_get_pressed_date, 0},\

// prefix lv_widgets calendar_header_arrow
int luat_lv_calendar_header_arrow_create(lua_State *L);

#define LUAT_LV_CALENDAR_HEADER_ARROW_RLT     {"calendar_header_arrow_create", luat_lv_calendar_header_arrow_create, 0},\

// prefix lv_widgets calendar_header_dropdown
int luat_lv_calendar_header_dropdown_create(lua_State *L);

#define LUAT_LV_CALENDAR_HEADER_DROPDOWN_RLT     {"calendar_header_dropdown_create", luat_lv_calendar_header_dropdown_create, 0},\

// prefix lv_widgets chart
int luat_lv_chart_create(lua_State *L);
int luat_lv_chart_set_type(lua_State *L);
int luat_lv_chart_set_point_count(lua_State *L);
int luat_lv_chart_set_range(lua_State *L);
int luat_lv_chart_set_update_mode(lua_State *L);
int luat_lv_chart_set_div_line_count(lua_State *L);
int luat_lv_chart_set_zoom_x(lua_State *L);
int luat_lv_chart_set_zoom_y(lua_State *L);
int luat_lv_chart_get_zoom_x(lua_State *L);
int luat_lv_chart_get_zoom_y(lua_State *L);
int luat_lv_chart_set_axis_tick(lua_State *L);
int luat_lv_chart_get_type(lua_State *L);
int luat_lv_chart_get_point_count(lua_State *L);
int luat_lv_chart_get_x_start_point(lua_State *L);
int luat_lv_chart_get_point_pos_by_id(lua_State *L);
int luat_lv_chart_refresh(lua_State *L);
int luat_lv_chart_add_series(lua_State *L);
int luat_lv_chart_remove_series(lua_State *L);
int luat_lv_chart_hide_series(lua_State *L);
int luat_lv_chart_set_series_color(lua_State *L);
int luat_lv_chart_set_x_start_point(lua_State *L);
int luat_lv_chart_get_series_next(lua_State *L);
int luat_lv_chart_add_cursor(lua_State *L);
int luat_lv_chart_set_cursor_pos(lua_State *L);
int luat_lv_chart_set_cursor_point(lua_State *L);
int luat_lv_chart_get_cursor_point(lua_State *L);
int luat_lv_chart_set_all_value(lua_State *L);
int luat_lv_chart_set_next_value(lua_State *L);
int luat_lv_chart_set_next_value2(lua_State *L);
int luat_lv_chart_set_value_by_id(lua_State *L);
int luat_lv_chart_set_value_by_id2(lua_State *L);
int luat_lv_chart_get_y_array(lua_State *L);
int luat_lv_chart_get_x_array(lua_State *L);
int luat_lv_chart_get_pressed_point(lua_State *L);

#define LUAT_LV_CHART_RLT     {"chart_create", luat_lv_chart_create, 0},\
    {"chart_set_type", luat_lv_chart_set_type, 0},\
    {"chart_set_point_count", luat_lv_chart_set_point_count, 0},\
    {"chart_set_range", luat_lv_chart_set_range, 0},\
    {"chart_set_update_mode", luat_lv_chart_set_update_mode, 0},\
    {"chart_set_div_line_count", luat_lv_chart_set_div_line_count, 0},\
    {"chart_set_zoom_x", luat_lv_chart_set_zoom_x, 0},\
    {"chart_set_zoom_y", luat_lv_chart_set_zoom_y, 0},\
    {"chart_get_zoom_x", luat_lv_chart_get_zoom_x, 0},\
    {"chart_get_zoom_y", luat_lv_chart_get_zoom_y, 0},\
    {"chart_set_axis_tick", luat_lv_chart_set_axis_tick, 0},\
    {"chart_get_type", luat_lv_chart_get_type, 0},\
    {"chart_get_point_count", luat_lv_chart_get_point_count, 0},\
    {"chart_get_x_start_point", luat_lv_chart_get_x_start_point, 0},\
    {"chart_get_point_pos_by_id", luat_lv_chart_get_point_pos_by_id, 0},\
    {"chart_refresh", luat_lv_chart_refresh, 0},\
    {"chart_add_series", luat_lv_chart_add_series, 0},\
    {"chart_remove_series", luat_lv_chart_remove_series, 0},\
    {"chart_hide_series", luat_lv_chart_hide_series, 0},\
    {"chart_set_series_color", luat_lv_chart_set_series_color, 0},\
    {"chart_set_x_start_point", luat_lv_chart_set_x_start_point, 0},\
    {"chart_get_series_next", luat_lv_chart_get_series_next, 0},\
    {"chart_add_cursor", luat_lv_chart_add_cursor, 0},\
    {"chart_set_cursor_pos", luat_lv_chart_set_cursor_pos, 0},\
    {"chart_set_cursor_point", luat_lv_chart_set_cursor_point, 0},\
    {"chart_get_cursor_point", luat_lv_chart_get_cursor_point, 0},\
    {"chart_set_all_value", luat_lv_chart_set_all_value, 0},\
    {"chart_set_next_value", luat_lv_chart_set_next_value, 0},\
    {"chart_set_next_value2", luat_lv_chart_set_next_value2, 0},\
    {"chart_set_value_by_id", luat_lv_chart_set_value_by_id, 0},\
    {"chart_set_value_by_id2", luat_lv_chart_set_value_by_id2, 0},\
    {"chart_get_y_array", luat_lv_chart_get_y_array, 0},\
    {"chart_get_x_array", luat_lv_chart_get_x_array, 0},\
    {"chart_get_pressed_point", luat_lv_chart_get_pressed_point, 0},\

// prefix lv_widgets colorwheel
int luat_lv_colorwheel_create(lua_State *L);
int luat_lv_colorwheel_set_hsv(lua_State *L);
int luat_lv_colorwheel_set_rgb(lua_State *L);
int luat_lv_colorwheel_set_mode(lua_State *L);
int luat_lv_colorwheel_set_mode_fixed(lua_State *L);
int luat_lv_colorwheel_get_hsv(lua_State *L);
int luat_lv_colorwheel_get_rgb(lua_State *L);
int luat_lv_colorwheel_get_color_mode(lua_State *L);
int luat_lv_colorwheel_get_color_mode_fixed(lua_State *L);

#define LUAT_LV_COLORWHEEL_RLT     {"colorwheel_create", luat_lv_colorwheel_create, 0},\
    {"colorwheel_set_hsv", luat_lv_colorwheel_set_hsv, 0},\
    {"colorwheel_set_rgb", luat_lv_colorwheel_set_rgb, 0},\
    {"colorwheel_set_mode", luat_lv_colorwheel_set_mode, 0},\
    {"colorwheel_set_mode_fixed", luat_lv_colorwheel_set_mode_fixed, 0},\
    {"colorwheel_get_hsv", luat_lv_colorwheel_get_hsv, 0},\
    {"colorwheel_get_rgb", luat_lv_colorwheel_get_rgb, 0},\
    {"colorwheel_get_color_mode", luat_lv_colorwheel_get_color_mode, 0},\
    {"colorwheel_get_color_mode_fixed", luat_lv_colorwheel_get_color_mode_fixed, 0},\

// prefix lv_widgets imgbtn
int luat_lv_imgbtn_create(lua_State *L);
int luat_lv_imgbtn_set_state(lua_State *L);
int luat_lv_imgbtn_get_src_left(lua_State *L);
int luat_lv_imgbtn_get_src_middle(lua_State *L);
int luat_lv_imgbtn_get_src_right(lua_State *L);

#define LUAT_LV_IMGBTN_RLT     {"imgbtn_create", luat_lv_imgbtn_create, 0},\
    {"imgbtn_set_state", luat_lv_imgbtn_set_state, 0},\
    {"imgbtn_get_src_left", luat_lv_imgbtn_get_src_left, 0},\
    {"imgbtn_get_src_middle", luat_lv_imgbtn_get_src_middle, 0},\
    {"imgbtn_get_src_right", luat_lv_imgbtn_get_src_right, 0},\

// prefix lv_widgets keyboard
int luat_lv_keyboard_create(lua_State *L);
int luat_lv_keyboard_set_textarea(lua_State *L);
int luat_lv_keyboard_set_mode(lua_State *L);
int luat_lv_keyboard_set_popovers(lua_State *L);
int luat_lv_keyboard_get_textarea(lua_State *L);
int luat_lv_keyboard_get_mode(lua_State *L);

#define LUAT_LV_KEYBOARD_RLT     {"keyboard_create", luat_lv_keyboard_create, 0},\
    {"keyboard_set_textarea", luat_lv_keyboard_set_textarea, 0},\
    {"keyboard_set_mode", luat_lv_keyboard_set_mode, 0},\
    {"keyboard_set_popovers", luat_lv_keyboard_set_popovers, 0},\
    {"keyboard_get_textarea", luat_lv_keyboard_get_textarea, 0},\
    {"keyboard_get_mode", luat_lv_keyboard_get_mode, 0},\

// prefix lv_widgets led
int luat_lv_led_create(lua_State *L);
int luat_lv_led_set_color(lua_State *L);
int luat_lv_led_set_brightness(lua_State *L);
int luat_lv_led_on(lua_State *L);
int luat_lv_led_off(lua_State *L);
int luat_lv_led_toggle(lua_State *L);
int luat_lv_led_get_brightness(lua_State *L);

#define LUAT_LV_LED_RLT     {"led_create", luat_lv_led_create, 0},\
    {"led_set_color", luat_lv_led_set_color, 0},\
    {"led_set_brightness", luat_lv_led_set_brightness, 0},\
    {"led_on", luat_lv_led_on, 0},\
    {"led_off", luat_lv_led_off, 0},\
    {"led_toggle", luat_lv_led_toggle, 0},\
    {"led_get_brightness", luat_lv_led_get_brightness, 0},\

// prefix lv_widgets list
int luat_lv_list_create(lua_State *L);
int luat_lv_list_add_text(lua_State *L);
int luat_lv_list_add_btn(lua_State *L);
int luat_lv_list_get_btn_text(lua_State *L);

#define LUAT_LV_LIST_RLT     {"list_create", luat_lv_list_create, 0},\
    {"list_add_text", luat_lv_list_add_text, 0},\
    {"list_add_btn", luat_lv_list_add_btn, 0},\
    {"list_get_btn_text", luat_lv_list_get_btn_text, 0},\

// prefix lv_widgets meter
int luat_lv_meter_create(lua_State *L);
int luat_lv_meter_add_scale(lua_State *L);
int luat_lv_meter_set_scale_ticks(lua_State *L);
int luat_lv_meter_set_scale_major_ticks(lua_State *L);
int luat_lv_meter_set_scale_range(lua_State *L);
int luat_lv_meter_add_needle_line(lua_State *L);
int luat_lv_meter_add_needle_img(lua_State *L);
int luat_lv_meter_add_arc(lua_State *L);
int luat_lv_meter_add_scale_lines(lua_State *L);
int luat_lv_meter_set_indicator_value(lua_State *L);
int luat_lv_meter_set_indicator_start_value(lua_State *L);
int luat_lv_meter_set_indicator_end_value(lua_State *L);

#define LUAT_LV_METER_RLT     {"meter_create", luat_lv_meter_create, 0},\
    {"meter_add_scale", luat_lv_meter_add_scale, 0},\
    {"meter_set_scale_ticks", luat_lv_meter_set_scale_ticks, 0},\
    {"meter_set_scale_major_ticks", luat_lv_meter_set_scale_major_ticks, 0},\
    {"meter_set_scale_range", luat_lv_meter_set_scale_range, 0},\
    {"meter_add_needle_line", luat_lv_meter_add_needle_line, 0},\
    {"meter_add_needle_img", luat_lv_meter_add_needle_img, 0},\
    {"meter_add_arc", luat_lv_meter_add_arc, 0},\
    {"meter_add_scale_lines", luat_lv_meter_add_scale_lines, 0},\
    {"meter_set_indicator_value", luat_lv_meter_set_indicator_value, 0},\
    {"meter_set_indicator_start_value", luat_lv_meter_set_indicator_start_value, 0},\
    {"meter_set_indicator_end_value", luat_lv_meter_set_indicator_end_value, 0},\

// prefix lv_widgets msgbox
int luat_lv_msgbox_get_title(lua_State *L);
int luat_lv_msgbox_get_close_btn(lua_State *L);
int luat_lv_msgbox_get_text(lua_State *L);
int luat_lv_msgbox_get_content(lua_State *L);
int luat_lv_msgbox_get_btns(lua_State *L);
int luat_lv_msgbox_get_active_btn(lua_State *L);
int luat_lv_msgbox_get_active_btn_text(lua_State *L);
int luat_lv_msgbox_close(lua_State *L);
int luat_lv_msgbox_close_async(lua_State *L);

#define LUAT_LV_MSGBOX_RLT     {"msgbox_get_title", luat_lv_msgbox_get_title, 0},\
    {"msgbox_get_close_btn", luat_lv_msgbox_get_close_btn, 0},\
    {"msgbox_get_text", luat_lv_msgbox_get_text, 0},\
    {"msgbox_get_content", luat_lv_msgbox_get_content, 0},\
    {"msgbox_get_btns", luat_lv_msgbox_get_btns, 0},\
    {"msgbox_get_active_btn", luat_lv_msgbox_get_active_btn, 0},\
    {"msgbox_get_active_btn_text", luat_lv_msgbox_get_active_btn_text, 0},\
    {"msgbox_close", luat_lv_msgbox_close, 0},\
    {"msgbox_close_async", luat_lv_msgbox_close_async, 0},\

// prefix lv_widgets span
int luat_lv_spangroup_create(lua_State *L);
int luat_lv_spangroup_new_span(lua_State *L);
int luat_lv_spangroup_del_span(lua_State *L);
int luat_lv_span_set_text(lua_State *L);
int luat_lv_span_set_text_static(lua_State *L);
int luat_lv_spangroup_set_align(lua_State *L);
int luat_lv_spangroup_set_overflow(lua_State *L);
int luat_lv_spangroup_set_indent(lua_State *L);
int luat_lv_spangroup_set_mode(lua_State *L);
int luat_lv_spangroup_get_child(lua_State *L);
int luat_lv_spangroup_get_child_cnt(lua_State *L);
int luat_lv_spangroup_get_align(lua_State *L);
int luat_lv_spangroup_get_overflow(lua_State *L);
int luat_lv_spangroup_get_indent(lua_State *L);
int luat_lv_spangroup_get_mode(lua_State *L);
int luat_lv_spangroup_get_max_line_h(lua_State *L);
int luat_lv_spangroup_get_expand_width(lua_State *L);
int luat_lv_spangroup_get_expand_height(lua_State *L);
int luat_lv_spangroup_refr_mode(lua_State *L);

#define LUAT_LV_SPAN_RLT     {"spangroup_create", luat_lv_spangroup_create, 0},\
    {"spangroup_new_span", luat_lv_spangroup_new_span, 0},\
    {"spangroup_del_span", luat_lv_spangroup_del_span, 0},\
    {"span_set_text", luat_lv_span_set_text, 0},\
    {"span_set_text_static", luat_lv_span_set_text_static, 0},\
    {"spangroup_set_align", luat_lv_spangroup_set_align, 0},\
    {"spangroup_set_overflow", luat_lv_spangroup_set_overflow, 0},\
    {"spangroup_set_indent", luat_lv_spangroup_set_indent, 0},\
    {"spangroup_set_mode", luat_lv_spangroup_set_mode, 0},\
    {"spangroup_get_child", luat_lv_spangroup_get_child, 0},\
    {"spangroup_get_child_cnt", luat_lv_spangroup_get_child_cnt, 0},\
    {"spangroup_get_align", luat_lv_spangroup_get_align, 0},\
    {"spangroup_get_overflow", luat_lv_spangroup_get_overflow, 0},\
    {"spangroup_get_indent", luat_lv_spangroup_get_indent, 0},\
    {"spangroup_get_mode", luat_lv_spangroup_get_mode, 0},\
    {"spangroup_get_max_line_h", luat_lv_spangroup_get_max_line_h, 0},\
    {"spangroup_get_expand_width", luat_lv_spangroup_get_expand_width, 0},\
    {"spangroup_get_expand_height", luat_lv_spangroup_get_expand_height, 0},\
    {"spangroup_refr_mode", luat_lv_spangroup_refr_mode, 0},\

// prefix lv_widgets spinbox
int luat_lv_spinbox_create(lua_State *L);
int luat_lv_spinbox_set_value(lua_State *L);
int luat_lv_spinbox_set_rollover(lua_State *L);
int luat_lv_spinbox_set_digit_format(lua_State *L);
int luat_lv_spinbox_set_step(lua_State *L);
int luat_lv_spinbox_set_range(lua_State *L);
int luat_lv_spinbox_set_pos(lua_State *L);
int luat_lv_spinbox_set_digit_step_direction(lua_State *L);
int luat_lv_spinbox_get_rollover(lua_State *L);
int luat_lv_spinbox_get_value(lua_State *L);
int luat_lv_spinbox_get_step(lua_State *L);
int luat_lv_spinbox_step_next(lua_State *L);
int luat_lv_spinbox_step_prev(lua_State *L);
int luat_lv_spinbox_increment(lua_State *L);
int luat_lv_spinbox_decrement(lua_State *L);

#define LUAT_LV_SPINBOX_RLT     {"spinbox_create", luat_lv_spinbox_create, 0},\
    {"spinbox_set_value", luat_lv_spinbox_set_value, 0},\
    {"spinbox_set_rollover", luat_lv_spinbox_set_rollover, 0},\
    {"spinbox_set_digit_format", luat_lv_spinbox_set_digit_format, 0},\
    {"spinbox_set_step", luat_lv_spinbox_set_step, 0},\
    {"spinbox_set_range", luat_lv_spinbox_set_range, 0},\
    {"spinbox_set_pos", luat_lv_spinbox_set_pos, 0},\
    {"spinbox_set_digit_step_direction", luat_lv_spinbox_set_digit_step_direction, 0},\
    {"spinbox_get_rollover", luat_lv_spinbox_get_rollover, 0},\
    {"spinbox_get_value", luat_lv_spinbox_get_value, 0},\
    {"spinbox_get_step", luat_lv_spinbox_get_step, 0},\
    {"spinbox_step_next", luat_lv_spinbox_step_next, 0},\
    {"spinbox_step_prev", luat_lv_spinbox_step_prev, 0},\
    {"spinbox_increment", luat_lv_spinbox_increment, 0},\
    {"spinbox_decrement", luat_lv_spinbox_decrement, 0},\

// prefix lv_widgets spinner
int luat_lv_spinner_create(lua_State *L);

#define LUAT_LV_SPINNER_RLT     {"spinner_create", luat_lv_spinner_create, 0},\

// prefix lv_widgets tabview
int luat_lv_tabview_create(lua_State *L);
int luat_lv_tabview_add_tab(lua_State *L);
int luat_lv_tabview_get_content(lua_State *L);
int luat_lv_tabview_get_tab_btns(lua_State *L);
int luat_lv_tabview_set_act(lua_State *L);
int luat_lv_tabview_get_tab_act(lua_State *L);

#define LUAT_LV_TABVIEW_RLT     {"tabview_create", luat_lv_tabview_create, 0},\
    {"tabview_add_tab", luat_lv_tabview_add_tab, 0},\
    {"tabview_get_content", luat_lv_tabview_get_content, 0},\
    {"tabview_get_tab_btns", luat_lv_tabview_get_tab_btns, 0},\
    {"tabview_set_act", luat_lv_tabview_set_act, 0},\
    {"tabview_get_tab_act", luat_lv_tabview_get_tab_act, 0},\

// prefix lv_widgets tileview
int luat_lv_tileview_create(lua_State *L);
int luat_lv_tileview_add_tile(lua_State *L);
int luat_lv_tileview_get_tile_act(lua_State *L);

#define LUAT_LV_TILEVIEW_RLT     {"tileview_create", luat_lv_tileview_create, 0},\
    {"tileview_add_tile", luat_lv_tileview_add_tile, 0},\
    {"tileview_get_tile_act", luat_lv_tileview_get_tile_act, 0},\

// prefix lv_widgets win
int luat_lv_win_create(lua_State *L);
int luat_lv_win_add_title(lua_State *L);
int luat_lv_win_get_header(lua_State *L);
int luat_lv_win_get_content(lua_State *L);

#define LUAT_LV_WIN_RLT     {"win_create", luat_lv_win_create, 0},\
    {"win_add_title", luat_lv_win_add_title, 0},\
    {"win_get_header", luat_lv_win_get_header, 0},\
    {"win_get_content", luat_lv_win_get_content, 0},\


// group lv_layouts
// prefix lv_layouts flex
int luat_lv_flex_init(lua_State *L);

#define LUAT_LV_FLEX_RLT     {"flex_init", luat_lv_flex_init, 0},\

// prefix lv_layouts grid
int luat_lv_grid_init(lua_State *L);
int luat_lv_grid_fr(lua_State *L);

#define LUAT_LV_GRID_RLT     {"grid_init", luat_lv_grid_init, 0},\
    {"grid_fr", luat_lv_grid_fr, 0},\


// group lv_themes
// prefix lv_themes theme_basic
int luat_lv_theme_basic_init(lua_State *L);

#define LUAT_LV_THEME_BASIC_RLT     {"theme_basic_init", luat_lv_theme_basic_init, 0},\

// prefix lv_themes theme_default
int luat_lv_theme_default_init(lua_State *L);
int luat_lv_theme_default_get(lua_State *L);
int luat_lv_theme_default_is_inited(lua_State *L);

#define LUAT_LV_THEME_DEFAULT_RLT     {"theme_default_init", luat_lv_theme_default_init, 0},\
    {"theme_default_get", luat_lv_theme_default_get, 0},\
    {"theme_default_is_inited", luat_lv_theme_default_is_inited, 0},\

// prefix lv_themes theme_mono
int luat_lv_theme_mono_init(lua_State *L);

#define LUAT_LV_THEME_MONO_RLT     {"theme_mono_init", luat_lv_theme_mono_init, 0},\

#endif
