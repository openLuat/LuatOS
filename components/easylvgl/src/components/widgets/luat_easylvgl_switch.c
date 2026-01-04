/**
 * @file luat_easylvgl_switch.c
 * @summary Switch 组件
 * @responsible 解析配置、创建 lv_switch、绑定事件
 */

#include "luat_easylvgl_component.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/lvgl.h"
#include "lvgl9/src/widgets/switch/lv_switch.h"
#include "lvgl9/src/core/lv_obj.h"
#include <string.h>

static easylvgl_ctx_t *easylvgl_binding_get_ctx(lua_State *L) {
    if (L == NULL) {
        return NULL;
    }

    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    return ctx;
}

/**
 * 根据 style 指定的语义色设置开关的 checked 背景
 */
static void easylvgl_switch_apply_style(lv_obj_t *sw, const char *style)
{
    if (sw == NULL || style == NULL) {
        return;
    }

    lv_color_t color = lv_color_hex(0x1A73E8);
    if (strcmp(style, "danger") == 0) {
        color = lv_color_hex(0xD93025);
    } else if (strcmp(style, "success") == 0) {
        color = lv_color_hex(0x188038);
    }

    lv_obj_set_style_bg_color(sw, color, LV_STATE_CHECKED);
}

/**
 * 从 Lua config 创建 Switch 对象
 */
lv_obj_t *easylvgl_switch_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    easylvgl_ctx_t *ctx = easylvgl_binding_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    // 读取布局与默认状态
    lv_obj_t *parent = easylvgl_marshal_parent(L, idx);
    int x = easylvgl_marshal_integer(L, idx, "x", 0);
    int y = easylvgl_marshal_integer(L, idx, "y", 0);
    int w = easylvgl_marshal_integer(L, idx, "w", 70);
    int h = easylvgl_marshal_integer(L, idx, "h", 40);
    bool checked = easylvgl_marshal_bool(L, idx, "checked", false);
    const char *style = easylvgl_marshal_string(L, idx, "style", NULL);

    lv_obj_t *sw = lv_switch_create(parent);
    if (sw == NULL) {
        return NULL;
    }

    lv_obj_set_pos(sw, x, y);
    lv_obj_set_size(sw, w, h);

    // 应用主题色
    if (style != NULL) {
        easylvgl_switch_apply_style(sw, style);
    }

    if (checked) {
        lv_obj_add_state(sw, LV_STATE_CHECKED);
    } else {
        lv_obj_clear_state(sw, LV_STATE_CHECKED);
    }

    easylvgl_component_meta_t *meta = easylvgl_component_meta_alloc(
        ctx, sw, EASYLVGL_COMPONENT_SWITCH);
    if (meta == NULL) {
        lv_obj_delete(sw);
        return NULL;
    }

    int callback_ref = easylvgl_component_capture_callback(L, idx, "on_change");
    if (callback_ref != LUA_NOREF) {
        easylvgl_switch_set_on_change(sw, callback_ref);
    }

    return sw;
}

/**
 * 修改 Switch 的状态并派发事件
 */
int easylvgl_switch_set_state(lv_obj_t *sw, bool checked)
{
    if (sw == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    if (checked) {
        lv_obj_add_state(sw, LV_STATE_CHECKED);
    } else {
        lv_obj_clear_state(sw, LV_STATE_CHECKED);
    }

    lv_event_send(sw, LV_EVENT_VALUE_CHANGED, NULL);
    return EASYLVGL_OK;
}

/**
 * 查询 Switch 是否处于选中状态
 */
bool easylvgl_switch_get_state(lv_obj_t *sw)
{
    if (sw == NULL) {
        return false;
    }

    return (lv_obj_get_state(sw) & LV_STATE_CHECKED) != 0;
}

/**
 * 绑定状态变化回调
 */
int easylvgl_switch_set_on_change(lv_obj_t *sw, int callback_ref)
{
    if (sw == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(sw);
    if (meta == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    return easylvgl_component_bind_event(
        meta, EASYLVGL_EVENT_VALUE_CHANGED, callback_ref);
}

