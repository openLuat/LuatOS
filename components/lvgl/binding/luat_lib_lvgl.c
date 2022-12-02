/*
@module  lvgl
@summary LVGL图像库
@version 1.0
@date    2021.06.01
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_lvgl.h"

#define LUAT_LOG_TAG "lvgl"
#include "luat_log.h"

int luat_lv_obj_add_event_cb(lua_State *L);
int luat_lv_obj_remove_event_cb(lua_State *L);
int luat_lv_obj_remove_event_cb_with_user_data(lua_State *L);
int luat_lv_keyboard_def_event_cb(lua_State *L);
int luat_lv_anim_set_exec_cb(lua_State *L);
int luat_lv_anim_set_ready_cb(lua_State *L);

//---------------------------------
// 几个快捷方法
//---------------------------------

/*
获取当前活跃的screen对象
@api lvgl.scr_act()
@return 指针 screen指针
@usage
local scr = lvgl.scr_act()

*/
static int luat_lv_scr_act(lua_State *L) {
    lua_pushlightuserdata(L, lv_scr_act());
    return 1;
};

/*
获取layer_top
@api lvgl.layer_top()
@return 指针 layer指针
*/
static int luat_lv_layer_top(lua_State *L) {
    lua_pushlightuserdata(L, lv_layer_top());
    return 1;
};

/*
获取layer_sys
@api lvgl.layer_sys()
@return 指针 layer指针
*/
static int luat_lv_layer_sys(lua_State *L) {
    lua_pushlightuserdata(L, lv_layer_sys());
    return 1;
};

/*
载入指定的screen
@api lvgl.scr_load(scr)
@userdata screen指针
@usage
    local scr = lvgl.obj_create(nil, nil)
    local btn = lvgl.btn_create(scr)
    lvgl.obj_align(btn, lvgl.scr_act(), lvgl.ALIGN_CENTER, 0, 0)
    local label = lvgl.label_create(btn)
    lvgl.label_set_text(label, "LuatOS!")
    lvgl.scr_load(scr)
*/
static int luat_lv_scr_load(lua_State *L) {
    lv_scr_load(lua_touserdata(L, 1));
    return 0;
};

/*
设置主题
@api lvgl.theme_set_act(name)
@string 主题名称,可选值有 default/mono/empty/material_light/material_dark/material_no_transition/material_no_focus
@return bool 成功返回true,否则返回nil
@usage
-- 黑白主题
lvgl.theme_set_act("mono")
-- 空白主题
lvgl.theme_set_act("empty")
*/
static int l_lv_theme_set_act(lua_State *L) {
    const char* name = luaL_checkstring(L, 1);
    lv_theme_t * th = NULL;
    if (!strcmp("default", name)) {
        th = LV_THEME_DEFAULT_INIT(LV_THEME_DEFAULT_COLOR_PRIMARY, LV_THEME_DEFAULT_COLOR_SECONDARY,
                            LV_THEME_DEFAULT_FLAG,
                            LV_THEME_DEFAULT_FONT_SMALL, LV_THEME_DEFAULT_FONT_NORMAL, 
                            LV_THEME_DEFAULT_FONT_SUBTITLE, LV_THEME_DEFAULT_FONT_TITLE);
    }
#if LV_USE_THEME_MONO
    else if (!strcmp("mono", name)) {
        th = lv_theme_mono_init(LV_THEME_DEFAULT_COLOR_PRIMARY, LV_THEME_DEFAULT_COLOR_SECONDARY,
                            LV_THEME_DEFAULT_FLAG,
                            LV_THEME_DEFAULT_FONT_SMALL, LV_THEME_DEFAULT_FONT_NORMAL, 
                            LV_THEME_DEFAULT_FONT_SUBTITLE, LV_THEME_DEFAULT_FONT_TITLE);
    }
#endif
#if LV_USE_THEME_EMPTY
    else if (!strcmp("empty", name)) {
        th = lv_theme_empty_init(LV_THEME_DEFAULT_COLOR_PRIMARY, LV_THEME_DEFAULT_COLOR_SECONDARY,
                            LV_THEME_DEFAULT_FLAG,
                            LV_THEME_DEFAULT_FONT_SMALL, LV_THEME_DEFAULT_FONT_NORMAL, 
                            LV_THEME_DEFAULT_FONT_SUBTITLE, LV_THEME_DEFAULT_FONT_TITLE);
    }
#endif
#if LV_USE_THEME_MATERIAL
    else if (!strcmp("material_light", name)) {
        th = lv_theme_material_init(LV_THEME_DEFAULT_COLOR_PRIMARY, LV_THEME_DEFAULT_COLOR_SECONDARY,
                            LV_THEME_MATERIAL_FLAG_LIGHT,
                            LV_THEME_DEFAULT_FONT_SMALL, LV_THEME_DEFAULT_FONT_NORMAL, 
                            LV_THEME_DEFAULT_FONT_SUBTITLE, LV_THEME_DEFAULT_FONT_TITLE);
    }
    else if (!strcmp("material_dark", name)) {
        th = lv_theme_material_init(LV_THEME_DEFAULT_COLOR_PRIMARY, LV_THEME_DEFAULT_COLOR_SECONDARY,
                            LV_THEME_MATERIAL_FLAG_DARK,
                            LV_THEME_DEFAULT_FONT_SMALL, LV_THEME_DEFAULT_FONT_NORMAL, 
                            LV_THEME_DEFAULT_FONT_SUBTITLE, LV_THEME_DEFAULT_FONT_TITLE);
    }
    else if (!strcmp("material_no_transition", name)) {
        th = lv_theme_material_init(LV_THEME_DEFAULT_COLOR_PRIMARY, LV_THEME_DEFAULT_COLOR_SECONDARY,
                            LV_THEME_MATERIAL_FLAG_NO_TRANSITION,
                            LV_THEME_DEFAULT_FONT_SMALL, LV_THEME_DEFAULT_FONT_NORMAL, 
                            LV_THEME_DEFAULT_FONT_SUBTITLE, LV_THEME_DEFAULT_FONT_TITLE);
    }
    else if (!strcmp("material_no_focus", name)) {
        th = lv_theme_material_init(LV_THEME_DEFAULT_COLOR_PRIMARY, LV_THEME_DEFAULT_COLOR_SECONDARY,
                            LV_THEME_MATERIAL_FLAG_NO_FOCUS,
                            LV_THEME_DEFAULT_FONT_SMALL, LV_THEME_DEFAULT_FONT_NORMAL, 
                            LV_THEME_DEFAULT_FONT_SUBTITLE, LV_THEME_DEFAULT_FONT_TITLE);
    }
#endif
    else {
        LLOGW("no such theme %s", name);
        return 0;
    }
    LLOGD("theme_set_act %s", name);
    lv_theme_set_act(th);
    lua_pushboolean(L, 1);
    return 1;
}

/*
LVGL休眠控制，暂停/恢复刷新定时器，目前只有105和EC618可以用
@api lvgl.sleep(enable)
@boolean true暂停 false恢复
@usage
lvgl.sleep(true)		--暂停刷新，系统可以休眠
lvgl.sleep(false)		--恢复刷新，系统不休眠
*/
static int luat_lv_sleep(lua_State *L) {
#ifdef __LVGL_SLEEP_ENABLE__
    luat_lvgl_tick_sleep(lua_toboolean(L, 1));
#endif
    return 0;
};

