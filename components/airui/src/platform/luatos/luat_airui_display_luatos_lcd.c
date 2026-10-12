/**
 * @file luat_airui_display_luatos_lcd.c
 * @summary AirUI LuatOS 显示后端：旧 lcd 库
 */
#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
    #include "luat_conf_bsp_air8101.h"
#endif

#if defined(LUAT_USE_AIRUI_LUATOS)

#include "luat_airui_display_luatos_backend.h"

#if defined(LUAT_USE_LCD)

#include "luat_airui.h"
#include "luat_lcd.h"
#include "luat_mem.h"
#include "lvgl9/src/draw/sw/lv_draw_sw_utils.h"
#include <string.h>

#define LUAT_LOG_TAG "airui.luatos.disp"
#include "luat_log.h"

typedef struct {
    luat_lcd_conf_t *lcd_conf;
    uint8_t *rotation_buf;
    uint32_t rotation_buf_size;
    uint8_t rotation_buf_in_psram;
} luatos_fb_lcd_ctx_t;

static uint8_t *luatos_fb_lcd_get_rotation_buf(luatos_fb_lcd_ctx_t *fb_ctx, uint32_t size)
{
    if (fb_ctx == NULL || size == 0) {
        return NULL;
    }
    if (fb_ctx->rotation_buf != NULL && fb_ctx->rotation_buf_size >= size) {
        return fb_ctx->rotation_buf;
    }
    if (fb_ctx->rotation_buf != NULL) {
        if (fb_ctx->rotation_buf_in_psram) {
            luat_heap_opt_free(LUAT_HEAP_PSRAM, fb_ctx->rotation_buf);
        } else {
            luat_heap_free(fb_ctx->rotation_buf);
        }
        fb_ctx->rotation_buf = NULL;
        fb_ctx->rotation_buf_size = 0;
        fb_ctx->rotation_buf_in_psram = 0;
    }
    fb_ctx->rotation_buf = (uint8_t *)luat_heap_opt_malloc(LUAT_HEAP_PSRAM, size);
    if (fb_ctx->rotation_buf != NULL) {
        fb_ctx->rotation_buf_in_psram = 1;
    } else {
        fb_ctx->rotation_buf = (uint8_t *)luat_heap_malloc(size);
    }
    if (fb_ctx->rotation_buf == NULL) {
        return NULL;
    }
    fb_ctx->rotation_buf_size = size;
    return fb_ctx->rotation_buf;
}

static inline uint16_t airui_rgb565_swap(uint16_t color)
{
    return (uint16_t)((color >> 8) | (color << 8));
}

