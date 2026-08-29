#include "luat_base.h"
#include "luat_mem.h"
#include "luat_display.h"
#include "luat_display_draw.h"

#define LUAT_LOG_TAG "display_draw"
#include "luat_log.h"


/*纯色填充*/
int luat_display_fill(struct luat_display *disp, struct luat_display_area area, uint32_t color)
{
    if (disp == NULL || disp->fb_info == NULL) {
        return 0;
    }

    struct luat_display_fb_info *info = disp->fb_info;

    uint32_t width = info->draw_buf.width;
    uint32_t height = info->draw_buf.height;
    uint32_t stride = info->draw_buf.stride;
    void *buf = (info->draw_buf.buffer) ? info->draw_buf.buffer : info->fb_start;

    int x1 = area.x1;
    int y1 = area.y1;
    int x2 = area.x2;
    int y2 = area.y2;

    if (x1 < 0) x1 = 0;
    if (y1 < 0) y1 = 0;
    if (x2 >= (int)width) x2 = width - 1;
    if (y2 >= (int)height) y2 = height - 1;
    if (x1 > x2 || y1 > y2 || buf == NULL) {
        return 0;
    }

    int rect_w = x2 - x1 + 1;
    int rect_h = y2 - y1 + 1;

    uint8_t *ptr = (uint8_t *)buf;

    switch (info->format) {
    case LUAT_DISPLAY_FORMAT_RGB565:
    case LUAT_DISPLAY_FORMAT_BGR565: {
        uint16_t c = (uint16_t)(color & 0xFFFF);
        for (int y = y1; y < y1 + rect_h; y++) {
            uint16_t *line = (uint16_t *)(ptr + y * stride + x1 * 2);
            for (int x = 0; x < rect_w; x++) {
                line[x] = c;
            }
        }
        break;
    }
    case LUAT_DISPLAY_FORMAT_RGB888: {
        uint8_t r = (color >> 16) & 0xFF;
        uint8_t g = (color >> 8) & 0xFF;
        uint8_t b = color & 0xFF;
        for (int y = y1; y < y1 + rect_h; y++) {
            uint8_t *line = ptr + y * stride + x1 * 3;
            for (int x = 0; x < rect_w; x++) {
                line[x * 3 + 0] = r;
                line[x * 3 + 1] = g;
                line[x * 3 + 2] = b;
            }
        }
        break;
    }
    case LUAT_DISPLAY_FORMAT_ARGB8888:
    case LUAT_DISPLAY_FORMAT_ABGR8888:
    case LUAT_DISPLAY_FORMAT_RGBA8888:
    case LUAT_DISPLAY_FORMAT_BGRA8888: {
        for (int y = y1; y < y1 + rect_h; y++) {
            uint32_t *line = (uint32_t *)(ptr + y * stride + x1 * 4);
            for (int x = 0; x < rect_w; x++) {
                line[x] = color;
            }
        }
        break;
    }
    default:
        return 0;
    }
    /*
    LLOGI("fill done fmt=%d bpp=%u buf=%p first=0x%04x",
          info->format, info->bits_per_pixel, buf,
          (info->bits_per_pixel == 16) ? ((uint16_t *)buf)[0] : (uint16_t)(((uint32_t *)buf)[0] & 0xFFFF));
    */

    return 1;
}
