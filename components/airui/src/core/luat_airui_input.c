/**
 * @file luat_airui_input.c
 * @summary 系统键盘与输入相关的上下文管理
 * @responsible 聚焦管理、系统键盘事件分发
 */

#include "luat_airui.h"
#include "lvgl9/src/widgets/textarea/lv_textarea.h"
#include "lua.h"
#include "lauxlib.h"
#include <stdint.h>
#define LUAT_LOG_TAG "airui_input"
#include "luat_log.h"

/**
 * 设置当前聚焦的 textarea
 */
void airui_ctx_set_focused_textarea(airui_ctx_t *ctx, lv_obj_t *textarea) {
    if (ctx == NULL) {
        return;
    }
    ctx->focused_textarea = textarea;
}

lv_obj_t *airui_ctx_get_focused_textarea(airui_ctx_t *ctx) {
    if (ctx == NULL) {
        return NULL;
    }
    return ctx->focused_textarea;
}

/**
 * 系统键盘开关
 */
int airui_system_keyboard_enable(airui_ctx_t *ctx, bool enable) {
    if (ctx == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    ctx->system_keyboard_enabled = enable ? 1 : 0;
    return AIRUI_OK;
}

bool airui_system_keyboard_is_enabled(airui_ctx_t *ctx) {
    if (ctx == NULL) return false;
    return ctx->system_keyboard_enabled;
}

static void airui_system_keyboard_insert_text(airui_ctx_t *ctx, const char *text) {
    if (ctx == NULL || ctx->focused_textarea == NULL || text == NULL) {
        return;
    }
    lv_textarea_add_text(ctx->focused_textarea, text);
}

void airui_system_keyboard_post_text(airui_ctx_t *ctx, const char *text) {
    if (!airui_system_keyboard_is_enabled(ctx) || text == NULL) {
        return;
    }
    airui_system_keyboard_insert_text(ctx, text);
}

void airui_system_keyboard_post_key(airui_ctx_t *ctx, uint32_t key, bool pressed) {
    if (ctx == NULL || ctx->focused_textarea == NULL || !airui_system_keyboard_is_enabled(ctx)) {
        return;
    }

    if (!pressed) {
        return;
    }

    lv_obj_t *textarea = ctx->focused_textarea;

    switch (key) {
        case LV_KEY_BACKSPACE:
            lv_textarea_delete_char(textarea);
            return;
        case LV_KEY_ENTER:
            lv_textarea_add_char(textarea, '\n');
            return;
        case LV_KEY_ESC:
            return;
        default:
            break;
    }

    if (key >= 32 && key < 127) {
        lv_textarea_add_char(textarea, (char)key);
    }
}

// 订阅触摸事件
int airui_touch_subscribe(airui_ctx_t *ctx, void *L, int callback_ref) {
    lua_State *L_state = (lua_State *)L;

    if (ctx == NULL || L_state == NULL || callback_ref <= 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (ctx->touch_callback_ref > 0) {
        luaL_unref(L_state, LUA_REGISTRYINDEX, ctx->touch_callback_ref);
    }

    ctx->touch_callback_ref = callback_ref;
    ctx->touch_last_state = AIRUI_TOUCH_STATE_NONE;
    ctx->touch_pressed = false;
    ctx->touch_last_point.x = 0;
    ctx->touch_last_point.y = 0;
    ctx->touch_last_track_id = 0;
    ctx->touch_last_timestamp = 0;
    return AIRUI_OK;
}

// 取消触摸事件订阅
void airui_touch_unsubscribe(airui_ctx_t *ctx, void *L) {
    lua_State *L_state = (lua_State *)L;

    if (ctx == NULL) {
        return;
    }

    if (L_state != NULL && ctx->touch_callback_ref > 0) {
        luaL_unref(L_state, LUA_REGISTRYINDEX, ctx->touch_callback_ref);
    }

    ctx->touch_callback_ref = 0;
    ctx->touch_last_state = AIRUI_TOUCH_STATE_NONE;
    ctx->touch_pressed = false;
    ctx->touch_last_point.x = 0;
    ctx->touch_last_point.y = 0;
    ctx->touch_last_track_id = 0;
    ctx->touch_last_timestamp = 0;
}

// 通知触摸事件
void airui_touch_notify(airui_ctx_t *ctx, airui_touch_state_t state, lv_coord_t x, lv_coord_t y, uint8_t track_id, uint32_t timestamp) {
    lua_State *L_state;

    if (ctx == NULL || ctx->L == NULL) {
        return;
    }

    L_state = (lua_State *)ctx->L;
    if (ctx->touch_callback_ref <= 0) {
        return;
    }

    ctx->touch_last_state = state;
    ctx->touch_last_point.x = x;
    ctx->touch_last_point.y = y;
    ctx->touch_last_track_id = track_id;
    ctx->touch_last_timestamp = timestamp;
    ctx->touch_pressed = (state == AIRUI_TOUCH_STATE_DOWN || state == AIRUI_TOUCH_STATE_HOLD);

    lua_rawgeti(L_state, LUA_REGISTRYINDEX, ctx->touch_callback_ref);
    if (lua_type(L_state, -1) != LUA_TFUNCTION) {
        lua_pop(L_state, 1);
        return;
    }

    lua_pushinteger(L_state, state);
    lua_pushinteger(L_state, x);
    lua_pushinteger(L_state, y);
    lua_pushinteger(L_state, track_id);
    lua_pushinteger(L_state, timestamp);

    if (lua_pcall(L_state, 5, 0, 0) != LUA_OK) {
        const char *err = lua_tostring(L_state, -1);
        LLOGE("touch callback error: %s", err ? err : "unknown");
        lua_pop(L_state, 1);
    }
}

// 订阅键盘事件
int airui_keypad_subscribe(airui_ctx_t *ctx, void *L, int callback_ref) {
    lua_State *L_state = (lua_State *)L;

    if (ctx == NULL || L_state == NULL || callback_ref <= 0) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (ctx->keypad_callback_ref > 0) {
        luaL_unref(L_state, LUA_REGISTRYINDEX, ctx->keypad_callback_ref);
    }

    ctx->keypad_callback_ref = callback_ref;
    ctx->keypad_last_key = 0;
    ctx->keypad_last_pressed = false;
    ctx->keypad_last_timestamp = 0;
    return AIRUI_OK;
}

// 取消键盘事件订阅
void airui_keypad_unsubscribe(airui_ctx_t *ctx, void *L) {
    lua_State *L_state = (lua_State *)L;

    if (ctx == NULL) {
        return;
    }

    if (L_state != NULL && ctx->keypad_callback_ref > 0) {
        luaL_unref(L_state, LUA_REGISTRYINDEX, ctx->keypad_callback_ref);
    }

    ctx->keypad_callback_ref = 0;
    ctx->keypad_last_key = 0;
    ctx->keypad_last_pressed = false;
    ctx->keypad_last_timestamp = 0;
}

// 通知键盘事件
void airui_keypad_notify(airui_ctx_t *ctx, uint32_t key, bool pressed, uint32_t timestamp) {
    lua_State *L_state;

    if (ctx == NULL || ctx->L == NULL) {
        return;
    }

    L_state = (lua_State *)ctx->L;
    if (ctx->keypad_callback_ref <= 0) {
        return;
    }

    ctx->keypad_last_key = key;
    ctx->keypad_last_pressed = pressed;
    ctx->keypad_last_timestamp = timestamp;

    lua_rawgeti(L_state, LUA_REGISTRYINDEX, ctx->keypad_callback_ref);
    if (lua_type(L_state, -1) != LUA_TFUNCTION) {
        lua_pop(L_state, 1);
        return;
    }

    // 参数: key (SDL keycode), pressed (bool), timestamp
    lua_pushinteger(L_state, key);
    lua_pushboolean(L_state, pressed);
    lua_pushinteger(L_state, timestamp);

    if (lua_pcall(L_state, 3, 0, 0) != LUA_OK) {
        const char *err = lua_tostring(L_state, -1);
        LLOGE("keypad callback error: %s", err ? err : "unknown");
        lua_pop(L_state, 1);
    }
}

