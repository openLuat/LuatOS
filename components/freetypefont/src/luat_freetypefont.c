#include "luat_freetypefont.h"

#include "ttf_parser.h"
#include "luat_lcd.h"
#include "luat_mem.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define LUAT_LOG_TAG "freetypefont"
#include "luat_log.h"

#define FREETYPE_FONT_PATH_MAX   260
#define FREETYPE_ADVANCE_RATIO   0.4f
#define FREETYPE_ASCENT_RATIO    0.80f

typedef struct {
    luat_freetypefont_state_t state;
    TtfFont font;
    char font_path[FREETYPE_FONT_PATH_MAX];
} freetypefont_ctx_t;

typedef struct {
    TtfBitmap bitmap;
    uint32_t advance;
    uint8_t has_bitmap;
} glyph_render_t;

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} rgb24_t;

static freetypefont_ctx_t g_ft_ctx = {
    .state = LUAT_FREETYPEFONT_STATE_UNINIT
};

extern luat_lcd_conf_t *lcd_dft_conf;
extern luat_color_t BACK_COLOR;

static uint32_t freetype_calc_fallback_advance(unsigned char font_size) {
    float adv = (float)font_size * FREETYPE_ADVANCE_RATIO;
    if (adv < 1.0f) {
        adv = 1.0f;
    }
    return (uint32_t)ceilf(adv);
}

static uint32_t freetype_default_ascent(unsigned char font_size) {
    float asc = (float)font_size * FREETYPE_ASCENT_RATIO;
    if (asc < 1.0f) {
        asc = 1.0f;
    }
    return (uint32_t)ceilf(asc);
}

static int utf8_decode_next(const unsigned char **cursor, const unsigned char *end, uint32_t *codepoint) {
    const unsigned char *ptr = *cursor;
    if (ptr >= end) {
        return 0;
    }
    unsigned char c0 = *ptr++;
    if (c0 < 0x80) {
        *codepoint = c0;
        *cursor = ptr;
        return 1;
    }
    if ((c0 & 0xE0) == 0xC0) {
        if (ptr < end) {
            unsigned char c1 = *ptr;
            if ((c1 & 0xC0) == 0x80) {
                *codepoint = ((uint32_t)(c0 & 0x1F) << 6) | (uint32_t)(c1 & 0x3F);
                *cursor = ptr + 1;
                return 1;
            }
        }
    } else if ((c0 & 0xF0) == 0xE0) {
        if (ptr + 1 < end) {
            unsigned char c1 = ptr[0];
            unsigned char c2 = ptr[1];
            if (((c1 & 0xC0) == 0x80) && ((c2 & 0xC0) == 0x80)) {
                *codepoint = ((uint32_t)(c0 & 0x0F) << 12) |
                             ((uint32_t)(c1 & 0x3F) << 6) |
                             (uint32_t)(c2 & 0x3F);
                *cursor = ptr + 2;
                return 1;
            }
        }
    } else if ((c0 & 0xF8) == 0xF0) {
        if (ptr + 2 < end) {
            unsigned char c1 = ptr[0];
            unsigned char c2 = ptr[1];
            unsigned char c3 = ptr[2];
            if (((c1 & 0xC0) == 0x80) && ((c2 & 0xC0) == 0x80) && ((c3 & 0xC0) == 0x80)) {
                *codepoint = ((uint32_t)(c0 & 0x07) << 18) |
                             ((uint32_t)(c1 & 0x3F) << 12) |
                             ((uint32_t)(c2 & 0x3F) << 6) |
                             (uint32_t)(c3 & 0x3F);
                *cursor = ptr + 3;
                return 1;
            }
        }
    }
    *codepoint = '?';
    *cursor = ptr;
    return 1;
}

static void rgb_from_rgb565(uint16_t color, uint8_t *r, uint8_t *g, uint8_t *b) {
    *r = (uint8_t)(((color >> 11) & 0x1F) * 255 / 31);
    *g = (uint8_t)(((color >> 5) & 0x3F) * 255 / 63);
    *b = (uint8_t)((color & 0x1F) * 255 / 31);
}

