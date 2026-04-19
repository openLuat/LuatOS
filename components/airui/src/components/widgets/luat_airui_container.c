/**
 * @file luat_airui_container.c
 * @summary Container 组件实现
 * @responsible Container 创建、样式控制
 */

#include "luat_airui_component.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/misc/lv_color.h"
#include "lua.h"
#include "lauxlib.h"
#include <stdint.h>

/**
 * 从配置表创建 Container 组件
 */
lv_obj_t *airui_container_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);

    if (ctx == NULL) {
        return NULL;
    }

    // 解析布局与样式配置
    lv_obj_t *parent = airui_marshal_parent(L, idx);
    int x = airui_marshal_floor_integer(L, idx, "x", 0);
    int y = airui_marshal_floor_integer(L, idx, "y", 0);
    int w = airui_marshal_floor_integer(L, idx, "w", 100);
    int h = airui_marshal_floor_integer(L, idx, "h", 100);
    int color_value = airui_marshal_integer(L, idx, "color", -1);
    int color_opacity = airui_marshal_integer(L, idx, "color_opacity", LV_OPA_COVER);
    int radius = airui_marshal_integer(L, idx, "radius", 0);
    int border_color_value = airui_marshal_integer(L, idx, "border_color", -1);
    int border_width = airui_marshal_integer(L, idx, "border_width", 1);

    lv_obj_t *container = lv_obj_create(parent);
    if (container == NULL) {
        return NULL;
    }

    // 设置位置、大小与默认样式
    lv_obj_set_pos(container, x, y);
    lv_obj_set_size(container, w, h);
    lv_style_selector_t main_default = (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT;
    lv_obj_set_style_border_width(container, 0, main_default);
    lv_obj_set_style_radius(container, radius, main_default);
    // 屏幕默认存在 padding，清掉内边距让 (0,0) 真正对齐
    lv_obj_set_style_pad_all(container, 0, main_default);

    // 设置背景颜色或透明度
    if (color_value >= 0) {
        airui_container_set_color(container, (uint32_t)color_value, color_opacity);
    } else {
        lv_obj_set_style_bg_opa(container, LV_OPA_TRANSP, main_default);
    }

    if (border_color_value >= 0 && border_width > 0) {
        airui_container_set_border_color(container, (uint32_t)border_color_value, border_width);
    } else {
        lv_obj_set_style_border_width(container, 0, main_default);
    }

    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, container, AIRUI_COMPONENT_CONTAINER);
    if (meta == NULL) {
        lv_obj_delete(container);
        return NULL;
    }

    int callback_ref = airui_component_capture_callback(L, idx, "on_click");
    if (callback_ref != LUA_NOREF) {
        lv_obj_add_flag(container, LV_OBJ_FLAG_CLICKABLE);
        airui_component_bind_event(meta, AIRUI_EVENT_CLICKED, callback_ref);
    }

    return container;
}

/**
 * 设置 Container 背景颜色
 */
int airui_container_set_color(lv_obj_t *container, uint32_t color_value, int opacity)
{
    if (container == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    // 设置背景颜色与透明度
    lv_style_selector_t main_default = (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT;
    lv_color_t bg_color = lv_color_hex(color_value);
    lv_obj_set_style_bg_color(container, bg_color, main_default);
    lv_obj_set_style_bg_opa(container, airui_marshal_opacity(opacity), main_default);

    return AIRUI_OK;
}

/**
 * 设置 Container 边框颜色
 */
int airui_container_set_border_color(lv_obj_t *container, uint32_t color_value, int width)
{
    if (container == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_style_selector_t main_default = (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT;
    lv_color_t border_color = lv_color_hex(color_value);
    int border_width = width > 0 ? width : 0;
    lv_obj_set_style_border_width(container, border_width, main_default);
    if (border_width > 0) {
        lv_obj_set_style_border_color(container, border_color, main_default);
        lv_obj_set_style_border_opa(container, LV_OPA_COVER, main_default);
    }

    return AIRUI_OK;
}

/**
 * 设置 Container 隐藏状态
 */
int airui_container_set_hidden(lv_obj_t *container, bool hidden)
{
    if (container == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_set_flag(container, LV_OBJ_FLAG_HIDDEN, hidden);
    return AIRUI_OK;
}

/**
 * 打开容器（用于子窗口），清除隐藏标志并置顶
 */
int airui_container_open(lv_obj_t *container)
{
    if (container == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_clear_flag(container, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(container);
    return AIRUI_OK;
}

/**
 * 设置 Container 点击回调
 */
int airui_container_set_on_click(lv_obj_t *container, int callback_ref)
{
    if (container == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(container);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_add_flag(container, LV_OBJ_FLAG_CLICKABLE);
    return airui_component_bind_event(meta, AIRUI_EVENT_CLICKED, callback_ref);
}

/**
 * 获取容器位置
 */
int airui_container_get_pos(lv_obj_t *container, int32_t *x, int32_t *y)
{
    if (container == NULL || x == NULL || y == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    *x = lv_obj_get_x(container);
    *y = lv_obj_get_y(container);
    return AIRUI_OK;
}

/**
 * 设置容器位置
 */
int airui_container_set_pos(lv_obj_t *container, int32_t x, int32_t y)
{
    if (container == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_set_pos(container, x, y);
    return AIRUI_OK;
}

/**
 * 按偏移量移动容器
 */
int airui_container_move(lv_obj_t *container, int32_t dx, int32_t dy)
{
    int32_t x;
    int32_t y;
    int ret = airui_container_get_pos(container, &x, &y);
    if (ret != AIRUI_OK) {
        return ret;
    }

    return airui_container_set_pos(container, x + dx, y + dy);
}