// 函数注册
#include "rotable2.h"
static const rotable_Reg_t reg_lvgl[] = {

{"init",        ROREG_FUNC(luat_lv_init)},
{"scr_act",     ROREG_FUNC(luat_lv_scr_act)},
{"layer_top",   ROREG_FUNC(luat_lv_layer_top)},
{"layer_sys",   ROREG_FUNC(luat_lv_layer_sys)},
{"scr_load",    ROREG_FUNC(luat_lv_scr_load)},
{"theme_set_act", ROREG_FUNC(l_lv_theme_set_act)},
#ifdef __LVGL_SLEEP_ENABLE__
{"sleep",	ROREG_FUNC(luat_lv_sleep)},
#endif

// 兼容性命名
{"sw_create", ROREG_FUNC(luat_lv_switch_create)},

{"disp_get_hor_res", ROREG_FUNC(luat_lv_disp_get_hor_res)},
{"disp_get_ver_res", ROREG_FUNC(luat_lv_disp_get_ver_res)},
{"disp_get_antialiasing", ROREG_FUNC(luat_lv_disp_get_antialiasing)},
{"disp_get_dpi", ROREG_FUNC(luat_lv_disp_get_dpi)},
{"disp_get_size_category", ROREG_FUNC(luat_lv_disp_get_size_category)},
{"disp_set_rotation", ROREG_FUNC(luat_lv_disp_set_rotation)},
{"disp_get_rotation", ROREG_FUNC(luat_lv_disp_get_rotation)},
{"disp_set_bg_color", ROREG_FUNC(luat_lv_disp_set_bg_color)},
{"disp_set_bg_image", ROREG_FUNC(luat_lv_disp_set_bg_image)},
{"disp_set_bg_opa", ROREG_FUNC(luat_lv_disp_set_bg_opa)},
{"disp_get_inactive_time", ROREG_FUNC(luat_lv_disp_get_inactive_time)},
{"disp_trig_activity", ROREG_FUNC(luat_lv_disp_trig_activity)},

{"group_create", ROREG_FUNC(luat_lv_group_create)},
{"group_del", ROREG_FUNC(luat_lv_group_del)},
{"group_add_obj", ROREG_FUNC(luat_lv_group_add_obj)},
{"group_remove_obj", ROREG_FUNC(luat_lv_group_remove_obj)},
{"group_remove_all_objs", ROREG_FUNC(luat_lv_group_remove_all_objs)},
{"group_focus_obj", ROREG_FUNC(luat_lv_group_focus_obj)},
{"group_focus_next", ROREG_FUNC(luat_lv_group_focus_next)},
{"group_focus_prev", ROREG_FUNC(luat_lv_group_focus_prev)},
{"group_focus_freeze", ROREG_FUNC(luat_lv_group_focus_freeze)},
{"group_send_data", ROREG_FUNC(luat_lv_group_send_data)},
{"group_set_refocus_policy", ROREG_FUNC(luat_lv_group_set_refocus_policy)},
{"group_set_editing", ROREG_FUNC(luat_lv_group_set_editing)},
{"group_set_click_focus", ROREG_FUNC(luat_lv_group_set_click_focus)},
{"group_set_wrap", ROREG_FUNC(luat_lv_group_set_wrap)},
{"group_get_focused", ROREG_FUNC(luat_lv_group_get_focused)},
{"group_get_user_data", ROREG_FUNC(luat_lv_group_get_user_data)},
{"group_get_editing", ROREG_FUNC(luat_lv_group_get_editing)},
{"group_get_click_focus", ROREG_FUNC(luat_lv_group_get_click_focus)},
{"group_get_wrap", ROREG_FUNC(luat_lv_group_get_wrap)},

{"obj_create", ROREG_FUNC(luat_lv_obj_create)},
{"obj_del", ROREG_FUNC(luat_lv_obj_del)},
{"obj_del_async", ROREG_FUNC(luat_lv_obj_del_async)},
{"obj_clean", ROREG_FUNC(luat_lv_obj_clean)},
{"obj_invalidate_area", ROREG_FUNC(luat_lv_obj_invalidate_area)},
{"obj_invalidate", ROREG_FUNC(luat_lv_obj_invalidate)},
{"obj_area_is_visible", ROREG_FUNC(luat_lv_obj_area_is_visible)},
{"obj_is_visible", ROREG_FUNC(luat_lv_obj_is_visible)},
{"obj_set_parent", ROREG_FUNC(luat_lv_obj_set_parent)},
{"obj_move_foreground", ROREG_FUNC(luat_lv_obj_move_foreground)},
{"obj_move_background", ROREG_FUNC(luat_lv_obj_move_background)},
{"obj_set_pos", ROREG_FUNC(luat_lv_obj_set_pos)},
{"obj_set_x", ROREG_FUNC(luat_lv_obj_set_x)},
{"obj_set_y", ROREG_FUNC(luat_lv_obj_set_y)},
{"obj_set_size", ROREG_FUNC(luat_lv_obj_set_size)},
{"obj_set_width", ROREG_FUNC(luat_lv_obj_set_width)},
{"obj_set_height", ROREG_FUNC(luat_lv_obj_set_height)},
{"obj_set_width_fit", ROREG_FUNC(luat_lv_obj_set_width_fit)},
{"obj_set_height_fit", ROREG_FUNC(luat_lv_obj_set_height_fit)},
{"obj_set_width_margin", ROREG_FUNC(luat_lv_obj_set_width_margin)},
{"obj_set_height_margin", ROREG_FUNC(luat_lv_obj_set_height_margin)},
{"obj_align", ROREG_FUNC(luat_lv_obj_align)},
{"obj_align_x", ROREG_FUNC(luat_lv_obj_align_x)},
{"obj_align_y", ROREG_FUNC(luat_lv_obj_align_y)},
{"obj_align_mid", ROREG_FUNC(luat_lv_obj_align_mid)},
{"obj_align_mid_x", ROREG_FUNC(luat_lv_obj_align_mid_x)},
{"obj_align_mid_y", ROREG_FUNC(luat_lv_obj_align_mid_y)},
{"obj_realign", ROREG_FUNC(luat_lv_obj_realign)},
{"obj_set_auto_realign", ROREG_FUNC(luat_lv_obj_set_auto_realign)},
{"obj_set_ext_click_area", ROREG_FUNC(luat_lv_obj_set_ext_click_area)},
{"obj_add_style", ROREG_FUNC(luat_lv_obj_add_style)},
{"obj_remove_style", ROREG_FUNC(luat_lv_obj_remove_style)},
{"obj_clean_style_list", ROREG_FUNC(luat_lv_obj_clean_style_list)},
{"obj_reset_style_list", ROREG_FUNC(luat_lv_obj_reset_style_list)},
{"obj_refresh_style", ROREG_FUNC(luat_lv_obj_refresh_style)},
{"obj_report_style_mod", ROREG_FUNC(luat_lv_obj_report_style_mod)},
{"obj_remove_style_local_prop", ROREG_FUNC(luat_lv_obj_remove_style_local_prop)},
{"obj_set_hidden", ROREG_FUNC(luat_lv_obj_set_hidden)},
{"obj_set_adv_hittest", ROREG_FUNC(luat_lv_obj_set_adv_hittest)},
{"obj_set_click", ROREG_FUNC(luat_lv_obj_set_click)},
{"obj_set_top", ROREG_FUNC(luat_lv_obj_set_top)},
{"obj_set_drag", ROREG_FUNC(luat_lv_obj_set_drag)},
{"obj_set_drag_dir", ROREG_FUNC(luat_lv_obj_set_drag_dir)},
{"obj_set_drag_throw", ROREG_FUNC(luat_lv_obj_set_drag_throw)},
{"obj_set_drag_parent", ROREG_FUNC(luat_lv_obj_set_drag_parent)},
{"obj_set_focus_parent", ROREG_FUNC(luat_lv_obj_set_focus_parent)},
{"obj_set_gesture_parent", ROREG_FUNC(luat_lv_obj_set_gesture_parent)},
{"obj_set_parent_event", ROREG_FUNC(luat_lv_obj_set_parent_event)},
{"obj_set_base_dir", ROREG_FUNC(luat_lv_obj_set_base_dir)},
{"obj_add_protect", ROREG_FUNC(luat_lv_obj_add_protect)},
{"obj_clear_protect", ROREG_FUNC(luat_lv_obj_clear_protect)},
{"obj_set_state", ROREG_FUNC(luat_lv_obj_set_state)},
{"obj_add_state", ROREG_FUNC(luat_lv_obj_add_state)},
{"obj_clear_state", ROREG_FUNC(luat_lv_obj_clear_state)},
#if LV_USE_ANIMATION
{"obj_finish_transitions", ROREG_FUNC(luat_lv_obj_finish_transitions)},
#endif
{"obj_allocate_ext_attr", ROREG_FUNC(luat_lv_obj_allocate_ext_attr)},
{"obj_refresh_ext_draw_pad", ROREG_FUNC(luat_lv_obj_refresh_ext_draw_pad)},
{"obj_get_screen", ROREG_FUNC(luat_lv_obj_get_screen)},
{"obj_get_disp", ROREG_FUNC(luat_lv_obj_get_disp)},
{"obj_get_parent", ROREG_FUNC(luat_lv_obj_get_parent)},
{"obj_get_child", ROREG_FUNC(luat_lv_obj_get_child)},
{"obj_get_child_back", ROREG_FUNC(luat_lv_obj_get_child_back)},
{"obj_count_children", ROREG_FUNC(luat_lv_obj_count_children)},
{"obj_count_children_recursive", ROREG_FUNC(luat_lv_obj_count_children_recursive)},
{"obj_get_coords", ROREG_FUNC(luat_lv_obj_get_coords)},
{"obj_get_inner_coords", ROREG_FUNC(luat_lv_obj_get_inner_coords)},
{"obj_get_x", ROREG_FUNC(luat_lv_obj_get_x)},
{"obj_get_y", ROREG_FUNC(luat_lv_obj_get_y)},
{"obj_get_width", ROREG_FUNC(luat_lv_obj_get_width)},
{"obj_get_height", ROREG_FUNC(luat_lv_obj_get_height)},
{"obj_get_width_fit", ROREG_FUNC(luat_lv_obj_get_width_fit)},
{"obj_get_height_fit", ROREG_FUNC(luat_lv_obj_get_height_fit)},
{"obj_get_height_margin", ROREG_FUNC(luat_lv_obj_get_height_margin)},
{"obj_get_width_margin", ROREG_FUNC(luat_lv_obj_get_width_margin)},
{"obj_get_width_grid", ROREG_FUNC(luat_lv_obj_get_width_grid)},
{"obj_get_height_grid", ROREG_FUNC(luat_lv_obj_get_height_grid)},
{"obj_get_auto_realign", ROREG_FUNC(luat_lv_obj_get_auto_realign)},
{"obj_get_ext_click_pad_left", ROREG_FUNC(luat_lv_obj_get_ext_click_pad_left)},
{"obj_get_ext_click_pad_right", ROREG_FUNC(luat_lv_obj_get_ext_click_pad_right)},
{"obj_get_ext_click_pad_top", ROREG_FUNC(luat_lv_obj_get_ext_click_pad_top)},
{"obj_get_ext_click_pad_bottom", ROREG_FUNC(luat_lv_obj_get_ext_click_pad_bottom)},
{"obj_get_ext_draw_pad", ROREG_FUNC(luat_lv_obj_get_ext_draw_pad)},
{"obj_get_style_list", ROREG_FUNC(luat_lv_obj_get_style_list)},
{"obj_get_local_style", ROREG_FUNC(luat_lv_obj_get_local_style)},
{"obj_get_style_radius", ROREG_FUNC(luat_lv_obj_get_style_radius)},
{"obj_set_style_local_radius", ROREG_FUNC(luat_lv_obj_set_style_local_radius)},
{"obj_get_style_clip_corner", ROREG_FUNC(luat_lv_obj_get_style_clip_corner)},
{"obj_set_style_local_clip_corner", ROREG_FUNC(luat_lv_obj_set_style_local_clip_corner)},
{"obj_get_style_size", ROREG_FUNC(luat_lv_obj_get_style_size)},
{"obj_set_style_local_size", ROREG_FUNC(luat_lv_obj_set_style_local_size)},
{"obj_get_style_transform_width", ROREG_FUNC(luat_lv_obj_get_style_transform_width)},
{"obj_set_style_local_transform_width", ROREG_FUNC(luat_lv_obj_set_style_local_transform_width)},
{"obj_get_style_transform_height", ROREG_FUNC(luat_lv_obj_get_style_transform_height)},
{"obj_set_style_local_transform_height", ROREG_FUNC(luat_lv_obj_set_style_local_transform_height)},
{"obj_get_style_transform_angle", ROREG_FUNC(luat_lv_obj_get_style_transform_angle)},
{"obj_set_style_local_transform_angle", ROREG_FUNC(luat_lv_obj_set_style_local_transform_angle)},
{"obj_get_style_transform_zoom", ROREG_FUNC(luat_lv_obj_get_style_transform_zoom)},
{"obj_set_style_local_transform_zoom", ROREG_FUNC(luat_lv_obj_set_style_local_transform_zoom)},
{"obj_get_style_opa_scale", ROREG_FUNC(luat_lv_obj_get_style_opa_scale)},
{"obj_set_style_local_opa_scale", ROREG_FUNC(luat_lv_obj_set_style_local_opa_scale)},
{"obj_get_style_pad_top", ROREG_FUNC(luat_lv_obj_get_style_pad_top)},
{"obj_set_style_local_pad_top", ROREG_FUNC(luat_lv_obj_set_style_local_pad_top)},
{"obj_get_style_pad_bottom", ROREG_FUNC(luat_lv_obj_get_style_pad_bottom)},
{"obj_set_style_local_pad_bottom", ROREG_FUNC(luat_lv_obj_set_style_local_pad_bottom)},
{"obj_get_style_pad_left", ROREG_FUNC(luat_lv_obj_get_style_pad_left)},
{"obj_set_style_local_pad_left", ROREG_FUNC(luat_lv_obj_set_style_local_pad_left)},
{"obj_get_style_pad_right", ROREG_FUNC(luat_lv_obj_get_style_pad_right)},
{"obj_set_style_local_pad_right", ROREG_FUNC(luat_lv_obj_set_style_local_pad_right)},
{"obj_get_style_pad_inner", ROREG_FUNC(luat_lv_obj_get_style_pad_inner)},
{"obj_set_style_local_pad_inner", ROREG_FUNC(luat_lv_obj_set_style_local_pad_inner)},
{"obj_get_style_margin_top", ROREG_FUNC(luat_lv_obj_get_style_margin_top)},
{"obj_set_style_local_margin_top", ROREG_FUNC(luat_lv_obj_set_style_local_margin_top)},
{"obj_get_style_margin_bottom", ROREG_FUNC(luat_lv_obj_get_style_margin_bottom)},
{"obj_set_style_local_margin_bottom", ROREG_FUNC(luat_lv_obj_set_style_local_margin_bottom)},
{"obj_get_style_margin_left", ROREG_FUNC(luat_lv_obj_get_style_margin_left)},
{"obj_set_style_local_margin_left", ROREG_FUNC(luat_lv_obj_set_style_local_margin_left)},
{"obj_get_style_margin_right", ROREG_FUNC(luat_lv_obj_get_style_margin_right)},
{"obj_set_style_local_margin_right", ROREG_FUNC(luat_lv_obj_set_style_local_margin_right)},
{"obj_get_style_bg_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_bg_blend_mode)},
{"obj_set_style_local_bg_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_bg_blend_mode)},
{"obj_get_style_bg_main_stop", ROREG_FUNC(luat_lv_obj_get_style_bg_main_stop)},
{"obj_set_style_local_bg_main_stop", ROREG_FUNC(luat_lv_obj_set_style_local_bg_main_stop)},
{"obj_get_style_bg_grad_stop", ROREG_FUNC(luat_lv_obj_get_style_bg_grad_stop)},
{"obj_set_style_local_bg_grad_stop", ROREG_FUNC(luat_lv_obj_set_style_local_bg_grad_stop)},
{"obj_get_style_bg_grad_dir", ROREG_FUNC(luat_lv_obj_get_style_bg_grad_dir)},
{"obj_set_style_local_bg_grad_dir", ROREG_FUNC(luat_lv_obj_set_style_local_bg_grad_dir)},
{"obj_get_style_bg_color", ROREG_FUNC(luat_lv_obj_get_style_bg_color)},
{"obj_set_style_local_bg_color", ROREG_FUNC(luat_lv_obj_set_style_local_bg_color)},
{"obj_get_style_bg_grad_color", ROREG_FUNC(luat_lv_obj_get_style_bg_grad_color)},
{"obj_set_style_local_bg_grad_color", ROREG_FUNC(luat_lv_obj_set_style_local_bg_grad_color)},
{"obj_get_style_bg_opa", ROREG_FUNC(luat_lv_obj_get_style_bg_opa)},
{"obj_set_style_local_bg_opa", ROREG_FUNC(luat_lv_obj_set_style_local_bg_opa)},
{"obj_get_style_border_width", ROREG_FUNC(luat_lv_obj_get_style_border_width)},
{"obj_set_style_local_border_width", ROREG_FUNC(luat_lv_obj_set_style_local_border_width)},
{"obj_get_style_border_side", ROREG_FUNC(luat_lv_obj_get_style_border_side)},
{"obj_set_style_local_border_side", ROREG_FUNC(luat_lv_obj_set_style_local_border_side)},
{"obj_get_style_border_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_border_blend_mode)},
{"obj_set_style_local_border_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_border_blend_mode)},
{"obj_get_style_border_post", ROREG_FUNC(luat_lv_obj_get_style_border_post)},
{"obj_set_style_local_border_post", ROREG_FUNC(luat_lv_obj_set_style_local_border_post)},
{"obj_get_style_border_color", ROREG_FUNC(luat_lv_obj_get_style_border_color)},
{"obj_set_style_local_border_color", ROREG_FUNC(luat_lv_obj_set_style_local_border_color)},
{"obj_get_style_border_opa", ROREG_FUNC(luat_lv_obj_get_style_border_opa)},
{"obj_set_style_local_border_opa", ROREG_FUNC(luat_lv_obj_set_style_local_border_opa)},
{"obj_get_style_outline_width", ROREG_FUNC(luat_lv_obj_get_style_outline_width)},
{"obj_set_style_local_outline_width", ROREG_FUNC(luat_lv_obj_set_style_local_outline_width)},
{"obj_get_style_outline_pad", ROREG_FUNC(luat_lv_obj_get_style_outline_pad)},
{"obj_set_style_local_outline_pad", ROREG_FUNC(luat_lv_obj_set_style_local_outline_pad)},
{"obj_get_style_outline_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_outline_blend_mode)},
{"obj_set_style_local_outline_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_outline_blend_mode)},
{"obj_get_style_outline_color", ROREG_FUNC(luat_lv_obj_get_style_outline_color)},
{"obj_set_style_local_outline_color", ROREG_FUNC(luat_lv_obj_set_style_local_outline_color)},
{"obj_get_style_outline_opa", ROREG_FUNC(luat_lv_obj_get_style_outline_opa)},
{"obj_set_style_local_outline_opa", ROREG_FUNC(luat_lv_obj_set_style_local_outline_opa)},
{"obj_get_style_shadow_width", ROREG_FUNC(luat_lv_obj_get_style_shadow_width)},
{"obj_set_style_local_shadow_width", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_width)},
{"obj_get_style_shadow_ofs_x", ROREG_FUNC(luat_lv_obj_get_style_shadow_ofs_x)},
{"obj_set_style_local_shadow_ofs_x", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_ofs_x)},
{"obj_get_style_shadow_ofs_y", ROREG_FUNC(luat_lv_obj_get_style_shadow_ofs_y)},
{"obj_set_style_local_shadow_ofs_y", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_ofs_y)},
{"obj_get_style_shadow_spread", ROREG_FUNC(luat_lv_obj_get_style_shadow_spread)},
{"obj_set_style_local_shadow_spread", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_spread)},
{"obj_get_style_shadow_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_shadow_blend_mode)},
{"obj_set_style_local_shadow_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_blend_mode)},
{"obj_get_style_shadow_color", ROREG_FUNC(luat_lv_obj_get_style_shadow_color)},
{"obj_set_style_local_shadow_color", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_color)},
{"obj_get_style_shadow_opa", ROREG_FUNC(luat_lv_obj_get_style_shadow_opa)},
{"obj_set_style_local_shadow_opa", ROREG_FUNC(luat_lv_obj_set_style_local_shadow_opa)},
{"obj_get_style_pattern_repeat", ROREG_FUNC(luat_lv_obj_get_style_pattern_repeat)},
{"obj_set_style_local_pattern_repeat", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_repeat)},
{"obj_get_style_pattern_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_pattern_blend_mode)},
{"obj_set_style_local_pattern_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_blend_mode)},
{"obj_get_style_pattern_recolor", ROREG_FUNC(luat_lv_obj_get_style_pattern_recolor)},
{"obj_set_style_local_pattern_recolor", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_recolor)},
{"obj_get_style_pattern_opa", ROREG_FUNC(luat_lv_obj_get_style_pattern_opa)},
{"obj_set_style_local_pattern_opa", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_opa)},
{"obj_get_style_pattern_recolor_opa", ROREG_FUNC(luat_lv_obj_get_style_pattern_recolor_opa)},
{"obj_set_style_local_pattern_recolor_opa", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_recolor_opa)},
{"obj_get_style_pattern_image", ROREG_FUNC(luat_lv_obj_get_style_pattern_image)},
{"obj_set_style_local_pattern_image", ROREG_FUNC(luat_lv_obj_set_style_local_pattern_image)},
{"obj_get_style_value_letter_space", ROREG_FUNC(luat_lv_obj_get_style_value_letter_space)},
{"obj_set_style_local_value_letter_space", ROREG_FUNC(luat_lv_obj_set_style_local_value_letter_space)},
{"obj_get_style_value_line_space", ROREG_FUNC(luat_lv_obj_get_style_value_line_space)},
{"obj_set_style_local_value_line_space", ROREG_FUNC(luat_lv_obj_set_style_local_value_line_space)},
{"obj_get_style_value_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_value_blend_mode)},
{"obj_set_style_local_value_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_value_blend_mode)},
{"obj_get_style_value_ofs_x", ROREG_FUNC(luat_lv_obj_get_style_value_ofs_x)},
{"obj_set_style_local_value_ofs_x", ROREG_FUNC(luat_lv_obj_set_style_local_value_ofs_x)},
{"obj_get_style_value_ofs_y", ROREG_FUNC(luat_lv_obj_get_style_value_ofs_y)},
{"obj_set_style_local_value_ofs_y", ROREG_FUNC(luat_lv_obj_set_style_local_value_ofs_y)},
{"obj_get_style_value_align", ROREG_FUNC(luat_lv_obj_get_style_value_align)},
{"obj_set_style_local_value_align", ROREG_FUNC(luat_lv_obj_set_style_local_value_align)},
{"obj_get_style_value_color", ROREG_FUNC(luat_lv_obj_get_style_value_color)},
{"obj_set_style_local_value_color", ROREG_FUNC(luat_lv_obj_set_style_local_value_color)},
{"obj_get_style_value_opa", ROREG_FUNC(luat_lv_obj_get_style_value_opa)},
{"obj_set_style_local_value_opa", ROREG_FUNC(luat_lv_obj_set_style_local_value_opa)},
{"obj_get_style_value_font", ROREG_FUNC(luat_lv_obj_get_style_value_font)},
{"obj_set_style_local_value_font", ROREG_FUNC(luat_lv_obj_set_style_local_value_font)},
{"obj_get_style_value_str", ROREG_FUNC(luat_lv_obj_get_style_value_str)},
{"obj_set_style_local_value_str", ROREG_FUNC(luat_lv_obj_set_style_local_value_str)},
{"obj_get_style_text_letter_space", ROREG_FUNC(luat_lv_obj_get_style_text_letter_space)},
{"obj_set_style_local_text_letter_space", ROREG_FUNC(luat_lv_obj_set_style_local_text_letter_space)},
{"obj_get_style_text_line_space", ROREG_FUNC(luat_lv_obj_get_style_text_line_space)},
{"obj_set_style_local_text_line_space", ROREG_FUNC(luat_lv_obj_set_style_local_text_line_space)},
{"obj_get_style_text_decor", ROREG_FUNC(luat_lv_obj_get_style_text_decor)},
{"obj_set_style_local_text_decor", ROREG_FUNC(luat_lv_obj_set_style_local_text_decor)},
{"obj_get_style_text_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_text_blend_mode)},
{"obj_set_style_local_text_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_text_blend_mode)},
{"obj_get_style_text_color", ROREG_FUNC(luat_lv_obj_get_style_text_color)},
{"obj_set_style_local_text_color", ROREG_FUNC(luat_lv_obj_set_style_local_text_color)},
{"obj_get_style_text_sel_color", ROREG_FUNC(luat_lv_obj_get_style_text_sel_color)},
{"obj_set_style_local_text_sel_color", ROREG_FUNC(luat_lv_obj_set_style_local_text_sel_color)},
{"obj_get_style_text_sel_bg_color", ROREG_FUNC(luat_lv_obj_get_style_text_sel_bg_color)},
{"obj_set_style_local_text_sel_bg_color", ROREG_FUNC(luat_lv_obj_set_style_local_text_sel_bg_color)},
{"obj_get_style_text_opa", ROREG_FUNC(luat_lv_obj_get_style_text_opa)},
{"obj_set_style_local_text_opa", ROREG_FUNC(luat_lv_obj_set_style_local_text_opa)},
{"obj_get_style_text_font", ROREG_FUNC(luat_lv_obj_get_style_text_font)},
{"obj_set_style_local_text_font", ROREG_FUNC(luat_lv_obj_set_style_local_text_font)},
{"obj_get_style_line_width", ROREG_FUNC(luat_lv_obj_get_style_line_width)},
{"obj_set_style_local_line_width", ROREG_FUNC(luat_lv_obj_set_style_local_line_width)},
{"obj_get_style_line_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_line_blend_mode)},
{"obj_set_style_local_line_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_line_blend_mode)},
{"obj_get_style_line_dash_width", ROREG_FUNC(luat_lv_obj_get_style_line_dash_width)},
{"obj_set_style_local_line_dash_width", ROREG_FUNC(luat_lv_obj_set_style_local_line_dash_width)},
{"obj_get_style_line_dash_gap", ROREG_FUNC(luat_lv_obj_get_style_line_dash_gap)},
{"obj_set_style_local_line_dash_gap", ROREG_FUNC(luat_lv_obj_set_style_local_line_dash_gap)},
{"obj_get_style_line_rounded", ROREG_FUNC(luat_lv_obj_get_style_line_rounded)},
{"obj_set_style_local_line_rounded", ROREG_FUNC(luat_lv_obj_set_style_local_line_rounded)},
{"obj_get_style_line_color", ROREG_FUNC(luat_lv_obj_get_style_line_color)},
{"obj_set_style_local_line_color", ROREG_FUNC(luat_lv_obj_set_style_local_line_color)},
{"obj_get_style_line_opa", ROREG_FUNC(luat_lv_obj_get_style_line_opa)},
{"obj_set_style_local_line_opa", ROREG_FUNC(luat_lv_obj_set_style_local_line_opa)},
{"obj_get_style_image_blend_mode", ROREG_FUNC(luat_lv_obj_get_style_image_blend_mode)},
{"obj_set_style_local_image_blend_mode", ROREG_FUNC(luat_lv_obj_set_style_local_image_blend_mode)},
{"obj_get_style_image_recolor", ROREG_FUNC(luat_lv_obj_get_style_image_recolor)},
{"obj_set_style_local_image_recolor", ROREG_FUNC(luat_lv_obj_set_style_local_image_recolor)},
{"obj_get_style_image_opa", ROREG_FUNC(luat_lv_obj_get_style_image_opa)},
{"obj_set_style_local_image_opa", ROREG_FUNC(luat_lv_obj_set_style_local_image_opa)},
{"obj_get_style_image_recolor_opa", ROREG_FUNC(luat_lv_obj_get_style_image_recolor_opa)},
{"obj_set_style_local_image_recolor_opa", ROREG_FUNC(luat_lv_obj_set_style_local_image_recolor_opa)},
{"obj_get_style_transition_time", ROREG_FUNC(luat_lv_obj_get_style_transition_time)},
{"obj_set_style_local_transition_time", ROREG_FUNC(luat_lv_obj_set_style_local_transition_time)},
{"obj_get_style_transition_delay", ROREG_FUNC(luat_lv_obj_get_style_transition_delay)},
{"obj_set_style_local_transition_delay", ROREG_FUNC(luat_lv_obj_set_style_local_transition_delay)},
{"obj_get_style_transition_prop_1", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_1)},
{"obj_set_style_local_transition_prop_1", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_1)},
{"obj_get_style_transition_prop_2", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_2)},
{"obj_set_style_local_transition_prop_2", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_2)},
{"obj_get_style_transition_prop_3", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_3)},
{"obj_set_style_local_transition_prop_3", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_3)},
{"obj_get_style_transition_prop_4", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_4)},
{"obj_set_style_local_transition_prop_4", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_4)},
{"obj_get_style_transition_prop_5", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_5)},
{"obj_set_style_local_transition_prop_5", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_5)},
{"obj_get_style_transition_prop_6", ROREG_FUNC(luat_lv_obj_get_style_transition_prop_6)},
{"obj_set_style_local_transition_prop_6", ROREG_FUNC(luat_lv_obj_set_style_local_transition_prop_6)},
#if LV_USE_ANIMATION
{"obj_get_style_transition_path", ROREG_FUNC(luat_lv_obj_get_style_transition_path)},
{"obj_set_style_local_transition_path", ROREG_FUNC(luat_lv_obj_set_style_local_transition_path)},
#endif
{"obj_get_style_scale_width", ROREG_FUNC(luat_lv_obj_get_style_scale_width)},
{"obj_set_style_local_scale_width", ROREG_FUNC(luat_lv_obj_set_style_local_scale_width)},
{"obj_get_style_scale_border_width", ROREG_FUNC(luat_lv_obj_get_style_scale_border_width)},
{"obj_set_style_local_scale_border_width", ROREG_FUNC(luat_lv_obj_set_style_local_scale_border_width)},
{"obj_get_style_scale_end_border_width", ROREG_FUNC(luat_lv_obj_get_style_scale_end_border_width)},
{"obj_set_style_local_scale_end_border_width", ROREG_FUNC(luat_lv_obj_set_style_local_scale_end_border_width)},
{"obj_get_style_scale_end_line_width", ROREG_FUNC(luat_lv_obj_get_style_scale_end_line_width)},
{"obj_set_style_local_scale_end_line_width", ROREG_FUNC(luat_lv_obj_set_style_local_scale_end_line_width)},
{"obj_get_style_scale_grad_color", ROREG_FUNC(luat_lv_obj_get_style_scale_grad_color)},
{"obj_set_style_local_scale_grad_color", ROREG_FUNC(luat_lv_obj_set_style_local_scale_grad_color)},
{"obj_get_style_scale_end_color", ROREG_FUNC(luat_lv_obj_get_style_scale_end_color)},
{"obj_set_style_local_scale_end_color", ROREG_FUNC(luat_lv_obj_set_style_local_scale_end_color)},
{"obj_set_style_local_pad_all", ROREG_FUNC(luat_lv_obj_set_style_local_pad_all)},
{"obj_set_style_local_pad_hor", ROREG_FUNC(luat_lv_obj_set_style_local_pad_hor)},
{"obj_set_style_local_pad_ver", ROREG_FUNC(luat_lv_obj_set_style_local_pad_ver)},
{"obj_set_style_local_margin_all", ROREG_FUNC(luat_lv_obj_set_style_local_margin_all)},
{"obj_set_style_local_margin_hor", ROREG_FUNC(luat_lv_obj_set_style_local_margin_hor)},
{"obj_set_style_local_margin_ver", ROREG_FUNC(luat_lv_obj_set_style_local_margin_ver)},
{"obj_get_hidden", ROREG_FUNC(luat_lv_obj_get_hidden)},
{"obj_get_adv_hittest", ROREG_FUNC(luat_lv_obj_get_adv_hittest)},
{"obj_get_click", ROREG_FUNC(luat_lv_obj_get_click)},
{"obj_get_top", ROREG_FUNC(luat_lv_obj_get_top)},
{"obj_get_drag", ROREG_FUNC(luat_lv_obj_get_drag)},
{"obj_get_drag_dir", ROREG_FUNC(luat_lv_obj_get_drag_dir)},
{"obj_get_drag_throw", ROREG_FUNC(luat_lv_obj_get_drag_throw)},
{"obj_get_drag_parent", ROREG_FUNC(luat_lv_obj_get_drag_parent)},
{"obj_get_focus_parent", ROREG_FUNC(luat_lv_obj_get_focus_parent)},
{"obj_get_parent_event", ROREG_FUNC(luat_lv_obj_get_parent_event)},
{"obj_get_gesture_parent", ROREG_FUNC(luat_lv_obj_get_gesture_parent)},
{"obj_get_base_dir", ROREG_FUNC(luat_lv_obj_get_base_dir)},
{"obj_get_protect", ROREG_FUNC(luat_lv_obj_get_protect)},
{"obj_is_protected", ROREG_FUNC(luat_lv_obj_is_protected)},
{"obj_get_state", ROREG_FUNC(luat_lv_obj_get_state)},
{"obj_is_point_on_coords", ROREG_FUNC(luat_lv_obj_is_point_on_coords)},
{"obj_hittest", ROREG_FUNC(luat_lv_obj_hittest)},
{"obj_get_ext_attr", ROREG_FUNC(luat_lv_obj_get_ext_attr)},
{"obj_get_type", ROREG_FUNC(luat_lv_obj_get_type)},
{"obj_get_user_data", ROREG_FUNC(luat_lv_obj_get_user_data)},
{"obj_get_user_data_ptr", ROREG_FUNC(luat_lv_obj_get_user_data_ptr)},
{"obj_set_user_data", ROREG_FUNC(luat_lv_obj_set_user_data)},
{"obj_get_group", ROREG_FUNC(luat_lv_obj_get_group)},
{"obj_is_focused", ROREG_FUNC(luat_lv_obj_is_focused)},
{"obj_get_focused_obj", ROREG_FUNC(luat_lv_obj_get_focused_obj)},
{"obj_handle_get_type_signal", ROREG_FUNC(luat_lv_obj_handle_get_type_signal)},
{"obj_init_draw_rect_dsc", ROREG_FUNC(luat_lv_obj_init_draw_rect_dsc)},
{"obj_init_draw_label_dsc", ROREG_FUNC(luat_lv_obj_init_draw_label_dsc)},
{"obj_init_draw_img_dsc", ROREG_FUNC(luat_lv_obj_init_draw_img_dsc)},
{"obj_init_draw_line_dsc", ROREG_FUNC(luat_lv_obj_init_draw_line_dsc)},
{"obj_get_draw_rect_ext_pad_size", ROREG_FUNC(luat_lv_obj_get_draw_rect_ext_pad_size)},
{"obj_fade_in", ROREG_FUNC(luat_lv_obj_fade_in)},
{"obj_fade_out", ROREG_FUNC(luat_lv_obj_fade_out)},