static uint16_t rgb565_from_rgb(uint8_t r, uint8_t g, uint8_t b) {
    uint16_t rr = (uint16_t)((r * 31 + 127) / 255) << 11;
    uint16_t gg = (uint16_t)((g * 63 + 127) / 255) << 5;
    uint16_t bb = (uint16_t)((b * 31 + 127) / 255);
    return (uint16_t)(rr | gg | bb);
}

static rgb24_t freetype_decode_input_color(uint32_t color) {
    rgb24_t out;
    if (color <= 0xFFFFu) {
        rgb_from_rgb565((uint16_t)color, &out.r, &out.g, &out.b);
    } else if (color <= 0xFFFFFFu) {
        out.r = (uint8_t)((color >> 16) & 0xFF);
        out.g = (uint8_t)((color >> 8) & 0xFF);
        out.b = (uint8_t)(color & 0xFF);
    } else {
        out.r = (uint8_t)((color >> 16) & 0xFF);
        out.g = (uint8_t)((color >> 8) & 0xFF);
        out.b = (uint8_t)(color & 0xFF);
    }
    return out;
}

static rgb24_t freetype_decode_luat_color(const luat_lcd_conf_t *conf, luat_color_t color) {
    rgb24_t out = {255, 255, 255};
    if (!conf) {
        return out;
    }
    switch (conf->bpp) {
    case 16:
        rgb_from_rgb565((uint16_t)color, &out.r, &out.g, &out.b);
        break;
    case 24:
    case 32:
        out.r = (uint8_t)((color >> 16) & 0xFF);
        out.g = (uint8_t)((color >> 8) & 0xFF);
        out.b = (uint8_t)(color & 0xFF);
        break;
    default:
        rgb_from_rgb565((uint16_t)color, &out.r, &out.g, &out.b);
        break;
    }
    return out;
}

static luat_color_t freetype_encode_color(const luat_lcd_conf_t *conf, uint8_t r, uint8_t g, uint8_t b) {
    if (!conf) {
        return rgb565_from_rgb(r, g, b);
    }
    switch (conf->bpp) {
    case 16:
        return rgb565_from_rgb(r, g, b);
    case 24:
        return (luat_color_t)((r << 16) | (g << 8) | b);
    case 32:
        return (luat_color_t)(0xFF000000u | (uint32_t)r << 16 | (uint32_t)g << 8 | (uint32_t)b);
    default:
        return rgb565_from_rgb(r, g, b);
    }
}

static luat_color_t freetype_coverage_to_color(uint8_t coverage, const luat_lcd_conf_t *conf,
                                               const rgb24_t *fg, const rgb24_t *bg) {
    if (coverage == 0) {
        return 0;
    }
    uint32_t inv = 255u - (uint32_t)coverage;
    uint32_t rr = ((uint32_t)fg->r * coverage + (uint32_t)bg->r * inv) / 255u;
    uint32_t gg = ((uint32_t)fg->g * coverage + (uint32_t)bg->g * inv) / 255u;
    uint32_t bb = ((uint32_t)fg->b * coverage + (uint32_t)bg->b * inv) / 255u;
    return freetype_encode_color(conf, (uint8_t)rr, (uint8_t)gg, (uint8_t)bb);
}

int luat_freetypefont_init(const char *ttf_path) {
    if (!ttf_path || ttf_path[0] == 0) {
        LLOGE("invalid ttf path");
        return 0;
    }
    if (g_ft_ctx.state == LUAT_FREETYPEFONT_STATE_READY) {
        LLOGE("font already initialized");
        return 0;
    }

    memset(&g_ft_ctx.font, 0, sizeof(g_ft_ctx.font));
    int rc = ttf_load_from_file(ttf_path, &g_ft_ctx.font);
    if (rc != TTF_OK) {
        LLOGE("load font fail rc=%d", rc);
        ttf_unload(&g_ft_ctx.font);
        g_ft_ctx.state = LUAT_FREETYPEFONT_STATE_ERROR;
        return 0;
    }
    strncpy(g_ft_ctx.font_path, ttf_path, sizeof(g_ft_ctx.font_path) - 1);
    g_ft_ctx.font_path[sizeof(g_ft_ctx.font_path) - 1] = 0;
    g_ft_ctx.state = LUAT_FREETYPEFONT_STATE_READY;
    LLOGI("font loaded units_per_em=%u glyphs=%u", g_ft_ctx.font.unitsPerEm, g_ft_ctx.font.numGlyphs);
    return 1;
}

