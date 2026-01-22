/**
 * @file luat_airui_textarea.c
 * @summary Textarea 组件实现
 * @responsible textarea 创建、文本控制、系统键盘焦点管理
 */

#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/widgets/textarea/lv_textarea.h"
#include "lvgl9/src/widgets/keyboard/lv_keyboard.h"
#include "lvgl9/src/misc/lv_event.h"
#include "lvgl9/src/core/lv_obj.h"
#include <string.h>
#include "luat_conf_bsp.h"

#define LUAT_LOG_TAG "airui_textarea"
#include "luat_log.h"

#if defined(LUAT_USE_AIRUI_SDL2)
/**
 * 设置 SDL2 文本输入矩形区域,让中文输入法能够定位到焦点
 * @param ctx AIRUI 上下文
 * @param target 目标对象
 */
void airui_platform_sdl2_set_text_input_rect(airui_ctx_t *ctx, lv_obj_t *target);
#else
static inline void airui_platform_sdl2_set_text_input_rect(airui_ctx_t *ctx, lv_obj_t *target) {
    (void)ctx;
    (void)target;
}
#endif

/**
 * 从 Lua 注册表获取 AIRUI 上下文
 * @pre Lua 已调用 airui.init 并保存 ctx
 * @return airui_ctx_t* 或 NULL
 */
static airui_ctx_t *airui_binding_get_ctx(lua_State *L_state) {
    if (L_state == NULL) {
        return NULL;
    }

    airui_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);
    return ctx;
}

/**
 * 焦点事件回调：维护当前系统键盘应该写入的 textarea
 */
static void airui_textarea_focus_cb(lv_event_t *e)
{
    if (e == NULL) {
        return;
    }

    // 获取事件目标和关联元数据
    lv_obj_t *target = lv_event_get_target(e);
    airui_component_meta_t *meta = airui_component_meta_get(target);
    if (meta == NULL || meta->ctx == NULL) {
        return;
    }

    lv_event_code_t code = lv_event_get_code(e);
    switch (code) {
        case LV_EVENT_FOCUSED:
            // 获得焦点时设置当前焦点 textarea 到上下文
            airui_ctx_set_focused_textarea(meta->ctx, target);
#if defined(LUAT_USE_AIRUI_SDL2)
            airui_platform_sdl2_set_text_input_rect(meta->ctx, target);
#endif
            break;
        case LV_EVENT_DEFOCUSED:
            // 失去焦点时，仅当当前焦点是本控件才置空
            if (airui_ctx_get_focused_textarea(meta->ctx) == target) {
#if defined(LUAT_USE_AIRUI_SDL2)
                airui_system_keyboard_clear_preedit(meta->ctx);
#endif
                airui_ctx_set_focused_textarea(meta->ctx, NULL);
            }
            break;
        case LV_EVENT_PRESSED:
            // 按下时强制设置当前 textarea 为焦点
            airui_ctx_set_focused_textarea(meta->ctx, target);
            if (!lv_obj_has_state(target, LV_STATE_FOCUSED)) {
                // 如果还没有 FOCUSED 状态，则添加该状态
                lv_obj_add_state(target, LV_STATE_FOCUSED);
            }
#if defined(LUAT_USE_AIRUI_SDL2)
            airui_platform_sdl2_set_text_input_rect(meta->ctx, target);
#endif
            break;
        case LV_EVENT_CLICKED:
            // 点击时，如果未处于 FOCUSED 状态，主动设为 FOCUSED 并发送 LV_EVENT_FOCUSED 事件
            if (!lv_obj_has_state(target, LV_STATE_FOCUSED)) {
                lv_obj_add_state(target, LV_STATE_FOCUSED);
                lv_event_send(target, LV_EVENT_FOCUSED, NULL);
            }
#if defined(LUAT_USE_AIRUI_SDL2)
            airui_platform_sdl2_set_text_input_rect(meta->ctx, target);
#endif
            break;
        case LV_EVENT_VALUE_CHANGED:
#if defined(LUAT_USE_AIRUI_SDL2)
            LLOGD("LV_EVENT_VALUE_CHANGED: system_keyboard_preedit_len=%d", meta->ctx->system_keyboard_preedit_len);
            if (!meta->ctx->system_keyboard_preedit_active) {
                airui_platform_sdl2_set_text_input_rect(meta->ctx, target);
            }
#endif
            break;
        default:
            break;
    }
}

/**
 * 从 Lua 配置表创建 textarea
 * @api airui.textarea(config)
 * @param L Lua 状态
 * @param idx 配置表索引
 * @return lv_obj_t*，失败返回 NULL
 * @pre 传入参数为有效 table；ctx 已初始化
 */
