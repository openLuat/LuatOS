#include "luat_display.h"

/*直接填充一条水平扫描线，避免在圆填充循环中反复调用 luat_display_fill 的开销。*/
static inline void fill_circle_hline(struct luat_display_fb_info *info, void *buf,
                                      int x1, int x2, int y, uint32_t color)
{
    uint32_t width = info->draw_buf.width;
    uint32_t height = info->draw_buf.height;
    uint32_t stride = info->draw_buf.stride;

    if (y < 0 || y >= (int)height || x1 > x2 || buf == NULL) {
        return;
    }
    if (x1 < 0) x1 = 0;
    if (x2 >= (int)width) x2 = (int)width - 1;
    if (x1 > x2) {
        return;
    }

    int rect_w = x2 - x1 + 1;
    uint8_t *ptr = (uint8_t *)buf;

    switch (info->format) {
    case LUAT_DISPLAY_FORMAT_RGB565:
    case LUAT_DISPLAY_FORMAT_BGR565: {
        uint16_t c = (uint16_t)(color & 0xFFFF);
        uint16_t *line = (uint16_t *)(ptr + y * stride + x1 * 2);
        for (int x = 0; x < rect_w; x++) {
            line[x] = c;
        }
        break;
    }
    case LUAT_DISPLAY_FORMAT_RGB888: {
        uint8_t r = (color >> 16) & 0xFF;
        uint8_t g = (color >> 8) & 0xFF;
        uint8_t b = color & 0xFF;
        uint8_t *line = ptr + y * stride + x1 * 3;
        for (int x = 0; x < rect_w; x++) {
            line[x * 3 + 0] = r;
            line[x * 3 + 1] = g;
            line[x * 3 + 2] = b;
        }
        break;
    }
    case LUAT_DISPLAY_FORMAT_ARGB8888:
    case LUAT_DISPLAY_FORMAT_ABGR8888:
    case LUAT_DISPLAY_FORMAT_RGBA8888:
    case LUAT_DISPLAY_FORMAT_BGRA8888: {
        uint32_t *line = (uint32_t *)(ptr + y * stride + x1 * 4);
        for (int x = 0; x < rect_w; x++) {
            line[x] = color;
        }
        break;
    }
    default:
        break;
    }
}

/*绘制实心圆：以 (cx, cy) 为圆心，r 为半径，填充 color 颜色。
  使用 Bresenham 中点圆算法，每步绘制 4 条水平扫描线完成填充。
  扫描线填充逻辑直接展开，不再调用 luat_display_fill，减少重复取 info、函数调用和格式判断开销。*/
int luat_display_fill_circle(struct luat_display *disp, int cx, int cy, int r, uint32_t color)
{
    if (disp == NULL || disp->fb_info == NULL || r < 0) {
        return 0;
    }

    struct luat_display_fb_info *info = disp->fb_info;
    void *buf = (info->draw_buf.buffer) ? info->draw_buf.buffer : info->fb_start;

    if (r == 0) {
        fill_circle_hline(info, buf, cx, cx, cy, color);
        return 1;
    }

    int x = 0;
    int y = r;
    int d = 3 - 2 * r;

    while (y >= x) {
        fill_circle_hline(info, buf, cx - x, cx + x, cy - y, color);
        fill_circle_hline(info, buf, cx - x, cx + x, cy + y, color);
        fill_circle_hline(info, buf, cx - y, cx + y, cy - x, color);
        fill_circle_hline(info, buf, cx - y, cx + y, cy + x, color);

        if (d < 0) {
            d = d + 4 * x + 6;
        } else {
            d = d + 4 * (x - y) + 10;
            y--;
        }
        x++;
    }

    return 1;
}
