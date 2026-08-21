#include "luat_base.h"
#include "luat_display.h"
#include "luat_display_sdl2.h"
#include "luat_display_if_comm.h"
#include "luat_mem.h"

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

/*设置显示层*/
static int sdl_set_layer(struct luat_display_layer_data *layer_data)
{
    return 0;
}

/*刷新显示缓冲区*/
static int sdl_fb_flush(struct luat_display *disp, struct luat_display_rect *rect, const void *data, enum disp_rotate rotation)
{
    if (disp == NULL || disp->userdata == NULL || rect == NULL || data == NULL) {
        return 0;
    }

    struct sdl_disp_userdata *ud = (struct sdl_disp_userdata *)disp->userdata;
    if (ud->ctx == NULL) {
        return 0;
    }

    luat_display_sdl2_draw(ud->ctx,
                           rect->x, rect->y,
                           rect->w, rect->h,
                           data, rect->w * 2);

    luat_display_sdl2_flush(ud->ctx);
    return 0;
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
    .wait_vsync = sdl_wait_vsync,
    .pan_display = sdl_pan_display,
    .deinit = sdl_deinit,
};