{"refr_now", ROREG_FUNC(luat_lv_refr_now)},

{"style_init", ROREG_FUNC(luat_lv_style_init)},
{"style_copy", ROREG_FUNC(luat_lv_style_copy)},
{"style_list_init", ROREG_FUNC(luat_lv_style_list_init)},
{"style_list_copy", ROREG_FUNC(luat_lv_style_list_copy)},
{"style_list_get_style", ROREG_FUNC(luat_lv_style_list_get_style)},
{"style_reset", ROREG_FUNC(luat_lv_style_reset)},
{"style_remove_prop", ROREG_FUNC(luat_lv_style_remove_prop)},
{"style_list_get_local_style", ROREG_FUNC(luat_lv_style_list_get_local_style)},


LUAT_LV_STYLE_RLT
{"style_t", ROREG_FUNC(luat_lv_style_t)},
{"style_create", ROREG_FUNC(luat_lv_style_create)},
{"style_list_create", ROREG_FUNC(luat_lv_style_list_create)},
{"style_list_t", ROREG_FUNC(luat_lv_style_list_create)},
{"style_delete", ROREG_FUNC(luat_lv_style_delete)},
{"style_list_delete", ROREG_FUNC(luat_lv_style_list_delete)},
#if LV_USE_ANIMATION
{"style_set_transition_path", ROREG_FUNC(luat_lv_style_set_transition_path)},
#endif

// 添加STYLE_DEC那一百多个函数
LUAT_LV_STYLE_DEC_RLT

{"draw_mask_add", ROREG_FUNC(luat_lv_draw_mask_add)},
{"draw_mask_apply", ROREG_FUNC(luat_lv_draw_mask_apply)},
{"draw_mask_remove_id", ROREG_FUNC(luat_lv_draw_mask_remove_id)},
{"draw_mask_remove_custom", ROREG_FUNC(luat_lv_draw_mask_remove_custom)},
{"draw_mask_get_cnt", ROREG_FUNC(luat_lv_draw_mask_get_cnt)},
{"draw_mask_line_points_init", ROREG_FUNC(luat_lv_draw_mask_line_points_init)},
{"draw_mask_line_angle_init", ROREG_FUNC(luat_lv_draw_mask_line_angle_init)},
{"draw_mask_angle_init", ROREG_FUNC(luat_lv_draw_mask_angle_init)},
{"draw_mask_radius_init", ROREG_FUNC(luat_lv_draw_mask_radius_init)},
{"draw_mask_fade_init", ROREG_FUNC(luat_lv_draw_mask_fade_init)},
{"draw_mask_map_init", ROREG_FUNC(luat_lv_draw_mask_map_init)},
{"draw_rect_dsc_init", ROREG_FUNC(luat_lv_draw_rect_dsc_init)},
{"draw_rect", ROREG_FUNC(luat_lv_draw_rect)},
{"draw_px", ROREG_FUNC(luat_lv_draw_px)},
{"draw_label_dsc_init", ROREG_FUNC(luat_lv_draw_label_dsc_init)},
{"draw_label", ROREG_FUNC(luat_lv_draw_label)},
{"draw_img_dsc_init", ROREG_FUNC(luat_lv_draw_img_dsc_init)},
{"draw_img", ROREG_FUNC(luat_lv_draw_img)},
{"draw_line", ROREG_FUNC(luat_lv_draw_line)},
{"draw_line_dsc_init", ROREG_FUNC(luat_lv_draw_line_dsc_init)},
{"draw_arc", ROREG_FUNC(luat_lv_draw_arc)},
LUAT_LV_DRAW_EX_RLT

#if LV_USE_ANIMATION
{"anim_init", ROREG_FUNC(luat_lv_anim_init)},
{"anim_set_var", ROREG_FUNC(luat_lv_anim_set_var)},
{"anim_set_time", ROREG_FUNC(luat_lv_anim_set_time)},
{"anim_set_delay", ROREG_FUNC(luat_lv_anim_set_delay)},
{"anim_set_values", ROREG_FUNC(luat_lv_anim_set_values)},
{"anim_set_path", ROREG_FUNC(luat_lv_anim_set_path)},
{"anim_set_playback_time", ROREG_FUNC(luat_lv_anim_set_playback_time)},
{"anim_set_playback_delay", ROREG_FUNC(luat_lv_anim_set_playback_delay)},
{"anim_set_repeat_count", ROREG_FUNC(luat_lv_anim_set_repeat_count)},
{"anim_set_repeat_delay", ROREG_FUNC(luat_lv_anim_set_repeat_delay)},
{"anim_start", ROREG_FUNC(luat_lv_anim_start)},
{"anim_path_init", ROREG_FUNC(luat_lv_anim_path_init)},
{"anim_path_set_user_data", ROREG_FUNC(luat_lv_anim_path_set_user_data)},
{"anim_get_delay", ROREG_FUNC(luat_lv_anim_get_delay)},
{"anim_del", ROREG_FUNC(luat_lv_anim_del)},
{"anim_del_all", ROREG_FUNC(luat_lv_anim_del_all)},
{"anim_get", ROREG_FUNC(luat_lv_anim_get)},
{"anim_custom_del", ROREG_FUNC(luat_lv_anim_custom_del)},
{"anim_count_running", ROREG_FUNC(luat_lv_anim_count_running)},
{"anim_speed_to_time", ROREG_FUNC(luat_lv_anim_speed_to_time)},
{"anim_refr_now", ROREG_FUNC(luat_lv_anim_refr_now)},
{"anim_path_linear", ROREG_FUNC(luat_lv_anim_path_linear)},
{"anim_path_ease_in", ROREG_FUNC(luat_lv_anim_path_ease_in)},
{"anim_path_ease_out", ROREG_FUNC(luat_lv_anim_path_ease_out)},
{"anim_path_ease_in_out", ROREG_FUNC(luat_lv_anim_path_ease_in_out)},
{"anim_path_overshoot", ROREG_FUNC(luat_lv_anim_path_overshoot)},
{"anim_path_bounce", ROREG_FUNC(luat_lv_anim_path_bounce)},
{"anim_path_step", ROREG_FUNC(luat_lv_anim_path_step)},
LUAT_LV_ANIM_EX_RLT
#endif

{"area_set", ROREG_FUNC(luat_lv_area_set)},
{"area_copy", ROREG_FUNC(luat_lv_area_copy)},
{"area_get_width", ROREG_FUNC(luat_lv_area_get_width)},
{"area_get_height", ROREG_FUNC(luat_lv_area_get_height)},
{"area_set_width", ROREG_FUNC(luat_lv_area_set_width)},
{"area_set_height", ROREG_FUNC(luat_lv_area_set_height)},
{"area_get_size", ROREG_FUNC(luat_lv_area_get_size)},

{"color_to1", ROREG_FUNC(luat_lv_color_to1)},
{"color_to8", ROREG_FUNC(luat_lv_color_to8)},
{"color_to16", ROREG_FUNC(luat_lv_color_to16)},
{"color_to32", ROREG_FUNC(luat_lv_color_to32)},
{"color_mix", ROREG_FUNC(luat_lv_color_mix)},
{"color_premult", ROREG_FUNC(luat_lv_color_premult)},
{"color_mix_premult", ROREG_FUNC(luat_lv_color_mix_premult)},
{"color_mix_with_alpha", ROREG_FUNC(luat_lv_color_mix_with_alpha)},
{"color_brightness", ROREG_FUNC(luat_lv_color_brightness)},
{"color_make", ROREG_FUNC(luat_lv_color_make)},
{"color_hex", ROREG_FUNC(luat_lv_color_hex)},
{"color_hex3", ROREG_FUNC(luat_lv_color_hex3)},
{"color_fill", ROREG_FUNC(luat_lv_color_fill)},
{"color_lighten", ROREG_FUNC(luat_lv_color_lighten)},
{"color_darken", ROREG_FUNC(luat_lv_color_darken)},
{"color_hsv_to_rgb", ROREG_FUNC(luat_lv_color_hsv_to_rgb)},
{"color_rgb_to_hsv", ROREG_FUNC(luat_lv_color_rgb_to_hsv)},
{"color_to_hsv", ROREG_FUNC(luat_lv_color_to_hsv)},


LUAT_LV_MAP_RLT

LUAT_LV_SYMBOL_RLT

#ifdef LUAT_USE_LVGL_DEMO
LUAT_LV_DEMO_RLT
#endif

// 输入设备
#ifdef LUAT_USE_LVGL_INDEV
LUAT_LV_INDEV_RLT
#endif

//LVGL组件
#ifdef LUAT_USE_LVGL_ARC
{"arc_create", ROREG_FUNC(luat_lv_arc_create)},
{"arc_set_start_angle", ROREG_FUNC(luat_lv_arc_set_start_angle)},
{"arc_set_end_angle", ROREG_FUNC(luat_lv_arc_set_end_angle)},
{"arc_set_angles", ROREG_FUNC(luat_lv_arc_set_angles)},
{"arc_set_bg_start_angle", ROREG_FUNC(luat_lv_arc_set_bg_start_angle)},
{"arc_set_bg_end_angle", ROREG_FUNC(luat_lv_arc_set_bg_end_angle)},
{"arc_set_bg_angles", ROREG_FUNC(luat_lv_arc_set_bg_angles)},
{"arc_set_rotation", ROREG_FUNC(luat_lv_arc_set_rotation)},
{"arc_set_type", ROREG_FUNC(luat_lv_arc_set_type)},
{"arc_set_value", ROREG_FUNC(luat_lv_arc_set_value)},
{"arc_set_range", ROREG_FUNC(luat_lv_arc_set_range)},
{"arc_set_chg_rate", ROREG_FUNC(luat_lv_arc_set_chg_rate)},
{"arc_set_adjustable", ROREG_FUNC(luat_lv_arc_set_adjustable)},
{"arc_get_angle_start", ROREG_FUNC(luat_lv_arc_get_angle_start)},
{"arc_get_angle_end", ROREG_FUNC(luat_lv_arc_get_angle_end)},
{"arc_get_bg_angle_start", ROREG_FUNC(luat_lv_arc_get_bg_angle_start)},
{"arc_get_bg_angle_end", ROREG_FUNC(luat_lv_arc_get_bg_angle_end)},
{"arc_get_type", ROREG_FUNC(luat_lv_arc_get_type)},
{"arc_get_value", ROREG_FUNC(luat_lv_arc_get_value)},
{"arc_get_min_value", ROREG_FUNC(luat_lv_arc_get_min_value)},
{"arc_get_max_value", ROREG_FUNC(luat_lv_arc_get_max_value)},
{"arc_is_dragged", ROREG_FUNC(luat_lv_arc_is_dragged)},
{"arc_get_adjustable", ROREG_FUNC(luat_lv_arc_get_adjustable)},

#endif
#ifdef LUAT_USE_LVGL_BAR
{"bar_create", ROREG_FUNC(luat_lv_bar_create)},
{"bar_set_value", ROREG_FUNC(luat_lv_bar_set_value)},
{"bar_set_start_value", ROREG_FUNC(luat_lv_bar_set_start_value)},
{"bar_set_range", ROREG_FUNC(luat_lv_bar_set_range)},
{"bar_set_type", ROREG_FUNC(luat_lv_bar_set_type)},
{"bar_set_anim_time", ROREG_FUNC(luat_lv_bar_set_anim_time)},
{"bar_get_value", ROREG_FUNC(luat_lv_bar_get_value)},
{"bar_get_start_value", ROREG_FUNC(luat_lv_bar_get_start_value)},
{"bar_get_min_value", ROREG_FUNC(luat_lv_bar_get_min_value)},
{"bar_get_max_value", ROREG_FUNC(luat_lv_bar_get_max_value)},
{"bar_get_type", ROREG_FUNC(luat_lv_bar_get_type)},
{"bar_get_anim_time", ROREG_FUNC(luat_lv_bar_get_anim_time)},

#endif
#ifdef LUAT_USE_LVGL_BTN
{"btn_create", ROREG_FUNC(luat_lv_btn_create)},
{"btn_set_checkable", ROREG_FUNC(luat_lv_btn_set_checkable)},
{"btn_set_state", ROREG_FUNC(luat_lv_btn_set_state)},
{"btn_toggle", ROREG_FUNC(luat_lv_btn_toggle)},
{"btn_set_layout", ROREG_FUNC(luat_lv_btn_set_layout)},
{"btn_set_fit4", ROREG_FUNC(luat_lv_btn_set_fit4)},
{"btn_set_fit2", ROREG_FUNC(luat_lv_btn_set_fit2)},
{"btn_set_fit", ROREG_FUNC(luat_lv_btn_set_fit)},
{"btn_get_state", ROREG_FUNC(luat_lv_btn_get_state)},
{"btn_get_checkable", ROREG_FUNC(luat_lv_btn_get_checkable)},
{"btn_get_layout", ROREG_FUNC(luat_lv_btn_get_layout)},
{"btn_get_fit_left", ROREG_FUNC(luat_lv_btn_get_fit_left)},
{"btn_get_fit_right", ROREG_FUNC(luat_lv_btn_get_fit_right)},
{"btn_get_fit_top", ROREG_FUNC(luat_lv_btn_get_fit_top)},
{"btn_get_fit_bottom", ROREG_FUNC(luat_lv_btn_get_fit_bottom)},

#endif
#ifdef LUAT_USE_LVGL_BTNMATRIX
{"btnmatrix_create", ROREG_FUNC(luat_lv_btnmatrix_create)},
{"btnmatrix_set_focused_btn", ROREG_FUNC(luat_lv_btnmatrix_set_focused_btn)},
{"btnmatrix_set_recolor", ROREG_FUNC(luat_lv_btnmatrix_set_recolor)},
{"btnmatrix_set_btn_ctrl", ROREG_FUNC(luat_lv_btnmatrix_set_btn_ctrl)},
{"btnmatrix_clear_btn_ctrl", ROREG_FUNC(luat_lv_btnmatrix_clear_btn_ctrl)},
{"btnmatrix_set_btn_ctrl_all", ROREG_FUNC(luat_lv_btnmatrix_set_btn_ctrl_all)},
{"btnmatrix_clear_btn_ctrl_all", ROREG_FUNC(luat_lv_btnmatrix_clear_btn_ctrl_all)},
{"btnmatrix_set_btn_width", ROREG_FUNC(luat_lv_btnmatrix_set_btn_width)},
{"btnmatrix_set_one_check", ROREG_FUNC(luat_lv_btnmatrix_set_one_check)},
{"btnmatrix_set_align", ROREG_FUNC(luat_lv_btnmatrix_set_align)},
{"btnmatrix_get_recolor", ROREG_FUNC(luat_lv_btnmatrix_get_recolor)},
{"btnmatrix_get_active_btn", ROREG_FUNC(luat_lv_btnmatrix_get_active_btn)},
{"btnmatrix_get_active_btn_text", ROREG_FUNC(luat_lv_btnmatrix_get_active_btn_text)},
{"btnmatrix_get_focused_btn", ROREG_FUNC(luat_lv_btnmatrix_get_focused_btn)},
{"btnmatrix_get_btn_text", ROREG_FUNC(luat_lv_btnmatrix_get_btn_text)},
{"btnmatrix_get_btn_ctrl", ROREG_FUNC(luat_lv_btnmatrix_get_btn_ctrl)},
{"btnmatrix_get_one_check", ROREG_FUNC(luat_lv_btnmatrix_get_one_check)},
{"btnmatrix_get_align", ROREG_FUNC(luat_lv_btnmatrix_get_align)},

LUAT_LV_BTNMATRIX_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_CALENDAR
{"calendar_create", ROREG_FUNC(luat_lv_calendar_create)},
{"calendar_set_today_date", ROREG_FUNC(luat_lv_calendar_set_today_date)},
{"calendar_set_showed_date", ROREG_FUNC(luat_lv_calendar_set_showed_date)},
{"calendar_get_today_date", ROREG_FUNC(luat_lv_calendar_get_today_date)},
{"calendar_get_showed_date", ROREG_FUNC(luat_lv_calendar_get_showed_date)},
{"calendar_get_pressed_date", ROREG_FUNC(luat_lv_calendar_get_pressed_date)},
{"calendar_get_highlighted_dates", ROREG_FUNC(luat_lv_calendar_get_highlighted_dates)},
{"calendar_get_highlighted_dates_num", ROREG_FUNC(luat_lv_calendar_get_highlighted_dates_num)},
{"calendar_get_day_of_week", ROREG_FUNC(luat_lv_calendar_get_day_of_week)},

LUAT_LV_CALENDAR_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_CANVAS
{"canvas_create", ROREG_FUNC(luat_lv_canvas_create)},
{"canvas_set_px", ROREG_FUNC(luat_lv_canvas_set_px)},
{"canvas_set_palette", ROREG_FUNC(luat_lv_canvas_set_palette)},
{"canvas_get_px", ROREG_FUNC(luat_lv_canvas_get_px)},
{"canvas_get_img", ROREG_FUNC(luat_lv_canvas_get_img)},
{"canvas_copy_buf", ROREG_FUNC(luat_lv_canvas_copy_buf)},
{"canvas_transform", ROREG_FUNC(luat_lv_canvas_transform)},
{"canvas_blur_hor", ROREG_FUNC(luat_lv_canvas_blur_hor)},
{"canvas_blur_ver", ROREG_FUNC(luat_lv_canvas_blur_ver)},
{"canvas_fill_bg", ROREG_FUNC(luat_lv_canvas_fill_bg)},
{"canvas_draw_rect", ROREG_FUNC(luat_lv_canvas_draw_rect)},
{"canvas_draw_text", ROREG_FUNC(luat_lv_canvas_draw_text)},
{"canvas_draw_img", ROREG_FUNC(luat_lv_canvas_draw_img)},
{"canvas_draw_arc", ROREG_FUNC(luat_lv_canvas_draw_arc)},

LUAT_LV_CANVAS_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_CHECKBOX
{"checkbox_create", ROREG_FUNC(luat_lv_checkbox_create)},
{"checkbox_set_text", ROREG_FUNC(luat_lv_checkbox_set_text)},
{"checkbox_set_text_static", ROREG_FUNC(luat_lv_checkbox_set_text_static)},
{"checkbox_set_checked", ROREG_FUNC(luat_lv_checkbox_set_checked)},
{"checkbox_set_disabled", ROREG_FUNC(luat_lv_checkbox_set_disabled)},
{"checkbox_set_state", ROREG_FUNC(luat_lv_checkbox_set_state)},
{"checkbox_get_text", ROREG_FUNC(luat_lv_checkbox_get_text)},
{"checkbox_is_checked", ROREG_FUNC(luat_lv_checkbox_is_checked)},
{"checkbox_is_inactive", ROREG_FUNC(luat_lv_checkbox_is_inactive)},
{"checkbox_get_state", ROREG_FUNC(luat_lv_checkbox_get_state)},

#endif
#ifdef LUAT_USE_LVGL_CHART
{"chart_create", ROREG_FUNC(luat_lv_chart_create)},
{"chart_add_series", ROREG_FUNC(luat_lv_chart_add_series)},
{"chart_remove_series", ROREG_FUNC(luat_lv_chart_remove_series)},
{"chart_add_cursor", ROREG_FUNC(luat_lv_chart_add_cursor)},
{"chart_clear_series", ROREG_FUNC(luat_lv_chart_clear_series)},
{"chart_hide_series", ROREG_FUNC(luat_lv_chart_hide_series)},
{"chart_set_div_line_count", ROREG_FUNC(luat_lv_chart_set_div_line_count)},
{"chart_set_y_range", ROREG_FUNC(luat_lv_chart_set_y_range)},
{"chart_set_type", ROREG_FUNC(luat_lv_chart_set_type)},
{"chart_set_point_count", ROREG_FUNC(luat_lv_chart_set_point_count)},
{"chart_init_points", ROREG_FUNC(luat_lv_chart_init_points)},
{"chart_set_next", ROREG_FUNC(luat_lv_chart_set_next)},
{"chart_set_update_mode", ROREG_FUNC(luat_lv_chart_set_update_mode)},
{"chart_set_x_tick_length", ROREG_FUNC(luat_lv_chart_set_x_tick_length)},
{"chart_set_y_tick_length", ROREG_FUNC(luat_lv_chart_set_y_tick_length)},
{"chart_set_secondary_y_tick_length", ROREG_FUNC(luat_lv_chart_set_secondary_y_tick_length)},
{"chart_set_x_tick_texts", ROREG_FUNC(luat_lv_chart_set_x_tick_texts)},
{"chart_set_secondary_y_tick_texts", ROREG_FUNC(luat_lv_chart_set_secondary_y_tick_texts)},
{"chart_set_y_tick_texts", ROREG_FUNC(luat_lv_chart_set_y_tick_texts)},
{"chart_set_x_start_point", ROREG_FUNC(luat_lv_chart_set_x_start_point)},
{"chart_set_point_id", ROREG_FUNC(luat_lv_chart_set_point_id)},
{"chart_set_series_axis", ROREG_FUNC(luat_lv_chart_set_series_axis)},
{"chart_set_cursor_point", ROREG_FUNC(luat_lv_chart_set_cursor_point)},
{"chart_get_type", ROREG_FUNC(luat_lv_chart_get_type)},
{"chart_get_point_count", ROREG_FUNC(luat_lv_chart_get_point_count)},
{"chart_get_x_start_point", ROREG_FUNC(luat_lv_chart_get_x_start_point)},
{"chart_get_point_id", ROREG_FUNC(luat_lv_chart_get_point_id)},
{"chart_get_series_axis", ROREG_FUNC(luat_lv_chart_get_series_axis)},
{"chart_get_series_area", ROREG_FUNC(luat_lv_chart_get_series_area)},
{"chart_get_cursor_point", ROREG_FUNC(luat_lv_chart_get_cursor_point)},
{"chart_get_nearest_index_from_coord", ROREG_FUNC(luat_lv_chart_get_nearest_index_from_coord)},
{"chart_get_x_from_index", ROREG_FUNC(luat_lv_chart_get_x_from_index)},
{"chart_get_y_from_index", ROREG_FUNC(luat_lv_chart_get_y_from_index)},
{"chart_refresh", ROREG_FUNC(luat_lv_chart_refresh)},

