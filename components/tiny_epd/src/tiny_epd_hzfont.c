#include "luat_base.h"
#include "tiny_epd_hzfont.h"

#include <limits.h>
#include <stddef.h>

void tiny_epd_hzfont_style_init(tiny_epd_hzfont_style_t *style)
{
    if (style == NULL) {
        return;
    }
    style->fg = TINY_EPD_COLOR_BLACK;
    style->bg = -1;
    style->antialias = -1;
    style->threshold = 128;
    style->dither = TINY_EPD_HZFONT_DITHER_THRESHOLD;
}

#if defined(LUAT_USE_HZFONT)

#include "luat_hzfont.h"

static int tiny_epd_hzfont_pick_antialias(uint8_t size, int8_t antialias)
{
    if (antialias < 0) {
        if (size <= 16u) return 1;
        if (size <= 32u) return 2;
        return 3;
    }
    if (antialias <= 1) return 1;
    return antialias == 2 ? 2 : 3;
}

static int tiny_epd_hzfont_utf8_next(const char **cursor, uint32_t *codepoint)
{
    const uint8_t *p;
    uint32_t cp;

    if (cursor == NULL || *cursor == NULL || codepoint == NULL) {
        return 0;
    }
    p = (const uint8_t *)*cursor;
    if (*p == 0) {
        return 0;
    }
    if ((p[0] & 0x80u) == 0) {
        *codepoint = p[0];
        *cursor += 1;
        return 1;
    }
    if ((p[0] & 0xE0u) == 0xC0u && (p[1] & 0xC0u) == 0x80u) {
        cp = ((uint32_t)(p[0] & 0x1Fu) << 6) | (p[1] & 0x3Fu);
        if (cp >= 0x80u) {
            *codepoint = cp;
            *cursor += 2;
            return 1;
        }
    }
    else if ((p[0] & 0xF0u) == 0xE0u && (p[1] & 0xC0u) == 0x80u &&
             (p[2] & 0xC0u) == 0x80u) {
        cp = ((uint32_t)(p[0] & 0x0Fu) << 12) |
             ((uint32_t)(p[1] & 0x3Fu) << 6) | (p[2] & 0x3Fu);
        if (cp >= 0x800u && (cp < 0xD800u || cp > 0xDFFFu)) {
            *codepoint = cp;
            *cursor += 3;
            return 1;
        }
    }
    else if ((p[0] & 0xF8u) == 0xF0u && (p[1] & 0xC0u) == 0x80u &&
             (p[2] & 0xC0u) == 0x80u && (p[3] & 0xC0u) == 0x80u) {
        cp = ((uint32_t)(p[0] & 0x07u) << 18) |
             ((uint32_t)(p[1] & 0x3Fu) << 12) |
             ((uint32_t)(p[2] & 0x3Fu) << 6) | (p[3] & 0x3Fu);
        if (cp >= 0x10000u && cp <= 0x10FFFFu) {
            *codepoint = cp;
            *cursor += 4;
            return 1;
        }
    }
    *cursor += 1;
    return -1;
}

static uint8_t tiny_epd_hzfont_covered(const tiny_epd_hzfont_style_t *style,
                                        uint8_t coverage, int32_t x, int32_t y)
{
    static const uint8_t bayer4[16] = {
        0, 128, 32, 160,
        192, 64, 224, 96,
        48, 176, 16, 144,
        240, 112, 208, 80
    };

    if (style->dither == TINY_EPD_HZFONT_DITHER_BAYER4) {
        return coverage > bayer4[((uint32_t)y & 3u) * 4u + ((uint32_t)x & 3u)];
    }
    return coverage > style->threshold;
}

uint32_t tiny_epd_hzfont_get_utf8_width(const char *utf8, uint8_t size)
{
    if (utf8 == NULL || size == 0 || luat_hzfont_get_state() != LUAT_HZFONT_STATE_READY) {
        return 0;
    }
    return luat_hzfont_get_str_width(utf8, size);
}

