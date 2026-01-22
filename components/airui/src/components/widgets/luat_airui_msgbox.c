/**
 * @file luat_airui_msgbox.c
 * @summary Msgbox 组件实现
 * @responsible 创建 lv_msgbox、按钮信息、超时、事件绑定
 */

#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/widgets/msgbox/lv_msgbox.h"
#include "lvgl9/src/widgets/label/lv_label.h"
#include "lvgl9/src/misc/lv_timer.h"
#include "lvgl9/src/core/lv_obj.h"
#include "lvgl9/src/misc/lv_event.h"

#include <string.h>

/**
 * 从注册表中获取 AIRUI 上下文
 * @param L Lua 状态
 * @return ctx 指针，失败返回 NULL
 */
static airui_ctx_t *airui_binding_get_ctx(lua_State *L) {
    if (L == NULL) {
        return NULL;
    }

    airui_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    return ctx;
}

/**
 * 释放 Msgbox 的用户数据结构并返回超时 timer（如果存在）
 */
lv_timer_t *airui_msgbox_release_user_data(airui_component_meta_t *meta)
{
    if (meta == NULL || meta->user_data == NULL) {
        return NULL;
    }

    airui_msgbox_data_t *data = (airui_msgbox_data_t *)meta->user_data;
    if (data != NULL) {
        lv_timer_t *timer = data->timeout_timer;
        data->timeout_timer = NULL;
        luat_heap_free(data);
        meta->user_data = NULL;
        return timer;
    }

    meta->user_data = NULL;
    return NULL;
}

/**
 * Msgbox 超时回调，关闭对话框并删除 timer
 */
static void airui_msgbox_timeout_cb(lv_timer_t *timer) {
    if (timer == NULL) {
        return;
    }

    lv_obj_t *msgbox = (lv_obj_t *)lv_timer_get_user_data(timer);
    if (msgbox == NULL) {
        lv_timer_delete(timer);
        return;
    }

    airui_component_meta_t *meta = airui_component_meta_get(msgbox);
    if (meta != NULL) {
        airui_msgbox_release_user_data(meta);
    }

    lv_msgbox_close(msgbox);
    lv_timer_delete(timer);
}

/**
 * 按钮点击事件回调，提取按钮文本并回调 Lua
 */
static void airui_msgbox_button_event_cb(lv_event_t *e) {
    if (e == NULL || lv_event_get_code(e) != LV_EVENT_CLICKED) {
        return;
    }

    lv_obj_t *btn = lv_event_get_target(e);
    lv_obj_t *msgbox = (lv_obj_t *)lv_event_get_user_data(e);
    if (msgbox == NULL) {
        return;
    }

    airui_component_meta_t *meta = airui_component_meta_get(msgbox);
    if (meta == NULL) {
        return;
    }

    const char *text = NULL;
    lv_obj_t *label = lv_obj_get_child(btn, 0);
    if (label != NULL) {
        text = lv_label_get_text(label);
    }

    airui_component_call_action_callback(meta, text);
}

/**
 * 从 Lua config 创建 Msgbox，支持 title/text/button 等配置
 */
lv_obj_t *airui_msgbox_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_binding_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    // 读取配置项
    lv_obj_t *parent = airui_marshal_parent(L, idx);
    const char *title = airui_marshal_string(L, idx, "title", NULL);
    const char *text = airui_marshal_string(L, idx, "text", NULL);
    bool auto_center = airui_marshal_bool(L, idx, "auto_center", true);
    int timeout = airui_marshal_integer(L, idx, "timeout", 0);

    lv_obj_t *msgbox = lv_msgbox_create(parent);
    if (msgbox == NULL) {
        return NULL;
    }

    // 可选居中
    if (auto_center) {
        lv_obj_center(msgbox);
    }

    // 设置标题与文本
    if (title != NULL) {
        lv_msgbox_add_title(msgbox, title);
    }

    if (text != NULL) {
        lv_msgbox_add_text(msgbox, text);
    }

    // 按钮列表处理
    int button_count = airui_marshal_table_length(L, idx, "buttons");
    if (button_count <= 0) {
        button_count = 1;
    }

    for (int i = 1; i <= button_count; i++) {
        const char *label_text = airui_marshal_table_string_at(L, idx, "buttons", i);
        if (label_text == NULL) {
            label_text = "OK";
        }
        lv_obj_t *btn = lv_msgbox_add_footer_button(msgbox, label_text);
        if (btn != NULL) {
            lv_obj_add_event_cb(btn, airui_msgbox_button_event_cb, LV_EVENT_CLICKED, msgbox);
        }
    }

    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, msgbox, AIRUI_COMPONENT_MSGBOX);
    if (meta == NULL) {
        lv_msgbox_close(msgbox);
        return NULL;
    }

    airui_msgbox_data_t *data = (airui_msgbox_data_t *)luat_heap_malloc(sizeof(airui_msgbox_data_t));
    if (data == NULL) {
        airui_component_meta_free(meta);
        lv_msgbox_close(msgbox);
        return NULL;
    }
    data->timeout_timer = NULL;
    meta->user_data = data;

    if (timeout > 0) {
        lv_timer_t *timer = lv_timer_create(airui_msgbox_timeout_cb, timeout, msgbox);
        if (timer != NULL) {
            data->timeout_timer = timer;
        }
    }

    int callback_ref = airui_component_capture_callback(L, idx, "on_action");
    if (callback_ref != LUA_NOREF) {
        airui_msgbox_set_on_action(msgbox, callback_ref);
    }

    return msgbox;
}

/**
 * 为 Msgbox 绑定 action 回调
 */
int airui_msgbox_set_on_action(lv_obj_t *msgbox, int callback_ref)
{
    if (msgbox == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(msgbox);
    if (meta == NULL || meta->ctx == NULL || meta->ctx->L == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lua_State *L_state = (lua_State *)meta->ctx->L;

    if (meta->callback_refs[AIRUI_EVENT_ACTION] != LUA_NOREF) {
        luaL_unref(L_state, LUA_REGISTRYINDEX, meta->callback_refs[AIRUI_EVENT_ACTION]);
        meta->callback_refs[AIRUI_EVENT_ACTION] = LUA_NOREF;
    }

    if (callback_ref == LUA_NOREF || callback_ref < 0) {
        return AIRUI_OK;
    }

    meta->callback_refs[AIRUI_EVENT_ACTION] = callback_ref;
    return AIRUI_OK;
}

/**
 * 显示 Msgbox 对话框
 */
int airui_msgbox_show(lv_obj_t *msgbox)
{
    if (msgbox == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_clear_flag(msgbox, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(msgbox);
    return AIRUI_OK;
}

/**
 * 隐藏 Msgbox 对话框
 */
int airui_msgbox_hide(lv_obj_t *msgbox)
{
    if (msgbox == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_obj_add_flag(msgbox, LV_OBJ_FLAG_HIDDEN);
    return AIRUI_OK;
}