void luat_freetypefont_deinit(void) {
    if (g_ft_ctx.state == LUAT_FREETYPEFONT_STATE_UNINIT) {
        return;
    }
    ttf_unload(&g_ft_ctx.font);
    memset(&g_ft_ctx, 0, sizeof(g_ft_ctx));
    g_ft_ctx.state = LUAT_FREETYPEFONT_STATE_UNINIT;
}

luat_freetypefont_state_t luat_freetypefont_get_state(void) {
    return g_ft_ctx.state;
}

static uint32_t glyph_estimate_width_px(const TtfGlyph *glyph, float scale) {
    if (!glyph || glyph->pointCount == 0 || glyph->contourCount == 0) {
        return 0;
    }
    float widthF = (glyph->maxX - glyph->minX) * scale + 2.0f;
    if (widthF < 1.0f) {
        widthF = 1.0f;
    }
    return (uint32_t)ceilf(widthF);
}

uint32_t luat_freetypefont_get_str_width(const char *utf8, unsigned char font_size) {
    if (!utf8 || font_size == 0 || g_ft_ctx.state != LUAT_FREETYPEFONT_STATE_READY) {
        return 0;
    }
    if (g_ft_ctx.font.unitsPerEm == 0) {
        return 0;
    }

    const unsigned char *cursor = (const unsigned char *)utf8;
    const unsigned char *end = cursor + strlen(utf8);
    uint32_t total = 0;
    float scale = (float)font_size / (float)g_ft_ctx.font.unitsPerEm;
    if (scale <= 0.0f) {
        scale = 1.0f;
    }

    while (cursor < end) {
        uint32_t cp = 0;
        if (!utf8_decode_next(&cursor, end, &cp)) {
            break;
        }
        if (cp == '\r' || cp == '\n') {
            continue;
        }
        uint16_t glyph_index = 0;
        if (ttf_lookup_glyph_index(&g_ft_ctx.font, cp, &glyph_index) != TTF_OK) {
            if (cp != ' ' && cp != '\t') {
                LLOGW("missing glyph cp=%lu", (unsigned long)cp);
            }
            total += freetype_calc_fallback_advance(font_size);
            continue;
        }

        TtfGlyph glyph;
        int rc = ttf_load_glyph(&g_ft_ctx.font, glyph_index, &glyph);
        if (rc != TTF_OK) {
            total += freetype_calc_fallback_advance(font_size);
            continue;
        }
        uint32_t width = glyph_estimate_width_px(&glyph, scale);
        ttf_free_glyph(&glyph);
        if (width == 0) {
            width = freetype_calc_fallback_advance(font_size);
        }
        total += width;
    }
    return total;
}

static void freetype_release_glyphs(glyph_render_t *glyphs, size_t count) {
    if (!glyphs) {
        return;
    }
    for (size_t i = 0; i < count; i++) {
        if (glyphs[i].bitmap.pixels) {
            ttf_free_bitmap(&glyphs[i].bitmap);
        }
    }
    luat_heap_free(glyphs);
}

