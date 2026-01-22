/**
 * @file luat_airui_input.c
 * @summary 系统键盘与输入相关的上下文管理
 * @responsible 聚焦管理、系统键盘事件分发
 */

#include "luat_airui.h"
#include "lvgl9/src/widgets/textarea/lv_textarea.h"
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