#endif
#ifdef LUAT_USE_LVGL_CONT
    {"cont_create", ROREG_FUNC(luat_lv_cont_create)},
    {"cont_set_layout", ROREG_FUNC(luat_lv_cont_set_layout)},
    {"cont_set_fit4", ROREG_FUNC(luat_lv_cont_set_fit4)},
    {"cont_set_fit2", ROREG_FUNC(luat_lv_cont_set_fit2)},
    {"cont_set_fit", ROREG_FUNC(luat_lv_cont_set_fit)},
    {"cont_get_layout", ROREG_FUNC(luat_lv_cont_get_layout)},
    {"cont_get_fit_left", ROREG_FUNC(luat_lv_cont_get_fit_left)},
    {"cont_get_fit_right", ROREG_FUNC(luat_lv_cont_get_fit_right)},
    {"cont_get_fit_top", ROREG_FUNC(luat_lv_cont_get_fit_top)},
    {"cont_get_fit_bottom", ROREG_FUNC(luat_lv_cont_get_fit_bottom)},

#endif
#ifdef LUAT_USE_LVGL_CPICKER
    {"cpicker_create", ROREG_FUNC(luat_lv_cpicker_create)},
    {"cpicker_set_type", ROREG_FUNC(luat_lv_cpicker_set_type)},
    {"cpicker_set_hue", ROREG_FUNC(luat_lv_cpicker_set_hue)},
    {"cpicker_set_saturation", ROREG_FUNC(luat_lv_cpicker_set_saturation)},
    {"cpicker_set_value", ROREG_FUNC(luat_lv_cpicker_set_value)},
    {"cpicker_set_hsv", ROREG_FUNC(luat_lv_cpicker_set_hsv)},
    {"cpicker_set_color", ROREG_FUNC(luat_lv_cpicker_set_color)},
    {"cpicker_set_color_mode", ROREG_FUNC(luat_lv_cpicker_set_color_mode)},
    {"cpicker_set_color_mode_fixed", ROREG_FUNC(luat_lv_cpicker_set_color_mode_fixed)},
    {"cpicker_set_knob_colored", ROREG_FUNC(luat_lv_cpicker_set_knob_colored)},
    {"cpicker_get_color_mode", ROREG_FUNC(luat_lv_cpicker_get_color_mode)},
    {"cpicker_get_color_mode_fixed", ROREG_FUNC(luat_lv_cpicker_get_color_mode_fixed)},
    {"cpicker_get_hue", ROREG_FUNC(luat_lv_cpicker_get_hue)},
    {"cpicker_get_saturation", ROREG_FUNC(luat_lv_cpicker_get_saturation)},
    {"cpicker_get_value", ROREG_FUNC(luat_lv_cpicker_get_value)},
    {"cpicker_get_hsv", ROREG_FUNC(luat_lv_cpicker_get_hsv)},
    {"cpicker_get_color", ROREG_FUNC(luat_lv_cpicker_get_color)},
    {"cpicker_get_knob_colored", ROREG_FUNC(luat_lv_cpicker_get_knob_colored)},

#endif
#ifdef LUAT_USE_LVGL_DROPDOWN
    {"dropdown_create", ROREG_FUNC(luat_lv_dropdown_create)},
    {"dropdown_set_text", ROREG_FUNC(luat_lv_dropdown_set_text)},
    {"dropdown_clear_options", ROREG_FUNC(luat_lv_dropdown_clear_options)},
    {"dropdown_set_options", ROREG_FUNC(luat_lv_dropdown_set_options)},
    {"dropdown_set_options_static", ROREG_FUNC(luat_lv_dropdown_set_options_static)},
    {"dropdown_add_option", ROREG_FUNC(luat_lv_dropdown_add_option)},
    {"dropdown_set_selected", ROREG_FUNC(luat_lv_dropdown_set_selected)},
    {"dropdown_set_dir", ROREG_FUNC(luat_lv_dropdown_set_dir)},
    {"dropdown_set_max_height", ROREG_FUNC(luat_lv_dropdown_set_max_height)},
    {"dropdown_set_show_selected", ROREG_FUNC(luat_lv_dropdown_set_show_selected)},
    {"dropdown_get_text", ROREG_FUNC(luat_lv_dropdown_get_text)},
    {"dropdown_get_options", ROREG_FUNC(luat_lv_dropdown_get_options)},
    {"dropdown_get_selected", ROREG_FUNC(luat_lv_dropdown_get_selected)},
    {"dropdown_get_option_cnt", ROREG_FUNC(luat_lv_dropdown_get_option_cnt)},
    {"dropdown_get_max_height", ROREG_FUNC(luat_lv_dropdown_get_max_height)},
    {"dropdown_get_symbol", ROREG_FUNC(luat_lv_dropdown_get_symbol)},
    {"dropdown_get_dir", ROREG_FUNC(luat_lv_dropdown_get_dir)},
    {"dropdown_get_show_selected", ROREG_FUNC(luat_lv_dropdown_get_show_selected)},
    {"dropdown_open", ROREG_FUNC(luat_lv_dropdown_open)},
    {"dropdown_close", ROREG_FUNC(luat_lv_dropdown_close)},


LUAT_LV_DROPDOWN_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_GAUGE
    {"gauge_create", ROREG_FUNC(luat_lv_gauge_create)},
    {"gauge_set_value", ROREG_FUNC(luat_lv_gauge_set_value)},
    {"gauge_set_range", ROREG_FUNC(luat_lv_gauge_set_range)},
    {"gauge_set_critical_value", ROREG_FUNC(luat_lv_gauge_set_critical_value)},
    {"gauge_set_scale", ROREG_FUNC(luat_lv_gauge_set_scale)},
    {"gauge_set_angle_offset", ROREG_FUNC(luat_lv_gauge_set_angle_offset)},
    {"gauge_set_needle_img", ROREG_FUNC(luat_lv_gauge_set_needle_img)},
    {"gauge_get_value", ROREG_FUNC(luat_lv_gauge_get_value)},
    {"gauge_get_needle_count", ROREG_FUNC(luat_lv_gauge_get_needle_count)},
    {"gauge_get_min_value", ROREG_FUNC(luat_lv_gauge_get_min_value)},
    {"gauge_get_max_value", ROREG_FUNC(luat_lv_gauge_get_max_value)},
    {"gauge_get_critical_value", ROREG_FUNC(luat_lv_gauge_get_critical_value)},
    {"gauge_get_label_count", ROREG_FUNC(luat_lv_gauge_get_label_count)},
    {"gauge_get_line_count", ROREG_FUNC(luat_lv_gauge_get_line_count)},
    {"gauge_get_scale_angle", ROREG_FUNC(luat_lv_gauge_get_scale_angle)},
    {"gauge_get_angle_offset", ROREG_FUNC(luat_lv_gauge_get_angle_offset)},
    {"gauge_get_needle_img", ROREG_FUNC(luat_lv_gauge_get_needle_img)},
    {"gauge_get_needle_img_pivot_x", ROREG_FUNC(luat_lv_gauge_get_needle_img_pivot_x)},
    {"gauge_get_needle_img_pivot_y", ROREG_FUNC(luat_lv_gauge_get_needle_img_pivot_y)},


LUAT_LV_GAUGE_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_IMG
    {"img_create", ROREG_FUNC(luat_lv_img_create)},
    {"img_set_auto_size", ROREG_FUNC(luat_lv_img_set_auto_size)},
    {"img_set_offset_x", ROREG_FUNC(luat_lv_img_set_offset_x)},
    {"img_set_offset_y", ROREG_FUNC(luat_lv_img_set_offset_y)},
    {"img_set_pivot", ROREG_FUNC(luat_lv_img_set_pivot)},
    {"img_set_angle", ROREG_FUNC(luat_lv_img_set_angle)},
    {"img_set_zoom", ROREG_FUNC(luat_lv_img_set_zoom)},
    {"img_set_antialias", ROREG_FUNC(luat_lv_img_set_antialias)},
    {"img_get_src", ROREG_FUNC(luat_lv_img_get_src)},
    {"img_get_file_name", ROREG_FUNC(luat_lv_img_get_file_name)},
    {"img_get_auto_size", ROREG_FUNC(luat_lv_img_get_auto_size)},
    {"img_get_offset_x", ROREG_FUNC(luat_lv_img_get_offset_x)},
    {"img_get_offset_y", ROREG_FUNC(luat_lv_img_get_offset_y)},
    {"img_get_angle", ROREG_FUNC(luat_lv_img_get_angle)},
    {"img_get_pivot", ROREG_FUNC(luat_lv_img_get_pivot)},
    {"img_get_zoom", ROREG_FUNC(luat_lv_img_get_zoom)},
    {"img_get_antialias", ROREG_FUNC(luat_lv_img_get_antialias)},

LUAT_LV_IMG_EX_RTL
#endif
#ifdef LUAT_USE_LVGL_IMGBTN
   {"imgbtn_create", ROREG_FUNC(luat_lv_imgbtn_create)},
    {"imgbtn_set_state", ROREG_FUNC(luat_lv_imgbtn_set_state)},
    {"imgbtn_toggle", ROREG_FUNC(luat_lv_imgbtn_toggle)},
    {"imgbtn_set_checkable", ROREG_FUNC(luat_lv_imgbtn_set_checkable)},
    {"imgbtn_get_src", ROREG_FUNC(luat_lv_imgbtn_get_src)},
    {"imgbtn_get_state", ROREG_FUNC(luat_lv_imgbtn_get_state)},
    {"imgbtn_get_checkable", ROREG_FUNC(luat_lv_imgbtn_get_checkable)},

LUAT_LV_IMGBTN_EX_RTL
#endif
#ifdef LUAT_USE_LVGL_KEYBOARD
   {"keyboard_create", ROREG_FUNC(luat_lv_keyboard_create)},
    {"keyboard_set_textarea", ROREG_FUNC(luat_lv_keyboard_set_textarea)},
    {"keyboard_set_mode", ROREG_FUNC(luat_lv_keyboard_set_mode)},
    {"keyboard_set_cursor_manage", ROREG_FUNC(luat_lv_keyboard_set_cursor_manage)},
    {"keyboard_get_textarea", ROREG_FUNC(luat_lv_keyboard_get_textarea)},
    {"keyboard_get_mode", ROREG_FUNC(luat_lv_keyboard_get_mode)},
    {"keyboard_get_cursor_manage", ROREG_FUNC(luat_lv_keyboard_get_cursor_manage)},


#endif
#ifdef LUAT_USE_LVGL_LABEL
    {"label_create", ROREG_FUNC(luat_lv_label_create)},
    {"label_set_text", ROREG_FUNC(luat_lv_label_set_text)},
    {"label_set_text_static", ROREG_FUNC(luat_lv_label_set_text_static)},
    {"label_set_long_mode", ROREG_FUNC(luat_lv_label_set_long_mode)},
    {"label_set_align", ROREG_FUNC(luat_lv_label_set_align)},
    {"label_set_recolor", ROREG_FUNC(luat_lv_label_set_recolor)},
    {"label_set_anim_speed", ROREG_FUNC(luat_lv_label_set_anim_speed)},
    {"label_set_text_sel_start", ROREG_FUNC(luat_lv_label_set_text_sel_start)},
    {"label_set_text_sel_end", ROREG_FUNC(luat_lv_label_set_text_sel_end)},
    {"label_get_text", ROREG_FUNC(luat_lv_label_get_text)},
    {"label_get_long_mode", ROREG_FUNC(luat_lv_label_get_long_mode)},
    {"label_get_align", ROREG_FUNC(luat_lv_label_get_align)},
    {"label_get_recolor", ROREG_FUNC(luat_lv_label_get_recolor)},
    {"label_get_anim_speed", ROREG_FUNC(luat_lv_label_get_anim_speed)},
    {"label_get_letter_pos", ROREG_FUNC(luat_lv_label_get_letter_pos)},
    {"label_get_letter_on", ROREG_FUNC(luat_lv_label_get_letter_on)},
    {"label_is_char_under_pos", ROREG_FUNC(luat_lv_label_is_char_under_pos)},
    {"label_get_text_sel_start", ROREG_FUNC(luat_lv_label_get_text_sel_start)},
    {"label_get_text_sel_end", ROREG_FUNC(luat_lv_label_get_text_sel_end)},
    {"label_get_style", ROREG_FUNC(luat_lv_label_get_style)},
    {"label_ins_text", ROREG_FUNC(luat_lv_label_ins_text)},
    {"label_cut_text", ROREG_FUNC(luat_lv_label_cut_text)},
    {"label_refr_text", ROREG_FUNC(luat_lv_label_refr_text)},

#endif
#ifdef LUAT_USE_LVGL_LED
    {"led_create", ROREG_FUNC(luat_lv_led_create)},
    {"led_set_bright", ROREG_FUNC(luat_lv_led_set_bright)},
    {"led_on", ROREG_FUNC(luat_lv_led_on)},
    {"led_off", ROREG_FUNC(luat_lv_led_off)},
    {"led_toggle", ROREG_FUNC(luat_lv_led_toggle)},
    {"led_get_bright", ROREG_FUNC(luat_lv_led_get_bright)},

#endif
#ifdef LUAT_USE_LVGL_LINE
    {"line_create", ROREG_FUNC(luat_lv_line_create)},
    {"line_set_auto_size", ROREG_FUNC(luat_lv_line_set_auto_size)},
    {"line_set_y_invert", ROREG_FUNC(luat_lv_line_set_y_invert)},
    {"line_get_auto_size", ROREG_FUNC(luat_lv_line_get_auto_size)},
    {"line_get_y_invert", ROREG_FUNC(luat_lv_line_get_y_invert)},
    
LUAT_LV_LINE_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_LIST
    {"list_create", ROREG_FUNC(luat_lv_list_create)},
    {"list_clean", ROREG_FUNC(luat_lv_list_clean)},
    {"list_add_btn", ROREG_FUNC(luat_lv_list_add_btn)},
    {"list_remove", ROREG_FUNC(luat_lv_list_remove)},
    {"list_focus_btn", ROREG_FUNC(luat_lv_list_focus_btn)},
    {"list_set_scrollbar_mode", ROREG_FUNC(luat_lv_list_set_scrollbar_mode)},
    {"list_set_scroll_propagation", ROREG_FUNC(luat_lv_list_set_scroll_propagation)},
    {"list_set_edge_flash", ROREG_FUNC(luat_lv_list_set_edge_flash)},
    {"list_set_anim_time", ROREG_FUNC(luat_lv_list_set_anim_time)},
    {"list_set_layout", ROREG_FUNC(luat_lv_list_set_layout)},
    {"list_get_btn_text", ROREG_FUNC(luat_lv_list_get_btn_text)},
    {"list_get_btn_label", ROREG_FUNC(luat_lv_list_get_btn_label)},
    {"list_get_btn_img", ROREG_FUNC(luat_lv_list_get_btn_img)},
    {"list_get_prev_btn", ROREG_FUNC(luat_lv_list_get_prev_btn)},
    {"list_get_next_btn", ROREG_FUNC(luat_lv_list_get_next_btn)},
    {"list_get_btn_index", ROREG_FUNC(luat_lv_list_get_btn_index)},
    {"list_get_size", ROREG_FUNC(luat_lv_list_get_size)},
    {"list_get_btn_selected", ROREG_FUNC(luat_lv_list_get_btn_selected)},
    {"list_get_layout", ROREG_FUNC(luat_lv_list_get_layout)},
    {"list_get_scrollbar_mode", ROREG_FUNC(luat_lv_list_get_scrollbar_mode)},
    {"list_get_scroll_propagation", ROREG_FUNC(luat_lv_list_get_scroll_propagation)},
    {"list_get_edge_flash", ROREG_FUNC(luat_lv_list_get_edge_flash)},
    {"list_get_anim_time", ROREG_FUNC(luat_lv_list_get_anim_time)},
    {"list_up", ROREG_FUNC(luat_lv_list_up)},
    {"list_down", ROREG_FUNC(luat_lv_list_down)},
    {"list_focus", ROREG_FUNC(luat_lv_list_focus)},


#endif
#ifdef LUAT_USE_LVGL_LINEMETER
    {"linemeter_create", ROREG_FUNC(luat_lv_linemeter_create)},
    {"linemeter_set_value", ROREG_FUNC(luat_lv_linemeter_set_value)},
    {"linemeter_set_range", ROREG_FUNC(luat_lv_linemeter_set_range)},
    {"linemeter_set_scale", ROREG_FUNC(luat_lv_linemeter_set_scale)},
    {"linemeter_set_angle_offset", ROREG_FUNC(luat_lv_linemeter_set_angle_offset)},
    {"linemeter_set_mirror", ROREG_FUNC(luat_lv_linemeter_set_mirror)},
    {"linemeter_get_value", ROREG_FUNC(luat_lv_linemeter_get_value)},
    {"linemeter_get_min_value", ROREG_FUNC(luat_lv_linemeter_get_min_value)},
    {"linemeter_get_max_value", ROREG_FUNC(luat_lv_linemeter_get_max_value)},
    {"linemeter_get_line_count", ROREG_FUNC(luat_lv_linemeter_get_line_count)},
    {"linemeter_get_scale_angle", ROREG_FUNC(luat_lv_linemeter_get_scale_angle)},
    {"linemeter_get_angle_offset", ROREG_FUNC(luat_lv_linemeter_get_angle_offset)},
    {"linemeter_draw_scale", ROREG_FUNC(luat_lv_linemeter_draw_scale)},
    {"linemeter_get_mirror", ROREG_FUNC(luat_lv_linemeter_get_mirror)},

#endif
#ifdef LUAT_USE_LVGL_MSGBOX
    {"msgbox_create", ROREG_FUNC(luat_lv_msgbox_create)},
    {"msgbox_set_text", ROREG_FUNC(luat_lv_msgbox_set_text)},
    {"msgbox_set_anim_time", ROREG_FUNC(luat_lv_msgbox_set_anim_time)},
    {"msgbox_start_auto_close", ROREG_FUNC(luat_lv_msgbox_start_auto_close)},
    {"msgbox_stop_auto_close", ROREG_FUNC(luat_lv_msgbox_stop_auto_close)},
    {"msgbox_set_recolor", ROREG_FUNC(luat_lv_msgbox_set_recolor)},
    {"msgbox_get_text", ROREG_FUNC(luat_lv_msgbox_get_text)},
    {"msgbox_get_active_btn", ROREG_FUNC(luat_lv_msgbox_get_active_btn)},
    {"msgbox_get_active_btn_text", ROREG_FUNC(luat_lv_msgbox_get_active_btn_text)},
    {"msgbox_get_anim_time", ROREG_FUNC(luat_lv_msgbox_get_anim_time)},
    {"msgbox_get_recolor", ROREG_FUNC(luat_lv_msgbox_get_recolor)},
    {"msgbox_get_btnmatrix", ROREG_FUNC(luat_lv_msgbox_get_btnmatrix)},

LUAT_LV_MSGBOX_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_OBJMASK
    {"objmask_create", ROREG_FUNC(luat_lv_objmask_create)},
    {"objmask_add_mask", ROREG_FUNC(luat_lv_objmask_add_mask)},
    {"objmask_update_mask", ROREG_FUNC(luat_lv_objmask_update_mask)},
    {"objmask_remove_mask", ROREG_FUNC(luat_lv_objmask_remove_mask)},

