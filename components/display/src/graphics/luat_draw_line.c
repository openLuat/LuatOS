#include "luat_display.h"


/*水平直线绘制：在 (x1,y1) 到 (x2,y1) 之间绘制一条水平线（单行像素）*/
static int luat_display_draw_line_hor(struct luat_display *disp, struct luat_display_area area, uint32_t color)
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
    int y  = area.y1;
    int x2 = area.x2;

    if (x1 < 0) x1 = 0;
    if (y < 0) y = 0;
    if (y >= (int)height) return 0;
    if (x2 >= (int)width) x2 = width - 1;
    if (x1 > x2 || buf == NULL) {
        return 0;
    }

    int line_w = x2 - x1 + 1;

    uint8_t *ptr = (uint8_t *)buf;

    switch (info->format) {
    case LUAT_DISPLAY_FORMAT_RGB565:
    case LUAT_DISPLAY_FORMAT_BGR565: {
        uint16_t c = (uint16_t)(color & 0xFFFF);
        uint16_t *line = (uint16_t *)(ptr + y * stride + x1 * 2);
        for (int x = 0; x < line_w; x++) {
            line[x] = c;
        }
        break;
    }
    case LUAT_DISPLAY_FORMAT_RGB888: {
        uint8_t r = (color >> 16) & 0xFF;
        uint8_t g = (color >> 8) & 0xFF;
        uint8_t b = color & 0xFF;
        uint8_t *line = ptr + y * stride + x1 * 3;
        for (int x = 0; x < line_w; x++) {
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
        for (int x = 0; x < line_w; x++) {
            line[x] = color;
        }
        break;
    }
    default:
        return 0;
    }

    return 1;
}

/*垂直直线绘制：在 (x1,y1) 到 (x1,y2) 之间绘制一条垂直线（单列像素）*/
static int luat_display_draw_line_ver(struct luat_display *disp, struct luat_display_area area, uint32_t color)
{
    if (disp == NULL || disp->fb_info == NULL) {
        return 0;
    }

    struct luat_display_fb_info *info = disp->fb_info;

    uint32_t width = info->draw_buf.width;
    uint32_t height = info->draw_buf.height;
    uint32_t stride = info->draw_buf.stride;
    void *buf = (info->draw_buf.buffer) ? info->draw_buf.buffer : info->fb_start;

    int x  = area.x1;
    int y1 = area.y1;
    int y2 = area.y2;

    if (x < 0) x = 0;
    if (y1 < 0) y1 = 0;
    if (x >= (int)width) return 0;
    if (y2 >= (int)height) y2 = height - 1;
    if (y1 > y2 || buf == NULL) {
        return 0;
    }

    int line_h = y2 - y1 + 1;

    uint8_t *ptr = (uint8_t *)buf;

    switch (info->format) {
    case LUAT_DISPLAY_FORMAT_RGB565:
    case LUAT_DISPLAY_FORMAT_BGR565: {
        uint16_t c = (uint16_t)(color & 0xFFFF);
        for (int y = y1; y < y1 + line_h; y++) {
            *(uint16_t *)(ptr + y * stride + x * 2) = c;
        }
        break;
    }
    case LUAT_DISPLAY_FORMAT_RGB888: {
        uint8_t r = (color >> 16) & 0xFF;
        uint8_t g = (color >> 8) & 0xFF;
        uint8_t b = color & 0xFF;
        for (int y = y1; y < y1 + line_h; y++) {
            uint8_t *px = ptr + y * stride + x * 3;
            px[0] = r;
            px[1] = g;
            px[2] = b;
        }
        break;
    }
    case LUAT_DISPLAY_FORMAT_ARGB8888:
    case LUAT_DISPLAY_FORMAT_ABGR8888:
    case LUAT_DISPLAY_FORMAT_RGBA8888:
    case LUAT_DISPLAY_FORMAT_BGRA8888: {
        for (int y = y1; y < y1 + line_h; y++) {
            *(uint32_t *)(ptr + y * stride + x * 4) = color;
        }
        break;
    }
    default:
        return 0;
    }

    return 1;
}

