#include "luat_base.h"
#include "luat_display.h"
#include "luat_display_sdl2.h"
#include "luat_display_if_comm.h"
#include "luat_mem.h"
#include <string.h>

#define LUAT_LOG_TAG "display_sdl"
#include "luat_log.h"

struct sdl_disp_userdata {
    luat_display_sdl2_ctx_t *ctx;
    void *draw_buf;
};


static int sdl_deinit(struct luat_display *disp)
{
    if (disp == NULL || disp->userdata == NULL) {
        return 0;
    }

    struct sdl_disp_userdata *ud = (struct sdl_disp_userdata *)disp->userdata;

    if (ud->ctx != NULL) {
        luat_display_sdl2_destroy(ud->ctx);
        ud->ctx = NULL;
    }
    if (ud->draw_buf != NULL) {
        luat_heap_free(ud->draw_buf);
        ud->draw_buf = NULL;
    }

    luat_heap_free(ud);
    disp->userdata = NULL;

    return 0;
}

/*探测显示缓冲区*/
static int sdl_fb_probe(struct luat_display_panel *panel, struct luat_display_fb_info *info)
{
    if (panel == NULL || panel->screen_win == NULL || info == NULL) {
        return -1;
    }

    info->width = panel->screen_win->w;
    info->height = panel->screen_win->h;

    /*SDL2 纹理使用 RGB565 格式，与 PC 模拟器常用配置保持一致*/
    info->format = LUAT_DISPLAY_FORMAT_RGB565;
    info->bits_per_pixel = 16;
    info->stride = info->width * 2;

    /*SDL2 framebuffer 由 SDL 纹理托管，不对外暴露 CPU 可写地址*/
    info->fb_start = NULL;
    info->fb_size = 0;
    info->fb_count = 1;

    return 0;
}

/*初始化接口，在这里创建 SDL2 窗口*/
static int sdl_inf_init(struct luat_display *disp)
{
    if (disp == NULL || disp->panel == NULL || disp->panel->screen_win == NULL) {
        return -1;
    }

    struct luat_display_panel *panel = disp->panel;
    struct luat_display_fb_info *info = disp->fb_info;

    if (info == NULL) {
        LLOGE("sdl2 fb_info not ready");
        return -1;
    }

    /*分配 userdata，用于管理该 display 实例的 SDL 上下文和 draw buffer*/
    struct sdl_disp_userdata *ud = luat_heap_zalloc(sizeof(struct sdl_disp_userdata));
    if (ud == NULL) {
        LLOGE("sdl2 userdata alloc failed");
        return -1;
    }

    /*分配 CPU 可写 draw buffer*/
    uint32_t draw_buf_size = info->width * info->height * 2;
    ud->draw_buf = luat_heap_zalloc(draw_buf_size);
    if (ud->draw_buf == NULL) {
        LLOGE("sdl2 draw buffer alloc failed");
        luat_heap_free(ud);
        return -1;
    }

    /*创建 SDL2 窗口*/
    ud->ctx = luat_display_sdl2_create(panel->name,
                                       panel->screen_win->w,
                                       panel->screen_win->h);
    if (ud->ctx == NULL) {
        LLOGE("sdl2 display create failed");
        luat_heap_free(ud->draw_buf);
        luat_heap_free(ud);
        return -1;
    }

    /*填充 draw_buf 信息*/
    info->draw_buf.buffer = ud->draw_buf;
    info->draw_buf.size = draw_buf_size;
    info->draw_buf.stride = info->stride;
    info->draw_buf.count = 1;
    info->draw_buf.format = info->format;
    info->draw_buf.width = info->width;
    info->draw_buf.height = info->height;

    disp->userdata = ud;

    return 0;
}

/* 视频层。layer_id 0 是 UI 层，不叠到画面上。解码线程只把 s_video_dirty 置 1。 */
static struct luat_display_layer_data s_video_layer;
static volatile int s_video_dirty;

static struct sdl_disp_userdata *sdl_ud(struct luat_display *disp)
{
    if (disp == NULL || disp->userdata == NULL) {
        return NULL;
    }
    return (struct sdl_disp_userdata *)disp->userdata;
}