#endif
#ifdef LUAT_USE_LVGL_PAGE
    {"page_create", ROREG_FUNC(luat_lv_page_create)},
    {"page_clean", ROREG_FUNC(luat_lv_page_clean)},
    {"page_get_scrollable", ROREG_FUNC(luat_lv_page_get_scrollable)},
    {"page_get_anim_time", ROREG_FUNC(luat_lv_page_get_anim_time)},
    {"page_set_scrollbar_mode", ROREG_FUNC(luat_lv_page_set_scrollbar_mode)},
    {"page_set_anim_time", ROREG_FUNC(luat_lv_page_set_anim_time)},
    {"page_set_scroll_propagation", ROREG_FUNC(luat_lv_page_set_scroll_propagation)},
    {"page_set_edge_flash", ROREG_FUNC(luat_lv_page_set_edge_flash)},
    {"page_set_scrollable_fit4", ROREG_FUNC(luat_lv_page_set_scrollable_fit4)},
    {"page_set_scrollable_fit2", ROREG_FUNC(luat_lv_page_set_scrollable_fit2)},
    {"page_set_scrollable_fit", ROREG_FUNC(luat_lv_page_set_scrollable_fit)},
    {"page_set_scrl_width", ROREG_FUNC(luat_lv_page_set_scrl_width)},
    {"page_set_scrl_height", ROREG_FUNC(luat_lv_page_set_scrl_height)},
    {"page_set_scrl_layout", ROREG_FUNC(luat_lv_page_set_scrl_layout)},
    {"page_get_scrollbar_mode", ROREG_FUNC(luat_lv_page_get_scrollbar_mode)},
    {"page_get_scroll_propagation", ROREG_FUNC(luat_lv_page_get_scroll_propagation)},
    {"page_get_edge_flash", ROREG_FUNC(luat_lv_page_get_edge_flash)},
    {"page_get_width_fit", ROREG_FUNC(luat_lv_page_get_width_fit)},
    {"page_get_height_fit", ROREG_FUNC(luat_lv_page_get_height_fit)},
    {"page_get_width_grid", ROREG_FUNC(luat_lv_page_get_width_grid)},
    {"page_get_height_grid", ROREG_FUNC(luat_lv_page_get_height_grid)},
    {"page_get_scrl_width", ROREG_FUNC(luat_lv_page_get_scrl_width)},
    {"page_get_scrl_height", ROREG_FUNC(luat_lv_page_get_scrl_height)},
    {"page_get_scrl_layout", ROREG_FUNC(luat_lv_page_get_scrl_layout)},
    {"page_get_scrl_fit_left", ROREG_FUNC(luat_lv_page_get_scrl_fit_left)},
    {"page_get_scrl_fit_right", ROREG_FUNC(luat_lv_page_get_scrl_fit_right)},
    {"page_get_scrl_fit_top", ROREG_FUNC(luat_lv_page_get_scrl_fit_top)},
    {"page_get_scrl_fit_bottom", ROREG_FUNC(luat_lv_page_get_scrl_fit_bottom)},
    {"page_on_edge", ROREG_FUNC(luat_lv_page_on_edge)},
    {"page_glue_obj", ROREG_FUNC(luat_lv_page_glue_obj)},
    {"page_focus", ROREG_FUNC(luat_lv_page_focus)},
    {"page_scroll_hor", ROREG_FUNC(luat_lv_page_scroll_hor)},
    {"page_scroll_ver", ROREG_FUNC(luat_lv_page_scroll_ver)},
    {"page_start_edge_flash", ROREG_FUNC(luat_lv_page_start_edge_flash)},
    
#endif
#ifdef LUAT_USE_LVGL_SPINNER
#if LV_USE_ANIMATION
    {"spinner_create", ROREG_FUNC(luat_lv_spinner_create)},
    {"spinner_set_arc_length", ROREG_FUNC(luat_lv_spinner_set_arc_length)},
    {"spinner_set_spin_time", ROREG_FUNC(luat_lv_spinner_set_spin_time)},
    {"spinner_set_type", ROREG_FUNC(luat_lv_spinner_set_type)},
    {"spinner_set_dir", ROREG_FUNC(luat_lv_spinner_set_dir)},
    {"spinner_get_arc_length", ROREG_FUNC(luat_lv_spinner_get_arc_length)},
    {"spinner_get_spin_time", ROREG_FUNC(luat_lv_spinner_get_spin_time)},
    {"spinner_get_type", ROREG_FUNC(luat_lv_spinner_get_type)},
    {"spinner_get_dir", ROREG_FUNC(luat_lv_spinner_get_dir)},
#endif
#endif
#ifdef LUAT_USE_LVGL_ROLLER
    {"roller_create", ROREG_FUNC(luat_lv_roller_create)},
    {"roller_set_options", ROREG_FUNC(luat_lv_roller_set_options)},
    {"roller_set_align", ROREG_FUNC(luat_lv_roller_set_align)},
    {"roller_set_selected", ROREG_FUNC(luat_lv_roller_set_selected)},
    {"roller_set_visible_row_count", ROREG_FUNC(luat_lv_roller_set_visible_row_count)},
    {"roller_set_auto_fit", ROREG_FUNC(luat_lv_roller_set_auto_fit)},
    {"roller_set_anim_time", ROREG_FUNC(luat_lv_roller_set_anim_time)},
    {"roller_get_selected", ROREG_FUNC(luat_lv_roller_get_selected)},
    {"roller_get_option_cnt", ROREG_FUNC(luat_lv_roller_get_option_cnt)},
    {"roller_get_align", ROREG_FUNC(luat_lv_roller_get_align)},
    {"roller_get_auto_fit", ROREG_FUNC(luat_lv_roller_get_auto_fit)},
    {"roller_get_options", ROREG_FUNC(luat_lv_roller_get_options)},
    {"roller_get_anim_time", ROREG_FUNC(luat_lv_roller_get_anim_time)},

LUAT_LV_ROLLER_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_SLIDER
    {"slider_create", ROREG_FUNC(luat_lv_slider_create)},
    {"slider_set_value", ROREG_FUNC(luat_lv_slider_set_value)},
    {"slider_set_left_value", ROREG_FUNC(luat_lv_slider_set_left_value)},
    {"slider_set_range", ROREG_FUNC(luat_lv_slider_set_range)},
    {"slider_set_anim_time", ROREG_FUNC(luat_lv_slider_set_anim_time)},
    {"slider_set_type", ROREG_FUNC(luat_lv_slider_set_type)},
    {"slider_get_value", ROREG_FUNC(luat_lv_slider_get_value)},
    {"slider_get_left_value", ROREG_FUNC(luat_lv_slider_get_left_value)},
    {"slider_get_min_value", ROREG_FUNC(luat_lv_slider_get_min_value)},
    {"slider_get_max_value", ROREG_FUNC(luat_lv_slider_get_max_value)},
    {"slider_is_dragged", ROREG_FUNC(luat_lv_slider_is_dragged)},
    {"slider_get_anim_time", ROREG_FUNC(luat_lv_slider_get_anim_time)},
    {"slider_get_type", ROREG_FUNC(luat_lv_slider_get_type)},


#endif
#ifdef LUAT_USE_LVGL_SPINBOX
    {"spinbox_create", ROREG_FUNC(luat_lv_spinbox_create)},
    {"spinbox_set_rollover", ROREG_FUNC(luat_lv_spinbox_set_rollover)},
    {"spinbox_set_value", ROREG_FUNC(luat_lv_spinbox_set_value)},
    {"spinbox_set_digit_format", ROREG_FUNC(luat_lv_spinbox_set_digit_format)},
    {"spinbox_set_step", ROREG_FUNC(luat_lv_spinbox_set_step)},
    {"spinbox_set_range", ROREG_FUNC(luat_lv_spinbox_set_range)},
    {"spinbox_set_padding_left", ROREG_FUNC(luat_lv_spinbox_set_padding_left)},
    {"spinbox_get_rollover", ROREG_FUNC(luat_lv_spinbox_get_rollover)},
    {"spinbox_get_value", ROREG_FUNC(luat_lv_spinbox_get_value)},
    {"spinbox_get_step", ROREG_FUNC(luat_lv_spinbox_get_step)},
    {"spinbox_step_next", ROREG_FUNC(luat_lv_spinbox_step_next)},
    {"spinbox_step_prev", ROREG_FUNC(luat_lv_spinbox_step_prev)},
    {"spinbox_increment", ROREG_FUNC(luat_lv_spinbox_increment)},
    {"spinbox_decrement", ROREG_FUNC(luat_lv_spinbox_decrement)},

#endif
#ifdef LUAT_USE_LVGL_SWITCH
    {"switch_create", ROREG_FUNC(luat_lv_switch_create)},
    {"switch_on", ROREG_FUNC(luat_lv_switch_on)},
    {"switch_off", ROREG_FUNC(luat_lv_switch_off)},
    {"switch_toggle", ROREG_FUNC(luat_lv_switch_toggle)},
    {"switch_set_anim_time", ROREG_FUNC(luat_lv_switch_set_anim_time)},
    {"switch_get_state", ROREG_FUNC(luat_lv_switch_get_state)},
    {"switch_get_anim_time", ROREG_FUNC(luat_lv_switch_get_anim_time)},

#endif
#ifdef LUAT_USE_LVGL_TEXTAREA
    {"textarea_create", ROREG_FUNC(luat_lv_textarea_create)},
    {"textarea_add_char", ROREG_FUNC(luat_lv_textarea_add_char)},
    {"textarea_add_text", ROREG_FUNC(luat_lv_textarea_add_text)},
    {"textarea_del_char", ROREG_FUNC(luat_lv_textarea_del_char)},
    {"textarea_del_char_forward", ROREG_FUNC(luat_lv_textarea_del_char_forward)},
    {"textarea_set_text", ROREG_FUNC(luat_lv_textarea_set_text)},
    {"textarea_set_placeholder_text", ROREG_FUNC(luat_lv_textarea_set_placeholder_text)},
    {"textarea_set_cursor_pos", ROREG_FUNC(luat_lv_textarea_set_cursor_pos)},
    {"textarea_set_cursor_hidden", ROREG_FUNC(luat_lv_textarea_set_cursor_hidden)},
    {"textarea_set_cursor_click_pos", ROREG_FUNC(luat_lv_textarea_set_cursor_click_pos)},
    {"textarea_set_pwd_mode", ROREG_FUNC(luat_lv_textarea_set_pwd_mode)},
    {"textarea_set_one_line", ROREG_FUNC(luat_lv_textarea_set_one_line)},
    {"textarea_set_text_align", ROREG_FUNC(luat_lv_textarea_set_text_align)},
    {"textarea_set_accepted_chars", ROREG_FUNC(luat_lv_textarea_set_accepted_chars)},
    {"textarea_set_max_length", ROREG_FUNC(luat_lv_textarea_set_max_length)},
    {"textarea_set_insert_replace", ROREG_FUNC(luat_lv_textarea_set_insert_replace)},
    {"textarea_set_scrollbar_mode", ROREG_FUNC(luat_lv_textarea_set_scrollbar_mode)},
    {"textarea_set_scroll_propagation", ROREG_FUNC(luat_lv_textarea_set_scroll_propagation)},
    {"textarea_set_edge_flash", ROREG_FUNC(luat_lv_textarea_set_edge_flash)},
    {"textarea_set_text_sel", ROREG_FUNC(luat_lv_textarea_set_text_sel)},
    {"textarea_set_pwd_show_time", ROREG_FUNC(luat_lv_textarea_set_pwd_show_time)},
    {"textarea_set_cursor_blink_time", ROREG_FUNC(luat_lv_textarea_set_cursor_blink_time)},
    {"textarea_get_text", ROREG_FUNC(luat_lv_textarea_get_text)},
    {"textarea_get_placeholder_text", ROREG_FUNC(luat_lv_textarea_get_placeholder_text)},
    {"textarea_get_label", ROREG_FUNC(luat_lv_textarea_get_label)},
    {"textarea_get_cursor_pos", ROREG_FUNC(luat_lv_textarea_get_cursor_pos)},
    {"textarea_get_cursor_hidden", ROREG_FUNC(luat_lv_textarea_get_cursor_hidden)},
    {"textarea_get_cursor_click_pos", ROREG_FUNC(luat_lv_textarea_get_cursor_click_pos)},
    {"textarea_get_pwd_mode", ROREG_FUNC(luat_lv_textarea_get_pwd_mode)},
    {"textarea_get_one_line", ROREG_FUNC(luat_lv_textarea_get_one_line)},
    {"textarea_get_accepted_chars", ROREG_FUNC(luat_lv_textarea_get_accepted_chars)},
    {"textarea_get_max_length", ROREG_FUNC(luat_lv_textarea_get_max_length)},
    {"textarea_get_scrollbar_mode", ROREG_FUNC(luat_lv_textarea_get_scrollbar_mode)},
    {"textarea_get_scroll_propagation", ROREG_FUNC(luat_lv_textarea_get_scroll_propagation)},
    {"textarea_get_edge_flash", ROREG_FUNC(luat_lv_textarea_get_edge_flash)},
    {"textarea_text_is_selected", ROREG_FUNC(luat_lv_textarea_text_is_selected)},
    {"textarea_get_text_sel_en", ROREG_FUNC(luat_lv_textarea_get_text_sel_en)},
    {"textarea_get_pwd_show_time", ROREG_FUNC(luat_lv_textarea_get_pwd_show_time)},
    {"textarea_get_cursor_blink_time", ROREG_FUNC(luat_lv_textarea_get_cursor_blink_time)},
    {"textarea_clear_selection", ROREG_FUNC(luat_lv_textarea_clear_selection)},
    {"textarea_cursor_right", ROREG_FUNC(luat_lv_textarea_cursor_right)},
    {"textarea_cursor_left", ROREG_FUNC(luat_lv_textarea_cursor_left)},
    {"textarea_cursor_down", ROREG_FUNC(luat_lv_textarea_cursor_down)},
    {"textarea_cursor_up", ROREG_FUNC(luat_lv_textarea_cursor_up)},


#endif
#ifdef LUAT_USE_LVGL_TABLE
    {"table_create", ROREG_FUNC(luat_lv_table_create)},
    {"table_set_cell_value", ROREG_FUNC(luat_lv_table_set_cell_value)},
    {"table_set_row_cnt", ROREG_FUNC(luat_lv_table_set_row_cnt)},
    {"table_set_col_cnt", ROREG_FUNC(luat_lv_table_set_col_cnt)},
    {"table_set_col_width", ROREG_FUNC(luat_lv_table_set_col_width)},
    {"table_set_cell_align", ROREG_FUNC(luat_lv_table_set_cell_align)},
    {"table_set_cell_type", ROREG_FUNC(luat_lv_table_set_cell_type)},
    {"table_set_cell_crop", ROREG_FUNC(luat_lv_table_set_cell_crop)},
    {"table_set_cell_merge_right", ROREG_FUNC(luat_lv_table_set_cell_merge_right)},
    {"table_get_cell_value", ROREG_FUNC(luat_lv_table_get_cell_value)},
    {"table_get_row_cnt", ROREG_FUNC(luat_lv_table_get_row_cnt)},
    {"table_get_col_cnt", ROREG_FUNC(luat_lv_table_get_col_cnt)},
    {"table_get_col_width", ROREG_FUNC(luat_lv_table_get_col_width)},
    {"table_get_cell_align", ROREG_FUNC(luat_lv_table_get_cell_align)},
    {"table_get_cell_type", ROREG_FUNC(luat_lv_table_get_cell_type)},
    {"table_get_cell_crop", ROREG_FUNC(luat_lv_table_get_cell_crop)},
    {"table_get_cell_merge_right", ROREG_FUNC(luat_lv_table_get_cell_merge_right)},
    {"table_get_pressed_cell", ROREG_FUNC(luat_lv_table_get_pressed_cell)},

#endif
#ifdef LUAT_USE_LVGL_TABVIEW
   {"tabview_create", ROREG_FUNC(luat_lv_tabview_create)},
    {"tabview_add_tab", ROREG_FUNC(luat_lv_tabview_add_tab)},
    {"tabview_clean_tab", ROREG_FUNC(luat_lv_tabview_clean_tab)},
    {"tabview_set_tab_act", ROREG_FUNC(luat_lv_tabview_set_tab_act)},
    {"tabview_set_tab_name", ROREG_FUNC(luat_lv_tabview_set_tab_name)},
    {"tabview_set_anim_time", ROREG_FUNC(luat_lv_tabview_set_anim_time)},
    {"tabview_set_btns_pos", ROREG_FUNC(luat_lv_tabview_set_btns_pos)},
    {"tabview_get_tab_act", ROREG_FUNC(luat_lv_tabview_get_tab_act)},
    {"tabview_get_tab_count", ROREG_FUNC(luat_lv_tabview_get_tab_count)},
    {"tabview_get_tab", ROREG_FUNC(luat_lv_tabview_get_tab)},
    {"tabview_get_anim_time", ROREG_FUNC(luat_lv_tabview_get_anim_time)},
    {"tabview_get_btns_pos", ROREG_FUNC(luat_lv_tabview_get_btns_pos)},

#endif
#ifdef LUAT_USE_LVGL_TILEVIEW
    {"tileview_create", ROREG_FUNC(luat_lv_tileview_create)},
    {"tileview_add_element", ROREG_FUNC(luat_lv_tileview_add_element)},
    {"tileview_set_tile_act", ROREG_FUNC(luat_lv_tileview_set_tile_act)},
    {"tileview_set_edge_flash", ROREG_FUNC(luat_lv_tileview_set_edge_flash)},
    {"tileview_set_anim_time", ROREG_FUNC(luat_lv_tileview_set_anim_time)},
    {"tileview_get_tile_act", ROREG_FUNC(luat_lv_tileview_get_tile_act)},
    {"tileview_get_edge_flash", ROREG_FUNC(luat_lv_tileview_get_edge_flash)},
    {"tileview_get_anim_time", ROREG_FUNC(luat_lv_tileview_get_anim_time)},

LUAT_LV_TILEVIEW_EX_RLT
#endif
#ifdef LUAT_USE_LVGL_WIN
    {"win_create", ROREG_FUNC(luat_lv_win_create)},
    {"win_clean", ROREG_FUNC(luat_lv_win_clean)},
    {"win_add_btn_right", ROREG_FUNC(luat_lv_win_add_btn_right)},
    {"win_add_btn_left", ROREG_FUNC(luat_lv_win_add_btn_left)},
    {"win_set_title", ROREG_FUNC(luat_lv_win_set_title)},
    {"win_set_header_height", ROREG_FUNC(luat_lv_win_set_header_height)},
    {"win_set_btn_width", ROREG_FUNC(luat_lv_win_set_btn_width)},
    {"win_set_content_size", ROREG_FUNC(luat_lv_win_set_content_size)},
    {"win_set_layout", ROREG_FUNC(luat_lv_win_set_layout)},
    {"win_set_scrollbar_mode", ROREG_FUNC(luat_lv_win_set_scrollbar_mode)},
    {"win_set_anim_time", ROREG_FUNC(luat_lv_win_set_anim_time)},
    {"win_set_drag", ROREG_FUNC(luat_lv_win_set_drag)},
    {"win_title_set_alignment", ROREG_FUNC(luat_lv_win_title_set_alignment)},
    {"win_get_title", ROREG_FUNC(luat_lv_win_get_title)},
    {"win_get_content", ROREG_FUNC(luat_lv_win_get_content)},
    {"win_get_header_height", ROREG_FUNC(luat_lv_win_get_header_height)},
    {"win_get_btn_width", ROREG_FUNC(luat_lv_win_get_btn_width)},
    {"win_get_from_btn", ROREG_FUNC(luat_lv_win_get_from_btn)},
    {"win_get_layout", ROREG_FUNC(luat_lv_win_get_layout)},
    {"win_get_sb_mode", ROREG_FUNC(luat_lv_win_get_sb_mode)},
    {"win_get_anim_time", ROREG_FUNC(luat_lv_win_get_anim_time)},
    {"win_get_width", ROREG_FUNC(luat_lv_win_get_width)},
    {"win_get_drag", ROREG_FUNC(luat_lv_win_get_drag)},
    {"win_title_get_alignment", ROREG_FUNC(luat_lv_win_title_get_alignment)},
    {"win_focus", ROREG_FUNC(luat_lv_win_focus)},
    {"win_scroll_hor", ROREG_FUNC(luat_lv_win_scroll_hor)},
    {"win_scroll_ver", ROREG_FUNC(luat_lv_win_scroll_ver)},

#endif

// 图像库
LUAT_LV_QRCODE_RLT
#if defined(LUA_USE_LINUX) || defined(LUA_USE_WINDOWS) || defined(LUA_USE_MACOSX)
LUAT_LV_GIF_RLT
#endif

// 回调
LUAT_LV_CB_RLT
// {"obj_add_event_cb", ROREG_FUNC(luat_lv_obj_add_event_cb)},
// {"obj_remove_event_cb", ROREG_FUNC(luat_lv_obj_remove_event_cb)},
// {"obj_remove_event_cb_with_user_data", ROREG_FUNC(luat_lv_obj_remove_event_cb_with_user_data)},
// {"keyboard_def_event_cb", ROREG_FUNC(luat_lv_keyboard_def_event_cb)},


// 额外添加的函数
LUAT_LV_EX_RLT
// LUAT_LV_WIDGETS_EX_RLT

// 字体API
{"font_get", ROREG_FUNC(luat_lv_font_get)},
{"font_load", ROREG_FUNC(luat_lv_font_load)},
{"font_free", ROREG_FUNC(luat_lv_font_free)},

// 结构体
#if LV_USE_ANIMATION
{"anim_t", ROREG_FUNC(luat_lv_struct_anim_t)},
#endif
{"area_t", ROREG_FUNC(luat_lv_struct_area_t)},
{"calendar_date_t", ROREG_FUNC(luat_lv_calendar_date_t)},
{"draw_rect_dsc_t", ROREG_FUNC(luat_lv_draw_rect_dsc_t)},
{"draw_label_dsc_t", ROREG_FUNC(luat_lv_draw_label_dsc_t)},
{"draw_img_dsc_t", ROREG_FUNC(luat_lv_draw_img_dsc_t)},
{"img_dsc_t", ROREG_FUNC(luat_lv_img_dsc_t)},
{"draw_line_dsc_t", ROREG_FUNC(luat_lv_draw_line_dsc_t)},

