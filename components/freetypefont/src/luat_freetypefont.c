#include "luat_freetypefont.h"

#include "ttf_parser.h"
#include "luat_lcd.h"
#include "luat_mem.h"
#include "luat_mcu.h"

#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define LUAT_LOG_TAG "freetypefont"
#include "luat_log.h"

#define FREETYPE_FONT_PATH_MAX   260
#define FREETYPE_ADVANCE_RATIO   0.4f
#define FREETYPE_ASCENT_RATIO    0.80f

// 位图缓存容量
#define FREETYPE_CACHE_CAPACITY 128
// 码点 -> glyph index 缓存槽位（需为 2 的幂以便快速哈希）
#define FREETYPE_CODEPOINT_CACHE_SIZE 256

typedef struct {
    luat_freetypefont_state_t state;
    TtfFont font;
    char font_path[FREETYPE_FONT_PATH_MAX];
} freetypefont_ctx_t;

typedef enum {
    FREETYPE_GLYPH_OK = 0,
    FREETYPE_GLYPH_LOOKUP_FAIL,
    FREETYPE_GLYPH_LOAD_FAIL,
    FREETYPE_GLYPH_RASTER_FAIL,
    FREETYPE_GLYPH_DRAW_FAIL
} freetype_glyph_status_t;

typedef struct {
    TtfBitmap bitmap;
    uint32_t advance;
    uint32_t codepoint;
    uint32_t glyph_index;
    uint32_t time_lookup_us;
    uint32_t time_load_us;
    uint32_t time_raster_us;
    uint32_t time_draw_us;
    uint8_t from_cache;
    uint8_t has_bitmap;
    uint8_t status;
} glyph_render_t;

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} rgb24_t;

static freetypefont_ctx_t g_ft_ctx = {
    .state = LUAT_FREETYPEFONT_STATE_UNINIT
};

typedef struct {
    uint16_t glyph_index;
    uint8_t font_size;
    uint8_t supersample;
    uint8_t in_use;
    uint32_t last_used;
    TtfBitmap bitmap;
} freetype_cache_entry_t;

static freetype_cache_entry_t g_ft_cache[FREETYPE_CACHE_CAPACITY];
static uint32_t g_ft_cache_stamp = 0;

typedef struct {
    uint32_t codepoint;
    uint16_t glyph_index;
    uint8_t in_use;
    uint32_t last_used;
} freetype_cp_cache_entry_t;

static freetype_cp_cache_entry_t g_ft_cp_cache[FREETYPE_CODEPOINT_CACHE_SIZE];

extern luat_lcd_conf_t *lcd_dft_conf;
extern luat_color_t BACK_COLOR;

#define FREETYPE_TIMING_THRESHOLD_US 3000

static uint64_t freetype_now_us(void) {
    int period = luat_mcu_us_period();
    if (period <= 0) {
        return luat_mcu_tick64_ms() * 1000ULL;
    }
    return luat_mcu_tick64() / (uint64_t)period;
}

static uint32_t freetype_elapsed_from(uint64_t start) {
    if (start == 0) {
        return 0;
    }
    uint64_t now = freetype_now_us();
    if (now <= start) {
        return 0;
    }
    uint64_t diff = now - start;
    if (diff > UINT32_MAX) {
        return UINT32_MAX;
    }
    return (uint32_t)diff;
}

static uint32_t freetype_elapsed_step(uint64_t *stamp) {
    if (!stamp || *stamp == 0) {
        return 0;
    }
    uint64_t now = freetype_now_us();
    uint64_t diff = (now > *stamp) ? (now - *stamp) : 0;
    *stamp = now;
    if (diff > UINT32_MAX) {
        return UINT32_MAX;
    }
    return (uint32_t)diff;
}

static const char *freetype_status_text(uint8_t status) {
    switch (status) {
    case FREETYPE_GLYPH_OK:
        return "ok";
    case FREETYPE_GLYPH_LOOKUP_FAIL:
        return "lookup_fail";
    case FREETYPE_GLYPH_LOAD_FAIL:
        return "load_fail";
    case FREETYPE_GLYPH_RASTER_FAIL:
        return "raster_fail";
    case FREETYPE_GLYPH_DRAW_FAIL:
        return "draw_fail";
    default:
        return "unknown";
    }
}