static void shadow_copy(struct luat_display *disp, struct sdl_disp_userdata *ud,
                        int x, int y, int w, int h, const void *data, uint32_t pitch)
{
    uint8_t *dst;
    const uint8_t *src;
    uint32_t dst_pitch;
    int row;

    if (ud == NULL || ud->draw_buf == NULL || disp->fb_info == NULL || data == NULL || w <= 0 || h <= 0) {
        return;
    }
    if (x < 0 || y < 0) {
        return;
    }
    dst_pitch = disp->fb_info->width * 2U;
    if ((uint32_t)(x + w) > disp->fb_info->width || (uint32_t)(y + h) > disp->fb_info->height) {
        return;
    }
    if (pitch == 0U) {
        pitch = (uint32_t)w * 2U;
    }
    dst = (uint8_t *)ud->draw_buf;
    src = (const uint8_t *)data;
    for (row = 0; row < h; row++) {
        memcpy(dst + (size_t)(y + row) * dst_pitch + (size_t)x * 2U,
               src + (size_t)row * pitch,
               (size_t)w * 2U);
    }
}

static void blit_video(struct luat_display *disp, struct sdl_disp_userdata *ud)
{
    int x;
    int y;
    int w;
    int h;

    if (!s_video_layer.enable || s_video_layer.buffer == NULL || ud == NULL || ud->ctx == NULL) {
        return;
    }
    if (s_video_layer.format != LUAT_DISPLAY_FORMAT_RGB565) {
        return;
    }
    x = (int)s_video_layer.area.x1;
    y = (int)s_video_layer.area.y1;
    w = (int)(s_video_layer.area.x2 - s_video_layer.area.x1);
    h = (int)(s_video_layer.area.y2 - s_video_layer.area.y1);
    if (w <= 0 || h <= 0 || disp->fb_info == NULL) {
        return;
    }
    if (x < 0 || y < 0 ||
        (uint32_t)(x + w) > disp->fb_info->width ||
        (uint32_t)(y + h) > disp->fb_info->height) {
        return;
    }
    luat_display_sdl2_draw(ud->ctx, (int16_t)x, (int16_t)y, (uint16_t)w, (uint16_t)h,
                           s_video_layer.buffer, (uint32_t)w * 2U);
}

static void restore_video_rect(struct luat_display *disp, struct sdl_disp_userdata *ud)
{
    int x;
    int y;
    int w;
    int h;
    uint32_t pitch;
    uint8_t *src;

    if (!s_video_layer.enable || ud == NULL || ud->ctx == NULL || ud->draw_buf == NULL || disp->fb_info == NULL) {
        return;
    }
    x = (int)s_video_layer.area.x1;
    y = (int)s_video_layer.area.y1;
    w = (int)(s_video_layer.area.x2 - s_video_layer.area.x1);
    h = (int)(s_video_layer.area.y2 - s_video_layer.area.y1);
    if (w <= 0 || h <= 0) {
        return;
    }
    pitch = disp->fb_info->width * 2U;
    src = (uint8_t *)ud->draw_buf + (size_t)y * pitch + (size_t)x * 2U;
    luat_display_sdl2_draw(ud->ctx, (int16_t)x, (int16_t)y, (uint16_t)w, (uint16_t)h, src, pitch);
}

/*设置显示层。UI 层只记录，视频层叠到 SDL 纹理上。*/
static int sdl_set_layer(struct luat_display_layer_data *layer_data)
{
    struct luat_display *disp;
    struct sdl_disp_userdata *ud;

    if (layer_data == NULL) {
        return -1;
    }
    if (layer_data->layer_id == 0) {
        return 0;
    }

    disp = luat_display_get_default();
    ud = sdl_ud(disp);
    if (!layer_data->enable) {
        if (ud != NULL && ud->ctx != NULL) {
            restore_video_rect(disp, ud);
            luat_display_sdl2_flush(ud->ctx);
        }
        memset(&s_video_layer, 0, sizeof(s_video_layer));
        s_video_dirty = 0;
        return 0;
    }

    s_video_layer = *layer_data;
    s_video_dirty = 0;
    if (ud != NULL && ud->ctx != NULL) {
        blit_video(disp, ud);
        luat_display_sdl2_flush(ud->ctx);
    }
    return 0;
}

