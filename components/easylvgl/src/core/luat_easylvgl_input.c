/**
 * @file luat_easylvgl_input.c
 * @summary 系统键盘与输入相关的上下文管理
 * @responsible 聚焦管理、系统键盘事件分发
 */

#include "luat_easylvgl.h"
#include "lvgl9/src/widgets/textarea/lv_textarea.h"
#include <stdint.h>

/**
 * 设置当前聚焦的 textarea
 */
void easylvgl_ctx_set_focused_textarea(easylvgl_ctx_t *ctx, lv_obj_t *textarea) {
    if (ctx == NULL) {
        return;
    }
    ctx->focused_textarea = textarea;
}

lv_obj_t *easylvgl_ctx_get_focused_textarea(easylvgl_ctx_t *ctx) {
    if (ctx == NULL) {
        return NULL;
    }
    return ctx->focused_textarea;
}

/**
 * 系统键盘开关
 */
int easylvgl_system_keyboard_enable(easylvgl_ctx_t *ctx, bool enable) {
    if (ctx == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    ctx->system_keyboard_enabled = enable ? 1 : 0;
    return EASYLVGL_OK;
}

bool easylvgl_system_keyboard_is_enabled(easylvgl_ctx_t *ctx) {
    if (ctx == NULL) return false;
    return ctx->system_keyboard_enabled;
}

static void easylvgl_system_keyboard_insert_text(easylvgl_ctx_t *ctx, const char *text) {
    if (ctx == NULL || ctx->focused_textarea == NULL || text == NULL) {
        return;
    }
    lv_textarea_add_text(ctx->focused_textarea, text);
}

void easylvgl_system_keyboard_post_text(easylvgl_ctx_t *ctx, const char *text) {
    if (!easylvgl_system_keyboard_is_enabled(ctx) || text == NULL) {
        return;
    }
    easylvgl_system_keyboard_insert_text(ctx, text);
}

void easylvgl_system_keyboard_post_key(easylvgl_ctx_t *ctx, uint32_t key, bool pressed) {
    if (ctx == NULL || ctx->focused_textarea == NULL || !easylvgl_system_keyboard_is_enabled(ctx)) {
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

