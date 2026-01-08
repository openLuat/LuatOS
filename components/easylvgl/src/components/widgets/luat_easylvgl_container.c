/**
 * @file luat_easylvgl_container.c
 * @summary Container 组件实现
 * @responsible Container 创建、样式控制
 */

#include "luat_easylvgl_component.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/misc/lv_color.h"
#include "lua.h"
#include "lauxlib.h"
#include <stdint.h>

/**
 * 从配置表创建 Container 组件
 */
lv_obj_t *easylvgl_container_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);

    if (ctx == NULL) {
        return NULL;
    }

    // 解析布局与样式配置
    lv_obj_t *parent = easylvgl_marshal_parent(L, idx);
    int x = easylvgl_marshal_integer(L, idx, "x", 0);
    int y = easylvgl_marshal_integer(L, idx, "y", 0);
    int w = easylvgl_marshal_integer(L, idx, "w", 100);
    int h = easylvgl_marshal_integer(L, idx, "h", 100);
    int color_value = easylvgl_marshal_integer(L, idx, "color", -1);
    int radius = easylvgl_marshal_integer(L, idx, "radius", 0);

    lv_obj_t *container = lv_obj_create(parent);
    if (container == NULL) {
        return NULL;
    }

    // 设置位置、大小与默认样式
    lv_obj_set_pos(container, x, y);
    lv_obj_set_size(container, w, h);
    lv_obj_set_style_border_width(container, 0, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_radius(container, radius, LV_PART_MAIN | LV_STATE_DEFAULT);

    // 设置背景颜色或透明度
    if (color_value >= 0) {
        lv_color_t bg_color = lv_color_hex((uint32_t)color_value);
        lv_obj_set_style_bg_color(container, bg_color, LV_PART_MAIN | LV_STATE_DEFAULT);
        lv_obj_set_style_bg_opa(container, LV_OPA_COVER, LV_PART_MAIN | LV_STATE_DEFAULT);
    } else {
        lv_obj_set_style_bg_opa(container, LV_OPA_TRANSP, LV_PART_MAIN | LV_STATE_DEFAULT);
    }

    easylvgl_component_meta_t *meta = easylvgl_component_meta_alloc(
        ctx, container, EASYLVGL_COMPONENT_CONTAINER);
    if (meta == NULL) {
        lv_obj_delete(container);
        return NULL;
    }

    return container;
}

/**
 * 设置 Container 背景颜色
 */
int easylvgl_container_set_color(lv_obj_t *container, uint32_t color_value)
{
    if (container == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    // 强制设置不透明背景
    lv_color_t bg_color = lv_color_hex(color_value);
    lv_obj_set_style_bg_color(container, bg_color, LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(container, LV_OPA_COVER, LV_PART_MAIN | LV_STATE_DEFAULT);

    return EASYLVGL_OK;
}

/**
 * 设置 Container 隐藏状态
 */
int easylvgl_container_set_hidden(lv_obj_t *container, bool hidden)
{
    if (container == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    lv_obj_set_flag(container, LV_OBJ_FLAG_HIDDEN, hidden);
    return EASYLVGL_OK;
}

/**
 * 打开容器（用于子窗口），清除隐藏标志并置顶
 */
int easylvgl_container_open(lv_obj_t *container)
{
    if (container == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    lv_obj_clear_flag(container, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(container);
    return EASYLVGL_OK;
}