static uint32_t freetype_clamp_u32(uint64_t value) {
    return value > UINT32_MAX ? UINT32_MAX : (uint32_t)value;
}

static uint32_t freetype_next_stamp(void) {
    g_ft_cache_stamp++;
    if (g_ft_cache_stamp == 0) {
        g_ft_cache_stamp = 1;
    }
    return g_ft_cache_stamp;
}

static void freetype_cp_cache_clear(void) {
    memset(g_ft_cp_cache, 0, sizeof(g_ft_cp_cache));
}

static void freetype_cache_clear(void) {
    for (size_t i = 0; i < FREETYPE_CACHE_CAPACITY; ++i) {
        freetype_cache_entry_t *entry = &g_ft_cache[i];
        if (entry->in_use) {
            if (entry->bitmap.pixels) {
                ttf_free_bitmap(&entry->bitmap);
            }
            memset(entry, 0, sizeof(*entry));
        }
    }
    freetype_cp_cache_clear();
    g_ft_cache_stamp = 0;
}

static void freetype_cache_touch(freetype_cache_entry_t *entry) {
    if (!entry) {
        return;
    }
    entry->last_used = freetype_next_stamp();
}

static freetype_cache_entry_t *freetype_cache_find(uint16_t glyph_index, uint8_t font_size, uint8_t supersample) {
    for (size_t i = 0; i < FREETYPE_CACHE_CAPACITY; ++i) {
        freetype_cache_entry_t *entry = &g_ft_cache[i];
        if (entry->in_use &&
            entry->glyph_index == glyph_index &&
            entry->font_size == font_size &&
            entry->supersample == supersample) {
            return entry;
        }
    }
    return NULL;
}

static freetype_cache_entry_t *freetype_cache_get(uint16_t glyph_index, uint8_t font_size, uint8_t supersample) {
    freetype_cache_entry_t *entry = freetype_cache_find(glyph_index, font_size, supersample);
    if (entry) {
        freetype_cache_touch(entry);
    }
    return entry;
}

static freetype_cache_entry_t *freetype_cache_allocate_slot(void) {
    for (size_t i = 0; i < FREETYPE_CACHE_CAPACITY; ++i) {
        if (!g_ft_cache[i].in_use) {
            return &g_ft_cache[i];
        }
    }
    uint32_t oldest = UINT32_MAX;
    size_t oldest_index = 0;
    for (size_t i = 0; i < FREETYPE_CACHE_CAPACITY; ++i) {
        if (g_ft_cache[i].last_used < oldest) {
            oldest = g_ft_cache[i].last_used;
            oldest_index = i;
        }
    }
    freetype_cache_entry_t *entry = &g_ft_cache[oldest_index];
    if (entry->in_use && entry->bitmap.pixels) {
        ttf_free_bitmap(&entry->bitmap);
    }
    memset(entry, 0, sizeof(*entry));
    return entry;
}

static freetype_cache_entry_t *freetype_cache_insert(uint16_t glyph_index, uint8_t font_size,
                                                     uint8_t supersample, TtfBitmap *bitmap) {
    if (!bitmap || !bitmap->pixels) {
        return NULL;
    }
    freetype_cache_entry_t *entry = freetype_cache_find(glyph_index, font_size, supersample);
    if (!entry) {
        entry = freetype_cache_allocate_slot();
    } else {
        if (entry->bitmap.pixels) {
            ttf_free_bitmap(&entry->bitmap);
        }
        memset(&entry->bitmap, 0, sizeof(entry->bitmap));
    }
    entry->glyph_index = glyph_index;
    entry->font_size = font_size;
    entry->supersample = supersample;
    entry->bitmap = *bitmap;
    entry->in_use = 1;
    freetype_cache_touch(entry);
    return entry;
}

