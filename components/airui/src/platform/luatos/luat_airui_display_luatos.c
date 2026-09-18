/**
 * @file luat_airui_display_luatos.c
 * @summary LuatOS 显示驱动实现
 * @responsible LCD 初始化、flush、vsync 占位、资源清理
 */
#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
    #include "luat_conf_bsp_air8101.h"
#endif

#if defined(LUAT_USE_AIRUI_LUATOS)

#include "luat_airui.h"
#include "luat_lcd.h"
#include "luat_display.h"
#include "luat_log.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_airui_platform_luatos.h"
#include "lvgl9/src/draw/sw/lv_draw_sw_utils.h"
#include <stdbool.h>
#include <string.h>

#define LUAT_LOG_TAG "airui.luatos.disp"
#include "luat_log.h"

/** 默认触摸配置绑定（由平台文件维护） */
extern luat_tp_config_t *airui_platform_luatos_get_tp_bind(void);
extern const airui_luatos_keypad_cfg_t *airui_platform_luatos_get_keypad_bind(void);

static luatos_platform_data_t *luatos_get_or_alloc_data(airui_ctx_t *ctx) {
    if (ctx == NULL) {
        return NULL;
    }
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    if (data != NULL) {
        return data;
    }
    data = (luatos_platform_data_t *)luat_heap_malloc(sizeof(luatos_platform_data_t));
    if (data == NULL) {
        return NULL;
    }
    memset(data, 0, sizeof(luatos_platform_data_t));
    ctx->platform_data = data;
    return data;
}

static uint8_t *luatos_display_get_rotation_buf(luatos_platform_data_t *data, uint32_t size)
{
    if (data == NULL || size == 0) {
        return NULL;
    }
    if (data->rotation_buf != NULL && data->rotation_buf_size >= size) {
        return data->rotation_buf;
    }
    if (data->rotation_buf != NULL) {
        if (data->rotation_buf_in_psram) {
            luat_heap_opt_free(LUAT_HEAP_PSRAM, data->rotation_buf);
        } else {
            luat_heap_free(data->rotation_buf);
        }
        data->rotation_buf = NULL;
        data->rotation_buf_size = 0;
        data->rotation_buf_in_psram = 0;
    }
    data->rotation_buf = (uint8_t *)luat_heap_opt_malloc(LUAT_HEAP_PSRAM, size);
    if (data->rotation_buf != NULL) {
        data->rotation_buf_in_psram = 1;
    } else {
        data->rotation_buf = (uint8_t *)luat_heap_malloc(size);
    }
    if (data->rotation_buf == NULL) {
        return NULL;
    }
    data->rotation_buf_size = size;
    return data->rotation_buf;
}

static inline uint16_t airui_rgb565_swap(uint16_t color)
{
    return (uint16_t)((color >> 8) | (color << 8));
}

/**
 * LuatOS 显示初始化
 */
static int luatos_display_init(airui_ctx_t *ctx, uint16_t w, uint16_t h, lv_color_format_t fmt)
{
    if (ctx == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    if (fmt != LV_COLOR_FORMAT_RGB565) {
        LLOGE("luatos disp only supports RGB565, fmt=%d", fmt);
        return AIRUI_ERR_INVALID_PARAM;
    }

    luatos_platform_data_t *data = luatos_get_or_alloc_data(ctx);
    if (data == NULL) {
        return AIRUI_ERR_NO_MEM;
    }

    /* 优先使用新 Display；未注册时兼容已由 lcd.init() 初始化的旧 LCD。 */
    struct luat_display *display_conf = luat_display_get_by_id(0);
    if (display_conf != NULL) {
        data->display_conf = display_conf;
    } else {
        luat_lcd_conf_t *lcd_conf = luat_lcd_get_default();
        if (lcd_conf == NULL) {
            LLOGE("luatos disp: neither display nor lcd is initialized");
            return AIRUI_ERR_PLATFORM_ERROR;
        }
        if (lcd_conf->w == 0) {
            lcd_conf->w = w;
        }
        if (lcd_conf->h == 0) {
            lcd_conf->h = h;
        }
        lcd_conf->lcd_use_lvgl = 1;
        data->lcd_conf = lcd_conf;
        LLOGI("reuse legacy lcd backend for airui");
    }

    /* 将预先绑定的 TP 配置同步到 platform_data，供输入驱动使用 */
    data->tp_config = airui_platform_luatos_get_tp_bind();

    /* 将预先绑定的 GPIO 按键配置同步到 platform_data，供输入驱动使用 */
    const airui_luatos_keypad_cfg_t *keypad_cfg = airui_platform_luatos_get_keypad_bind();
    if (keypad_cfg != NULL) {
        data->keypad_cfg = *keypad_cfg;
    }

    return AIRUI_OK;
}

/**
 * 获取平台提供的绘制缓冲（STM32N6 的 g_draw_framebuffer）
 * 供 core airui_init 作为 LVGL 绘制缓冲使用
 */
static int luatos_display_get_buffers(airui_ctx_t *ctx, void **fb_addr, uint32_t *buf_size, uint32_t *count)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    if (data == NULL || data->display_conf == NULL || data->display_conf->fb_info == NULL) {
        return -1;
    }

    struct luat_display_fb_info *fb_info = data->display_conf->fb_info;
    struct luat_display_buf *dbuf = &fb_info->draw_buf;
    if (dbuf->buffer == NULL || dbuf->size == 0U || dbuf->count == 0U) {
        return -1;
    }

    if (fb_addr != NULL) {
        *fb_addr = dbuf->buffer;
    }
    if (buf_size != NULL) {
        *buf_size = dbuf->size;
    }
    if (count != NULL) {
        *count = dbuf->count;
    }
    
    return 0;
}

