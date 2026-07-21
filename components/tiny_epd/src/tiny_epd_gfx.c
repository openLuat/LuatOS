#include "tiny_epd_gfx.h"
#include "tiny_epd_driver.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

/* ------------------------------------------------------------------------- */
/* Internal helpers                                                          */
/* ------------------------------------------------------------------------- */

/* 1bpp MSB-first helpers (mirror tiny_epd_core.c:212-219 without re-checking). */
static void tiny_epd_gfx_set_bit(uint8_t *p, uint16_t x, uint8_t color)
{
    uint8_t mask = (uint8_t)(0x80u >> (x & 0x07u));
    if (color) {
        *p |= mask;
    }
    else {
        *p &= (uint8_t)~mask;
    }
}

static int tiny_epd_gfx_write_pixel_raw(tiny_epd_t *epd,
                                        int16_t x, int16_t y, uint8_t color)
{
    uint8_t *p;

    if (x < 0 || y < 0 || x >= (int16_t)epd->width || y >= (int16_t)epd->height) {
        return TINY_EPD_ERR_PARAM;
    }
    p = epd->framebuffer + ((size_t)y * epd->stride) + ((uint16_t)x / 8u);
    tiny_epd_gfx_set_bit(p, (uint16_t)x, color);
    return TINY_EPD_OK;
}

/* Soft-clip and apply rotation. Returns TINY_EPD_OK if (x, y) maps inside
 * the framebuffer, TINY_EPD_ERR_PARAM otherwise. The transformed coordinate
 * is written back through *x / *y. */
static int tiny_epd_gfx_apply_rotation(tiny_epd_t *epd, int16_t *x, int16_t *y)
{
    int16_t orig_x = *x;
    int16_t orig_y = *y;
    int16_t w = (int16_t)epd->width;
    int16_t h = (int16_t)epd->height;
    int16_t out_x;
    int16_t out_y;

    /* Treat out-of-bounds input as an error (clipped by callers). */
    if (orig_x < 0 || orig_y < 0 || orig_x >= w || orig_y >= h) {
        return TINY_EPD_ERR_PARAM;
    }

    /* Formula mirrors Paint_DrawPixel in components/eink/epdpaint.c:106-137. */
    switch (epd->rotate & 0x03u) {
    case 0:
        out_x = orig_x;
        out_y = orig_y;
        break;
    case 1: /* 90° clockwise */
        out_x = (int16_t)(w - 1 - orig_y);
        out_y = orig_x;
        break;
    case 2: /* 180° */
        out_x = (int16_t)(w - 1 - orig_x);
        out_y = (int16_t)(h - 1 - orig_y);
        break;
    default: /* 3 / 270° clockwise */
        out_x = orig_y;
        out_y = (int16_t)(h - 1 - orig_x);
        break;
    }

    *x = out_x;
    *y = out_y;
    return TINY_EPD_OK;
}