static freetype_cp_cache_entry_t *freetype_cp_cache_lookup(uint32_t codepoint) {
    if (FREETYPE_CODEPOINT_CACHE_SIZE == 0) {
        return NULL;
    }
    uint32_t mask = FREETYPE_CODEPOINT_CACHE_SIZE - 1u;
    uint32_t start = (uint32_t)((codepoint * 2654435761u) & mask);
    for (uint32_t probe = 0; probe < FREETYPE_CODEPOINT_CACHE_SIZE; ++probe) {
        freetype_cp_cache_entry_t *entry = &g_ft_cp_cache[(start + probe) & mask];
        if (!entry->in_use) {
            return NULL;
        }
        if (entry->codepoint == codepoint) {
            entry->last_used = freetype_next_stamp();
            return entry;
        }
    }
    return NULL;
}

static void freetype_cp_cache_insert(uint32_t codepoint, uint16_t glyph_index) {
    if (FREETYPE_CODEPOINT_CACHE_SIZE == 0) {
        return;
    }
    uint32_t mask = FREETYPE_CODEPOINT_CACHE_SIZE - 1u;
    uint32_t start = (uint32_t)((codepoint * 2654435761u) & mask);
    freetype_cp_cache_entry_t *empty_slot = NULL;
    for (uint32_t probe = 0; probe < FREETYPE_CODEPOINT_CACHE_SIZE; ++probe) {
        freetype_cp_cache_entry_t *entry = &g_ft_cp_cache[(start + probe) & mask];
        if (!entry->in_use) {
            empty_slot = entry;
            break;
        }
        if (entry->codepoint == codepoint) {
            entry->glyph_index = glyph_index;
            entry->last_used = freetype_next_stamp();
            return;
        }
    }
    freetype_cp_cache_entry_t *target = empty_slot;
    if (!target) {
        uint32_t oldest = UINT32_MAX;
        size_t oldest_idx = 0;
        for (size_t i = 0; i < FREETYPE_CODEPOINT_CACHE_SIZE; ++i) {
            if (g_ft_cp_cache[i].last_used < oldest) {
                oldest = g_ft_cp_cache[i].last_used;
                oldest_idx = i;
            }
        }
        target = &g_ft_cp_cache[oldest_idx];
    }
    target->codepoint = codepoint;
    target->glyph_index = glyph_index;
    target->in_use = 1;
    target->last_used = freetype_next_stamp();
}

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
        LLOGE("don't support rgb24 color=%u", color);
        break;
    case 32:
        LLOGE("don't support rgb32 color=%u", color);
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
        return (luat_color_t)(((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b);
    case 32:
        return (luat_color_t)(0xFF000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b);
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

    freetype_cache_clear();
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
    freetype_cache_clear();
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
        if (glyphs[i].bitmap.pixels && !glyphs[i].from_cache) {
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

    int timing_enabled = ttf_get_debug();
    uint64_t func_start_ts = timing_enabled ? freetype_now_us() : 0;
    uint64_t sum_lookup_us = 0;
    uint64_t sum_load_us = 0;
    uint64_t sum_raster_us = 0;
    uint64_t sum_draw_us = 0;
    uint64_t sum_total_us = 0;
    uint64_t sum_rendered_total_us = 0;
    size_t rendered_count = 0;
    size_t profiled_glyphs = 0;
    size_t max_slot_index = (size_t)-1;
    uint32_t max_glyph_total_us = 0;
    int result = 0;

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
        slot->codepoint = cp;
        slot->glyph_index = 0;
        slot->time_lookup_us = 0;
        slot->time_load_us = 0;
        slot->time_raster_us = 0;
        slot->time_draw_us = 0;
        slot->from_cache = 0;
        slot->status = FREETYPE_GLYPH_LOOKUP_FAIL;

        uint64_t glyph_stamp = timing_enabled ? freetype_now_us() : 0;

        uint16_t glyph_index = 0;
        int rc = TTF_OK;
        freetype_cp_cache_entry_t *cp_entry = freetype_cp_cache_lookup(cp);
        if (cp_entry) {
            glyph_index = cp_entry->glyph_index;
            if (timing_enabled) {
                slot->time_lookup_us = glyph_stamp ? freetype_elapsed_step(&glyph_stamp) : 0;
                sum_lookup_us += slot->time_lookup_us;
            }
        } else {
            rc = ttf_lookup_glyph_index(&g_ft_ctx.font, cp, &glyph_index);
            if (timing_enabled) {
                slot->time_lookup_us = glyph_stamp ? freetype_elapsed_step(&glyph_stamp) : 0;
                sum_lookup_us += slot->time_lookup_us;
            }
            if (rc != TTF_OK) {
                glyph_count++;
                continue;
            }
            freetype_cp_cache_insert(cp, glyph_index);
        }

        slot->glyph_index = glyph_index;
        slot->status = FREETYPE_GLYPH_LOAD_FAIL;

        uint8_t supersample = (uint8_t)ttf_get_supersample_rate();
        freetype_cache_entry_t *cache_entry = freetype_cache_get(glyph_index, (uint8_t)font_size, supersample);
        if (cache_entry) {
            slot->bitmap = cache_entry->bitmap;
            slot->from_cache = 1;
            slot->status = FREETYPE_GLYPH_OK;
        } else {
            TtfGlyph glyph;
            rc = ttf_load_glyph(&g_ft_ctx.font, glyph_index, &glyph);
            if (timing_enabled) {
                slot->time_load_us = glyph_stamp ? freetype_elapsed_step(&glyph_stamp) : 0;
                sum_load_us += slot->time_load_us;
            }
            if (rc != TTF_OK) {
                glyph_count++;
                continue;
            }

            slot->status = FREETYPE_GLYPH_RASTER_FAIL;
            rc = ttf_rasterize_glyph(&g_ft_ctx.font, &glyph, font_size, &slot->bitmap);
            if (timing_enabled) {
                slot->time_raster_us = glyph_stamp ? freetype_elapsed_step(&glyph_stamp) : 0;
                sum_raster_us += slot->time_raster_us;
            }
            ttf_free_glyph(&glyph);
            if (rc != TTF_OK) {
                glyph_count++;
                continue;
            }

            slot->status = FREETYPE_GLYPH_OK;
            freetype_cache_entry_t *new_entry = freetype_cache_insert(glyph_index, (uint8_t)font_size, supersample, &slot->bitmap);
            if (new_entry) {
                slot->from_cache = 1;
                slot->bitmap = new_entry->bitmap;
            }
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
            if (timing_enabled) {
                slot->time_draw_us = 0;
            }
            pen_x += (int)slot->advance;
            goto glyph_timing_update;
        }

        uint64_t draw_stamp = timing_enabled ? freetype_now_us() : 0;
        int draw_x = pen_x;
        int draw_y_base = y + (int)baseline_offset - (int)slot->bitmap.originY;

        size_t row_buf_capacity = (size_t)slot->bitmap.width;
        if (row_buf_capacity == 0) {
            if (timing_enabled && draw_stamp) {
                slot->time_draw_us = freetype_elapsed_from(draw_stamp);
                sum_draw_us += slot->time_draw_us;
            }
            pen_x += (int)slot->advance;
            goto glyph_timing_update;
        }

        luat_color_t *row_buf = (luat_color_t *)luat_heap_malloc(row_buf_capacity * sizeof(luat_color_t));
        if (!row_buf) {
            if (timing_enabled && draw_stamp) {
                slot->time_draw_us = freetype_elapsed_from(draw_stamp);
                sum_draw_us += slot->time_draw_us;
            }
            slot->status = FREETYPE_GLYPH_DRAW_FAIL;
            pen_x += (int)slot->advance;
            result = -5;
            LLOGE("oom row buffer");
            goto glyph_timing_update;
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
        if (timing_enabled && draw_stamp) {
            slot->time_draw_us = freetype_elapsed_from(draw_stamp);
            sum_draw_us += slot->time_draw_us;
        }
        pen_x += (int)slot->advance;
        rendered_count++;

glyph_timing_update:
        if (timing_enabled) {
            uint64_t glyph_total64 = (uint64_t)slot->time_lookup_us +
                                     (uint64_t)slot->time_load_us +
                                     (uint64_t)slot->time_raster_us +
                                     (uint64_t)slot->time_draw_us;
            sum_total_us += glyph_total64;
            if (slot->has_bitmap && slot->status == FREETYPE_GLYPH_OK) {
                sum_rendered_total_us += glyph_total64;
            }
            uint32_t glyph_total32 = freetype_clamp_u32(glyph_total64);
            if (glyph_total32 > max_glyph_total_us) {
                max_glyph_total_us = glyph_total32;
                max_slot_index = i;
            }
            if (glyph_total32 >= FREETYPE_TIMING_THRESHOLD_US || slot->status != FREETYPE_GLYPH_OK) {
                LLOGI("glyph[%u] cp=U+%04lX idx=%u status=%s total=%luus lookup=%lu load=%lu raster=%lu draw=%lu",
                      (unsigned)i,
                      (unsigned long)slot->codepoint,
                      (unsigned)slot->glyph_index,
                      freetype_status_text(slot->status),
                      (unsigned long)glyph_total32,
                      (unsigned long)slot->time_lookup_us,
                      (unsigned long)slot->time_load_us,
                      (unsigned long)slot->time_raster_us,
                      (unsigned long)slot->time_draw_us);
            }
            profiled_glyphs++;
        }
        if (result != 0) {
            break;
        }
    }

finalize:
    if (timing_enabled) {
        uint32_t total_us = freetype_elapsed_from(func_start_ts);
        uint32_t sum_lookup32 = freetype_clamp_u32(sum_lookup_us);
        uint32_t sum_load32 = freetype_clamp_u32(sum_load_us);
        uint32_t sum_raster32 = freetype_clamp_u32(sum_raster_us);
        uint32_t sum_draw32 = freetype_clamp_u32(sum_draw_us);
        uint32_t avg_all_us = profiled_glyphs ? freetype_clamp_u32(sum_total_us / profiled_glyphs) : 0;
        uint32_t avg_rendered_us = rendered_count ? freetype_clamp_u32(sum_rendered_total_us / rendered_count) : 0;
        LLOGI("timing total=%luus glyphs=%u profiled=%u rendered=%u avg_all=%lu avg_render=%lu lookup=%lu load=%lu raster=%lu draw=%lu result=%d",
              (unsigned long)total_us,
              (unsigned)glyph_count,
              (unsigned)profiled_glyphs,
              (unsigned)rendered_count,
              (unsigned long)avg_all_us,
              (unsigned long)avg_rendered_us,
              (unsigned long)sum_lookup32,
              (unsigned long)sum_load32,
              (unsigned long)sum_raster32,
              (unsigned long)sum_draw32,
              result);
        if (max_slot_index != (size_t)-1 && max_slot_index < glyph_count) {
            glyph_render_t *max_slot = &glyphs[max_slot_index];
            uint32_t glyph_total32 = freetype_clamp_u32((uint64_t)max_slot->time_lookup_us +
                                                        (uint64_t)max_slot->time_load_us +
                                                        (uint64_t)max_slot->time_raster_us +
                                                        (uint64_t)max_slot->time_draw_us);
            LLOGI("timing max glyph idx=%u cp=U+%04lX status=%s total=%luus lookup=%lu load=%lu raster=%lu draw=%lu",
                  (unsigned)max_slot_index,
                  (unsigned long)max_slot->codepoint,
                  freetype_status_text(max_slot->status),
                  (unsigned long)glyph_total32,
                  (unsigned long)max_slot->time_lookup_us,
                  (unsigned long)max_slot->time_load_us,
                  (unsigned long)max_slot->time_raster_us,
                  (unsigned long)max_slot->time_draw_us);
        }
    }

    freetype_release_glyphs(glyphs, glyph_count);
    return result;
}
