// 负责：TTF 字体加载、缓存与渲染（HzFont）
#include "luat_hzfont.h"

#include "ttf_parser.h"
#include "luat_lcd.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_fs.h"

#include <math.h>
#include <stdio.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define LUAT_LOG_TAG "hzfont"
#include "luat_log.h"

#define HZFONT_FONT_PATH_MAX   260
#define HZFONT_ADVANCE_RATIO   0.4f
#define HZFONT_ASCENT_RATIO    0.80f

/* 默认/允许缓存容量集中定义，便于维护 */
#define HZFONT_CACHE_DEFAULT 256u
static const uint32_t HZFONT_CACHE_ALLOWED[] = {128u, 256u, 512u, 1024u, 2048u};
static const size_t   HZFONT_CACHE_ALLOWED_LEN = sizeof(HZFONT_CACHE_ALLOWED) / sizeof(HZFONT_CACHE_ALLOWED[0]);

#ifdef LUAT_CONF_USE_HZFONT_BUILTIN_TTF
extern const unsigned char hzfont_builtin_ttf[];
extern const unsigned int hzfont_builtin_ttf_len;
#endif

typedef struct {
    luat_hzfont_state_t state;
    TtfFont font;
    char font_path[HZFONT_FONT_PATH_MAX];
} hzfont_ctx_t;

typedef enum {
    HZFONT_GLYPH_OK = 0,
    HZFONT_GLYPH_LOOKUP_FAIL,
    HZFONT_GLYPH_LOAD_FAIL,
    HZFONT_GLYPH_RASTER_FAIL,
    HZFONT_GLYPH_DRAW_FAIL
} hzfont_glyph_status_t;

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

static hzfont_ctx_t g_ft_ctx = {
    .state = LUAT_HZFONT_STATE_UNINIT
};

typedef struct {
    uint16_t glyph_index;
    uint8_t font_size;
    uint8_t supersample;
    uint8_t in_use;
    uint32_t last_used;
    TtfBitmap bitmap;
} hzfont_cache_entry_t;

static hzfont_cache_entry_t *g_hzfont_cache = NULL;
static uint32_t g_hzfont_cache_capacity = 0;
static uint32_t g_hzfont_cache_stamp = 0;

typedef struct {
    uint32_t codepoint;
    uint16_t glyph_index;
    uint8_t in_use;
    uint32_t last_used;
} hzfont_cp_cache_entry_t;

static hzfont_cp_cache_entry_t *g_hzfont_cp_cache = NULL;
static uint32_t g_hzfont_cp_cache_size = 0; /* 必须为 2 的幂，便于掩码寻址 */
/* 单次告警开关，避免重复噪声 */
static uint8_t g_warn_fontsize = 0;
static uint8_t g_warn_cache_invalid = 0;

extern luat_lcd_conf_t *lcd_dft_conf;
extern luat_color_t BACK_COLOR;

#define HZFONT_TIMING_THRESHOLD_US 3000

static uint64_t hzfont_now_us(void) {
    int period = luat_mcu_us_period();
    if (period <= 0) {
        return luat_mcu_tick64_ms() * 1000ULL;
    }
    return luat_mcu_tick64() / (uint64_t)period;
}

static uint32_t hzfont_elapsed_from(uint64_t start) {
    if (start == 0) {
        return 0;
    }
    uint64_t now = hzfont_now_us();
    if (now <= start) {
        return 0;
    }
    uint64_t diff = now - start;
    if (diff > UINT32_MAX) {
        return UINT32_MAX;
    }
    return (uint32_t)diff;
}

static uint32_t hzfont_elapsed_step(uint64_t *stamp) {
    if (!stamp || *stamp == 0) {
        return 0;
    }
    uint64_t now = hzfont_now_us();
    uint64_t diff = (now > *stamp) ? (now - *stamp) : 0;
    *stamp = now;
    if (diff > UINT32_MAX) {
        return UINT32_MAX;
    }
    return (uint32_t)diff;
}

static const char *hzfont_status_text(uint8_t status) {
    switch (status) {
    case HZFONT_GLYPH_OK:
        return "ok";
    case HZFONT_GLYPH_LOOKUP_FAIL:
        return "lookup_fail";
    case HZFONT_GLYPH_LOAD_FAIL:
        return "load_fail";
    case HZFONT_GLYPH_RASTER_FAIL:
        return "raster_fail";
    case HZFONT_GLYPH_DRAW_FAIL:
        return "draw_fail";
    default:
        return "unknown";
    }
}