static int luatos_fb_lcd_attach(airui_ctx_t *ctx, uint16_t w, uint16_t h, void **out_ctx)
{
    luat_lcd_conf_t *lcd_conf;
    luatos_fb_lcd_ctx_t *fb_ctx;

    (void)ctx;
    if (out_ctx == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lcd_conf = luat_lcd_get_default();
    if (lcd_conf == NULL) {
        return AIRUI_ERR_NOT_INITIALIZED;
    }

    fb_ctx = (luatos_fb_lcd_ctx_t *)luat_heap_malloc(sizeof(luatos_fb_lcd_ctx_t));
    if (fb_ctx == NULL) {
        return AIRUI_ERR_NO_MEM;
    }
    memset(fb_ctx, 0, sizeof(*fb_ctx));
    if (lcd_conf->w == 0) {
        lcd_conf->w = w;
    }
    if (lcd_conf->h == 0) {
        lcd_conf->h = h;
    }
    lcd_conf->lcd_use_lvgl = 1;
    fb_ctx->lcd_conf = lcd_conf;
    *out_ctx = fb_ctx;
    LLOGI("reuse legacy lcd backend for airui");
    return AIRUI_OK;
}

static int luatos_fb_lcd_get_buffers(void *backend_ctx, void **fb_addr, uint32_t *buf_size, uint32_t *count)
{
    (void)backend_ctx;
    (void)fb_addr;
    (void)buf_size;
    (void)count;
    return -1;
}

static void luatos_fb_lcd_flush(airui_ctx_t *ctx, void *backend_ctx,
                                const lv_area_t *area, const uint8_t *px_map)
{
    luatos_fb_lcd_ctx_t *fb_ctx = (luatos_fb_lcd_ctx_t *)backend_ctx;
    luat_lcd_conf_t *lcd_conf;
    luat_color_t *color;
    lv_display_rotation_t rotation;

    if (fb_ctx == NULL || fb_ctx->lcd_conf == NULL || area == NULL || px_map == NULL ||
        ctx == NULL || ctx->display == NULL) {
        return;
    }

    lcd_conf = fb_ctx->lcd_conf;
    color = (luat_color_t *)px_map;
    rotation = lv_display_get_rotation(ctx->display);

    if (rotation == LV_DISPLAY_ROTATION_0) {
        uint32_t count = (uint32_t)lv_area_get_width(area) * (uint32_t)lv_area_get_height(area);
        if (lcd_conf->port == LUAT_LCD_SPI_DEVICE && lcd_conf->endianness_swap) {
            for (uint32_t i = 0; i < count; i++) {
                color[i] = airui_rgb565_swap(color[i]);
            }
        }
        luat_lcd_draw(lcd_conf, area->x1, area->y1, area->x2, area->y2, color);
    } else {
        lv_area_t rotated_area = *area;
        lv_color_format_t cf = lv_display_get_color_format(ctx->display);
        uint32_t pixel_size = lv_color_format_get_size(cf);
        uint32_t src_w = (uint32_t)lv_area_get_width(area);
        uint32_t src_h = (uint32_t)lv_area_get_height(area);
        uint32_t src_stride = src_w * pixel_size;
        uint32_t dst_w;
        uint32_t dst_h;
        uint32_t dst_stride;
        uint32_t rotate_size;
        luat_color_t *rotate_buf;

        lv_display_rotate_area(ctx->display, &rotated_area);
        dst_w = (uint32_t)lv_area_get_width(&rotated_area);
        dst_h = (uint32_t)lv_area_get_height(&rotated_area);
        dst_stride = dst_w * pixel_size;
        rotate_size = dst_stride * dst_h;
        rotate_buf = (luat_color_t *)luatos_fb_lcd_get_rotation_buf(fb_ctx, rotate_size);
        if (rotate_buf == NULL) {
            LLOGE("legacy lcd rotation buffer alloc failed size=%u", rotate_size);
            return;
        }
        lv_draw_sw_rotate(px_map, rotate_buf, (int32_t)src_w, (int32_t)src_h,
                          (int32_t)src_stride, (int32_t)dst_stride, rotation, cf);
        if (lcd_conf->port == LUAT_LCD_SPI_DEVICE && lcd_conf->endianness_swap) {
            for (uint32_t i = 0; i < dst_w * dst_h; i++) {
                rotate_buf[i] = airui_rgb565_swap(rotate_buf[i]);
            }
        }
        luat_lcd_draw(lcd_conf, rotated_area.x1, rotated_area.y1,
                      rotated_area.x2, rotated_area.y2, rotate_buf);
    }

    if (lv_display_flush_is_last(ctx->display)) {
        luat_lcd_flush(lcd_conf);
    }
}

static int luatos_fb_lcd_suspend(airui_ctx_t *ctx, void *backend_ctx)
{
    luatos_fb_lcd_ctx_t *fb_ctx = (luatos_fb_lcd_ctx_t *)backend_ctx;
    if (fb_ctx == NULL || fb_ctx->lcd_conf == NULL || ctx == NULL) {
        return AIRUI_ERR_NOT_INITIALIZED;
    }
    return luat_lcd_airui_sleep(fb_ctx->lcd_conf, ctx->sleep_power_down_lcd ? 1 : 0);
}

static int luatos_fb_lcd_resume(airui_ctx_t *ctx, void *backend_ctx)
{
    luatos_fb_lcd_ctx_t *fb_ctx = (luatos_fb_lcd_ctx_t *)backend_ctx;
    (void)ctx;
    if (fb_ctx == NULL || fb_ctx->lcd_conf == NULL) {
        return AIRUI_ERR_NOT_INITIALIZED;
    }
    return luat_lcd_wakeup(fb_ctx->lcd_conf);
}

static void luatos_fb_lcd_detach(void *backend_ctx)
{
    luatos_fb_lcd_ctx_t *fb_ctx = (luatos_fb_lcd_ctx_t *)backend_ctx;
    if (fb_ctx == NULL) {
        return;
    }
    if (fb_ctx->lcd_conf != NULL) {
        fb_ctx->lcd_conf->lcd_use_lvgl = 0;
    }
    if (fb_ctx->rotation_buf != NULL) {
        if (fb_ctx->rotation_buf_in_psram) {
            luat_heap_opt_free(LUAT_HEAP_PSRAM, fb_ctx->rotation_buf);
        } else {
            luat_heap_free(fb_ctx->rotation_buf);
        }
    }
    luat_heap_free(fb_ctx);
}

static const airui_luatos_fb_backend_t luatos_fb_lcd_ops = {
    .name = "lcd",
    .attach = luatos_fb_lcd_attach,
    .get_buffers = luatos_fb_lcd_get_buffers,
    .flush = luatos_fb_lcd_flush,
    .direct_present = NULL,
    .direct_hide = NULL,
    .suspend = luatos_fb_lcd_suspend,
    .resume = luatos_fb_lcd_resume,
    .detach = luatos_fb_lcd_detach,
};

const airui_luatos_fb_backend_t *airui_luatos_fb_backend_lcd(void)
{
    return &luatos_fb_lcd_ops;
}

#else

const airui_luatos_fb_backend_t *airui_luatos_fb_backend_lcd(void)
{
    return NULL;
}

#endif /* LUAT_USE_LCD */

#endif /* LUAT_USE_AIRUI_LUATOS */