/**
 * LuatOS 显示 flush
 */
static void luatos_display_flush(airui_ctx_t *ctx, const lv_area_t *area, const uint8_t *px_map)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    if (data == NULL || area == NULL || px_map == NULL) {
        return;
    }

    lv_display_rotation_t rotation = lv_display_get_rotation(ctx->display);

    if (data->display_conf != NULL) {
        struct luat_display_rect rect = {
            .x = area->x1,
            .y = area->y1,
            .w = area->x2 - area->x1 + 1,
            .h = area->y2 - area->y1 + 1,
        };
        data->display_conf->display_funcs->fb_flush(data->display_conf, &rect, px_map,
                                                    (enum disp_rotate)rotation);
    } else if (data->lcd_conf != NULL) {
        luat_lcd_conf_t *lcd_conf = data->lcd_conf;
        luat_color_t *color = (luat_color_t *)px_map;

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

            lv_display_rotate_area(ctx->display, &rotated_area);
            uint32_t dst_w = (uint32_t)lv_area_get_width(&rotated_area);
            uint32_t dst_h = (uint32_t)lv_area_get_height(&rotated_area);
            uint32_t dst_stride = dst_w * pixel_size;
            uint32_t rotate_size = dst_stride * dst_h;
            luat_color_t *rotate_buf = (luat_color_t *)luatos_display_get_rotation_buf(data, rotate_size);
            if (rotate_buf == NULL) {
                LLOGE("legacy lcd rotation buffer alloc failed size=%u", rotate_size);
                lv_display_flush_ready(ctx->display);
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

    /* lv_display_flush_ready 必须在每次 flush 回调结束时调用，否则 LVGL 会阻塞后续渲染 */
    lv_display_flush_ready(ctx->display);
}

/**
 * 将持久 RGB565 缓冲直接提交到硬件 Layer 1。
 * Layer 0 由 AirUI/LVGL 使用；Layer 1 同一时间只允许一个组件占用。
 */
static int luatos_display_direct_present(airui_ctx_t *ctx, const void *owner,
                                         const lv_area_t *area, const void *buffer,
                                         lv_color_format_t fmt)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    struct luat_display *disp;
    int32_t screen_w;
    int32_t screen_h;
    int ret;

    if (data == NULL || owner == NULL || area == NULL || buffer == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    disp = data->display_conf;
    if (disp == NULL && data->lcd_conf != NULL) {
        LLOGE("direct_render requires display.init; legacy lcd backend has no layer API");
        return AIRUI_ERR_NOT_SUPPORTED;
    }
    if (disp == NULL || disp->display_funcs == NULL || disp->display_funcs->set_layer == NULL ||
        disp->panel == NULL || disp->panel->screen_win == NULL) {
        return AIRUI_ERR_NOT_SUPPORTED;
    }
    if (fmt != LV_COLOR_FORMAT_RGB565 || disp->rotation != LUAT_DISPLAY_ROTATE_0) {
        return AIRUI_ERR_NOT_SUPPORTED;
    }
    if (data->direct_layer_owner != NULL && data->direct_layer_owner != owner) {
        LLOGE("direct layer is already occupied");
        return AIRUI_ERR_PLATFORM_ERROR;
    }

    screen_w = disp->panel->screen_win->w;
    screen_h = disp->panel->screen_win->h;
    if (area->x1 < 0 || area->y1 < 0 || area->x2 < area->x1 || area->y2 < area->y1 ||
        area->x2 >= screen_w || area->y2 >= screen_h) {
        LLOGE("direct layer area out of screen: (%d,%d)-(%d,%d), screen=%dx%d",
              (int)area->x1, (int)area->y1, (int)area->x2, (int)area->y2,
              (int)screen_w, (int)screen_h);
        return AIRUI_ERR_INVALID_PARAM;
    }

    data->direct_layer.enable = 1;
    data->direct_layer.layer_id = 1;
    data->direct_layer.area_id = 0;
    data->direct_layer.alpha = 255;
    data->direct_layer.area.x1 = area->x1;
    data->direct_layer.area.y1 = area->y1;
    /* display layer 使用右/下开区间，LVGL area 使用闭区间。 */
    data->direct_layer.area.x2 = area->x2 + 1;
    data->direct_layer.area.y2 = area->y2 + 1;
    data->direct_layer.buffer = (void *)buffer;
    data->direct_layer.format = LUAT_DISPLAY_FORMAT_RGB565;

    ret = disp->display_funcs->set_layer(&data->direct_layer);
    if (ret != 0) {
        LLOGE("direct layer present failed: %d", ret);
        return AIRUI_ERR_PLATFORM_ERROR;
    }

    data->direct_layer_owner = owner;
    return AIRUI_OK;
}

/** 仅允许图层 owner 关闭 Layer 1，避免一个 Video 误关另一个 Video。 */
static void luatos_display_direct_hide(airui_ctx_t *ctx, const void *owner)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    struct luat_display *disp;

    if (data == NULL || owner == NULL || data->direct_layer_owner != owner) {
        return;
    }

    disp = data->display_conf;
    if (disp != NULL && disp->display_funcs != NULL && disp->display_funcs->set_layer != NULL &&
        data->direct_layer.buffer != NULL) {
        data->direct_layer.enable = 0;
        if (disp->display_funcs->set_layer(&data->direct_layer) != 0) {
            LLOGE("direct layer hide failed");
        }
    }

    data->direct_layer_owner = NULL;
    memset(&data->direct_layer, 0, sizeof(data->direct_layer));
}

