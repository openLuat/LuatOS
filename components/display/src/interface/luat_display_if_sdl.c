#include "luat_base.h"
#include "luat_display.h"
#include "luat_display_sdl2.h"
#include "luat_display_if_comm.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "display_sdl"
#include "luat_log.h"

static luat_display_sdl2_ctx_t *g_sdl2_ctx = NULL;
static void *g_sdl2_draw_buf = NULL;

static int sdl_init(struct luat_display *disp)
{
    return 0;
}

static int sdl_deinit(struct luat_display *disp)
{
    if (g_sdl2_ctx != NULL) {
        luat_display_sdl2_destroy(g_sdl2_ctx);
        g_sdl2_ctx = NULL;
    }
    if (g_sdl2_draw_buf != NULL) {
        luat_heap_free(g_sdl2_draw_buf);
        g_sdl2_draw_buf = NULL;
    }
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

    /*为上层绘制分配 CPU 可写 draw buffer*/
    uint32_t draw_buf_size = info->width * info->height * 2;
    if (g_sdl2_draw_buf == NULL) {
        g_sdl2_draw_buf = luat_heap_zalloc(draw_buf_size);
        if (g_sdl2_draw_buf == NULL) {
            LLOGE("sdl2 draw buffer alloc failed");
            return -1;
        }
    }

    info->draw_buf.buffer = g_sdl2_draw_buf;
    info->draw_buf.size = draw_buf_size;
    info->draw_buf.stride = info->stride;
    info->draw_buf.count = 1;
    info->draw_buf.format = info->format;
    info->draw_buf.width = info->width;
    info->draw_buf.height = info->height;

    info->inited = 1;
    return 0;
}

/*初始化接口，在这里创建 SDL2 窗口*/
static int sdl_inf_init(struct luat_display_panel *panel)
{
    if (panel == NULL || panel->screen_win == NULL) {
        return -1;
    }

    if (g_sdl2_ctx != NULL) {
        LLOGD("sdl2 display already inited");
        return 0;
    }

    g_sdl2_ctx = luat_display_sdl2_create(panel->name,
                                          panel->screen_win->w,
                                          panel->screen_win->h);
    if (g_sdl2_ctx == NULL) {
        LLOGE("sdl2 display create failed");
        return -1;
    }

    return 0;
}

/*设置显示层*/
static int sdl_set_layer(struct luat_display_layer_data *layer_data)
{
    return 0;
}

/*刷新显示缓冲区*/
static int sdl_fb_flush(struct luat_display_rect *rect, const void *data, enum disp_rotate rotation)
{
    if (g_sdl2_ctx == NULL || rect == NULL || data == NULL) {
        return 0;
    }

    luat_display_sdl2_draw(g_sdl2_ctx,
                           rect->x, rect->y,
                           rect->w, rect->h,
                           data, rect->w * 2);

    luat_display_sdl2_flush(g_sdl2_ctx);
    return 0;
}

static int sdl_wait_vsync(void)
{
    if (g_sdl2_ctx != NULL) {
        luat_display_sdl2_pump_events(g_sdl2_ctx);
    }
    return 0;
}

static int sdl_pan_display(int index)
{
    if (g_sdl2_ctx != NULL) {
        luat_display_sdl2_flush(g_sdl2_ctx);
        luat_display_sdl2_pump_events(g_sdl2_ctx);
    }
    return 0;
}


struct luat_display_funcs sdl_funcs = {
    .name = "sdl",
    .fb_probe = sdl_fb_probe,
    .inf_init = sdl_inf_init,
    .set_layer = sdl_set_layer,
    .fb_flush = sdl_fb_flush,
    .wait_vsync = sdl_wait_vsync,
    .pan_display = sdl_pan_display,
};
