/**
 * @file luat_easylvgl_display_bk7258.c
 * @summary BK7258 显示驱动实现
 * @responsible LCD 初始化、flush、vsync 占位、资源清理
 */
#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
    #include "luat_conf_bsp_air8101.h"
#endif

#if defined(LUAT_USE_EASYLVGL_BK7258)

#include "luat_easylvgl.h"
#include "luat_lcd.h"
#include "luat_log.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_easylvgl_platform_bk7258.h"
#include <stdbool.h>
#include <string.h>

#define LUAT_LOG_TAG "easylvgl.bk.disp"
#include "luat_log.h"

/** 默认触摸配置绑定（由平台文件维护） */
extern luat_tp_config_t *easylvgl_platform_bk7258_get_tp_bind(void);

static bk7258_platform_data_t *bk7258_get_or_alloc_data(easylvgl_ctx_t *ctx) {
    if (ctx == NULL) {
        return NULL;
    }
    bk7258_platform_data_t *data = easylvgl_bk7258_get_data(ctx);
    if (data != NULL) {
        return data;
    }
    data = (bk7258_platform_data_t *)luat_heap_malloc(sizeof(bk7258_platform_data_t));
    if (data == NULL) {
        return NULL;
    }
    memset(data, 0, sizeof(bk7258_platform_data_t));
    ctx->platform_data = data;
    return data;
}

/**
 * BK7258 显示初始化
 */
static int bk7258_display_init(easylvgl_ctx_t *ctx, uint16_t w, uint16_t h, lv_color_format_t fmt)
{
    if (ctx == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    if (fmt != LV_COLOR_FORMAT_RGB565) {
        LLOGE("bk7258 disp only supports RGB565, fmt=%d", fmt);
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    bk7258_platform_data_t *data = bk7258_get_or_alloc_data(ctx);
    if (data == NULL) {
        return EASYLVGL_ERR_NO_MEM;
    }

    luat_lcd_conf_t *lcd_conf = luat_lcd_get_default();
    if (lcd_conf == NULL) {
        LLOGE("bk7258 disp: lcd_conf is NULL");
        return EASYLVGL_ERR_PLATFORM_ERROR;
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

    /* 将预先绑定的 TP 配置同步到 platform_data，供输入驱动使用 */
    data->tp_config = easylvgl_platform_bk7258_get_tp_bind();

    return EASYLVGL_OK;
}

/**
 * BK7258 显示 flush
 */
static void bk7258_display_flush(easylvgl_ctx_t *ctx, const lv_area_t *area, const uint8_t *px_map)
{
    bk7258_platform_data_t *data = easylvgl_bk7258_get_data(ctx);
    if (data == NULL || data->lcd_conf == NULL || area == NULL || px_map == NULL) {
        return;
    }

    luat_color_t *color_p = (luat_color_t *)px_map;
    luat_lcd_conf_t *lcd_conf = data->lcd_conf;
    bool is_last = lv_display_flush_is_last(ctx->display);

    /* 直接绘制到 LCD，逐块刷新 */
    // LLOGD("bk7258_display_flush: area=(%d,%d,%d,%d) size=(%d,%d)", area->x1, area->y1, area->x2, area->y2,
    //       area->x2 - area->x1 + 1, area->y2 - area->y1 + 1);
    luat_lcd_draw(lcd_conf, area->x1, area->y1, area->x2, area->y2, color_p);

    /* 在最后一块时触发 flush，确保硬件输出（假定 luat_lcd_flush 同步完成） */
    if (is_last) {
        luat_lcd_flush(lcd_conf);
    }

    /* lv_display_flush_ready 必须在每次 flush 回调结束时调用，否则 LVGL 会阻塞后续渲染 */
    lv_display_flush_ready(ctx->display);
}

/**
 * BK7258 等待 vsync（占位）
 */
static void bk7258_display_wait_vsync(easylvgl_ctx_t *ctx)
{
    (void)ctx;
    /* 硬件接口未暴露 vsync，保留占位 */
}

/**
 * BK7258 显示反初始化
 */
static void bk7258_display_deinit(easylvgl_ctx_t *ctx)
{
    bk7258_platform_data_t *data = easylvgl_bk7258_get_data(ctx);
    if (data == NULL) {
        return;
    }

    if (data->lcd_conf != NULL) {
        data->lcd_conf->lcd_use_lvgl = 0;
    }

    luat_heap_free(data);
    ctx->platform_data = NULL;
}

/** BK7258 显示驱动操作接口 */
static const easylvgl_display_ops_t bk7258_display_ops = {
    .init = bk7258_display_init,
    .flush = bk7258_display_flush,
    .wait_vsync = bk7258_display_wait_vsync,
    .deinit = bk7258_display_deinit
};

/** 获取 BK7258 显示驱动操作接口 */
const easylvgl_display_ops_t *easylvgl_platform_bk7258_get_display_ops(void)
{
    return &bk7258_display_ops;
}

#endif /* LUAT_USE_EASYLVGL_BK7258 */


