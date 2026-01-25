/**
 * @file luat_airui_display.c
 * @summary AIRUI 显示抽象封装
 * @responsible 封装 lv_display_set_buffers，缓冲模式配置
 */

#include "luat_airui.h"

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