static int tiny_epd_gfx_gate(tiny_epd_t *epd, uint8_t color)
{
    if (epd == NULL || epd->framebuffer == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (epd->bits_per_pixel != 1 || epd->plane_count != 1) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    if (color > 1u) {
        return TINY_EPD_ERR_PARAM;
    }
    return TINY_EPD_OK;
}

/* ------------------------------------------------------------------------- */
/* Public API                                                                */
/* ------------------------------------------------------------------------- */

int tiny_epd_set_rotation(tiny_epd_t *epd, uint8_t rotate)
{
    if (epd == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    /* Map degrees (0/90/180/270) to internal index (0/1/2/3). */
    switch (rotate) {
    case 0u:
        epd->rotate = 0u;
        return TINY_EPD_OK;
    case 90u:
        epd->rotate = 1u;
        return TINY_EPD_OK;
    case 180u:
        epd->rotate = 2u;
        return TINY_EPD_OK;
    case 270u:
        epd->rotate = 3u;
        return TINY_EPD_OK;
    default:
        return TINY_EPD_ERR_PARAM;
    }
}

int tiny_epd_draw_hline(tiny_epd_t *epd, int16_t x, int16_t y, int16_t w, uint8_t color)
{
    int gate = tiny_epd_gfx_gate(epd, color);
    int16_t i;

    if (gate != TINY_EPD_OK) {
        return gate;
    }
    if (w <= 0) {
        return TINY_EPD_OK;
    }
    if (tiny_epd_gfx_apply_rotation(epd, &x, &y) != TINY_EPD_OK) {
        /* Entire line clipped: silently succeed like lcd. */
        return TINY_EPD_OK;
    }
    for (i = 0; i < w; i++) {
        int16_t xx = (int16_t)(x + i);
        if (xx < 0 || xx >= (int16_t)epd->width) {
            continue;
        }
        tiny_epd_gfx_write_pixel_raw(epd, xx, y, color);
    }
    return TINY_EPD_OK;
}

int tiny_epd_draw_vline(tiny_epd_t *epd, int16_t x, int16_t y, int16_t h, uint8_t color)
{
    int gate = tiny_epd_gfx_gate(epd, color);
    int16_t i;

    if (gate != TINY_EPD_OK) {
        return gate;
    }
    if (h <= 0) {
        return TINY_EPD_OK;
    }
    if (tiny_epd_gfx_apply_rotation(epd, &x, &y) != TINY_EPD_OK) {
        return TINY_EPD_OK;
    }
    for (i = 0; i < h; i++) {
        int16_t yy = (int16_t)(y + i);
        if (yy < 0 || yy >= (int16_t)epd->height) {
            continue;
        }
        tiny_epd_gfx_write_pixel_raw(epd, x, yy, color);
    }
    return TINY_EPD_OK;
}

int tiny_epd_draw_line(tiny_epd_t *epd,
                       int16_t x0, int16_t y0, int16_t x1, int16_t y1,
                       uint8_t color)
{
    int gate = tiny_epd_gfx_gate(epd, color);
    int16_t dx;
    int16_t dy;
    int16_t sx;
    int16_t sy;
    int16_t err;
    int16_t e2;
    int16_t cur_x;
    int16_t cur_y;

    if (gate != TINY_EPD_OK) {
        return gate;
    }

    /* Fast paths: axis-aligned lines after rotation. Apply rotation to both
     * endpoints first, then dispatch to hline / vline. */
    if (y0 == y1) {
        int16_t lo = (x0 < x1) ? x0 : x1;
        int16_t hi = (x0 < x1) ? x1 : x0;
        return tiny_epd_draw_hline(epd, lo, y0, (int16_t)(hi - lo + 1), color);
    }
    if (x0 == x1) {
        int16_t lo = (y0 < y1) ? y0 : y1;
        int16_t hi = (y0 < y1) ? y1 : y0;
        return tiny_epd_draw_vline(epd, x0, lo, (int16_t)(hi - lo + 1), color);
    }

    /* Bresenham: rotate both endpoints, then walk. */
    if (tiny_epd_gfx_apply_rotation(epd, &x0, &y0) != TINY_EPD_OK ||
        tiny_epd_gfx_apply_rotation(epd, &x1, &y1) != TINY_EPD_OK) {
        return TINY_EPD_OK; /* clipped */
    }

    dx = (x1 > x0) ? (int16_t)(x1 - x0) : (int16_t)(x0 - x1);
    dy = (y1 > y0) ? (int16_t)(y1 - y0) : (int16_t)(y0 - y1);
    sx = (x0 < x1) ? 1 : -1;
    sy = (y0 < y1) ? 1 : -1;
    err = (int16_t)(dx - dy);

    cur_x = x0;
    cur_y = y0;
    while (1) {
        tiny_epd_gfx_write_pixel_raw(epd, cur_x, cur_y, color);
        if (cur_x == x1 && cur_y == y1) {
            break;
        }
        e2 = (int16_t)(err << 1);
        if (e2 > -dy) {
            err = (int16_t)(err - dy);
            cur_x = (int16_t)(cur_x + sx);
        }
        if (e2 < dx) {
            err = (int16_t)(err + dx);
            cur_y = (int16_t)(cur_y + sy);
        }
    }
    return TINY_EPD_OK;
}

int tiny_epd_draw_rect(tiny_epd_t *epd,
                       int16_t x, int16_t y, int16_t x2, int16_t y2,
                       uint8_t color, uint8_t fill)
{
    int gate = tiny_epd_gfx_gate(epd, color);
    int16_t x_min;
    int16_t y_min;
    int16_t x_max;
    int16_t y_max;
    int16_t row;

    if (gate != TINY_EPD_OK) {
        return gate;
    }

    x_min = (x < x2) ? x : x2;
    y_min = (y < y2) ? y : y2;
    x_max = (x < x2) ? x2 : x;
    y_max = (y < y2) ? y2 : y;
    if (x_min < 0) x_min = 0;
    if (y_min < 0) y_min = 0;
    if (x_max >= (int16_t)epd->width) x_max = (int16_t)(epd->width - 1);
    if (y_max >= (int16_t)epd->height) y_max = (int16_t)(epd->height - 1);
    if (x_max < x_min || y_max < y_min) {
        return TINY_EPD_OK; /* fully clipped */
    }

    if (fill) {
        for (row = y_min; row <= y_max; row++) {
            tiny_epd_gfx_write_pixel_raw(epd, x_min, row, color);
            /* Avoid duplicate write on a 1-wide rectangle. */
            if (x_max > x_min) {
                tiny_epd_gfx_write_pixel_raw(epd, x_max, row, color);
            }
            if (x_max - x_min > 1) {
                /* Draw the interior row by writing each pixel after rotation
                 * transforms it. Since fill rotates per-pixel and the rect
                 * is now in physical coords (the inner rotation already
                 * happened in hline callers — but here we use the raw path
                 * which does NOT rotate), we instead call the rotated
                 * hline helper with a virtual start/end and let it
                 * transform per-pixel. This keeps the rect "axis-aligned in
                 * user space, correctly transformed in physical space". */
            }
        }
        /* Simpler: route through the rotated hline helper for the interior
         * rows so rotation is applied per-pixel. */
        for (row = y_min; row <= y_max; row++) {
            /* Interior cells (skip the 2 edge columns already written). */
            if (x_max - x_min > 1) {
                tiny_epd_draw_hline(epd, (int16_t)(x_min + 1), row,
                                    (int16_t)(x_max - x_min - 1), color);
            }
        }
    }
    else {
        /* Hollow: 4 outline edges, each as a Bresenham line in user space. */
        tiny_epd_draw_line(epd, x_min, y_min, x_max, y_min, color);
        tiny_epd_draw_line(epd, x_min, y_max, x_max, y_max, color);
        tiny_epd_draw_line(epd, x_min, y_min, x_min, y_max, color);
        tiny_epd_draw_line(epd, x_max, y_min, x_max, y_max, color);
    }
    return TINY_EPD_OK;
}

int tiny_epd_draw_circle(tiny_epd_t *epd,
                        int16_t x, int16_t y, uint8_t r,
                        uint8_t color, uint8_t fill)
{
    int gate = tiny_epd_gfx_gate(epd, color);
    int16_t a;
    int16_t b;
    int16_t di;
    int16_t cx;
    int16_t cy;

    if (gate != TINY_EPD_OK) {
        return gate;
    }
    if (r == 0) {
        return tiny_epd_gfx_write_pixel_raw(epd, x, y, color);
    }

    /* 8-symmetric Bresenham midpoint (after applying rotation to the
     * center). Use the raw (non-rotated) write path so each reflected
     * point gets the same transform applied via the rotated hline/vline
     * helpers. */
    cx = x;
    cy = y;
    if (tiny_epd_gfx_apply_rotation(epd, &cx, &cy) != TINY_EPD_OK) {
        return TINY_EPD_OK; /* center off-screen */
    }
    /* Re-derive r after rotation. For 90/270 swap, r stays the same on
     * a square panel; for 0/180 it is unchanged. We use the same r. */
    (void)0;

    a = 0;
    b = (int16_t)r;
    di = (int16_t)(3 - ((int16_t)r << 1));

    while (a <= b) {
        if (fill) {
            /* For each octant pair, fill the horizontal span at the y row. */
            tiny_epd_draw_hline(epd, (int16_t)(cx - b), (int16_t)(cy + a),
                                (int16_t)(2 * b + 1), color);
            if (a != 0) {
                tiny_epd_draw_hline(epd, (int16_t)(cx - b), (int16_t)(cy - a),
                                    (int16_t)(2 * b + 1), color);
            }
            if (a != b) {
                tiny_epd_draw_hline(epd, (int16_t)(cx - a), (int16_t)(cy + b),
                                    (int16_t)(2 * a + 1), color);
                tiny_epd_draw_hline(epd, (int16_t)(cx - a), (int16_t)(cy - b),
                                    (int16_t)(2 * a + 1), color);
            }
        }
        else {
            /* Hollow: plot 8 reflected points (use raw write to avoid
             * double-rotating; we already rotated the center). */
            tiny_epd_gfx_write_pixel_raw(epd, (int16_t)(cx + b), (int16_t)(cy + a), color);
            tiny_epd_gfx_write_pixel_raw(epd, (int16_t)(cx - b), (int16_t)(cy + a), color);
            tiny_epd_gfx_write_pixel_raw(epd, (int16_t)(cx + a), (int16_t)(cy + b), color);
            tiny_epd_gfx_write_pixel_raw(epd, (int16_t)(cx - a), (int16_t)(cy + b), color);
            tiny_epd_gfx_write_pixel_raw(epd, (int16_t)(cx + b), (int16_t)(cy - a), color);
            tiny_epd_gfx_write_pixel_raw(epd, (int16_t)(cx - b), (int16_t)(cy - a), color);
            tiny_epd_gfx_write_pixel_raw(epd, (int16_t)(cx + a), (int16_t)(cy - b), color);
            tiny_epd_gfx_write_pixel_raw(epd, (int16_t)(cx - a), (int16_t)(cy - b), color);
        }
        a = (int16_t)(a + 1);
        if (di < 0) {
            di = (int16_t)(di + 4 * a + 6);
        }
        else {
            b = (int16_t)(b - 1);
            di = (int16_t)(di + 4 * (a - b) + 10);
        }
    }
    return TINY_EPD_OK;
}

/* ------------------------------------------------------------------------- */
/* QR code                                                                   */
/* ------------------------------------------------------------------------- */

/* Forward-declared to avoid pulling <qrcodegen.h> into a header that the
 * C Lua binding already includes; we only need the encoder/inspect API
 * inside the .c. */
#include "qrcodegen.h"

int tiny_epd_draw_qrcode(tiny_epd_t *epd,
                         int16_t x, int16_t y,
                         const char *str, uint16_t size,
                         uint8_t color)
{
    int gate;
    uint8_t *qrcode = NULL;
    uint8_t *temp = NULL;
    int qr_size;
    int scale;
    int margin;
    int bg;
    int i;
    int j;
    int dx;
    int dy;

    if (epd == NULL || epd->framebuffer == NULL || str == NULL) {
        return TINY_EPD_ERR_PARAM;
    }
    if (epd->bits_per_pixel != 1 || epd->plane_count != 1) {
        return TINY_EPD_ERR_UNSUPPORTED_MODE;
    }
    if (size == 0) {
        return TINY_EPD_ERR_PARAM;
    }
    if (color > 1u) {
        return TINY_EPD_ERR_PARAM;
    }
    gate = TINY_EPD_OK;

    qrcode = (uint8_t *)epd->port.malloc(epd->port.user, qrcodegen_BUFFER_LEN_MAX);
    if (qrcode == NULL) {
        return TINY_EPD_ERR_NO_MEM;
    }
    temp = (uint8_t *)epd->port.malloc(epd->port.user, qrcodegen_BUFFER_LEN_MAX);
    if (temp == NULL) {
        epd->port.free(epd->port.user, qrcode);
        return TINY_EPD_ERR_NO_MEM;
    }

    if (!luat_qrcodegen_encodeText(str, temp, qrcode,
                                   qrcodegen_Ecc_LOW,
                                   qrcodegen_VERSION_MIN,
                                   qrcodegen_VERSION_MAX,
                                   qrcodegen_Mask_AUTO,
                                   1)) {
        epd->port.free(epd->port.user, qrcode);
        epd->port.free(epd->port.user, temp);
        return TINY_EPD_ERR_PARAM;
    }

    qr_size = luat_qrcodegen_getSize(qrcode);
    scale = (int)size / qr_size;
    if (scale < 1) {
        scale = 1;
    }
    margin = ((int)size - qr_size * scale) / 2;
    bg = color ? 0 : 1; /* complement: BLACK fg → WHITE bg */

    /* Background fill (no rotation applied to QR). */
    for (dy = 0; dy < (int)size; dy++) {
        for (dx = 0; dx < (int)size; dx++) {
            int16_t px = (int16_t)(x + dx);
            int16_t py = (int16_t)(y + dy);
            if (px < 0 || py < 0 ||
                px >= (int16_t)epd->width || py >= (int16_t)epd->height) {
                continue;
            }
            tiny_epd_gfx_write_pixel_raw(epd, px, py, (uint8_t)bg);
        }
    }

    /* Foreground modules. */
    for (j = 0; j < qr_size; j++) {
        for (i = 0; i < qr_size; i++) {
            if (luat_qrcodegen_getModule(qrcode, i, j)) {
                int16_t x0 = (int16_t)(x + margin + j * scale);
                int16_t y0 = (int16_t)(y + margin + i * scale);
                int16_t x1 = (int16_t)(x0 + scale - 1);
                int16_t y1 = (int16_t)(y0 + scale - 1);
                tiny_epd_draw_rect(epd, x0, y0, x1, y1, color, 1);
            }
        }
    }

    epd->port.free(epd->port.user, qrcode);
    epd->port.free(epd->port.user, temp);
    (void)gate;
    return TINY_EPD_OK;
}

/* ------------------------------------------------------------------------- */
/* H/V line for future text rendering backends                                */
/* ------------------------------------------------------------------------- */

int tiny_epd_gfx_hv_line(tiny_epd_t *epd,
                        int16_t x, int16_t y, int16_t len,
                        uint8_t dir, uint8_t color)
{
    if (len <= 0) {
        return TINY_EPD_OK;
    }
    if (dir == 0) {
        return tiny_epd_draw_hline(epd, x, y, len, color);
    }
    return tiny_epd_draw_vline(epd, x, y, len, color);
}