/*解码线程调用。只做标记，真正贴图在主线程。*/
static int sdl_refresh_layer(struct luat_display_layer_data *layer_data)
{
    (void)layer_data;
    if (s_video_layer.enable) {
        s_video_dirty = 1;
    }
    return 0;
}

void luat_display_sdl_present_overlay(void)
{
    struct luat_display *disp;
    struct sdl_disp_userdata *ud;

    if (!s_video_dirty || !s_video_layer.enable) {
        return;
    }
    disp = luat_display_get_default();
    ud = sdl_ud(disp);
    if (ud == NULL || ud->ctx == NULL) {
        return;
    }
    blit_video(disp, ud);
    luat_display_sdl2_flush(ud->ctx);
    s_video_dirty = 0;
}

static void *sdl_native(struct luat_display *disp, int which)
{
    struct sdl_disp_userdata *ud = sdl_ud(disp);
    if (ud == NULL || ud->ctx == NULL) {
        return NULL;
    }
    if (which == 0) {
        return ud->ctx->window;
    }
    if (which == 1) {
        return ud->ctx->renderer;
    }
    return ud->ctx->texture;
}

void *luat_display_sdl_get_window(struct luat_display *disp)
{
    return sdl_native(disp, 0);
}

void *luat_display_sdl_get_renderer(struct luat_display *disp)
{
    return sdl_native(disp, 1);
}

void *luat_display_sdl_get_texture(struct luat_display *disp)
{
    return sdl_native(disp, 2);
}

int luat_display_sdl_blit(struct luat_display *disp, int32_t x, int32_t y, int32_t w, int32_t h,
                          const void *data, uint32_t pitch, int present)
{
    struct sdl_disp_userdata *ud;

    if (disp == NULL || data == NULL || w <= 0 || h <= 0) {
        return -1;
    }
    ud = sdl_ud(disp);
    if (ud == NULL || ud->ctx == NULL) {
        return -1;
    }
    if (pitch == 0U) {
        pitch = (uint32_t)w * 2U;
    }
    shadow_copy(disp, ud, (int)x, (int)y, (int)w, (int)h, data, pitch);
    luat_display_sdl2_draw(ud->ctx, (int16_t)x, (int16_t)y, (uint16_t)w, (uint16_t)h, data, pitch);
    if (present) {
        if (s_video_layer.enable) {
            blit_video(disp, ud);
            s_video_dirty = 0;
        }
        luat_display_sdl2_flush(ud->ctx);
    }
    return 0;
}

/*刷新显示缓冲区*/
static int sdl_fb_flush(struct luat_display *disp, struct luat_display_rect *rect, const void *data, enum disp_rotate rotation)
{
    (void)rotation;
    if (rect == NULL) {
        return 0;
    }
    return luat_display_sdl_blit(disp, rect->x, rect->y, rect->w, rect->h, data, (uint32_t)rect->w * 2U, 1);
}

static int sdl_wait_vsync(struct luat_display *disp)
{
    if (disp == NULL || disp->userdata == NULL) {
        return 0;
    }

    struct sdl_disp_userdata *ud = (struct sdl_disp_userdata *)disp->userdata;
    if (ud->ctx != NULL) {
        luat_display_sdl2_pump_events(ud->ctx);
    }
    return 0;
}

static int sdl_pan_display(struct luat_display *disp, int index)
{
    if (disp == NULL || disp->userdata == NULL) {
        return 0;
    }

    struct sdl_disp_userdata *ud = (struct sdl_disp_userdata *)disp->userdata;
    if (ud->ctx != NULL) {
        luat_display_sdl2_flush(ud->ctx);
        luat_display_sdl2_pump_events(ud->ctx);
    }
    return 0;
}

struct luat_display_funcs sdl_funcs = {
    .name = "sdl",
    .fb_probe = sdl_fb_probe,
    .inf_init = sdl_inf_init,
    .fb_flush = sdl_fb_flush,
    .set_layer = sdl_set_layer,
    .refresh_layer = sdl_refresh_layer,
    .wait_vsync = sdl_wait_vsync,
    .pan_display = sdl_pan_display,
    .deinit = sdl_deinit,
};