int luat_freetypefont_draw_utf8(int x, int y, const char *utf8, unsigned char font_size, uint32_t color) {
    if (!utf8 || font_size == 0) {
        return -1;
    }
    if (g_ft_ctx.state != LUAT_FREETYPEFONT_STATE_READY) {
        LLOGE("font not ready");
        return -2;
    }
    if (!lcd_dft_conf) {
        LLOGE("lcd not init");
        return -3;
    }
    size_t utf8_len = strlen(utf8);
    if (utf8_len == 0) {
        return 0;
    }

    glyph_render_t *glyphs = (glyph_render_t *)luat_heap_malloc(utf8_len * sizeof(glyph_render_t));
    if (!glyphs) {
        LLOGE("oom glyph cache");
        return -4;
    }
    memset(glyphs, 0, utf8_len * sizeof(glyph_render_t));

    const unsigned char *cursor = (const unsigned char *)utf8;
    const unsigned char *end = cursor + utf8_len;
    size_t glyph_count = 0;
    uint32_t baseline_above = 0;
    while (cursor < end && glyph_count < utf8_len) {
        uint32_t cp = 0;
        if (!utf8_decode_next(&cursor, end, &cp)) {
            break;
        }
        if (cp == '\r' || cp == '\n') {
            continue;
        }

        glyph_render_t *slot = &glyphs[glyph_count];
        slot->advance = freetype_calc_fallback_advance(font_size);
        slot->has_bitmap = 0;
        memset(&slot->bitmap, 0, sizeof(slot->bitmap));

        uint16_t glyph_index = 0;
        if (ttf_lookup_glyph_index(&g_ft_ctx.font, cp, &glyph_index) != TTF_OK) {
            glyph_count++;
            continue;
        }

        TtfGlyph glyph;
        int rc = ttf_load_glyph(&g_ft_ctx.font, glyph_index, &glyph);
        if (rc != TTF_OK) {
            glyph_count++;
            continue;
        }
        rc = ttf_rasterize_glyph(&g_ft_ctx.font, &glyph, font_size, &slot->bitmap);
        ttf_free_glyph(&glyph);
        if (rc != TTF_OK) {
            glyph_count++;
            continue;
        }

        if (slot->bitmap.width > 0 && slot->bitmap.height > 0 && slot->bitmap.pixels) {
            slot->has_bitmap = 1;
            slot->advance = slot->bitmap.width;
            if (slot->advance == 0) {
                slot->advance = freetype_calc_fallback_advance(font_size);
            }
            uint32_t above = slot->bitmap.originY;
            if (above > baseline_above) {
                baseline_above = above;
            }
        } else {
            uint32_t fallback_above = freetype_default_ascent(font_size);
            if (fallback_above > baseline_above) {
                baseline_above = fallback_above;
            }
        }
        glyph_count++;
    }

    if (baseline_above == 0) {
        baseline_above = freetype_default_ascent(font_size);
    }
    rgb24_t fg = freetype_decode_input_color(color);
    rgb24_t bg = freetype_decode_luat_color(lcd_dft_conf, BACK_COLOR);

    int pen_x = x;
    uint32_t baseline_offset = baseline_above;

    for (size_t i = 0; i < glyph_count; i++) {
        glyph_render_t *slot = &glyphs[i];
        if (!slot->has_bitmap) {
            pen_x += (int)slot->advance;
            continue;
        }
        int draw_x = pen_x;
        int draw_y_base = y + (int)baseline_offset - (int)slot->bitmap.originY;

        size_t row_buf_capacity = (size_t)slot->bitmap.width;
        if (row_buf_capacity == 0) {
            pen_x += (int)slot->advance;
            continue;
        }
        luat_color_t *row_buf = (luat_color_t *)luat_heap_malloc(row_buf_capacity * sizeof(luat_color_t));
        if (!row_buf) {
            freetype_release_glyphs(glyphs, glyph_count);
            LLOGE("oom row buffer");
            return -5;
        }

        for (uint32_t row = 0; row < slot->bitmap.height; row++) {
            const uint8_t *row_pixels = slot->bitmap.pixels + row * slot->bitmap.width;
            uint32_t col = 0;
            while (col < slot->bitmap.width) {
                while (col < slot->bitmap.width && row_pixels[col] == 0) {
                    col++;
                }
                if (col >= slot->bitmap.width) {
                    break;
                }
                uint32_t run_start = col;
                size_t run_len = 0;
                while (col < slot->bitmap.width && row_pixels[col] != 0) {
                    row_buf[run_len++] = freetype_coverage_to_color(row_pixels[col], lcd_dft_conf, &fg, &bg);
                    col++;
                }
                if (run_len > 0) {
                    int y_draw = draw_y_base + (int)row;
                    int x_start = draw_x + (int)run_start;
                    int x_end = x_start + (int)run_len - 1;
                    luat_lcd_draw(lcd_dft_conf, (int16_t)x_start, (int16_t)y_draw, (int16_t)x_end, (int16_t)y_draw, row_buf);
                }
            }
        }

        luat_heap_free(row_buf);
        pen_x += (int)slot->advance;
    }

    freetype_release_glyphs(glyphs, glyph_count);
    return 0;
}