int tiny_epd_hzfont_draw_utf8(tiny_epd_t *epd,
                               int16_t x, int16_t baseline_y,
                               const char *utf8, uint8_t size,
                               const tiny_epd_hzfont_style_t *style)
{
    tiny_epd_hzfont_style_t default_style;
    const tiny_epd_hzfont_style_t *resolved_style;
    const char *cursor;
    int previous_rate;
    int supersample;
    int32_t pen_x;
    int ret = TINY_EPD_OK;

    if (epd == NULL || utf8 == NULL || size == 0) {
        return TINY_EPD_ERR_PARAM;
    }
    tiny_epd_hzfont_style_init(&default_style);
    if (style == NULL) {
        /* A missing style deliberately follows the panel-local drawing
         * colors. Explicit styles retain their historic concrete values. */
        default_style.fg = TINY_EPD_COLOR_FG;
        default_style.bg = (int16_t)TINY_EPD_COLOR_BG;
        resolved_style = &default_style;
    }
    else {
        resolved_style = style;
    }
    if (resolved_style->bg < -1 || resolved_style->bg > UINT8_MAX ||
        (resolved_style->dither != TINY_EPD_HZFONT_DITHER_THRESHOLD &&
         resolved_style->dither != TINY_EPD_HZFONT_DITHER_BAYER4)) {
        return TINY_EPD_ERR_PARAM;
    }
    if (!tiny_epd_color_supported(epd, resolved_style->fg) ||
        (resolved_style->bg >= 0 &&
         !tiny_epd_color_supported(epd, (tiny_epd_color_t)resolved_style->bg))) {
        return TINY_EPD_ERR_UNSUPPORTED_COLOR;
    }
    if (luat_hzfont_get_state() != LUAT_HZFONT_STATE_READY) {
        return TINY_EPD_ERR_FONT_NOT_READY;
    }

    previous_rate = ttf_get_supersample_rate();
    supersample = tiny_epd_hzfont_pick_antialias(size, resolved_style->antialias);
    (void)ttf_set_supersample_rate(supersample);

    cursor = utf8;
    pen_x = x;
    while (*cursor != '\0') {
        const TtfBitmap *bitmap;
        uint32_t codepoint;
        uint16_t glyph_index;
        uint32_t row;
        uint32_t col;
        int decoded = tiny_epd_hzfont_utf8_next(&cursor, &codepoint);

        if (decoded == 0) {
            break;
        }
        if (decoded < 0 || luat_hzfont_lookup_glyph_index(codepoint, &glyph_index) != 0) {
            continue;
        }
        bitmap = luat_hzfont_get_bitmap(glyph_index, size, (uint8_t)supersample);
        if (bitmap == NULL || bitmap->pixels == NULL) {
            continue;
        }
        for (row = 0; row < bitmap->height; row++) {
            for (col = 0; col < bitmap->width; col++) {
                int32_t draw_x = pen_x + (int32_t)col;
                int32_t draw_y = (int32_t)baseline_y - bitmap->originY + (int32_t)row;
                uint8_t color;

                if (draw_x < INT16_MIN || draw_x > INT16_MAX ||
                    draw_y < INT16_MIN || draw_y > INT16_MAX) {
                    continue;
                }
                if (tiny_epd_hzfont_covered(resolved_style,
                                             bitmap->pixels[row * bitmap->width + col],
                                             draw_x, draw_y)) {
                    color = resolved_style->fg;
                }
                else if (resolved_style->bg >= 0) {
                    color = (uint8_t)resolved_style->bg;
                }
                else {
                    continue;
                }
                ret = tiny_epd_draw_pixel(epd, (int16_t)draw_x, (int16_t)draw_y, color);
                /*
                 * Drawing deliberately clips glyphs at the framebuffer edge.
                 * An out-of-canvas pixel is therefore not a failure of the
                 * whole string; do not leak that transient result to Lua.
                 */
                if (ret == TINY_EPD_ERR_PARAM) {
                    ret = TINY_EPD_OK;
                    continue;
                }
                if (ret != TINY_EPD_OK) {
                    goto done;
                }
            }
        }
        pen_x += (int32_t)bitmap->width;
    }

done:
    (void)ttf_set_supersample_rate(previous_rate);
    /* The only recoverable error produced while rasterizing is clipping. */
    return ret == TINY_EPD_ERR_PARAM ? TINY_EPD_OK : ret;
}

#else

uint32_t tiny_epd_hzfont_get_utf8_width(const char *utf8, uint8_t size)
{
    (void)utf8;
    (void)size;
    return 0;
}

int tiny_epd_hzfont_draw_utf8(tiny_epd_t *epd,
                               int16_t x, int16_t baseline_y,
                               const char *utf8, uint8_t size,
                               const tiny_epd_hzfont_style_t *style)
{
    (void)epd;
    (void)x;
    (void)baseline_y;
    (void)utf8;
    (void)size;
    (void)style;
    return TINY_EPD_ERR_UNSUPPORTED_MODE;
}

#endif
