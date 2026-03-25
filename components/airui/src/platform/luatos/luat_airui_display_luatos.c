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
#include "luat_log.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_airui_platform_luatos.h"
#include <stdbool.h>
#include <string.h>

#define LUAT_LOG_TAG "airui.luatos.disp"
#include "luat_log.h"

/** 默认触摸配置绑定（由平台文件维护） */
extern luat_tp_config_t *airui_platform_luatos_get_tp_bind(void);
extern const airui_luatos_keypad_cfg_t *airui_platform_luatos_get_keypad_bind(void);

#if defined(__BK72XX__)
typedef void (*luat_lcd_async_flush_cb_t)(void *userdata, int result);
extern void luat_lcd_bk72xx_set_async_flush_cb(luat_lcd_conf_t *conf, luat_lcd_async_flush_cb_t cb, void *userdata);

static void luatos_display_async_flush_done(void *userdata, int result)
{
    lv_display_t *display = (lv_display_t *)userdata;
    if (display == NULL) {
        return;
    }
    if (result != 0) {
        LLOGW("async flush complete with result=%d", result);
    }
    lv_display_flush_ready(display);
}
#endif

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

    luat_lcd_conf_t *lcd_conf = luat_lcd_get_default();
    if (lcd_conf == NULL) {
        LLOGE("luatos disp: lcd_conf is NULL");
        return AIRUI_ERR_PLATFORM_ERROR;
    }

    /* 保留调用前的长宽，若未配置则使用入参 */
    if (lcd_conf->w == 0) {
        lcd_conf->w = w;
    }
    if (lcd_conf->h == 0) {
        lcd_conf->h = h;
    }
    lcd_conf->lcd_use_lvgl = 1;

    data->lcd_conf = lcd_conf;

#if defined(__BK72XX__)
    luat_lcd_bk72xx_set_async_flush_cb(lcd_conf, luatos_display_async_flush_done, ctx->display);
#endif

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
 * LuatOS 显示 flush
 */
static void luatos_display_flush(airui_ctx_t *ctx, const lv_area_t *area, const uint8_t *px_map)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    if (data == NULL || data->lcd_conf == NULL || area == NULL || px_map == NULL) {
        return;
    }

    luat_color_t *color_p = (luat_color_t *)px_map;
    luat_lcd_conf_t *lcd_conf = data->lcd_conf;
    bool is_last = lv_display_flush_is_last(ctx->display);

    /* 直接绘制到 LCD，逐块刷新 */
    luat_lcd_draw(lcd_conf, area->x1, area->y1, area->x2, area->y2, color_p);

    if (!is_last) {
        lv_display_flush_ready(ctx->display);
        return;
    }

    if (luat_lcd_flush(lcd_conf) != 0) {
        lv_display_flush_ready(ctx->display);
    }
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
    if (data == NULL || data->lcd_conf == NULL) {
        LLOGE("display suspend invalid platform_data ctx=%p data=%p lcd=%p", ctx, data, data ? data->lcd_conf : NULL);
        return AIRUI_ERR_NOT_INITIALIZED;
    }

    int ret = luat_lcd_airui_sleep(data->lcd_conf, ctx->sleep_power_down_lcd ? 1 : 0);
    return ret;
}

/**
 * LuatOS 显示唤醒
 */
static int luatos_display_resume(airui_ctx_t *ctx)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    if (data == NULL || data->lcd_conf == NULL) {
        LLOGE("display resume invalid platform_data ctx=%p data=%p lcd=%p", ctx, data, data ? data->lcd_conf : NULL);
        return AIRUI_ERR_NOT_INITIALIZED;
    }

    int ret = luat_lcd_wakeup(data->lcd_conf);
    return ret;
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

    if (data->lcd_conf != NULL) {
#if defined(__BK72XX__)
        luat_lcd_bk72xx_set_async_flush_cb(data->lcd_conf, NULL, NULL);
#endif
        data->lcd_conf->lcd_use_lvgl = 0;
    }

    luat_heap_free(data);
    ctx->platform_data = NULL;
}

/** LuatOS 显示驱动操作接口 */
static const airui_display_ops_t luatos_display_ops = {
    .init = luatos_display_init,
    .flush = luatos_display_flush,
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

