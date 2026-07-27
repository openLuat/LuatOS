#include "tiny_epd_gfx.h"

#include <stdint.h>

static int tiny_epd_gfx_gate(const tiny_epd_t *epd, uint8_t color)
{
    if (epd == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (tiny_epd_bits_per_pixel(epd) != 1 || tiny_epd_plane_count(epd) != 1) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    return color <= TINY_EPD_COLOR_WHITE ? TINY_EPD_OK : TINY_EPD_ERR_PARAM;
}

/* Primitives deliberately rasterize in logical coordinates. The core owns
 * coordinate rotation and dirty tracking, which prevents a primitive from
 * accidentally rotating a span twice or only rotating its first endpoint. */
static void tiny_epd_gfx_put_pixel_clipped(tiny_epd_t *epd, int32_t x, int32_t y, uint8_t color)
{
    if (x < 0 || y < 0 || x >= tiny_epd_width(epd) || y >= tiny_epd_height(epd)) {
        return;
    }
    (void)tiny_epd_draw_pixel(epd, (int16_t)x, (int16_t)y, color);
}

static void tiny_epd_gfx_draw_span(tiny_epd_t *epd,
                                   int32_t x, int32_t y, int32_t len,
                                   int32_t dx, int32_t dy, uint8_t color)
{
    int32_t i;

    if (len <= 0) {
        return;
    }
    for (i = 0; i < len; i++) {
        tiny_epd_gfx_put_pixel_clipped(epd, x + i * dx, y + i * dy, color);
    }
}

int tiny_epd_draw_hline(tiny_epd_t *epd, int16_t x, int16_t y, int16_t w, uint8_t color)
{
    int ret = tiny_epd_gfx_gate(epd, color);

    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_gfx_draw_span(epd, x, y, w, 1, 0, color);
    return TINY_EPD_OK;
}

int tiny_epd_draw_vline(tiny_epd_t *epd, int16_t x, int16_t y, int16_t h, uint8_t color)
{
    int ret = tiny_epd_gfx_gate(epd, color);

    if (ret != TINY_EPD_OK) {
        return ret;
    }
    tiny_epd_gfx_draw_span(epd, x, y, h, 0, 1, color);
    return TINY_EPD_OK;
}

int tiny_epd_draw_line(tiny_epd_t *epd,
                       int16_t x0, int16_t y0, int16_t x1, int16_t y1,
                       uint8_t color)
{
    int ret = tiny_epd_gfx_gate(epd, color);
    int32_t dx;
    int32_t dy;
    int32_t sx;
    int32_t sy;
    int32_t err;
    int32_t e2;
    int32_t x = x0;
    int32_t y = y0;

    if (ret != TINY_EPD_OK) {
        return ret;
    }
    dx = x1 >= x0 ? (int32_t)x1 - x0 : (int32_t)x0 - x1;
    dy = y1 >= y0 ? (int32_t)y1 - y0 : (int32_t)y0 - y1;
    sx = x0 < x1 ? 1 : -1;
    sy = y0 < y1 ? 1 : -1;
    err = dx - dy;

    for (;;) {
        tiny_epd_gfx_put_pixel_clipped(epd, x, y, color);
        if (x == x1 && y == y1) {
            break;
        }
        e2 = err * 2;
        if (e2 > -dy) {
            err -= dy;
            x += sx;
        }
        if (e2 < dx) {
            err += dx;
            y += sy;
        }
    }
    return TINY_EPD_OK;
}

int tiny_epd_draw_rect(tiny_epd_t *epd,
                       int16_t x, int16_t y, int16_t x2, int16_t y2,
                       uint8_t color, uint8_t fill)
{
    int ret = tiny_epd_gfx_gate(epd, color);
    int32_t x_min;
    int32_t x_max;
    int32_t y_min;
    int32_t y_max;
    int32_t row;

    if (ret != TINY_EPD_OK || fill > 1u) {
        return ret == TINY_EPD_OK ? TINY_EPD_ERR_PARAM : ret;
    }
    x_min = x < x2 ? x : x2;
    x_max = x < x2 ? x2 : x;
    y_min = y < y2 ? y : y2;
    y_max = y < y2 ? y2 : y;

    if (fill) {
        for (row = y_min; row <= y_max; row++) {
            tiny_epd_gfx_draw_span(epd, x_min, row, x_max - x_min + 1, 1, 0, color);
        }
    }
    else {
        tiny_epd_gfx_draw_span(epd, x_min, y_min, x_max - x_min + 1, 1, 0, color);
        if (y_max != y_min) {
            tiny_epd_gfx_draw_span(epd, x_min, y_max, x_max - x_min + 1, 1, 0, color);
        }
        if (y_max - y_min > 1) {
            tiny_epd_gfx_draw_span(epd, x_min, y_min + 1, y_max - y_min - 1, 0, 1, color);
            if (x_max != x_min) {
                tiny_epd_gfx_draw_span(epd, x_max, y_min + 1, y_max - y_min - 1, 0, 1, color);
            }
        }
    }
    return TINY_EPD_OK;
}

int tiny_epd_draw_circle(tiny_epd_t *epd,
                         int16_t x, int16_t y, uint8_t r,
                         uint8_t color, uint8_t fill)
{
    int ret = tiny_epd_gfx_gate(epd, color);
    int32_t a = 0;
    int32_t b = r;
    int32_t d = 3 - 2 * b;

    if (ret != TINY_EPD_OK || fill > 1u) {
        return ret == TINY_EPD_OK ? TINY_EPD_ERR_PARAM : ret;
    }
    if (r == 0) {
        tiny_epd_gfx_put_pixel_clipped(epd, x, y, color);
        return TINY_EPD_OK;
    }

    while (a <= b) {
        if (fill) {
            tiny_epd_gfx_draw_span(epd, (int32_t)x - b, (int32_t)y + a, 2 * b + 1, 1, 0, color);
            if (a != 0) {
                tiny_epd_gfx_draw_span(epd, (int32_t)x - b, (int32_t)y - a, 2 * b + 1, 1, 0, color);
            }
            if (a != b) {
                tiny_epd_gfx_draw_span(epd, (int32_t)x - a, (int32_t)y + b, 2 * a + 1, 1, 0, color);
                tiny_epd_gfx_draw_span(epd, (int32_t)x - a, (int32_t)y - b, 2 * a + 1, 1, 0, color);
            }
        }
        else {
            tiny_epd_gfx_put_pixel_clipped(epd, (int32_t)x + b, (int32_t)y + a, color);
            tiny_epd_gfx_put_pixel_clipped(epd, (int32_t)x - b, (int32_t)y + a, color);
            tiny_epd_gfx_put_pixel_clipped(epd, (int32_t)x + a, (int32_t)y + b, color);
            tiny_epd_gfx_put_pixel_clipped(epd, (int32_t)x - a, (int32_t)y + b, color);
            tiny_epd_gfx_put_pixel_clipped(epd, (int32_t)x + b, (int32_t)y - a, color);
            tiny_epd_gfx_put_pixel_clipped(epd, (int32_t)x - b, (int32_t)y - a, color);
            tiny_epd_gfx_put_pixel_clipped(epd, (int32_t)x + a, (int32_t)y - b, color);
            tiny_epd_gfx_put_pixel_clipped(epd, (int32_t)x - a, (int32_t)y - b, color);
        }
        a++;
        if (d < 0) {
            d += 4 * a + 6;
        }
        else {
            b--;
            d += 4 * (a - b) + 10;
        }
    }
    return TINY_EPD_OK;
}

int tiny_epd_gfx_hv_line(tiny_epd_t *epd,
                          int16_t x, int16_t y, int16_t len,
                          uint8_t dir, uint8_t color)
{
    int ret = tiny_epd_gfx_gate(epd, color);

    if (ret != TINY_EPD_OK) {
        return ret;
    }
    switch (dir) {
    case 0: /* right */
        tiny_epd_gfx_draw_span(epd, x, y, len, 1, 0, color);
        break;
    case 1: /* down */
        tiny_epd_gfx_draw_span(epd, x, y, len, 0, 1, color);
        break;
    case 2: /* left */
        tiny_epd_gfx_draw_span(epd, x, y, len, -1, 0, color);
        break;
    case 3: /* up */
        tiny_epd_gfx_draw_span(epd, x, y, len, 0, -1, color);
        break;
    default:
        return TINY_EPD_ERR_PARAM;
    }
    return TINY_EPD_OK;
}