lv_obj_t *airui_textarea_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_binding_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    // 将 textarea 插入指定 parent，未指定时使用当前 lv_scr_act
    lv_obj_t *parent = airui_marshal_parent(L, idx);
    if (parent == NULL) {
        parent = lv_scr_act();
    }

    // 解析布局相关字段
    int x = airui_marshal_integer(L, idx, "x", 0);
    int y = airui_marshal_integer(L, idx, "y", 0);
    int w = airui_marshal_integer(L, idx, "w", ctx->width > 0 ? ctx->width - x : 200);
    int h = airui_marshal_integer(L, idx, "h", 120);
    int max_len = airui_marshal_integer(L, idx, "max_len", 256);
    const char *text = airui_marshal_string(L, idx, "text", NULL);
    const char *placeholder = airui_marshal_string(L, idx, "placeholder", NULL);

    lv_obj_t *textarea = lv_textarea_create(parent);
    if (textarea == NULL) {
        return NULL;
    }

    // 应用布局与文本约束
    lv_obj_set_pos(textarea, x, y);
    lv_obj_set_size(textarea, w, h);
    lv_textarea_set_max_length(textarea, max_len);

    if (placeholder != NULL && placeholder[0] != '\0') {
        lv_textarea_set_placeholder_text(textarea, placeholder);
    }

    if (text != NULL) {
        lv_textarea_set_text(textarea, text);
    }

    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, textarea, AIRUI_COMPONENT_TEXTAREA);
    if (meta == NULL) {
        lv_obj_delete(textarea);
        return NULL;
    }

    // 监听 focus 事件依次同步系统键盘焦点
    lv_obj_add_event_cb(textarea, airui_textarea_focus_cb, LV_EVENT_FOCUSED, NULL);
    lv_obj_add_event_cb(textarea, airui_textarea_focus_cb, LV_EVENT_DEFOCUSED, NULL);
    lv_obj_add_event_cb(textarea, airui_textarea_focus_cb, LV_EVENT_PRESSED, NULL);
    lv_obj_add_event_cb(textarea, airui_textarea_focus_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_add_event_cb(textarea, airui_textarea_focus_cb, LV_EVENT_VALUE_CHANGED, NULL);

    airui_textarea_data_t *data = (airui_textarea_data_t *)luat_heap_malloc(sizeof(airui_textarea_data_t));
    if (data == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(textarea);
        return NULL;
    }
    data->keyboard = NULL;
    meta->user_data = data;

    // 绑定 Lua on_text_change 回调
    int callback_ref = airui_component_capture_callback(L, idx, "on_text_change");
    if (callback_ref != LUA_NOREF) {
        airui_component_bind_event(meta, AIRUI_EVENT_VALUE_CHANGED, callback_ref);
    }

    // 可选的虚拟键盘配置：创建并自动绑定
    lua_getfield(L_state, idx, "keyboard");
    if (lua_istable(L_state, -1)) {
        lv_obj_t *keyboard = airui_keyboard_create_from_config(L_state, lua_gettop(L_state));
        if (keyboard != NULL) {
            airui_keyboard_set_target(keyboard, textarea);
            airui_textarea_attach_keyboard(textarea, keyboard);
        }
    }
    lua_pop(L_state, 1);

    return textarea;
}

/**
 * 设置 textarea 内容
 * @param textarea LVGL textarea
 * @param text 新文本
 */
int airui_textarea_set_text(lv_obj_t *textarea, const char *text)
{
    if (textarea == NULL || text == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_textarea_set_text(textarea, text);
    return AIRUI_OK;
}

/**
 * 获取 textarea 当前文本
 */
const char *airui_textarea_get_text(lv_obj_t *textarea)
{
    if (textarea == NULL) {
        return NULL;
    }
    return lv_textarea_get_text(textarea);
}

/**
 * 设置光标位置
 */
int airui_textarea_set_cursor(lv_obj_t *textarea, uint32_t pos)
{
    if (textarea == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_textarea_set_cursor_pos(textarea, pos);
    return AIRUI_OK;
}

/**
 * 绑定文本变化回调
 * @param callback_ref Lua 函数 registry 引用
 */
int airui_textarea_set_on_text_change(lv_obj_t *textarea, int callback_ref)
{
    if (textarea == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(textarea);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    return airui_component_bind_event(meta, AIRUI_EVENT_VALUE_CHANGED, callback_ref);
}

/**
 * 绑定虚拟键盘，当键盘按钮按下时同步输入
 */
int airui_textarea_attach_keyboard(lv_obj_t *textarea, lv_obj_t *keyboard)
{
    if (textarea == NULL || keyboard == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    // 将 keyboard 联动到本 textarea
    lv_keyboard_set_textarea(keyboard, textarea);

    // 读取已有 metadata，便于存储 keyboard 指针
    airui_component_meta_t *meta = airui_component_meta_get(textarea);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_textarea_data_t *data = (airui_textarea_data_t *)meta->user_data;
    if (data == NULL) {
        data = (airui_textarea_data_t *)luat_heap_malloc(sizeof(airui_textarea_data_t));
        if (data == NULL) {
            return AIRUI_ERR_NO_MEM;
        }
        data->keyboard = NULL;
        meta->user_data = data;
    }
    data->keyboard = keyboard;
    return AIRUI_OK;
}

/**
 * 查询绑定的虚拟键盘
 */
lv_obj_t *airui_textarea_get_keyboard(lv_obj_t *textarea)
{
    if (textarea == NULL) {
        return NULL;
    }

    airui_component_meta_t *meta = airui_component_meta_get(textarea);
    if (meta == NULL || meta->user_data == NULL) {
        return NULL;
    }

    airui_textarea_data_t *data = (airui_textarea_data_t *)meta->user_data;
    return data->keyboard;
}

