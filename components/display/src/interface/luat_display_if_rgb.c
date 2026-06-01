#include "luat_base.h"
#include "luat_display.h"

#define LUAT_LOG_TAG "display_rgb"
#include "luat_log.h"

static int rgb_write_cmd(luat_display_t *disp, uint8_t cmd) {
    return -1;
}

static int rgb_write_data(luat_display_t *disp, const uint8_t *data, uint32_t len) {
    return -1;
}

static int rgb_write_cmd_data(luat_display_t *disp, uint8_t cmd,
                               const uint8_t *data, uint32_t len) {
    return -1;
}

static int rgb_fb_flush(luat_display_t *disp,
                         int16_t x1, int16_t y1, int16_t x2, int16_t y2,
                         const void *data) {
    return 0;
}

static int rgb_pan_display(luat_display_t *disp) {
    return 0;
}

static int rgb_init(luat_display_t *disp) {
    return 0;
}

const luat_display_if_ops_t if_ops_rgb = {
    .name = "rgb",
    .write_cmd      = rgb_write_cmd,
    .write_data     = rgb_write_data,
    .write_cmd_data = rgb_write_cmd_data,
    .fb_flush       = rgb_fb_flush,
    .pan_display    = rgb_pan_display,
    .init           = rgb_init,
    .deinit         = NULL,
};