static uint32_t hzfont_clamp_u32(uint64_t value) {
    return value > UINT32_MAX ? UINT32_MAX : (uint32_t)value;
}

static uint32_t hzfont_next_stamp(void) {
    g_hzfont_cache_stamp++;
    if (g_hzfont_cache_stamp == 0) {
        g_hzfont_cache_stamp = 1;
    }
    return g_hzfont_cache_stamp;
}

/* 判断缓存容量是否在允许列表 */
static int hzfont_is_allowed_capacity(uint32_t cap) {
    for (size_t i = 0; i < HZFONT_CACHE_ALLOWED_LEN; i++) {
        if (cap == HZFONT_CACHE_ALLOWED[i]) {
            return 1;
        }
    }
    return 0;
}

/* 将字体文件完整读入内存（PSRAM），用于后续内存解析 */
static int hzfont_load_file_to_ram(const char *path, uint8_t **out_data, size_t *out_size) {
    if (!path || !out_data || !out_size) {
        return TTF_ERR_RANGE;
    }
    *out_data = NULL;
    *out_size = 0;

    FILE *fp = luat_fs_fopen(path, "rb");
#ifdef LUA_USE_WINDOWS
    FILE *std_fp = NULL;
#endif
    if (!fp) {
#ifdef LUA_USE_WINDOWS
        std_fp = fopen(path, "rb");
        if (!std_fp) {
            return TTF_ERR_IO;
        }
        if (fseek(std_fp, 0, SEEK_END) != 0) {
            fclose(std_fp);
            return TTF_ERR_IO;
        }
        long fsz = ftell(std_fp);
        if (fsz <= 0) {
            fclose(std_fp);
            return TTF_ERR_IO;
        }
        if (fseek(std_fp, 0, SEEK_SET) != 0) {
            fclose(std_fp);
            return TTF_ERR_IO;
        }
        uint8_t *buf = (uint8_t *)luat_heap_malloc((size_t)fsz);
        if (!buf) {
            fclose(std_fp);
            return TTF_ERR_OOM;
        }
        size_t n = fread(buf, 1, (size_t)fsz, std_fp);
        fclose(std_fp);
        if (n != (size_t)fsz) {
            luat_heap_free(buf);
            return TTF_ERR_IO;
        }
        *out_data = buf;
        *out_size = (size_t)fsz;
        return TTF_OK;
#else
        return TTF_ERR_IO;
#endif
    }

    if (luat_fs_fseek(fp, 0, SEEK_END) != 0) {
        luat_fs_fclose(fp);
        return TTF_ERR_IO;
    }
    long vsize = luat_fs_ftell(fp);
    if (vsize <= 0) {
        luat_fs_fclose(fp);
        return TTF_ERR_IO;
    }
    if (luat_fs_fseek(fp, 0, SEEK_SET) != 0) {
        luat_fs_fclose(fp);
        return TTF_ERR_IO;
    }
    uint8_t *buf = (uint8_t *)luat_heap_malloc((size_t)vsize);
    if (!buf) {
        luat_fs_fclose(fp);
        return TTF_ERR_OOM;
    }
    size_t n = luat_fs_fread(buf, 1, (size_t)vsize, fp);
    luat_fs_fclose(fp);
    if (n != (size_t)vsize) {
        luat_heap_free(buf);
        return TTF_ERR_IO;
    }
    *out_data = buf;
    *out_size = (size_t)vsize;
    return TTF_OK;
}

static void hzfont_cache_destroy(void) {
    if (g_hzfont_cache && g_hzfont_cache_capacity) {
        for (size_t i = 0; i < g_hzfont_cache_capacity; ++i) {
            hzfont_cache_entry_t *entry = &g_hzfont_cache[i];
            if (entry->in_use && entry->bitmap.pixels) {
                ttf_free_bitmap(&entry->bitmap);
            }
        }
        luat_heap_free(g_hzfont_cache);
    }
    g_hzfont_cache = NULL;
    g_hzfont_cache_capacity = 0;

    if (g_hzfont_cp_cache && g_hzfont_cp_cache_size) {
        luat_heap_free(g_hzfont_cp_cache);
    }
    g_hzfont_cp_cache = NULL;
    g_hzfont_cp_cache_size = 0;
    g_hzfont_cache_stamp = 0;
}