/**
 * LuatOS 等待 vsync（占位）
 */
static void luatos_display_wait_vsync(airui_ctx_t *ctx)
{
    (void)ctx;
    /* 硬件接口未暴露 vsync，保留占位 */
}

/**
 * LuatOS 显示休眠
 */
static int luatos_display_suspend(airui_ctx_t *ctx)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    if (data == NULL) {
        LLOGE("display suspend invalid platform_data");
        return AIRUI_ERR_NOT_INITIALIZED;
    }
    if (data->display_conf != NULL) {
        return luat_display_sleep(data->display_conf);
    }
    if (data->lcd_conf != NULL) {
        return luat_lcd_airui_sleep(data->lcd_conf, ctx->sleep_power_down_lcd ? 1 : 0);
    }
    return AIRUI_ERR_NOT_INITIALIZED;
}

/**
 * LuatOS 显示唤醒
 */
static int luatos_display_resume(airui_ctx_t *ctx)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    if (data == NULL) {
        LLOGE("display resume invalid platform_data");
        return AIRUI_ERR_NOT_INITIALIZED;
    }
    if (data->display_conf != NULL) {
        return luat_display_wakeup(data->display_conf);
    }
    if (data->lcd_conf != NULL) {
        return luat_lcd_wakeup(data->lcd_conf);
    }
    return AIRUI_ERR_NOT_INITIALIZED;
}

/**
 * LuatOS 显示反初始化
 */
static void luatos_display_deinit(airui_ctx_t *ctx)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    if (data == NULL) {
        return;
    }

    if (data->direct_layer_owner != NULL) {
        luatos_display_direct_hide(ctx, data->direct_layer_owner);
    }

    if (data->lcd_conf != NULL) {
        data->lcd_conf->lcd_use_lvgl = 0;
    }
    if (data->rotation_buf != NULL) {
        if (data->rotation_buf_in_psram) {
            luat_heap_opt_free(LUAT_HEAP_PSRAM, data->rotation_buf);
        } else {
            luat_heap_free(data->rotation_buf);
        }
    }

    luat_heap_free(data);
    ctx->platform_data = NULL;
}

/** LuatOS 显示驱动操作接口 */
static const airui_display_ops_t luatos_display_ops = {
    .init = luatos_display_init,
    .get_buffers = luatos_display_get_buffers,
    .flush = luatos_display_flush,
    .direct_present = luatos_display_direct_present,
    .direct_hide = luatos_display_direct_hide,
    .wait_vsync = luatos_display_wait_vsync,
    .suspend = luatos_display_suspend,
    .resume = luatos_display_resume,
    .deinit = luatos_display_deinit
};

/** 获取 LuatOS 显示驱动操作接口 */
const airui_display_ops_t *airui_platform_luatos_get_display_ops(void)
{
    return &luatos_display_ops;
}

#endif /* LUAT_USE_AIRUI_LUATOS */
