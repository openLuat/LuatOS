/**
 * @file luat_airui_display.c
 * @summary AIRUI 显示抽象封装
 * @responsible 封装 lv_display_set_buffers，缓冲模式配置
 */

#include "luat_airui.h"

static lv_display_rotation_t airui_rotation_to_lv(uint16_t rotation)
{
    switch (rotation) {
        case 0:
            return LV_DISPLAY_ROTATION_0;
        case 90:
            return LV_DISPLAY_ROTATION_90;
        case 180:
            return LV_DISPLAY_ROTATION_180;
        case 270:
            return LV_DISPLAY_ROTATION_270;
        default:
            return LV_DISPLAY_ROTATION_0;
    }
}

static uint16_t airui_rotation_from_lv(lv_display_rotation_t rotation)
{
    switch (rotation) {
        case LV_DISPLAY_ROTATION_90:
            return 90;
        case LV_DISPLAY_ROTATION_180:
            return 180;
        case LV_DISPLAY_ROTATION_270:
            return 270;
        case LV_DISPLAY_ROTATION_0:
        default:
            return 0;
    }
}

/**
 * 设置显示缓冲
 * @param ctx 上下文指针
 * @param buf1 缓冲1指针
 * @param buf2 缓冲2指针（双缓冲时使用）
 * @param buf_size 缓冲大小（字节）
 * @param mode 缓冲模式
 * @return 0 成功，<0 失败
 */
int airui_display_set_buffers(
    airui_ctx_t *ctx,
    void *buf1,
    void *buf2,
    uint32_t buf_size,
    airui_buffer_mode_t mode)
{
    if (ctx == NULL || ctx->display == NULL || buf1 == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }
    
    // 转换为 LVGL 渲染模式
    lv_display_render_mode_t render_mode;
    switch (mode) {
        case AIRUI_BUFFER_MODE_SINGLE:
        case AIRUI_BUFFER_MODE_DOUBLE:
            render_mode = LV_DISPLAY_RENDER_MODE_PARTIAL;
            break;
        case AIRUI_BUFFER_MODE_LCD_SHARED:
        case AIRUI_BUFFER_MODE_EXTERNAL:
            render_mode = LV_DISPLAY_RENDER_MODE_DIRECT;
            break;
        default:
            return AIRUI_ERR_INVALID_PARAM;
    }
    
    lv_display_set_buffers(ctx->display, buf1, buf2, buf_size, render_mode);
    return AIRUI_OK;
}

int airui_display_set_rotation(airui_ctx_t *ctx, uint16_t rotation)
{
    if (ctx == NULL || ctx->display == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (rotation != 0 && rotation != 90 && rotation != 180 && rotation != 270) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_display_set_rotation(ctx->display, airui_rotation_to_lv(rotation));
    ctx->width = (uint16_t)lv_display_get_horizontal_resolution(ctx->display);
    ctx->height = (uint16_t)lv_display_get_vertical_resolution(ctx->display);

    if (!ctx->sleeping) {
        lv_obj_t *act_scr = lv_display_get_screen_active(ctx->display);
        if (act_scr != NULL) {
            lv_obj_invalidate(act_scr);
        }
    }

    return AIRUI_OK;
}

uint16_t airui_display_get_rotation(airui_ctx_t *ctx)
{
    if (ctx == NULL || ctx->display == NULL) {
        return 0;
    }

    return airui_rotation_from_lv(lv_display_get_rotation(ctx->display));
}

uint16_t airui_display_get_width(airui_ctx_t *ctx)
{
    if (ctx == NULL) {
        return 0;
    }

    return ctx->width;
}

uint16_t airui_display_get_height(airui_ctx_t *ctx)
{
    if (ctx == NULL) {
        return 0;
    }

    return ctx->height;
}