static int hzfont_setup_caches(uint32_t capacity) {
    uint32_t cap = hzfont_is_allowed_capacity(capacity) ? capacity : HZFONT_CACHE_DEFAULT;
    if (!hzfont_is_allowed_capacity(capacity) && !g_warn_cache_invalid) {
        LLOGW("hzfont event=init cache_size_invalid=%lu use_default=%lu", (unsigned long)capacity, (unsigned long)cap);
        g_warn_cache_invalid = 1;
    }

    if (g_hzfont_cache_capacity == cap && g_hzfont_cache && g_hzfont_cp_cache && g_hzfont_cp_cache_size == cap) {
        memset(g_hzfont_cache, 0, sizeof(hzfont_cache_entry_t) * cap);
        memset(g_hzfont_cp_cache, 0, sizeof(hzfont_cp_cache_entry_t) * cap);
        g_hzfont_cache_stamp = 0;
        return 1;
    }

    hzfont_cache_destroy();

    g_hzfont_cache = (hzfont_cache_entry_t *)luat_heap_malloc(sizeof(hzfont_cache_entry_t) * cap);
    if (!g_hzfont_cache) {
        return 0;
    }
    memset(g_hzfont_cache, 0, sizeof(hzfont_cache_entry_t) * cap);
    g_hzfont_cache_capacity = cap;

    /* 码点缓存大小与位图缓存容量保持一致，且为 2 的幂 */
    g_hzfont_cp_cache = (hzfont_cp_cache_entry_t *)luat_heap_malloc(sizeof(hzfont_cp_cache_entry_t) * cap);
    if (!g_hzfont_cp_cache) {
        luat_heap_free(g_hzfont_cache);
        g_hzfont_cache = NULL;
        g_hzfont_cache_capacity = 0;
        return 0;
    }
    memset(g_hzfont_cp_cache, 0, sizeof(hzfont_cp_cache_entry_t) * cap);
    g_hzfont_cp_cache_size = cap;
    g_hzfont_cache_stamp = 0;
    return 1;
}

static void hzfont_cp_cache_clear(void) {
    if (g_hzfont_cp_cache && g_hzfont_cp_cache_size) {
        memset(g_hzfont_cp_cache, 0, sizeof(hzfont_cp_cache_entry_t) * g_hzfont_cp_cache_size);
    }
}

static void hzfont_cache_clear(void) {
    if (g_hzfont_cache && g_hzfont_cache_capacity) {
        for (size_t i = 0; i < g_hzfont_cache_capacity; ++i) {
            hzfont_cache_entry_t *entry = &g_hzfont_cache[i];
            if (entry->in_use) {
                if (entry->bitmap.pixels) {
                    ttf_free_bitmap(&entry->bitmap);
                }
                memset(entry, 0, sizeof(*entry));
            }
        }
    }
    hzfont_cp_cache_clear();
    g_hzfont_cache_stamp = 0;
}

static void hzfont_cache_touch(hzfont_cache_entry_t *entry) {
    if (!entry) {
        return;
    }
    entry->last_used = hzfont_next_stamp();
}

static hzfont_cache_entry_t *hzfont_cache_find(uint16_t glyph_index, uint8_t font_size, uint8_t supersample) {
    if (!g_hzfont_cache || g_hzfont_cache_capacity == 0) {
        return NULL;
    }
    for (size_t i = 0; i < g_hzfont_cache_capacity; ++i) {
        hzfont_cache_entry_t *entry = &g_hzfont_cache[i];
        if (entry->in_use &&
            entry->glyph_index == glyph_index &&
            entry->font_size == font_size &&
            entry->supersample == supersample) {
            return entry;
        }
    }
    return NULL;
}

static hzfont_cache_entry_t *hzfont_cache_get(uint16_t glyph_index, uint8_t font_size, uint8_t supersample) {
    hzfont_cache_entry_t *entry = hzfont_cache_find(glyph_index, font_size, supersample);
    if (entry) {
        hzfont_cache_touch(entry);
    }
    return entry;
}

static hzfont_cache_entry_t *hzfont_cache_allocate_slot(void) {
    if (!g_hzfont_cache || g_hzfont_cache_capacity == 0) {
        return NULL;
    }
    for (size_t i = 0; i < g_hzfont_cache_capacity; ++i) {
        if (!g_hzfont_cache[i].in_use) {
            return &g_hzfont_cache[i];
        }
    }
    uint32_t oldest = UINT32_MAX;
    size_t oldest_index = 0;
    for (size_t i = 0; i < g_hzfont_cache_capacity; ++i) {
        if (g_hzfont_cache[i].last_used < oldest) {
            oldest = g_hzfont_cache[i].last_used;
            oldest_index = i;
        }
    }
    hzfont_cache_entry_t *entry = &g_hzfont_cache[oldest_index];
    if (entry->in_use && entry->bitmap.pixels) {
        ttf_free_bitmap(&entry->bitmap);
    }
    memset(entry, 0, sizeof(*entry));
    return entry;
}

