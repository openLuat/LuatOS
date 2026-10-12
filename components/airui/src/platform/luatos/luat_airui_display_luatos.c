/**
 * @file luat_airui_display_luatos.c
 * @summary LuatOS 显示驱动调度器
 * @responsible 按 display → lcd 探测后端，不依赖任一底层库头文件
 */
#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
    #include "luat_conf_bsp_air8101.h"
#endif

#if defined(LUAT_USE_AIRUI_LUATOS)

#include "luat_airui.h"
#include "luat_log.h"
#include "luat_mem.h"
#include "luat_airui_platform_luatos.h"
#include "luat_airui_display_luatos_backend.h"
#include <string.h>

#define LUAT_LOG_TAG "airui.luatos.disp"
#include "luat_log.h"

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

static const airui_luatos_fb_backend_t *luatos_fb_ops(luatos_platform_data_t *data)
{
    return data ? (const airui_luatos_fb_backend_t *)data->fb_backend : NULL;
}

static int luatos_try_attach(const airui_luatos_fb_backend_t *backend,
                             airui_ctx_t *ctx, uint16_t w, uint16_t h,
                             luatos_platform_data_t *data)
{
    if (backend == NULL || backend->attach == NULL) {
        return AIRUI_ERR_NOT_SUPPORTED;
    }
    int ret = backend->attach(ctx, w, h, &data->fb_ctx);
    if (ret != AIRUI_OK) {
        data->fb_ctx = NULL;
        return ret;
    }
    data->fb_backend = backend;
    LLOGI("airui display backend: %s", backend->name ? backend->name : "unknown");
    return AIRUI_OK;
}

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

    if (luatos_try_attach(airui_luatos_fb_backend_display(), ctx, w, h, data) != AIRUI_OK &&
        luatos_try_attach(airui_luatos_fb_backend_lcd(), ctx, w, h, data) != AIRUI_OK) {
        LLOGE("luatos disp: neither display nor lcd is initialized");
        luat_heap_free(data);
        ctx->platform_data = NULL;
        return AIRUI_ERR_PLATFORM_ERROR;
    }

    data->tp_config = airui_platform_luatos_get_tp_bind();

    const airui_luatos_keypad_cfg_t *keypad_cfg = airui_platform_luatos_get_keypad_bind();
    if (keypad_cfg != NULL) {
        data->keypad_cfg = *keypad_cfg;
    }

    return AIRUI_OK;
}

static int luatos_display_get_buffers(airui_ctx_t *ctx, void **fb_addr, uint32_t *buf_size, uint32_t *count)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    const airui_luatos_fb_backend_t *ops = luatos_fb_ops(data);
    if (ops == NULL || ops->get_buffers == NULL) {
        return -1;
    }
    return ops->get_buffers(data->fb_ctx, fb_addr, buf_size, count);
}

static void luatos_display_flush(airui_ctx_t *ctx, const lv_area_t *area, const uint8_t *px_map)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    const airui_luatos_fb_backend_t *ops = luatos_fb_ops(data);
    if (data != NULL && ops != NULL && ops->flush != NULL && area != NULL && px_map != NULL) {
        ops->flush(ctx, data->fb_ctx, area, px_map);
    }

    /* lv_display_flush_ready 必须在每次 flush 回调结束时调用，否则 LVGL 会阻塞后续渲染 */
    if (ctx != NULL && ctx->display != NULL) {
        lv_display_flush_ready(ctx->display);
    }
}

static int luatos_display_direct_present(airui_ctx_t *ctx, const void *owner,
                                         const lv_area_t *area, const void *buffer,
                                         lv_color_format_t fmt)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    const airui_luatos_fb_backend_t *ops = luatos_fb_ops(data);
    if (ops == NULL || ops->direct_present == NULL) {
        return AIRUI_ERR_NOT_SUPPORTED;
    }
    return ops->direct_present(ctx, data->fb_ctx, owner, area, buffer, fmt);
}

static void luatos_display_direct_hide(airui_ctx_t *ctx, const void *owner)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    const airui_luatos_fb_backend_t *ops = luatos_fb_ops(data);
    if (ops == NULL || ops->direct_hide == NULL) {
        return;
    }
    ops->direct_hide(ctx, data->fb_ctx, owner);
}

static void luatos_display_wait_vsync(airui_ctx_t *ctx)
{
    (void)ctx;
}

static int luatos_display_suspend(airui_ctx_t *ctx)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    const airui_luatos_fb_backend_t *ops = luatos_fb_ops(data);
    if (data == NULL || ops == NULL || ops->suspend == NULL) {
        LLOGE("display suspend invalid platform_data");
        return AIRUI_ERR_NOT_INITIALIZED;
    }
    return ops->suspend(ctx, data->fb_ctx);
}

static int luatos_display_resume(airui_ctx_t *ctx)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    const airui_luatos_fb_backend_t *ops = luatos_fb_ops(data);
    if (data == NULL || ops == NULL || ops->resume == NULL) {
        LLOGE("display resume invalid platform_data");
        return AIRUI_ERR_NOT_INITIALIZED;
    }
    return ops->resume(ctx, data->fb_ctx);
}

static void luatos_display_deinit(airui_ctx_t *ctx)
{
    luatos_platform_data_t *data = airui_luatos_get_data(ctx);
    const airui_luatos_fb_backend_t *ops;
    if (data == NULL) {
        return;
    }

    ops = luatos_fb_ops(data);
    if (ops != NULL && ops->detach != NULL) {
        ops->detach(data->fb_ctx);
    }

    luat_heap_free(data);
    ctx->platform_data = NULL;
}

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

const airui_display_ops_t *airui_platform_luatos_get_display_ops(void)
{
    return &luatos_display_ops;
}

#endif /* LUAT_USE_AIRUI_LUATOS */
