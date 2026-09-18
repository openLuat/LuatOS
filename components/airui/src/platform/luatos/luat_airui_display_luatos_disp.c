/**
 * @file luat_airui_display_luatos_disp.c
 * @summary AirUI LuatOS 显示后端：新 display 库
 */
#include "luat_conf_bsp.h"
#if defined(__BK72XX__)
    #include "luat_conf_bsp_air8101.h"
#endif

#if defined(LUAT_USE_AIRUI_LUATOS)

#include "luat_airui_display_luatos_backend.h"

#if defined(LUAT_USE_DISPLAY)

#include "luat_airui.h"
#include "luat_display.h"
#include "luat_mem.h"
#include <string.h>

#define LUAT_LOG_TAG "airui.luatos.disp"
#include "luat_log.h"

typedef struct {
    struct luat_display *display_conf;
    struct luat_display_layer_data direct_layer;
    const void *direct_layer_owner;
} luatos_fb_display_ctx_t;

static int luatos_fb_display_attach(airui_ctx_t *ctx, uint16_t w, uint16_t h, void **out_ctx)
{
    struct luat_display *display_conf;
    luatos_fb_display_ctx_t *fb_ctx;

    (void)ctx;
    (void)w;
    (void)h;
    if (out_ctx == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    display_conf = luat_display_get_by_id(0);
    if (display_conf == NULL) {
        return AIRUI_ERR_NOT_INITIALIZED;
    }

    fb_ctx = (luatos_fb_display_ctx_t *)luat_heap_malloc(sizeof(luatos_fb_display_ctx_t));
    if (fb_ctx == NULL) {
        return AIRUI_ERR_NO_MEM;
    }
    memset(fb_ctx, 0, sizeof(*fb_ctx));
    fb_ctx->display_conf = display_conf;
    *out_ctx = fb_ctx;
    return AIRUI_OK;
}

static int luatos_fb_display_get_buffers(void *backend_ctx, void **fb_addr, uint32_t *buf_size, uint32_t *count)
{
    luatos_fb_display_ctx_t *fb_ctx = (luatos_fb_display_ctx_t *)backend_ctx;
    struct luat_display_fb_info *fb_info;
    struct luat_display_buf *dbuf;

    if (fb_ctx == NULL || fb_ctx->display_conf == NULL || fb_ctx->display_conf->fb_info == NULL) {
        return -1;
    }

    fb_info = fb_ctx->display_conf->fb_info;
    dbuf = &fb_info->draw_buf;
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

static void luatos_fb_display_flush(airui_ctx_t *ctx, void *backend_ctx,
                                    const lv_area_t *area, const uint8_t *px_map)
{
    luatos_fb_display_ctx_t *fb_ctx = (luatos_fb_display_ctx_t *)backend_ctx;
    struct luat_display_rect rect;
    lv_display_rotation_t rotation;

    if (fb_ctx == NULL || fb_ctx->display_conf == NULL || fb_ctx->display_conf->display_funcs == NULL ||
        fb_ctx->display_conf->display_funcs->fb_flush == NULL || area == NULL || px_map == NULL) {
        return;
    }

    rotation = (ctx != NULL && ctx->display != NULL) ? lv_display_get_rotation(ctx->display)
                                                     : LV_DISPLAY_ROTATION_0;
    rect.x = area->x1;
    rect.y = area->y1;
    rect.w = area->x2 - area->x1 + 1;
    rect.h = area->y2 - area->y1 + 1;
    fb_ctx->display_conf->display_funcs->fb_flush(fb_ctx->display_conf, &rect, px_map,
                                                  (enum disp_rotate)rotation);
}

static int luatos_fb_display_direct_present(airui_ctx_t *ctx, void *backend_ctx, const void *owner,
                                            const lv_area_t *area, const void *buffer,
                                            lv_color_format_t fmt)
{
    luatos_fb_display_ctx_t *fb_ctx = (luatos_fb_display_ctx_t *)backend_ctx;
    struct luat_display *disp;
    int32_t screen_w;
    int32_t screen_h;
    int ret;

    (void)ctx;
    if (fb_ctx == NULL || owner == NULL || area == NULL || buffer == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    disp = fb_ctx->display_conf;
    if (disp == NULL || disp->display_funcs == NULL || disp->display_funcs->set_layer == NULL ||
        disp->panel == NULL || disp->panel->screen_win == NULL) {
        return AIRUI_ERR_NOT_SUPPORTED;
    }
    if (fmt != LV_COLOR_FORMAT_RGB565 || disp->rotation != LUAT_DISPLAY_ROTATE_0) {
        return AIRUI_ERR_NOT_SUPPORTED;
    }
    if (fb_ctx->direct_layer_owner != NULL && fb_ctx->direct_layer_owner != owner) {
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

    fb_ctx->direct_layer.enable = 1;
    fb_ctx->direct_layer.layer_id = 1;
    fb_ctx->direct_layer.area_id = 0;
    fb_ctx->direct_layer.alpha = 255;
    fb_ctx->direct_layer.area.x1 = area->x1;
    fb_ctx->direct_layer.area.y1 = area->y1;
    /* display layer 使用右/下开区间，LVGL area 使用闭区间。 */
    fb_ctx->direct_layer.area.x2 = area->x2 + 1;
    fb_ctx->direct_layer.area.y2 = area->y2 + 1;
    fb_ctx->direct_layer.buffer = (void *)buffer;
    fb_ctx->direct_layer.format = LUAT_DISPLAY_FORMAT_RGB565;

    ret = disp->display_funcs->set_layer(&fb_ctx->direct_layer);
    if (ret != 0) {
        LLOGE("direct layer present failed: %d", ret);
        return AIRUI_ERR_PLATFORM_ERROR;
    }

    fb_ctx->direct_layer_owner = owner;
    return AIRUI_OK;
}

static void luatos_fb_display_direct_hide(airui_ctx_t *ctx, void *backend_ctx, const void *owner)
{
    luatos_fb_display_ctx_t *fb_ctx = (luatos_fb_display_ctx_t *)backend_ctx;
    struct luat_display *disp;

    (void)ctx;
    if (fb_ctx == NULL || owner == NULL || fb_ctx->direct_layer_owner != owner) {
        return;
    }

    disp = fb_ctx->display_conf;
    if (disp != NULL && disp->display_funcs != NULL && disp->display_funcs->set_layer != NULL &&
        fb_ctx->direct_layer.buffer != NULL) {
        fb_ctx->direct_layer.enable = 0;
        if (disp->display_funcs->set_layer(&fb_ctx->direct_layer) != 0) {
            LLOGE("direct layer hide failed");
        }
    }

    fb_ctx->direct_layer_owner = NULL;
    memset(&fb_ctx->direct_layer, 0, sizeof(fb_ctx->direct_layer));
}

static int luatos_fb_display_suspend(airui_ctx_t *ctx, void *backend_ctx)
{
    luatos_fb_display_ctx_t *fb_ctx = (luatos_fb_display_ctx_t *)backend_ctx;
    (void)ctx;
    if (fb_ctx == NULL || fb_ctx->display_conf == NULL) {
        return AIRUI_ERR_NOT_INITIALIZED;
    }
    return luat_display_sleep(fb_ctx->display_conf);
}

static int luatos_fb_display_resume(airui_ctx_t *ctx, void *backend_ctx)
{
    luatos_fb_display_ctx_t *fb_ctx = (luatos_fb_display_ctx_t *)backend_ctx;
    (void)ctx;
    if (fb_ctx == NULL || fb_ctx->display_conf == NULL) {
        return AIRUI_ERR_NOT_INITIALIZED;
    }
    return luat_display_wakeup(fb_ctx->display_conf);
}

static void luatos_fb_display_detach(void *backend_ctx)
{
    luatos_fb_display_ctx_t *fb_ctx = (luatos_fb_display_ctx_t *)backend_ctx;
    if (fb_ctx == NULL) {
        return;
    }
    if (fb_ctx->direct_layer_owner != NULL) {
        luatos_fb_display_direct_hide(NULL, fb_ctx, fb_ctx->direct_layer_owner);
    }
    luat_heap_free(fb_ctx);
}

static const airui_luatos_fb_backend_t luatos_fb_display_ops = {
    .name = "display",
    .attach = luatos_fb_display_attach,
    .get_buffers = luatos_fb_display_get_buffers,
    .flush = luatos_fb_display_flush,
    .direct_present = luatos_fb_display_direct_present,
    .direct_hide = luatos_fb_display_direct_hide,
    .suspend = luatos_fb_display_suspend,
    .resume = luatos_fb_display_resume,
    .detach = luatos_fb_display_detach,
};

const airui_luatos_fb_backend_t *airui_luatos_fb_backend_display(void)
{
    return &luatos_fb_display_ops;
}

#else

const airui_luatos_fb_backend_t *airui_luatos_fb_backend_display(void)
{
    return NULL;
}

#endif /* LUAT_USE_DISPLAY */

#endif /* LUAT_USE_AIRUI_LUATOS */