// 常量
    {"RES_INV", ROREG_INT(LV_RES_INV)},
    {"RES_OK", ROREG_INT(LV_RES_OK)},
    {"OPA_TRANSP", ROREG_INT(LV_OPA_TRANSP)},
    {"OPA_0", ROREG_INT(LV_OPA_0)},
    {"OPA_10", ROREG_INT(LV_OPA_10)},
    {"OPA_20", ROREG_INT(LV_OPA_20)},
    {"OPA_30", ROREG_INT(LV_OPA_30)},
    {"OPA_40", ROREG_INT(LV_OPA_40)},
    {"OPA_50", ROREG_INT(LV_OPA_50)},
    {"OPA_60", ROREG_INT(LV_OPA_60)},
    {"OPA_70", ROREG_INT(LV_OPA_70)},
    {"OPA_80", ROREG_INT(LV_OPA_80)},
    {"OPA_90", ROREG_INT(LV_OPA_90)},
    {"OPA_100", ROREG_INT(LV_OPA_100)},
    {"OPA_COVER", ROREG_INT(LV_OPA_COVER)},
    {"ALIGN_CENTER", ROREG_INT(LV_ALIGN_CENTER)},
    {"ALIGN_IN_TOP_LEFT", ROREG_INT(LV_ALIGN_IN_TOP_LEFT)},
    {"ALIGN_IN_TOP_MID", ROREG_INT(LV_ALIGN_IN_TOP_MID)},
    {"ALIGN_IN_TOP_RIGHT", ROREG_INT(LV_ALIGN_IN_TOP_RIGHT)},
    {"ALIGN_IN_BOTTOM_LEFT", ROREG_INT(LV_ALIGN_IN_BOTTOM_LEFT)},
    {"ALIGN_IN_BOTTOM_MID", ROREG_INT(LV_ALIGN_IN_BOTTOM_MID)},
    {"ALIGN_IN_BOTTOM_RIGHT", ROREG_INT(LV_ALIGN_IN_BOTTOM_RIGHT)},
    {"ALIGN_IN_LEFT_MID", ROREG_INT(LV_ALIGN_IN_LEFT_MID)},
    {"ALIGN_IN_RIGHT_MID", ROREG_INT(LV_ALIGN_IN_RIGHT_MID)},
    {"ALIGN_OUT_TOP_LEFT", ROREG_INT(LV_ALIGN_OUT_TOP_LEFT)},
    {"ALIGN_OUT_TOP_MID", ROREG_INT(LV_ALIGN_OUT_TOP_MID)},
    {"ALIGN_OUT_TOP_RIGHT", ROREG_INT(LV_ALIGN_OUT_TOP_RIGHT)},
    {"ALIGN_OUT_BOTTOM_LEFT", ROREG_INT(LV_ALIGN_OUT_BOTTOM_LEFT)},
    {"ALIGN_OUT_BOTTOM_MID", ROREG_INT(LV_ALIGN_OUT_BOTTOM_MID)},
    {"ALIGN_OUT_BOTTOM_RIGHT", ROREG_INT(LV_ALIGN_OUT_BOTTOM_RIGHT)},
    {"ALIGN_OUT_LEFT_TOP", ROREG_INT(LV_ALIGN_OUT_LEFT_TOP)},
    {"ALIGN_OUT_LEFT_MID", ROREG_INT(LV_ALIGN_OUT_LEFT_MID)},
    {"ALIGN_OUT_LEFT_BOTTOM", ROREG_INT(LV_ALIGN_OUT_LEFT_BOTTOM)},
    {"ALIGN_OUT_RIGHT_TOP", ROREG_INT(LV_ALIGN_OUT_RIGHT_TOP)},
    {"ALIGN_OUT_RIGHT_MID", ROREG_INT(LV_ALIGN_OUT_RIGHT_MID)},
    {"ALIGN_OUT_RIGHT_BOTTOM", ROREG_INT(LV_ALIGN_OUT_RIGHT_BOTTOM)},
    {"TASK_PRIO_OFF", ROREG_INT(LV_TASK_PRIO_OFF)},
    {"TASK_PRIO_LOWEST", ROREG_INT(LV_TASK_PRIO_LOWEST)},
    {"TASK_PRIO_LOW", ROREG_INT(LV_TASK_PRIO_LOW)},
    {"TASK_PRIO_MID", ROREG_INT(LV_TASK_PRIO_MID)},
    {"TASK_PRIO_HIGH", ROREG_INT(LV_TASK_PRIO_HIGH)},
    {"TASK_PRIO_HIGHEST", ROREG_INT(LV_TASK_PRIO_HIGHEST)},
    {"DISP_ROT_NONE", ROREG_INT(LV_DISP_ROT_NONE)},
    {"DISP_ROT_90", ROREG_INT(LV_DISP_ROT_90)},
    {"DISP_ROT_180", ROREG_INT(LV_DISP_ROT_180)},
    {"DISP_ROT_270", ROREG_INT(LV_DISP_ROT_270)},
    {"DISP_SIZE_SMALL", ROREG_INT(LV_DISP_SIZE_SMALL)},
    {"DISP_SIZE_MEDIUM", ROREG_INT(LV_DISP_SIZE_MEDIUM)},
    {"DISP_SIZE_LARGE", ROREG_INT(LV_DISP_SIZE_LARGE)},
    {"DISP_SIZE_EXTRA_LARGE", ROREG_INT(LV_DISP_SIZE_EXTRA_LARGE)},
    {"INDEV_TYPE_NONE", ROREG_INT(LV_INDEV_TYPE_NONE)},
    {"INDEV_TYPE_POINTER", ROREG_INT(LV_INDEV_TYPE_POINTER)},
    {"INDEV_TYPE_KEYPAD", ROREG_INT(LV_INDEV_TYPE_KEYPAD)},
    {"INDEV_TYPE_BUTTON", ROREG_INT(LV_INDEV_TYPE_BUTTON)},
    {"INDEV_TYPE_ENCODER", ROREG_INT(LV_INDEV_TYPE_ENCODER)},
    {"INDEV_STATE_REL", ROREG_INT(LV_INDEV_STATE_REL)},
    {"INDEV_STATE_PR", ROREG_INT(LV_INDEV_STATE_PR)},
    {"DRAG_DIR_HOR", ROREG_INT(LV_DRAG_DIR_HOR)},
    {"DRAG_DIR_VER", ROREG_INT(LV_DRAG_DIR_VER)},
    {"DRAG_DIR_BOTH", ROREG_INT(LV_DRAG_DIR_BOTH)},
    {"DRAG_DIR_ONE", ROREG_INT(LV_DRAG_DIR_ONE)},
    {"GESTURE_DIR_TOP", ROREG_INT(LV_GESTURE_DIR_TOP)},
    {"GESTURE_DIR_BOTTOM", ROREG_INT(LV_GESTURE_DIR_BOTTOM)},
    {"GESTURE_DIR_LEFT", ROREG_INT(LV_GESTURE_DIR_LEFT)},
    {"GESTURE_DIR_RIGHT", ROREG_INT(LV_GESTURE_DIR_RIGHT)},
    {"FONT_SUBPX_NONE", ROREG_INT(LV_FONT_SUBPX_NONE)},
    {"FONT_SUBPX_HOR", ROREG_INT(LV_FONT_SUBPX_HOR)},
    {"FONT_SUBPX_VER", ROREG_INT(LV_FONT_SUBPX_VER)},
    {"FONT_SUBPX_BOTH", ROREG_INT(LV_FONT_SUBPX_BOTH)},
    {"ANIM_OFF", ROREG_INT(LV_ANIM_OFF)},
    {"ANIM_ON", ROREG_INT(LV_ANIM_ON)},
    {"DRAW_MASK_RES_TRANSP", ROREG_INT(LV_DRAW_MASK_RES_TRANSP)},
    {"DRAW_MASK_RES_FULL_COVER", ROREG_INT(LV_DRAW_MASK_RES_FULL_COVER)},
    {"DRAW_MASK_RES_CHANGED", ROREG_INT(LV_DRAW_MASK_RES_CHANGED)},
    {"DRAW_MASK_RES_UNKNOWN", ROREG_INT(LV_DRAW_MASK_RES_UNKNOWN)},
    {"DRAW_MASK_TYPE_LINE", ROREG_INT(LV_DRAW_MASK_TYPE_LINE)},
    {"DRAW_MASK_TYPE_ANGLE", ROREG_INT(LV_DRAW_MASK_TYPE_ANGLE)},
    {"DRAW_MASK_TYPE_RADIUS", ROREG_INT(LV_DRAW_MASK_TYPE_RADIUS)},
    {"DRAW_MASK_TYPE_FADE", ROREG_INT(LV_DRAW_MASK_TYPE_FADE)},
    {"DRAW_MASK_TYPE_MAP", ROREG_INT(LV_DRAW_MASK_TYPE_MAP)},
    {"DRAW_MASK_LINE_SIDE_LEFT", ROREG_INT(LV_DRAW_MASK_LINE_SIDE_LEFT)},
    {"DRAW_MASK_LINE_SIDE_RIGHT", ROREG_INT(LV_DRAW_MASK_LINE_SIDE_RIGHT)},
    {"DRAW_MASK_LINE_SIDE_TOP", ROREG_INT(LV_DRAW_MASK_LINE_SIDE_TOP)},
    {"DRAW_MASK_LINE_SIDE_BOTTOM", ROREG_INT(LV_DRAW_MASK_LINE_SIDE_BOTTOM)},
    {"BLEND_MODE_NORMAL", ROREG_INT(LV_BLEND_MODE_NORMAL)},
    {"BLEND_MODE_ADDITIVE", ROREG_INT(LV_BLEND_MODE_ADDITIVE)},
    {"BLEND_MODE_SUBTRACTIVE", ROREG_INT(LV_BLEND_MODE_SUBTRACTIVE)},
    {"BORDER_SIDE_NONE", ROREG_INT(LV_BORDER_SIDE_NONE)},
    {"BORDER_SIDE_BOTTOM", ROREG_INT(LV_BORDER_SIDE_BOTTOM)},
    {"BORDER_SIDE_TOP", ROREG_INT(LV_BORDER_SIDE_TOP)},
    {"BORDER_SIDE_LEFT", ROREG_INT(LV_BORDER_SIDE_LEFT)},
    {"BORDER_SIDE_RIGHT", ROREG_INT(LV_BORDER_SIDE_RIGHT)},
    {"BORDER_SIDE_FULL", ROREG_INT(LV_BORDER_SIDE_FULL)},
    {"BORDER_SIDE_INTERNAL", ROREG_INT(LV_BORDER_SIDE_INTERNAL)},
    {"GRAD_DIR_NONE", ROREG_INT(LV_GRAD_DIR_NONE)},
    {"GRAD_DIR_VER", ROREG_INT(LV_GRAD_DIR_VER)},
    {"GRAD_DIR_HOR", ROREG_INT(LV_GRAD_DIR_HOR)},
    {"TEXT_DECOR_NONE", ROREG_INT(LV_TEXT_DECOR_NONE)},
    {"TEXT_DECOR_UNDERLINE", ROREG_INT(LV_TEXT_DECOR_UNDERLINE)},
    {"TEXT_DECOR_STRIKETHROUGH", ROREG_INT(LV_TEXT_DECOR_STRIKETHROUGH)},
    {"STYLE_RADIUS", ROREG_INT(LV_STYLE_RADIUS)},
    {"STYLE_CLIP_CORNER", ROREG_INT(LV_STYLE_CLIP_CORNER)},
    {"STYLE_SIZE", ROREG_INT(LV_STYLE_SIZE)},
    {"STYLE_TRANSFORM_WIDTH", ROREG_INT(LV_STYLE_TRANSFORM_WIDTH)},
    {"STYLE_TRANSFORM_HEIGHT", ROREG_INT(LV_STYLE_TRANSFORM_HEIGHT)},
    {"STYLE_TRANSFORM_ANGLE", ROREG_INT(LV_STYLE_TRANSFORM_ANGLE)},
    {"STYLE_TRANSFORM_ZOOM", ROREG_INT(LV_STYLE_TRANSFORM_ZOOM)},
    {"STYLE_OPA_SCALE", ROREG_INT(LV_STYLE_OPA_SCALE)},
    {"STYLE_PAD_TOP", ROREG_INT(LV_STYLE_PAD_TOP)},
    {"STYLE_PAD_BOTTOM", ROREG_INT(LV_STYLE_PAD_BOTTOM)},
    {"STYLE_PAD_LEFT", ROREG_INT(LV_STYLE_PAD_LEFT)},
    {"STYLE_PAD_RIGHT", ROREG_INT(LV_STYLE_PAD_RIGHT)},
    {"STYLE_PAD_INNER", ROREG_INT(LV_STYLE_PAD_INNER)},
    {"STYLE_MARGIN_TOP", ROREG_INT(LV_STYLE_MARGIN_TOP)},
    {"STYLE_MARGIN_BOTTOM", ROREG_INT(LV_STYLE_MARGIN_BOTTOM)},
    {"STYLE_MARGIN_LEFT", ROREG_INT(LV_STYLE_MARGIN_LEFT)},
    {"STYLE_MARGIN_RIGHT", ROREG_INT(LV_STYLE_MARGIN_RIGHT)},
    {"STYLE_BG_BLEND_MODE", ROREG_INT(LV_STYLE_BG_BLEND_MODE)},
    {"STYLE_BG_MAIN_STOP", ROREG_INT(LV_STYLE_BG_MAIN_STOP)},
    {"STYLE_BG_GRAD_STOP", ROREG_INT(LV_STYLE_BG_GRAD_STOP)},
    {"STYLE_BG_GRAD_DIR", ROREG_INT(LV_STYLE_BG_GRAD_DIR)},
    {"STYLE_BG_COLOR", ROREG_INT(LV_STYLE_BG_COLOR)},
    {"STYLE_BG_GRAD_COLOR", ROREG_INT(LV_STYLE_BG_GRAD_COLOR)},
    {"STYLE_BG_OPA", ROREG_INT(LV_STYLE_BG_OPA)},
    {"STYLE_BORDER_WIDTH", ROREG_INT(LV_STYLE_BORDER_WIDTH)},
    {"STYLE_BORDER_SIDE", ROREG_INT(LV_STYLE_BORDER_SIDE)},
    {"STYLE_BORDER_BLEND_MODE", ROREG_INT(LV_STYLE_BORDER_BLEND_MODE)},
    {"STYLE_BORDER_POST", ROREG_INT(LV_STYLE_BORDER_POST)},
    {"STYLE_BORDER_COLOR", ROREG_INT(LV_STYLE_BORDER_COLOR)},
    {"STYLE_BORDER_OPA", ROREG_INT(LV_STYLE_BORDER_OPA)},
    {"STYLE_OUTLINE_WIDTH", ROREG_INT(LV_STYLE_OUTLINE_WIDTH)},
    {"STYLE_OUTLINE_PAD", ROREG_INT(LV_STYLE_OUTLINE_PAD)},
    {"STYLE_OUTLINE_BLEND_MODE", ROREG_INT(LV_STYLE_OUTLINE_BLEND_MODE)},
    {"STYLE_OUTLINE_COLOR", ROREG_INT(LV_STYLE_OUTLINE_COLOR)},
    {"STYLE_OUTLINE_OPA", ROREG_INT(LV_STYLE_OUTLINE_OPA)},
    {"STYLE_SHADOW_WIDTH", ROREG_INT(LV_STYLE_SHADOW_WIDTH)},
    {"STYLE_SHADOW_OFS_X", ROREG_INT(LV_STYLE_SHADOW_OFS_X)},
    {"STYLE_SHADOW_OFS_Y", ROREG_INT(LV_STYLE_SHADOW_OFS_Y)},
    {"STYLE_SHADOW_SPREAD", ROREG_INT(LV_STYLE_SHADOW_SPREAD)},
    {"STYLE_SHADOW_BLEND_MODE", ROREG_INT(LV_STYLE_SHADOW_BLEND_MODE)},
    {"STYLE_SHADOW_COLOR", ROREG_INT(LV_STYLE_SHADOW_COLOR)},
    {"STYLE_SHADOW_OPA", ROREG_INT(LV_STYLE_SHADOW_OPA)},
    {"STYLE_PATTERN_BLEND_MODE", ROREG_INT(LV_STYLE_PATTERN_BLEND_MODE)},
    {"STYLE_PATTERN_REPEAT", ROREG_INT(LV_STYLE_PATTERN_REPEAT)},
    {"STYLE_PATTERN_RECOLOR", ROREG_INT(LV_STYLE_PATTERN_RECOLOR)},
    {"STYLE_PATTERN_OPA", ROREG_INT(LV_STYLE_PATTERN_OPA)},
    {"STYLE_PATTERN_RECOLOR_OPA", ROREG_INT(LV_STYLE_PATTERN_RECOLOR_OPA)},
    {"STYLE_PATTERN_IMAGE", ROREG_INT(LV_STYLE_PATTERN_IMAGE)},
    {"STYLE_VALUE_LETTER_SPACE", ROREG_INT(LV_STYLE_VALUE_LETTER_SPACE)},
    {"STYLE_VALUE_LINE_SPACE", ROREG_INT(LV_STYLE_VALUE_LINE_SPACE)},
    {"STYLE_VALUE_BLEND_MODE", ROREG_INT(LV_STYLE_VALUE_BLEND_MODE)},
    {"STYLE_VALUE_OFS_X", ROREG_INT(LV_STYLE_VALUE_OFS_X)},
    {"STYLE_VALUE_OFS_Y", ROREG_INT(LV_STYLE_VALUE_OFS_Y)},
    {"STYLE_VALUE_ALIGN", ROREG_INT(LV_STYLE_VALUE_ALIGN)},
    {"STYLE_VALUE_COLOR", ROREG_INT(LV_STYLE_VALUE_COLOR)},
    {"STYLE_VALUE_OPA", ROREG_INT(LV_STYLE_VALUE_OPA)},
    {"STYLE_VALUE_FONT", ROREG_INT(LV_STYLE_VALUE_FONT)},
    {"STYLE_VALUE_STR", ROREG_INT(LV_STYLE_VALUE_STR)},
    {"STYLE_TEXT_LETTER_SPACE", ROREG_INT(LV_STYLE_TEXT_LETTER_SPACE)},
    {"STYLE_TEXT_LINE_SPACE", ROREG_INT(LV_STYLE_TEXT_LINE_SPACE)},
    {"STYLE_TEXT_DECOR", ROREG_INT(LV_STYLE_TEXT_DECOR)},
    {"STYLE_TEXT_BLEND_MODE", ROREG_INT(LV_STYLE_TEXT_BLEND_MODE)},
    {"STYLE_TEXT_COLOR", ROREG_INT(LV_STYLE_TEXT_COLOR)},
    {"STYLE_TEXT_SEL_COLOR", ROREG_INT(LV_STYLE_TEXT_SEL_COLOR)},
    {"STYLE_TEXT_SEL_BG_COLOR", ROREG_INT(LV_STYLE_TEXT_SEL_BG_COLOR)},
    {"STYLE_TEXT_OPA", ROREG_INT(LV_STYLE_TEXT_OPA)},
    {"STYLE_TEXT_FONT", ROREG_INT(LV_STYLE_TEXT_FONT)},
    {"STYLE_LINE_WIDTH", ROREG_INT(LV_STYLE_LINE_WIDTH)},
    {"STYLE_LINE_BLEND_MODE", ROREG_INT(LV_STYLE_LINE_BLEND_MODE)},
    {"STYLE_LINE_DASH_WIDTH", ROREG_INT(LV_STYLE_LINE_DASH_WIDTH)},
    {"STYLE_LINE_DASH_GAP", ROREG_INT(LV_STYLE_LINE_DASH_GAP)},
    {"STYLE_LINE_ROUNDED", ROREG_INT(LV_STYLE_LINE_ROUNDED)},
    {"STYLE_LINE_COLOR", ROREG_INT(LV_STYLE_LINE_COLOR)},
    {"STYLE_LINE_OPA", ROREG_INT(LV_STYLE_LINE_OPA)},
    {"STYLE_IMAGE_BLEND_MODE", ROREG_INT(LV_STYLE_IMAGE_BLEND_MODE)},
    {"STYLE_IMAGE_RECOLOR", ROREG_INT(LV_STYLE_IMAGE_RECOLOR)},
    {"STYLE_IMAGE_OPA", ROREG_INT(LV_STYLE_IMAGE_OPA)},
    {"STYLE_IMAGE_RECOLOR_OPA", ROREG_INT(LV_STYLE_IMAGE_RECOLOR_OPA)},
    {"STYLE_TRANSITION_TIME", ROREG_INT(LV_STYLE_TRANSITION_TIME)},
    {"STYLE_TRANSITION_DELAY", ROREG_INT(LV_STYLE_TRANSITION_DELAY)},
    {"STYLE_TRANSITION_PROP_1", ROREG_INT(LV_STYLE_TRANSITION_PROP_1)},
    {"STYLE_TRANSITION_PROP_2", ROREG_INT(LV_STYLE_TRANSITION_PROP_2)},
    {"STYLE_TRANSITION_PROP_3", ROREG_INT(LV_STYLE_TRANSITION_PROP_3)},
    {"STYLE_TRANSITION_PROP_4", ROREG_INT(LV_STYLE_TRANSITION_PROP_4)},
    {"STYLE_TRANSITION_PROP_5", ROREG_INT(LV_STYLE_TRANSITION_PROP_5)},
    {"STYLE_TRANSITION_PROP_6", ROREG_INT(LV_STYLE_TRANSITION_PROP_6)},
    {"STYLE_TRANSITION_PATH", ROREG_INT(LV_STYLE_TRANSITION_PATH)},
    {"STYLE_SCALE_WIDTH", ROREG_INT(LV_STYLE_SCALE_WIDTH)},
    {"STYLE_SCALE_BORDER_WIDTH", ROREG_INT(LV_STYLE_SCALE_BORDER_WIDTH)},
    {"STYLE_SCALE_END_BORDER_WIDTH", ROREG_INT(LV_STYLE_SCALE_END_BORDER_WIDTH)},
    {"STYLE_SCALE_END_LINE_WIDTH", ROREG_INT(LV_STYLE_SCALE_END_LINE_WIDTH)},
    {"STYLE_SCALE_GRAD_COLOR", ROREG_INT(LV_STYLE_SCALE_GRAD_COLOR)},
    {"STYLE_SCALE_END_COLOR", ROREG_INT(LV_STYLE_SCALE_END_COLOR)},
    {"BIDI_DIR_LTR", ROREG_INT(LV_BIDI_DIR_LTR)},
    {"BIDI_DIR_RTL", ROREG_INT(LV_BIDI_DIR_RTL)},
    {"BIDI_DIR_AUTO", ROREG_INT(LV_BIDI_DIR_AUTO)},
    {"BIDI_DIR_INHERIT", ROREG_INT(LV_BIDI_DIR_INHERIT)},
    {"BIDI_DIR_NEUTRAL", ROREG_INT(LV_BIDI_DIR_NEUTRAL)},
    {"BIDI_DIR_WEAK", ROREG_INT(LV_BIDI_DIR_WEAK)},
    {"TXT_FLAG_NONE", ROREG_INT(LV_TXT_FLAG_NONE)},
    {"TXT_FLAG_RECOLOR", ROREG_INT(LV_TXT_FLAG_RECOLOR)},
    {"TXT_FLAG_EXPAND", ROREG_INT(LV_TXT_FLAG_EXPAND)},
    {"TXT_FLAG_CENTER", ROREG_INT(LV_TXT_FLAG_CENTER)},
    {"TXT_FLAG_RIGHT", ROREG_INT(LV_TXT_FLAG_RIGHT)},
    {"TXT_FLAG_FIT", ROREG_INT(LV_TXT_FLAG_FIT)},
    {"TXT_CMD_STATE_WAIT", ROREG_INT(LV_TXT_CMD_STATE_WAIT)},
    {"TXT_CMD_STATE_PAR", ROREG_INT(LV_TXT_CMD_STATE_PAR)},
    {"TXT_CMD_STATE_IN", ROREG_INT(LV_TXT_CMD_STATE_IN)},
    {"IMG_SRC_VARIABLE", ROREG_INT(LV_IMG_SRC_VARIABLE)},
    {"IMG_SRC_FILE", ROREG_INT(LV_IMG_SRC_FILE)},
    {"IMG_SRC_SYMBOL", ROREG_INT(LV_IMG_SRC_SYMBOL)},
    {"IMG_SRC_UNKNOWN", ROREG_INT(LV_IMG_SRC_UNKNOWN)},
    {"DESIGN_DRAW_MAIN", ROREG_INT(LV_DESIGN_DRAW_MAIN)},
    {"DESIGN_DRAW_POST", ROREG_INT(LV_DESIGN_DRAW_POST)},
    {"DESIGN_COVER_CHK", ROREG_INT(LV_DESIGN_COVER_CHK)},
    {"DESIGN_RES_OK", ROREG_INT(LV_DESIGN_RES_OK)},
    {"DESIGN_RES_COVER", ROREG_INT(LV_DESIGN_RES_COVER)},
    {"DESIGN_RES_NOT_COVER", ROREG_INT(LV_DESIGN_RES_NOT_COVER)},
    {"DESIGN_RES_MASKED", ROREG_INT(LV_DESIGN_RES_MASKED)},
    {"EVENT_PRESSED", ROREG_INT(LV_EVENT_PRESSED)},
    {"EVENT_PRESSING", ROREG_INT(LV_EVENT_PRESSING)},
    {"EVENT_PRESS_LOST", ROREG_INT(LV_EVENT_PRESS_LOST)},
    {"EVENT_SHORT_CLICKED", ROREG_INT(LV_EVENT_SHORT_CLICKED)},
    {"EVENT_LONG_PRESSED", ROREG_INT(LV_EVENT_LONG_PRESSED)},
    {"EVENT_LONG_PRESSED_REPEAT", ROREG_INT(LV_EVENT_LONG_PRESSED_REPEAT)},
    {"EVENT_CLICKED", ROREG_INT(LV_EVENT_CLICKED)},
    {"EVENT_RELEASED", ROREG_INT(LV_EVENT_RELEASED)},
    {"EVENT_DRAG_BEGIN", ROREG_INT(LV_EVENT_DRAG_BEGIN)},
    {"EVENT_DRAG_END", ROREG_INT(LV_EVENT_DRAG_END)},
    {"EVENT_DRAG_THROW_BEGIN", ROREG_INT(LV_EVENT_DRAG_THROW_BEGIN)},
    {"EVENT_GESTURE", ROREG_INT(LV_EVENT_GESTURE)},
    {"EVENT_KEY", ROREG_INT(LV_EVENT_KEY)},
    {"EVENT_FOCUSED", ROREG_INT(LV_EVENT_FOCUSED)},
    {"EVENT_DEFOCUSED", ROREG_INT(LV_EVENT_DEFOCUSED)},
    {"EVENT_LEAVE", ROREG_INT(LV_EVENT_LEAVE)},
    {"EVENT_VALUE_CHANGED", ROREG_INT(LV_EVENT_VALUE_CHANGED)},
    {"EVENT_INSERT", ROREG_INT(LV_EVENT_INSERT)},
    {"EVENT_REFRESH", ROREG_INT(LV_EVENT_REFRESH)},
    {"EVENT_APPLY", ROREG_INT(LV_EVENT_APPLY)},
    {"EVENT_CANCEL", ROREG_INT(LV_EVENT_CANCEL)},
    {"EVENT_DELETE", ROREG_INT(LV_EVENT_DELETE)},
    {"SIGNAL_CLEANUP", ROREG_INT(LV_SIGNAL_CLEANUP)},
    {"SIGNAL_CHILD_CHG", ROREG_INT(LV_SIGNAL_CHILD_CHG)},
    {"SIGNAL_COORD_CHG", ROREG_INT(LV_SIGNAL_COORD_CHG)},
    {"SIGNAL_PARENT_SIZE_CHG", ROREG_INT(LV_SIGNAL_PARENT_SIZE_CHG)},
    {"SIGNAL_STYLE_CHG", ROREG_INT(LV_SIGNAL_STYLE_CHG)},
    {"SIGNAL_BASE_DIR_CHG", ROREG_INT(LV_SIGNAL_BASE_DIR_CHG)},
    {"SIGNAL_REFR_EXT_DRAW_PAD", ROREG_INT(LV_SIGNAL_REFR_EXT_DRAW_PAD)},
    {"SIGNAL_GET_TYPE", ROREG_INT(LV_SIGNAL_GET_TYPE)},
    {"SIGNAL_GET_STYLE", ROREG_INT(LV_SIGNAL_GET_STYLE)},
    {"SIGNAL_GET_STATE_DSC", ROREG_INT(LV_SIGNAL_GET_STATE_DSC)},
    {"SIGNAL_HIT_TEST", ROREG_INT(LV_SIGNAL_HIT_TEST)},
    {"SIGNAL_PRESSED", ROREG_INT(LV_SIGNAL_PRESSED)},
    {"SIGNAL_PRESSING", ROREG_INT(LV_SIGNAL_PRESSING)},
    {"SIGNAL_PRESS_LOST", ROREG_INT(LV_SIGNAL_PRESS_LOST)},
    {"SIGNAL_RELEASED", ROREG_INT(LV_SIGNAL_RELEASED)},
    {"SIGNAL_LONG_PRESS", ROREG_INT(LV_SIGNAL_LONG_PRESS)},
    {"SIGNAL_LONG_PRESS_REP", ROREG_INT(LV_SIGNAL_LONG_PRESS_REP)},
    {"SIGNAL_DRAG_BEGIN", ROREG_INT(LV_SIGNAL_DRAG_BEGIN)},
    {"SIGNAL_DRAG_THROW_BEGIN", ROREG_INT(LV_SIGNAL_DRAG_THROW_BEGIN)},
    {"SIGNAL_DRAG_END", ROREG_INT(LV_SIGNAL_DRAG_END)},
    {"SIGNAL_GESTURE", ROREG_INT(LV_SIGNAL_GESTURE)},
    {"SIGNAL_LEAVE", ROREG_INT(LV_SIGNAL_LEAVE)},
    {"SIGNAL_FOCUS", ROREG_INT(LV_SIGNAL_FOCUS)},
    {"SIGNAL_DEFOCUS", ROREG_INT(LV_SIGNAL_DEFOCUS)},
    {"SIGNAL_CONTROL", ROREG_INT(LV_SIGNAL_CONTROL)},
    {"SIGNAL_GET_EDITABLE", ROREG_INT(LV_SIGNAL_GET_EDITABLE)},
    {"PROTECT_NONE", ROREG_INT(LV_PROTECT_NONE)},
    {"PROTECT_CHILD_CHG", ROREG_INT(LV_PROTECT_CHILD_CHG)},
    {"PROTECT_PARENT", ROREG_INT(LV_PROTECT_PARENT)},
    {"PROTECT_POS", ROREG_INT(LV_PROTECT_POS)},
    {"PROTECT_FOLLOW", ROREG_INT(LV_PROTECT_FOLLOW)},
    {"PROTECT_PRESS_LOST", ROREG_INT(LV_PROTECT_PRESS_LOST)},
    {"PROTECT_CLICK_FOCUS", ROREG_INT(LV_PROTECT_CLICK_FOCUS)},
    {"PROTECT_EVENT_TO_DISABLED", ROREG_INT(LV_PROTECT_EVENT_TO_DISABLED)},
    {"STATE_DEFAULT", ROREG_INT(LV_STATE_DEFAULT)},
    {"STATE_CHECKED", ROREG_INT(LV_STATE_CHECKED)},
    {"STATE_FOCUSED", ROREG_INT(LV_STATE_FOCUSED)},
    {"STATE_EDITED", ROREG_INT(LV_STATE_EDITED)},
    {"STATE_HOVERED", ROREG_INT(LV_STATE_HOVERED)},
    {"STATE_PRESSED", ROREG_INT(LV_STATE_PRESSED)},
    {"STATE_DISABLED", ROREG_INT(LV_STATE_DISABLED)},
    {"OBJ_PART_MAIN", ROREG_INT(LV_OBJ_PART_MAIN)},
    {"OBJ_PART_ALL", ROREG_INT(LV_OBJ_PART_ALL)},
    {"SCR_LOAD_ANIM_NONE", ROREG_INT(LV_SCR_LOAD_ANIM_NONE)},
    {"SCR_LOAD_ANIM_OVER_LEFT", ROREG_INT(LV_SCR_LOAD_ANIM_OVER_LEFT)},
    {"SCR_LOAD_ANIM_OVER_RIGHT", ROREG_INT(LV_SCR_LOAD_ANIM_OVER_RIGHT)},
    {"SCR_LOAD_ANIM_OVER_TOP", ROREG_INT(LV_SCR_LOAD_ANIM_OVER_TOP)},
    {"SCR_LOAD_ANIM_OVER_BOTTOM", ROREG_INT(LV_SCR_LOAD_ANIM_OVER_BOTTOM)},
    {"SCR_LOAD_ANIM_MOVE_LEFT", ROREG_INT(LV_SCR_LOAD_ANIM_MOVE_LEFT)},
    {"SCR_LOAD_ANIM_MOVE_RIGHT", ROREG_INT(LV_SCR_LOAD_ANIM_MOVE_RIGHT)},
    {"SCR_LOAD_ANIM_MOVE_TOP", ROREG_INT(LV_SCR_LOAD_ANIM_MOVE_TOP)},
    {"SCR_LOAD_ANIM_MOVE_BOTTOM", ROREG_INT(LV_SCR_LOAD_ANIM_MOVE_BOTTOM)},
    {"SCR_LOAD_ANIM_FADE_ON", ROREG_INT(LV_SCR_LOAD_ANIM_FADE_ON)},
    {"KEY_UP", ROREG_INT(LV_KEY_UP)},
    {"KEY_DOWN", ROREG_INT(LV_KEY_DOWN)},
    {"KEY_RIGHT", ROREG_INT(LV_KEY_RIGHT)},
    {"KEY_LEFT", ROREG_INT(LV_KEY_LEFT)},
    {"KEY_ESC", ROREG_INT(LV_KEY_ESC)},
    {"KEY_DEL", ROREG_INT(LV_KEY_DEL)},
    {"KEY_BACKSPACE", ROREG_INT(LV_KEY_BACKSPACE)},
    {"KEY_ENTER", ROREG_INT(LV_KEY_ENTER)},
    {"KEY_NEXT", ROREG_INT(LV_KEY_NEXT)},
    {"KEY_PREV", ROREG_INT(LV_KEY_PREV)},
    {"KEY_HOME", ROREG_INT(LV_KEY_HOME)},
    {"KEY_END", ROREG_INT(LV_KEY_END)},
    {"GROUP_REFOCUS_POLICY_NEXT", ROREG_INT(LV_GROUP_REFOCUS_POLICY_NEXT)},
    {"GROUP_REFOCUS_POLICY_PREV", ROREG_INT(LV_GROUP_REFOCUS_POLICY_PREV)},
    {"FONT_FMT_TXT_CMAP_FORMAT0_FULL", ROREG_INT(LV_FONT_FMT_TXT_CMAP_FORMAT0_FULL)},
    {"FONT_FMT_TXT_CMAP_SPARSE_FULL", ROREG_INT(LV_FONT_FMT_TXT_CMAP_SPARSE_FULL)},
    {"FONT_FMT_TXT_CMAP_FORMAT0_TINY", ROREG_INT(LV_FONT_FMT_TXT_CMAP_FORMAT0_TINY)},
    {"FONT_FMT_TXT_CMAP_SPARSE_TINY", ROREG_INT(LV_FONT_FMT_TXT_CMAP_SPARSE_TINY)},
    {"FONT_FMT_TXT_PLAIN", ROREG_INT(LV_FONT_FMT_TXT_PLAIN)},
    {"FONT_FMT_TXT_COMPRESSED", ROREG_INT(LV_FONT_FMT_TXT_COMPRESSED)},
    {"FONT_FMT_TXT_COMPRESSED_NO_PREFILTER", ROREG_INT(LV_FONT_FMT_TXT_COMPRESSED_NO_PREFILTER)},
    // {"THEME_NONE", ROREG_INT(LV_THEME_NONE)},
    // {"THEME_SCR", ROREG_INT(LV_THEME_SCR)},
    // {"THEME_OBJ", ROREG_INT(LV_THEME_OBJ)},
    // {"THEME_ARC", ROREG_INT(LV_THEME_ARC)},
    // {"THEME_BAR", ROREG_INT(LV_THEME_BAR)},
    // {"THEME_BTN", ROREG_INT(LV_THEME_BTN)},
    // {"THEME_BTNMATRIX", ROREG_INT(LV_THEME_BTNMATRIX)},
    // {"THEME_CALENDAR", ROREG_INT(LV_THEME_CALENDAR)},
    // {"THEME_CANVAS", ROREG_INT(LV_THEME_CANVAS)},
    // {"THEME_CHECKBOX", ROREG_INT(LV_THEME_CHECKBOX)},
    // {"THEME_CHART", ROREG_INT(LV_THEME_CHART)},
    // {"THEME_CONT", ROREG_INT(LV_THEME_CONT)},
    // {"THEME_CPICKER", ROREG_INT(LV_THEME_CPICKER)},
    // {"THEME_DROPDOWN", ROREG_INT(LV_THEME_DROPDOWN)},
    // {"THEME_GAUGE", ROREG_INT(LV_THEME_GAUGE)},
    // {"THEME_IMAGE", ROREG_INT(LV_THEME_IMAGE)},
    // {"THEME_IMGBTN", ROREG_INT(LV_THEME_IMGBTN)},
    // {"THEME_KEYBOARD", ROREG_INT(LV_THEME_KEYBOARD)},
    // {"THEME_LABEL", ROREG_INT(LV_THEME_LABEL)},
    // {"THEME_LED", ROREG_INT(LV_THEME_LED)},
    // {"THEME_LINE", ROREG_INT(LV_THEME_LINE)},
    // {"THEME_LIST", ROREG_INT(LV_THEME_LIST)},
    // {"THEME_LIST_BTN", ROREG_INT(LV_THEME_LIST_BTN)},
    // {"THEME_LINEMETER", ROREG_INT(LV_THEME_LINEMETER)},
    // {"THEME_MSGBOX", ROREG_INT(LV_THEME_MSGBOX)},
    // {"THEME_MSGBOX_BTNS", ROREG_INT(LV_THEME_MSGBOX_BTNS)},
    // {"THEME_OBJMASK", ROREG_INT(LV_THEME_OBJMASK)},
    // {"THEME_PAGE", ROREG_INT(LV_THEME_PAGE)},
    // {"THEME_ROLLER", ROREG_INT(LV_THEME_ROLLER)},
    // {"THEME_SLIDER", ROREG_INT(LV_THEME_SLIDER)},
    // {"THEME_SPINBOX", ROREG_INT(LV_THEME_SPINBOX)},
    // {"THEME_SPINBOX_BTN", ROREG_INT(LV_THEME_SPINBOX_BTN)},
    // {"THEME_SPINNER", ROREG_INT(LV_THEME_SPINNER)},
    // {"THEME_SWITCH", ROREG_INT(LV_THEME_SWITCH)},
    // {"THEME_TABLE", ROREG_INT(LV_THEME_TABLE)},
    // {"THEME_TABVIEW", ROREG_INT(LV_THEME_TABVIEW)},
    // {"THEME_TABVIEW_PAGE", ROREG_INT(LV_THEME_TABVIEW_PAGE)},
    // {"THEME_TEXTAREA", ROREG_INT(LV_THEME_TEXTAREA)},
    // {"THEME_TILEVIEW", ROREG_INT(LV_THEME_TILEVIEW)},
    // {"THEME_WIN", ROREG_INT(LV_THEME_WIN)},
    // {"THEME_WIN_BTN", ROREG_INT(LV_THEME_WIN_BTN)},
    // {"THEME_CUSTOM_START", ROREG_INT(LV_THEME_CUSTOM_START)},
    // {"THEME_MATERIAL_FLAG_DARK", ROREG_INT(LV_THEME_MATERIAL_FLAG_DARK)},
    // {"THEME_MATERIAL_FLAG_LIGHT", ROREG_INT(LV_THEME_MATERIAL_FLAG_LIGHT)},
    // {"THEME_MATERIAL_FLAG_NO_TRANSITION", ROREG_INT(LV_THEME_MATERIAL_FLAG_NO_TRANSITION)},
    // {"THEME_MATERIAL_FLAG_NO_FOCUS", ROREG_INT(LV_THEME_MATERIAL_FLAG_NO_FOCUS)},
    {"ARC_TYPE_NORMAL", ROREG_INT(LV_ARC_TYPE_NORMAL)},
    {"ARC_TYPE_SYMMETRIC", ROREG_INT(LV_ARC_TYPE_SYMMETRIC)},
    {"ARC_TYPE_REVERSE", ROREG_INT(LV_ARC_TYPE_REVERSE)},
    {"ARC_PART_BG", ROREG_INT(LV_ARC_PART_BG)},
    {"ARC_PART_INDIC", ROREG_INT(LV_ARC_PART_INDIC)},
    {"ARC_PART_KNOB", ROREG_INT(LV_ARC_PART_KNOB)},
    {"LAYOUT_OFF", ROREG_INT(LV_LAYOUT_OFF)},
    {"LAYOUT_CENTER", ROREG_INT(LV_LAYOUT_CENTER)},
    {"LAYOUT_COLUMN_LEFT", ROREG_INT(LV_LAYOUT_COLUMN_LEFT)},
    {"LAYOUT_COLUMN_MID", ROREG_INT(LV_LAYOUT_COLUMN_MID)},
    {"LAYOUT_COLUMN_RIGHT", ROREG_INT(LV_LAYOUT_COLUMN_RIGHT)},
    {"LAYOUT_ROW_TOP", ROREG_INT(LV_LAYOUT_ROW_TOP)},
    {"LAYOUT_ROW_MID", ROREG_INT(LV_LAYOUT_ROW_MID)},
    {"LAYOUT_ROW_BOTTOM", ROREG_INT(LV_LAYOUT_ROW_BOTTOM)},
    {"LAYOUT_PRETTY_TOP", ROREG_INT(LV_LAYOUT_PRETTY_TOP)},
    {"LAYOUT_PRETTY_MID", ROREG_INT(LV_LAYOUT_PRETTY_MID)},
    {"LAYOUT_PRETTY_BOTTOM", ROREG_INT(LV_LAYOUT_PRETTY_BOTTOM)},
    {"LAYOUT_GRID", ROREG_INT(LV_LAYOUT_GRID)},
    {"FIT_NONE", ROREG_INT(LV_FIT_NONE)},
    {"FIT_TIGHT", ROREG_INT(LV_FIT_TIGHT)},
    {"FIT_PARENT", ROREG_INT(LV_FIT_PARENT)},
    {"FIT_MAX", ROREG_INT(LV_FIT_MAX)},
    {"CONT_PART_MAIN", ROREG_INT(LV_CONT_PART_MAIN)},
    {"BTN_STATE_RELEASED", ROREG_INT(LV_BTN_STATE_RELEASED)},
    {"BTN_STATE_PRESSED", ROREG_INT(LV_BTN_STATE_PRESSED)},
    {"BTN_STATE_DISABLED", ROREG_INT(LV_BTN_STATE_DISABLED)},
    {"BTN_STATE_CHECKED_RELEASED", ROREG_INT(LV_BTN_STATE_CHECKED_RELEASED)},
    {"BTN_STATE_CHECKED_PRESSED", ROREG_INT(LV_BTN_STATE_CHECKED_PRESSED)},
    {"BTN_STATE_CHECKED_DISABLED", ROREG_INT(LV_BTN_STATE_CHECKED_DISABLED)},
    {"BTN_PART_MAIN", ROREG_INT(LV_BTN_PART_MAIN)},
    {"LABEL_LONG_EXPAND", ROREG_INT(LV_LABEL_LONG_EXPAND)},
    {"LABEL_LONG_BREAK", ROREG_INT(LV_LABEL_LONG_BREAK)},
    {"LABEL_LONG_DOT", ROREG_INT(LV_LABEL_LONG_DOT)},
    {"LABEL_LONG_SROLL", ROREG_INT(LV_LABEL_LONG_SROLL)},
    {"LABEL_LONG_SROLL_CIRC", ROREG_INT(LV_LABEL_LONG_SROLL_CIRC)},
    {"LABEL_LONG_CROP", ROREG_INT(LV_LABEL_LONG_CROP)},
    {"LABEL_ALIGN_LEFT", ROREG_INT(LV_LABEL_ALIGN_LEFT)},
    {"LABEL_ALIGN_CENTER", ROREG_INT(LV_LABEL_ALIGN_CENTER)},
    {"LABEL_ALIGN_RIGHT", ROREG_INT(LV_LABEL_ALIGN_RIGHT)},
    {"LABEL_ALIGN_AUTO", ROREG_INT(LV_LABEL_ALIGN_AUTO)},
    {"LABEL_PART_MAIN", ROREG_INT(LV_LABEL_PART_MAIN)},
    {"BAR_TYPE_NORMAL", ROREG_INT(LV_BAR_TYPE_NORMAL)},
    {"BAR_TYPE_SYMMETRICAL", ROREG_INT(LV_BAR_TYPE_SYMMETRICAL)},
    {"BAR_TYPE_CUSTOM", ROREG_INT(LV_BAR_TYPE_CUSTOM)},
    {"BAR_PART_BG", ROREG_INT(LV_BAR_PART_BG)},
    {"BAR_PART_INDIC", ROREG_INT(LV_BAR_PART_INDIC)},
    {"BTNMATRIX_CTRL_HIDDEN", ROREG_INT(LV_BTNMATRIX_CTRL_HIDDEN)},
    {"BTNMATRIX_CTRL_NO_REPEAT", ROREG_INT(LV_BTNMATRIX_CTRL_NO_REPEAT)},
    {"BTNMATRIX_CTRL_DISABLED", ROREG_INT(LV_BTNMATRIX_CTRL_DISABLED)},
    {"BTNMATRIX_CTRL_CHECKABLE", ROREG_INT(LV_BTNMATRIX_CTRL_CHECKABLE)},
    {"BTNMATRIX_CTRL_CHECK_STATE", ROREG_INT(LV_BTNMATRIX_CTRL_CHECK_STATE)},
    {"BTNMATRIX_CTRL_CLICK_TRIG", ROREG_INT(LV_BTNMATRIX_CTRL_CLICK_TRIG)},
    {"BTNMATRIX_PART_BG", ROREG_INT(LV_BTNMATRIX_PART_BG)},
    {"BTNMATRIX_PART_BTN", ROREG_INT(LV_BTNMATRIX_PART_BTN)},
    {"CALENDAR_PART_BG", ROREG_INT(LV_CALENDAR_PART_BG)},
    {"CALENDAR_PART_HEADER", ROREG_INT(LV_CALENDAR_PART_HEADER)},
    {"CALENDAR_PART_DAY_NAMES", ROREG_INT(LV_CALENDAR_PART_DAY_NAMES)},
    {"CALENDAR_PART_DATE", ROREG_INT(LV_CALENDAR_PART_DATE)},
    {"IMG_PART_MAIN", ROREG_INT(LV_IMG_PART_MAIN)},
    {"CANVAS_PART_MAIN", ROREG_INT(LV_CANVAS_PART_MAIN)},
    {"LINE_PART_MAIN", ROREG_INT(LV_LINE_PART_MAIN)},
    {"CHART_TYPE_NONE", ROREG_INT(LV_CHART_TYPE_NONE)},
    {"CHART_TYPE_LINE", ROREG_INT(LV_CHART_TYPE_LINE)},
    {"CHART_TYPE_COLUMN", ROREG_INT(LV_CHART_TYPE_COLUMN)},
    {"CHART_UPDATE_MODE_SHIFT", ROREG_INT(LV_CHART_UPDATE_MODE_SHIFT)},
    {"CHART_UPDATE_MODE_CIRCULAR", ROREG_INT(LV_CHART_UPDATE_MODE_CIRCULAR)},
    {"CHART_AXIS_PRIMARY_Y", ROREG_INT(LV_CHART_AXIS_PRIMARY_Y)},
    {"CHART_AXIS_SECONDARY_Y", ROREG_INT(LV_CHART_AXIS_SECONDARY_Y)},
    {"CHART_CURSOR_NONE", ROREG_INT(LV_CHART_CURSOR_NONE)},
    {"CHART_CURSOR_RIGHT", ROREG_INT(LV_CHART_CURSOR_RIGHT)},
    {"CHART_CURSOR_UP", ROREG_INT(LV_CHART_CURSOR_UP)},
    {"CHART_CURSOR_LEFT", ROREG_INT(LV_CHART_CURSOR_LEFT)},
    {"CHART_CURSOR_DOWN", ROREG_INT(LV_CHART_CURSOR_DOWN)},
    {"CHART_AXIS_SKIP_LAST_TICK", ROREG_INT(LV_CHART_AXIS_SKIP_LAST_TICK)},
    {"CHART_AXIS_DRAW_LAST_TICK", ROREG_INT(LV_CHART_AXIS_DRAW_LAST_TICK)},
    {"CHART_AXIS_INVERSE_LABELS_ORDER", ROREG_INT(LV_CHART_AXIS_INVERSE_LABELS_ORDER)},
    {"CHART_PART_BG", ROREG_INT(LV_CHART_PART_BG)},
    {"CHART_PART_SERIES_BG", ROREG_INT(LV_CHART_PART_SERIES_BG)},
    {"CHART_PART_SERIES", ROREG_INT(LV_CHART_PART_SERIES)},
    {"CHART_PART_CURSOR", ROREG_INT(LV_CHART_PART_CURSOR)},
    {"CHECKBOX_PART_BG", ROREG_INT(LV_CHECKBOX_PART_BG)},
    {"CHECKBOX_PART_BULLET", ROREG_INT(LV_CHECKBOX_PART_BULLET)},
    {"CPICKER_TYPE_RECT", ROREG_INT(LV_CPICKER_TYPE_RECT)},
    {"CPICKER_TYPE_DISC", ROREG_INT(LV_CPICKER_TYPE_DISC)},
    {"CPICKER_COLOR_MODE_HUE", ROREG_INT(LV_CPICKER_COLOR_MODE_HUE)},
    {"CPICKER_COLOR_MODE_SATURATION", ROREG_INT(LV_CPICKER_COLOR_MODE_SATURATION)},
    {"CPICKER_COLOR_MODE_VALUE", ROREG_INT(LV_CPICKER_COLOR_MODE_VALUE)},
    {"CPICKER_PART_MAIN", ROREG_INT(LV_CPICKER_PART_MAIN)},
    {"CPICKER_PART_KNOB", ROREG_INT(LV_CPICKER_PART_KNOB)},
    {"SCROLLBAR_MODE_OFF", ROREG_INT(LV_SCROLLBAR_MODE_OFF)},
    {"SCROLLBAR_MODE_ON", ROREG_INT(LV_SCROLLBAR_MODE_ON)},
    {"SCROLLBAR_MODE_DRAG", ROREG_INT(LV_SCROLLBAR_MODE_DRAG)},
    {"SCROLLBAR_MODE_AUTO", ROREG_INT(LV_SCROLLBAR_MODE_AUTO)},
    {"SCROLLBAR_MODE_HIDE", ROREG_INT(LV_SCROLLBAR_MODE_HIDE)},
    {"SCROLLBAR_MODE_UNHIDE", ROREG_INT(LV_SCROLLBAR_MODE_UNHIDE)},
    {"PAGE_EDGE_LEFT", ROREG_INT(LV_PAGE_EDGE_LEFT)},
    {"PAGE_EDGE_TOP", ROREG_INT(LV_PAGE_EDGE_TOP)},
    {"PAGE_EDGE_RIGHT", ROREG_INT(LV_PAGE_EDGE_RIGHT)},
    {"PAGE_EDGE_BOTTOM", ROREG_INT(LV_PAGE_EDGE_BOTTOM)},
    {"PAGE_PART_BG", ROREG_INT(LV_PAGE_PART_BG)},
    {"PAGE_PART_SCROLLBAR", ROREG_INT(LV_PAGE_PART_SCROLLBAR)},
