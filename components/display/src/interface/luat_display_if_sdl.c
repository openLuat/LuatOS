#include "luat_base.h"
#include "luat_display.h"
#include "luat_sdl2.h"
#include "luat_display_if_comm.h"

#define LUAT_LOG_TAG "display_sdl"
#include "luat_log.h"

static int sdl_init(struct luat_display *disp) 
{
    luat_sdl2_conf_t cfg = {
        .width = disp->width,
        .height = disp->height,
        .title = "LuatOS Display",
    };
    int ret = luat_sdl2_init(&cfg);
    if (ret != 0) {
        LLOGE("sdl_init failed %d", ret);
    }
    return ret;
}

static int sdl_deinit(struct luat_display *disp) 
{
    luat_sdl2_conf_t cfg = {0};
    luat_sdl2_deinit(&cfg);
    return 0;
}



static int sdl_fb_probe(struct luat_display_panel *panel, struct luat_display_fb_info *info) 
{
    return 0;
}

/*初始化接口，在这里设置timing参数*/
static int sdl_inf_init(struct luat_display_panel *panel) 
{
    return 0;
}

/*设置显示层*/
static int sdl_set_layer(struct luat_display_layer_data *layer_data) 
{
    return 0;
}

static int sdl_fb_flush(struct luat_display *disp,int16_t x1, int16_t y1, int16_t x2, int16_t y2, const void *data, enum disp_rotate rotation) 
{
    const void *src = data ? data : disp->fb_info.addr;
    if (src == NULL) {
        return 0;
    }
    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x2 < 0 || x2 >= disp->width) x2 = disp->width - 1;
    if (y2 < 0 || y2 >= disp->height) y2 = disp->height - 1;
    luat_sdl2_draw(x1, y1, x2, y2, (uint32_t*)src);
    luat_sdl2_flush();
    return 0;
}

static int sdl_wait_vsync(struct luat_display *disp) 
{
    return 0;
}

static int sdl_pan_display(struct luat_display *disp) 
{
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



