#include "luat_base.h"
#include "luat_display.h"
#include "luat_sdl2.h"

#define LUAT_LOG_TAG "display_sdl"
#include "luat_log.h"

static int sdl_init(luat_display_t *disp) {
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

static int sdl_deinit(luat_display_t *disp) {
    luat_sdl2_conf_t cfg = {0};
    luat_sdl2_deinit(&cfg);
    return 0;
}

static int sdl_write_cmd(luat_display_t *disp, uint8_t cmd) {
    return 0;
}

static int sdl_write_data(luat_display_t *disp, const uint8_t *data, uint32_t len) {
    return 0;
}

static int sdl_write_cmd_data(luat_display_t *disp, uint8_t cmd,
                               const uint8_t *data, uint32_t len) {
    return 0;
}

static int sdl_fb_flush(luat_display_t *disp,
                         int16_t x1, int16_t y1, int16_t x2, int16_t y2,
                         const void *data) {
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

static int sdl_pan_display(luat_display_t *disp) {
    return 0;
}

const luat_display_if_ops_t if_ops_sdl = {
    .name = "sdl",
    .write_cmd      = sdl_write_cmd,
    .write_data     = sdl_write_data,
    .write_cmd_data = sdl_write_cmd_data,
    .fb_flush       = sdl_fb_flush,
    .pan_display    = sdl_pan_display,
    .init           = sdl_init,
    .deinit         = sdl_deinit,
};