#if LV_USE_ANIMATION
    {"PAGE_PART_EDGE_FLASH", ROREG_INT(LV_PAGE_PART_EDGE_FLASH)},
#endif
    {"PAGE_PART_SCROLLABLE", ROREG_INT(LV_PAGE_PART_SCROLLABLE)},
    {"DROPDOWN_DIR_DOWN", ROREG_INT(LV_DROPDOWN_DIR_DOWN)},
    {"DROPDOWN_DIR_UP", ROREG_INT(LV_DROPDOWN_DIR_UP)},
    {"DROPDOWN_DIR_LEFT", ROREG_INT(LV_DROPDOWN_DIR_LEFT)},
    {"DROPDOWN_DIR_RIGHT", ROREG_INT(LV_DROPDOWN_DIR_RIGHT)},
    {"DROPDOWN_PART_MAIN", ROREG_INT(LV_DROPDOWN_PART_MAIN)},
    {"DROPDOWN_PART_LIST", ROREG_INT(LV_DROPDOWN_PART_LIST)},
    {"DROPDOWN_PART_SCROLLBAR", ROREG_INT(LV_DROPDOWN_PART_SCROLLBAR)},
    {"DROPDOWN_PART_SELECTED", ROREG_INT(LV_DROPDOWN_PART_SELECTED)},
    {"LINEMETER_PART_MAIN", ROREG_INT(LV_LINEMETER_PART_MAIN)},
    {"GAUGE_PART_MAIN", ROREG_INT(LV_GAUGE_PART_MAIN)},
    {"GAUGE_PART_MAJOR", ROREG_INT(LV_GAUGE_PART_MAJOR)},
    {"GAUGE_PART_NEEDLE", ROREG_INT(LV_GAUGE_PART_NEEDLE)},
    {"IMGBTN_PART_MAIN", ROREG_INT(LV_IMGBTN_PART_MAIN)},
    {"KEYBOARD_MODE_TEXT_LOWER", ROREG_INT(LV_KEYBOARD_MODE_TEXT_LOWER)},
    {"KEYBOARD_MODE_TEXT_UPPER", ROREG_INT(LV_KEYBOARD_MODE_TEXT_UPPER)},
    {"KEYBOARD_MODE_SPECIAL", ROREG_INT(LV_KEYBOARD_MODE_SPECIAL)},
    {"KEYBOARD_MODE_NUM", ROREG_INT(LV_KEYBOARD_MODE_NUM)},
    {"KEYBOARD_PART_BG", ROREG_INT(LV_KEYBOARD_PART_BG)},
    {"KEYBOARD_PART_BTN", ROREG_INT(LV_KEYBOARD_PART_BTN)},
    {"LED_PART_MAIN", ROREG_INT(LV_LED_PART_MAIN)},
    {"LIST_PART_BG", ROREG_INT(LV_LIST_PART_BG)},
    {"LIST_PART_SCROLLBAR", ROREG_INT(LV_LIST_PART_SCROLLBAR)},