static hzfont_cache_entry_t *hzfont_cache_insert(uint16_t glyph_index, uint8_t font_size,
                                                     uint8_t supersample, TtfBitmap *bitmap) {
    if (!bitmap || !bitmap->pixels) {
        return NULL;
    }
    hzfont_cache_entry_t *entry = hzfont_cache_find(glyph_index, font_size, supersample);
    if (!entry) {
        entry = hzfont_cache_allocate_slot();
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
    hzfont_cache_touch(entry);
    return entry;
}

static hzfont_cp_cache_entry_t *hzfont_cp_cache_lookup(uint32_t codepoint) {
    if (!g_hzfont_cp_cache || g_hzfont_cp_cache_size == 0) {
        return NULL;
    }
    uint32_t mask = g_hzfont_cp_cache_size - 1u;
    uint32_t start = (uint32_t)((codepoint * 2654435761u) & mask);
    for (uint32_t probe = 0; probe < g_hzfont_cp_cache_size; ++probe) {
        hzfont_cp_cache_entry_t *entry = &g_hzfont_cp_cache[(start + probe) & mask];
        if (!entry->in_use) {
            return NULL;
        }
        if (entry->codepoint == codepoint) {
            entry->last_used = hzfont_next_stamp();
            return entry;
        }
    }
    return NULL;
}

static void hzfont_cp_cache_insert(uint32_t codepoint, uint16_t glyph_index) {
    if (!g_hzfont_cp_cache || g_hzfont_cp_cache_size == 0) {
        return;
    }
    uint32_t mask = g_hzfont_cp_cache_size - 1u;
    uint32_t start = (uint32_t)((codepoint * 2654435761u) & mask);
    hzfont_cp_cache_entry_t *empty_slot = NULL;
    for (uint32_t probe = 0; probe < g_hzfont_cp_cache_size; ++probe) {
        hzfont_cp_cache_entry_t *entry = &g_hzfont_cp_cache[(start + probe) & mask];
        if (!entry->in_use) {
            empty_slot = entry;
            break;
        }
        if (entry->codepoint == codepoint) {
            entry->glyph_index = glyph_index;
            entry->last_used = hzfont_next_stamp();
            return;
        }
    }
    hzfont_cp_cache_entry_t *target = empty_slot;
    if (!target) {
        uint32_t oldest = UINT32_MAX;
        size_t oldest_idx = 0;
        for (size_t i = 0; i < g_hzfont_cp_cache_size; ++i) {
            if (g_hzfont_cp_cache[i].last_used < oldest) {
                oldest = g_hzfont_cp_cache[i].last_used;
                oldest_idx = i;
            }
        }
        target = &g_hzfont_cp_cache[oldest_idx];
    }
    target->codepoint = codepoint;
    target->glyph_index = glyph_index;
    target->in_use = 1;
    target->last_used = hzfont_next_stamp();
}

static uint32_t hzfont_calc_fallback_advance(unsigned char font_size) {
    float adv = (float)font_size * HZFONT_ADVANCE_RATIO;
    if (adv < 1.0f) {
        adv = 1.0f;
    }
    return (uint32_t)ceilf(adv);
}

static uint32_t hzfont_default_ascent(unsigned char font_size) {
    float asc = (float)font_size * HZFONT_ASCENT_RATIO;
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

static rgb24_t hzfont_decode_input_color(uint32_t color) {
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

static rgb24_t hzfont_decode_luat_color(const luat_lcd_conf_t *conf, luat_color_t color) {
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

static luat_color_t hzfont_encode_color(const luat_lcd_conf_t *conf, uint8_t r, uint8_t g, uint8_t b) {
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

static luat_color_t hzfont_coverage_to_color(uint8_t coverage, const luat_lcd_conf_t *conf,
                                               const rgb24_t *fg, const rgb24_t *bg) {
    if (coverage == 0) {
        return 0;
    }
    uint32_t inv = 255u - (uint32_t)coverage;
    uint32_t rr = ((uint32_t)fg->r * coverage + (uint32_t)bg->r * inv) / 255u;
    uint32_t gg = ((uint32_t)fg->g * coverage + (uint32_t)bg->g * inv) / 255u;
    uint32_t bb = ((uint32_t)fg->b * coverage + (uint32_t)bg->b * inv) / 255u;
    return hzfont_encode_color(conf, (uint8_t)rr, (uint8_t)gg, (uint8_t)bb);
}

/* 初始化字体库
 * What: 加载 TTF（外部/内置），可选整包读入 PSRAM，建立码点与位图缓存。
 * Pre: 需要有效的 ttf_path 或启用内置字库宏；cache_size 仅允许 128/256/512/1024/2048；load_to_psram=1 时需有足够 RAM。
 * Post: 状态置为 READY，后续方可测宽/绘制；失败时状态为 ERROR。
 */
int luat_hzfont_init(const char *ttf_path, uint32_t cache_size, int load_to_psram) {
    if (g_ft_ctx.state == LUAT_HZFONT_STATE_READY) {
        LLOGE("font already initialized");
        return 0;
    }

    /* 分配/重置缓存 */
    if (!hzfont_setup_caches(cache_size)) {
        LLOGE("cache alloc fail size=%lu", (unsigned long)cache_size);
        return 0;
    }
    hzfont_cache_clear();
    memset(&g_ft_ctx.font, 0, sizeof(g_ft_ctx.font));

    int rc = TTF_ERR_RANGE;
    uint8_t *ram_buf = NULL;
    size_t ram_size = 0;
    if (ttf_path && ttf_path[0]) {
        if (load_to_psram) {
            rc = hzfont_load_file_to_ram(ttf_path, &ram_buf, &ram_size);
            if (rc == TTF_OK) {
                rc = ttf_load_from_memory(ram_buf, ram_size, &g_ft_ctx.font);
                if (rc == TTF_OK) {
                    g_ft_ctx.font.ownsData = 1; /* 允许 ttf_unload 释放 */
                    g_ft_ctx.font_path[0] = 0;
                    strncpy(g_ft_ctx.font_path, ttf_path, sizeof(g_ft_ctx.font_path) - 1);
                    g_ft_ctx.font_path[sizeof(g_ft_ctx.font_path) - 1] = 0;
                } else {
                    luat_heap_free(ram_buf);
                    ram_buf = NULL;
                }
            }
        } else {
            rc = ttf_load_from_file(ttf_path, &g_ft_ctx.font);
            if (rc == TTF_OK) {
                strncpy(g_ft_ctx.font_path, ttf_path, sizeof(g_ft_ctx.font_path) - 1);
                g_ft_ctx.font_path[sizeof(g_ft_ctx.font_path) - 1] = 0;
            }
        }
    } else {
#ifdef LUAT_CONF_USE_HZFONT_BUILTIN_TTF
        if (load_to_psram) {
            ram_buf = (uint8_t *)luat_heap_malloc((size_t)hzfont_builtin_ttf_len);
            if (!ram_buf) {
                rc = TTF_ERR_OOM;
            } else {
                memcpy(ram_buf, hzfont_builtin_ttf, (size_t)hzfont_builtin_ttf_len);
                ram_size = (size_t)hzfont_builtin_ttf_len;
                rc = ttf_load_from_memory(ram_buf, ram_size, &g_ft_ctx.font);
                if (rc == TTF_OK) {
                    g_ft_ctx.font.ownsData = 1;
                    g_ft_ctx.font_path[0] = '\0';
                } else {
                    luat_heap_free(ram_buf);
                    ram_buf = NULL;
                }
            }
        } else {
            rc = ttf_load_from_memory(hzfont_builtin_ttf, (size_t)hzfont_builtin_ttf_len, &g_ft_ctx.font);
            if (rc == TTF_OK) {
                g_ft_ctx.font_path[0] = '\0';
            }
        }
#else
        LLOGE("empty ttf path and no builtin ttf");
        rc = TTF_ERR_RANGE;
#endif
    }

    if (rc != TTF_OK) {
        LLOGE("load font fail rc=%d", rc);
        ttf_unload(&g_ft_ctx.font);
        g_ft_ctx.state = LUAT_HZFONT_STATE_ERROR;
        return 0;
    }
    g_ft_ctx.state = LUAT_HZFONT_STATE_READY;
    LLOGI("font loaded units_per_em=%u glyphs=%u", g_ft_ctx.font.unitsPerEm, g_ft_ctx.font.numGlyphs);
    return 1;
}

void luat_hzfont_deinit(void) {
    if (g_ft_ctx.state == LUAT_HZFONT_STATE_UNINIT) {
        return;
    }
    hzfont_cache_clear();
    ttf_unload(&g_ft_ctx.font);
    hzfont_cache_destroy();
    memset(&g_ft_ctx, 0, sizeof(g_ft_ctx));
    g_ft_ctx.state = LUAT_HZFONT_STATE_UNINIT;
}

luat_hzfont_state_t luat_hzfont_get_state(void) {
    return g_ft_ctx.state;
}

static uint32_t hzfont_glyph_estimate_width_px(const TtfGlyph *glyph, float scale) {
    if (!glyph || glyph->pointCount == 0 || glyph->contourCount == 0) {
        return 0;
    }
    float widthF = (glyph->maxX - glyph->minX) * scale + 2.0f;
    if (widthF < 1.0f) {
        widthF = 1.0f;
    }
    return (uint32_t)ceilf(widthF);
}

uint32_t luat_hzfont_get_str_width(const char *utf8, unsigned char font_size) {
    if (!utf8 || font_size == 0 || g_ft_ctx.state != LUAT_HZFONT_STATE_READY) {
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
            if (cp == ' ' || cp == '\t') {
                total += hzfont_calc_fallback_advance(font_size);
                continue;
            }
            uint16_t star_index = 0;
            if (ttf_lookup_glyph_index(&g_ft_ctx.font, (uint32_t)'*', &star_index) == TTF_OK) {
                TtfGlyph star_glyph;
                int rc2 = ttf_load_glyph(&g_ft_ctx.font, star_index, &star_glyph);
                if (rc2 == TTF_OK) {
                    uint32_t width = hzfont_glyph_estimate_width_px(&star_glyph, scale);
                    ttf_free_glyph(&star_glyph);
                    if (width == 0) {
                        width = hzfont_calc_fallback_advance(font_size);
                    }
                    total += width;
                    continue;
                }
            }
            total += hzfont_calc_fallback_advance(font_size);
            continue;
        }

        TtfGlyph glyph;
        int rc = ttf_load_glyph(&g_ft_ctx.font, glyph_index, &glyph);
        if (rc != TTF_OK) {
            total += hzfont_calc_fallback_advance(font_size);
            continue;
        }
        uint32_t width = hzfont_glyph_estimate_width_px(&glyph, scale);
        ttf_free_glyph(&glyph);
        if (width == 0) {
            width = hzfont_calc_fallback_advance(font_size);
        }
        total += width;
    }
    return total;
}

static void hzfont_release_glyphs(glyph_render_t *glyphs, size_t count) {
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

static inline int hzfont_pick_antialias_auto(unsigned char font_size) {
    /* 规则：<=12 无抗锯齿 ，>12 用2x2超采样抗锯齿 */
    return (font_size <= 12) ? 1 : 2;
}

int luat_hzfont_draw_utf8(int x, int y, const char *utf8, unsigned char font_size, uint32_t color, int antialias) {
    if (!utf8 || font_size == 0) {
        if (!g_warn_fontsize) {
            LLOGE("hzfont event=draw invalid_font_size=%u range=1..255", (unsigned)font_size);
            g_warn_fontsize = 1;
        }
        return -1;
    }
    if (g_ft_ctx.state != LUAT_HZFONT_STATE_READY) {
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
    // 处理抗锯齿（antialias）方式的选择与设置（副作用：临时修改全局 supersample_rate，后面会恢复）
    // antialias < 0   ：自动选择（根据字体大小决定抗锯齿等级，见hzfont_pick_antialias_auto）
    // antialias <= 1  ：关闭抗锯齿（1x，即无抗锯齿）
    // antialias == 2  ：2x2超采样抗锯齿
    // antialias > 2   ：4x4超采样抗锯齿
    int prev_rate = ttf_get_supersample_rate();
    int new_rate = prev_rate;
    if (antialias < 0) {
        // 自动选择AA等级
        new_rate = hzfont_pick_antialias_auto(font_size);
    } else if (antialias <= 1) {
        new_rate = 1;
    } else if (antialias == 2) {
        new_rate = 2;
    } else {
        new_rate = 4;
    }
    if (new_rate != prev_rate) {
        (void)ttf_set_supersample_rate(new_rate);
    }
    uint64_t func_start_ts = timing_enabled ? hzfont_now_us() : 0;
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
    uint32_t default_ascent = hzfont_default_ascent(font_size);
    while (cursor < end && glyph_count < utf8_len) {
        uint32_t cp = 0;
        if (!utf8_decode_next(&cursor, end, &cp)) {
            break;
        }
        if (cp == '\r' || cp == '\n') {
            continue;
        }

        glyph_render_t *slot = &glyphs[glyph_count];
        slot->advance = hzfont_calc_fallback_advance(font_size);
        slot->has_bitmap = 0;
        memset(&slot->bitmap, 0, sizeof(slot->bitmap));
        slot->codepoint = cp;
        slot->glyph_index = 0;
        slot->time_lookup_us = 0;
        slot->time_load_us = 0;
        slot->time_raster_us = 0;
        slot->time_draw_us = 0;
        slot->from_cache = 0;
        slot->status = HZFONT_GLYPH_LOOKUP_FAIL;

        uint64_t glyph_stamp = timing_enabled ? hzfont_now_us() : 0;

        uint16_t glyph_index = 0;
        int rc = TTF_OK;
        hzfont_cp_cache_entry_t *cp_entry = hzfont_cp_cache_lookup(cp);
        if (cp_entry) {
            glyph_index = cp_entry->glyph_index;
            if (timing_enabled) {
                slot->time_lookup_us = glyph_stamp ? hzfont_elapsed_step(&glyph_stamp) : 0;
                sum_lookup_us += slot->time_lookup_us;
            }
        } else {
            rc = ttf_lookup_glyph_index(&g_ft_ctx.font, cp, &glyph_index);
            if (timing_enabled) {
                slot->time_lookup_us = glyph_stamp ? hzfont_elapsed_step(&glyph_stamp) : 0;
                sum_lookup_us += slot->time_lookup_us;
            }
            if (rc != TTF_OK) {
                uint16_t star_index = 0;
                if (ttf_lookup_glyph_index(&g_ft_ctx.font, (uint32_t)'*', &star_index) == TTF_OK) {
                    glyph_index = star_index;
                    // 不把原cp写入codepoint缓存，避免误缓存
                } else {
                    glyph_count++;
                    continue;
                }
            } else {
                hzfont_cp_cache_insert(cp, glyph_index);
            }
        }

        slot->glyph_index = glyph_index;
        slot->status = HZFONT_GLYPH_LOAD_FAIL;

        uint8_t supersample = (uint8_t)ttf_get_supersample_rate();
        hzfont_cache_entry_t *cache_entry = hzfont_cache_get(glyph_index, (uint8_t)font_size, supersample);
        if (cache_entry) {
            slot->bitmap = cache_entry->bitmap;
            slot->from_cache = 1;
            slot->status = HZFONT_GLYPH_OK;
        } else {
            TtfGlyph glyph;
            rc = ttf_load_glyph(&g_ft_ctx.font, glyph_index, &glyph);
            if (timing_enabled) {
                slot->time_load_us = glyph_stamp ? hzfont_elapsed_step(&glyph_stamp) : 0;
                sum_load_us += slot->time_load_us;
            }
            if (rc != TTF_OK) {
                glyph_count++;
                continue;
            }

            slot->status = HZFONT_GLYPH_RASTER_FAIL;
            rc = ttf_rasterize_glyph(&g_ft_ctx.font, &glyph, font_size, &slot->bitmap);
            if (timing_enabled) {
                slot->time_raster_us = glyph_stamp ? hzfont_elapsed_step(&glyph_stamp) : 0;
                sum_raster_us += slot->time_raster_us;
            }
            ttf_free_glyph(&glyph);
            if (rc != TTF_OK) {
                glyph_count++;
                continue;
            }

            slot->status = HZFONT_GLYPH_OK;
            hzfont_cache_entry_t *new_entry = hzfont_cache_insert(glyph_index, (uint8_t)font_size, supersample, &slot->bitmap);
            if (new_entry) {
                slot->from_cache = 1;
                slot->bitmap = new_entry->bitmap;
            }
        }

        if (slot->bitmap.width > 0 && slot->bitmap.height > 0 && slot->bitmap.pixels) {
            slot->has_bitmap = 1;
            slot->advance = slot->bitmap.width;
            if (slot->advance == 0) {
                slot->advance = hzfont_calc_fallback_advance(font_size);
            }
        } else {
            slot->bitmap.originY = (int32_t)default_ascent;
        }
        glyph_count++;
    }

    rgb24_t fg = hzfont_decode_input_color(color);
    rgb24_t bg = hzfont_decode_luat_color(lcd_dft_conf, BACK_COLOR);

    int pen_x = x;

    for (size_t i = 0; i < glyph_count; i++) {
        glyph_render_t *slot = &glyphs[i];
        uint32_t advance = slot->advance;
        slot->advance = advance;
        if (!slot->has_bitmap) {
            if (slot->bitmap.originY == 0) {
                slot->bitmap.originY = (int32_t)default_ascent;
            }
            if (timing_enabled) {
                slot->time_draw_us = 0;
            }
            pen_x += (int)slot->advance;
            goto glyph_timing_update;
        }

        uint64_t draw_stamp = timing_enabled ? hzfont_now_us() : 0;
        int draw_x = pen_x;
        int draw_y_base = y - (int)slot->bitmap.originY;

        size_t row_buf_capacity = (size_t)slot->bitmap.width;
        if (row_buf_capacity == 0) {
            if (timing_enabled && draw_stamp) {
                slot->time_draw_us = hzfont_elapsed_from(draw_stamp);
                sum_draw_us += slot->time_draw_us;
            }
            pen_x += (int)slot->advance;
            goto glyph_timing_update;
        }

        /* 行缓冲按行申请/复用，绘制后立即释放，避免长生命周期占用 */
        luat_color_t *row_buf = (luat_color_t *)luat_heap_malloc(row_buf_capacity * sizeof(luat_color_t));
        if (!row_buf) {
            if (timing_enabled && draw_stamp) {
                slot->time_draw_us = hzfont_elapsed_from(draw_stamp);
                sum_draw_us += slot->time_draw_us;
            }
            slot->status = HZFONT_GLYPH_DRAW_FAIL;
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
                    row_buf[run_len++] = hzfont_coverage_to_color(row_pixels[col], lcd_dft_conf, &fg, &bg);
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
            slot->time_draw_us = hzfont_elapsed_from(draw_stamp);
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
            if (slot->has_bitmap && slot->status == HZFONT_GLYPH_OK) {
                sum_rendered_total_us += glyph_total64;
            }
            uint32_t glyph_total32 = hzfont_clamp_u32(glyph_total64);
            if (glyph_total32 > max_glyph_total_us) {
                max_glyph_total_us = glyph_total32;
                max_slot_index = i;
            }
            if (glyph_total32 >= HZFONT_TIMING_THRESHOLD_US || slot->status != HZFONT_GLYPH_OK) {
                LLOGI("glyph[%u] cp=U+%04lX idx=%u status=%s total=%luus lookup=%lu load=%lu raster=%lu draw=%lu",
                      (unsigned)i,
                      (unsigned long)slot->codepoint,
                      (unsigned)slot->glyph_index,
                      hzfont_status_text(slot->status),
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

    /* 恢复超采样率，避免影响外部绘制 */
    if (new_rate != prev_rate) {
        int restore = ttf_set_supersample_rate(prev_rate);
        if (restore != prev_rate) {
            LLOGE("hzfont event=draw restore_supersample_fail prev=%d got=%d", prev_rate, restore);
        }
    }
    if (timing_enabled) {
        uint32_t total_us = hzfont_elapsed_from(func_start_ts);
        uint32_t sum_lookup32 = hzfont_clamp_u32(sum_lookup_us);
        uint32_t sum_load32 = hzfont_clamp_u32(sum_load_us);
        uint32_t sum_raster32 = hzfont_clamp_u32(sum_raster_us);
        uint32_t sum_draw32 = hzfont_clamp_u32(sum_draw_us);
        uint32_t avg_all_us = profiled_glyphs ? hzfont_clamp_u32(sum_total_us / profiled_glyphs) : 0;
        uint32_t avg_rendered_us = rendered_count ? hzfont_clamp_u32(sum_rendered_total_us / rendered_count) : 0;
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
            uint32_t glyph_total32 = hzfont_clamp_u32((uint64_t)max_slot->time_lookup_us +
                                                        (uint64_t)max_slot->time_load_us +
                                                        (uint64_t)max_slot->time_raster_us +
                                                        (uint64_t)max_slot->time_draw_us);
            LLOGI("timing max glyph idx=%u cp=U+%04lX status=%s total=%luus lookup=%lu load=%lu raster=%lu draw=%lu",
                  (unsigned)max_slot_index,
                  (unsigned long)max_slot->codepoint,
                  hzfont_status_text(max_slot->status),
                  (unsigned long)glyph_total32,
                  (unsigned long)max_slot->time_lookup_us,
                  (unsigned long)max_slot->time_load_us,
                  (unsigned long)max_slot->time_raster_us,
                  (unsigned long)max_slot->time_draw_us);
        }
    }

    hzfont_release_glyphs(glyphs, glyph_count);
    return result;
}