/*斜线绘制：在 (x1,y1) 到 (x2,y2) 之间用 Bresenham 算法绘制任意斜率直线*/
static int luat_display_draw_line_skew(struct luat_display *disp, struct luat_display_area area, uint32_t color)
{
    if (disp == NULL || disp->fb_info == NULL) {
        return 0;
    }

    struct luat_display_fb_info *info = disp->fb_info;

    uint32_t width = info->draw_buf.width;
    uint32_t height = info->draw_buf.height;
    uint32_t stride = info->draw_buf.stride;
    void *buf = (info->draw_buf.buffer) ? info->draw_buf.buffer : info->fb_start;

    if (buf == NULL) {
        return 0;
    }

    int x0 = area.x1;
    int y0 = area.y1;
    int x1 = area.x2;
    int y1 = area.y2;

    int dx = (x1 > x0) ? (x1 - x0) : (x0 - x1);
    int sx = (x0 < x1) ? 1 : -1;
    int dy = -((y1 > y0) ? (y1 - y0) : (y0 - y1));
    int sy = (y0 < y1) ? 1 : -1;
    int err = dx + dy;

    uint8_t *ptr = (uint8_t *)buf;

    switch (info->format) {
    case LUAT_DISPLAY_FORMAT_RGB565:
    case LUAT_DISPLAY_FORMAT_BGR565: {
        uint16_t c = (uint16_t)(color & 0xFFFF);
        for (;;) {
            if (x0 >= 0 && x0 < (int)width && y0 >= 0 && y0 < (int)height) {
                *(uint16_t *)(ptr + y0 * stride + x0 * 2) = c;
            }
            if (x0 == x1 && y0 == y1) break;
            int e2 = 2 * err;
            if (e2 >= dy) { err += dy; x0 += sx; }
            if (e2 <= dx) { err += dx; y0 += sy; }
        }
        break;
    }
    case LUAT_DISPLAY_FORMAT_RGB888: {
        uint8_t r = (color >> 16) & 0xFF;
        uint8_t g = (color >> 8) & 0xFF;
        uint8_t b = color & 0xFF;
        for (;;) {
            if (x0 >= 0 && x0 < (int)width && y0 >= 0 && y0 < (int)height) {
                uint8_t *px = ptr + y0 * stride + x0 * 3;
                px[0] = r;
                px[1] = g;
                px[2] = b;
            }
            if (x0 == x1 && y0 == y1) break;
            int e2 = 2 * err;
            if (e2 >= dy) { err += dy; x0 += sx; }
            if (e2 <= dx) { err += dx; y0 += sy; }
        }
        break;
    }
    case LUAT_DISPLAY_FORMAT_ARGB8888:
    case LUAT_DISPLAY_FORMAT_ABGR8888:
    case LUAT_DISPLAY_FORMAT_RGBA8888:
    case LUAT_DISPLAY_FORMAT_BGRA8888: {
        for (;;) {
            if (x0 >= 0 && x0 < (int)width && y0 >= 0 && y0 < (int)height) {
                *(uint32_t *)(ptr + y0 * stride + x0 * 4) = color;
            }
            if (x0 == x1 && y0 == y1) break;
            int e2 = 2 * err;
            if (e2 >= dy) { err += dy; x0 += sx; }
            if (e2 <= dx) { err += dx; y0 += sy; }
        }
        break;
    }
    default:
        return 0;
    }

    return 1;
}

/*绘制任意线段：按斜率自动分发到水平/垂直/斜线实现*/
int luat_display_draw_line(struct luat_display *disp, struct luat_display_area area, uint32_t color)
{
    if (disp == NULL || disp->fb_info == NULL) {
        return 0;
    }

    if (area.y1 == area.y2) {
        /*水平线（含单点）*/
        return luat_display_draw_line_hor(disp, area, color);
    } else if (area.x1 == area.x2) {
        /*垂直线*/
        return luat_display_draw_line_ver(disp, area, color);
    } else {
        /*任意斜率斜线*/
        return luat_display_draw_line_skew(disp, area, color);
    }
}