#if LV_USE_ANIMATION
    {"LIST_PART_EDGE_FLASH", ROREG_INT(LV_LIST_PART_EDGE_FLASH)},
#endif
    {"LIST_PART_SCROLLABLE", ROREG_INT(LV_LIST_PART_SCROLLABLE)},
    {"MSGBOX_PART_BG", ROREG_INT(LV_MSGBOX_PART_BG)},
    {"MSGBOX_PART_BTN_BG", ROREG_INT(LV_MSGBOX_PART_BTN_BG)},
    {"MSGBOX_PART_BTN", ROREG_INT(LV_MSGBOX_PART_BTN)},
    {"OBJMASK_PART_MAIN", ROREG_INT(LV_OBJMASK_PART_MAIN)},
    {"ROLLER_MODE_NORMAL", ROREG_INT(LV_ROLLER_MODE_NORMAL)},
    {"ROLLER_MODE_INFINITE", ROREG_INT(LV_ROLLER_MODE_INFINITE)},
    {"ROLLER_PART_BG", ROREG_INT(LV_ROLLER_PART_BG)},
    {"ROLLER_PART_SELECTED", ROREG_INT(LV_ROLLER_PART_SELECTED)},
    {"SLIDER_TYPE_NORMAL", ROREG_INT(LV_SLIDER_TYPE_NORMAL)},
    {"SLIDER_TYPE_SYMMETRICAL", ROREG_INT(LV_SLIDER_TYPE_SYMMETRICAL)},
    {"SLIDER_TYPE_RANGE", ROREG_INT(LV_SLIDER_TYPE_RANGE)},
    {"SLIDER_PART_BG", ROREG_INT(LV_SLIDER_PART_BG)},
    {"SLIDER_PART_INDIC", ROREG_INT(LV_SLIDER_PART_INDIC)},
    {"SLIDER_PART_KNOB", ROREG_INT(LV_SLIDER_PART_KNOB)},
    {"TEXTAREA_PART_BG", ROREG_INT(LV_TEXTAREA_PART_BG)},
    {"TEXTAREA_PART_SCROLLBAR", ROREG_INT(LV_TEXTAREA_PART_SCROLLBAR)},
#if LV_USE_ANIMATION
    {"TEXTAREA_PART_EDGE_FLASH", ROREG_INT(LV_TEXTAREA_PART_EDGE_FLASH)},
#endif
    {"TEXTAREA_PART_CURSOR", ROREG_INT(LV_TEXTAREA_PART_CURSOR)},
    {"TEXTAREA_PART_PLACEHOLDER", ROREG_INT(LV_TEXTAREA_PART_PLACEHOLDER)},
    {"SPINBOX_PART_BG", ROREG_INT(LV_SPINBOX_PART_BG)},
    {"SPINBOX_PART_CURSOR", ROREG_INT(LV_SPINBOX_PART_CURSOR)},
#if LV_USE_ANIMATION
    {"SPINNER_TYPE_SPINNING_ARC", ROREG_INT(LV_SPINNER_TYPE_SPINNING_ARC)},
    {"SPINNER_TYPE_FILLSPIN_ARC", ROREG_INT(LV_SPINNER_TYPE_FILLSPIN_ARC)},
    {"SPINNER_TYPE_CONSTANT_ARC", ROREG_INT(LV_SPINNER_TYPE_CONSTANT_ARC)},
    {"SPINNER_DIR_FORWARD", ROREG_INT(LV_SPINNER_DIR_FORWARD)},
    {"SPINNER_DIR_BACKWARD", ROREG_INT(LV_SPINNER_DIR_BACKWARD)},
    {"SPINNER_PART_BG", ROREG_INT(LV_SPINNER_PART_BG)},
    {"SPINNER_PART_INDIC", ROREG_INT(LV_SPINNER_PART_INDIC)},
#endif
    {"SWITCH_PART_BG", ROREG_INT(LV_SWITCH_PART_BG)},
    {"SWITCH_PART_INDIC", ROREG_INT(LV_SWITCH_PART_INDIC)},
    {"SWITCH_PART_KNOB", ROREG_INT(LV_SWITCH_PART_KNOB)},
    {"TABLE_PART_BG", ROREG_INT(LV_TABLE_PART_BG)},
    {"TABLE_PART_CELL1", ROREG_INT(LV_TABLE_PART_CELL1)},
    {"TABLE_PART_CELL2", ROREG_INT(LV_TABLE_PART_CELL2)},
    {"TABLE_PART_CELL3", ROREG_INT(LV_TABLE_PART_CELL3)},
    {"TABLE_PART_CELL4", ROREG_INT(LV_TABLE_PART_CELL4)},
    {"WIN_PART_BG", ROREG_INT(LV_WIN_PART_BG)},
    {"WIN_PART_HEADER", ROREG_INT(LV_WIN_PART_HEADER)},
    {"WIN_PART_CONTENT_SCROLLABLE", ROREG_INT(LV_WIN_PART_CONTENT_SCROLLABLE)},
    {"WIN_PART_SCROLLBAR", ROREG_INT(LV_WIN_PART_SCROLLBAR)},
    {"TABVIEW_TAB_POS_NONE", ROREG_INT(LV_TABVIEW_TAB_POS_NONE)},
    {"TABVIEW_TAB_POS_TOP", ROREG_INT(LV_TABVIEW_TAB_POS_TOP)},
    {"TABVIEW_TAB_POS_BOTTOM", ROREG_INT(LV_TABVIEW_TAB_POS_BOTTOM)},
    {"TABVIEW_TAB_POS_LEFT", ROREG_INT(LV_TABVIEW_TAB_POS_LEFT)},
    {"TABVIEW_TAB_POS_RIGHT", ROREG_INT(LV_TABVIEW_TAB_POS_RIGHT)},
    {"TABVIEW_PART_BG", ROREG_INT(LV_TABVIEW_PART_BG)},
    {"TABVIEW_PART_BG_SCROLLABLE", ROREG_INT(LV_TABVIEW_PART_BG_SCROLLABLE)},
    {"TABVIEW_PART_TAB_BG", ROREG_INT(LV_TABVIEW_PART_TAB_BG)},
    {"TABVIEW_PART_TAB_BTN", ROREG_INT(LV_TABVIEW_PART_TAB_BTN)},
    {"TABVIEW_PART_INDIC", ROREG_INT(LV_TABVIEW_PART_INDIC)},
    {"TILEVIEW_PART_BG", ROREG_INT(LV_TILEVIEW_PART_BG)},
    {"TILEVIEW_PART_SCROLLBAR", ROREG_INT(LV_TILEVIEW_PART_SCROLLBAR)},
#if LV_USE_ANIMATION
    {"TILEVIEW_PART_EDGE_FLASH", ROREG_INT(LV_TILEVIEW_PART_EDGE_FLASH)},
#endif
    {"ROLLER_MODE_INIFINITE", ROREG_INT(LV_ROLLER_MODE_INIFINITE)},
    {NULL, ROREG_INT(0)},
};

#if (LV_USE_LOG && LV_LOG_PRINTF == 0)
static void lv_log_print(lv_log_level_t level, const char * file, uint32_t lineno, const char * func, const char * desc) {
    switch (level)
    {
    case LV_LOG_LEVEL_TRACE:
        LLOGD("%s:%d - %s - %s", file, lineno, func, desc);
        break;
    case LV_LOG_LEVEL_INFO:
        LLOGI("%s:%d - %s - %s", file, lineno, func, desc);
        break;
    case LV_LOG_LEVEL_WARN:
        LLOGW("%s:%d - %s - %s", file, lineno, func, desc);
        break;
    case LV_LOG_LEVEL_ERROR:
        LLOGE("%s:%d - %s - %s", file, lineno, func, desc);
        break;
    default:
        LLOGD("%s:%d - %s - %s", file, lineno, func, desc);
        break;
    }
};
#endif

LUAMOD_API int luaopen_lvgl( lua_State *L ) {
    #if (LV_USE_LOG && LV_LOG_PRINTF == 0)
    lv_log_register_print_cb(lv_log_print);
    #endif
    luat_newlib2(L, reg_lvgl);
    luat_lvgl_struct_init(L);
    return 1;
}

static int lv_func_unref(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (msg->arg1)
        luaL_unref(L, LUA_REGISTRYINDEX, msg->arg1);
    if (msg->arg2)
        luaL_unref(L, LUA_REGISTRYINDEX, msg->arg2);
    return 0;
}

void luat_lv_user_data_free(lv_obj_t * obj) {
    if (obj == NULL || (obj->user_data.event_cb_ref == 0 && obj->user_data.signal_cb_ref)) return;
    rtos_msg_t msg = {0};
    msg.handler = lv_func_unref;
    msg.arg1 = obj->user_data.event_cb_ref;
    msg.arg2 = obj->user_data.signal_cb_ref;
    luat_msgbus_put(&msg, 0);
}
