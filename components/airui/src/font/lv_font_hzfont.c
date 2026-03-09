// 负责：LVGL 适配 HZFont (TTF) 渲染驱动实现

#include "lvgl9/lvgl.h"
#include "luat_base.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "airui.hzfont"
#include "luat_log.h"

#if defined(LUAT_USE_AIRUI) && defined(LUAT_USE_HZFONT)

#include "luat_hzfont.h"
#include "ttf_parser.h"

/**
 * HZFont 字体描述私有数据结构 
 */
typedef struct {
    uint16_t font_size; /**< 默认字号 */
    uint8_t antialias;  /**< 抗锯齿等级 (1, 2, 3) */
    TtfFont *ttf;       /**< 底层 TTF 句柄引用 */
    uint16_t *render_size; /**< 动态渲染字号引用 */
} lv_font_hzfont_dsc_t;

static lv_font_t *g_airui_hzfont_font = NULL; // 共享字体对象
static lv_font_hzfont_dsc_t *g_airui_hzfont_dsc = NULL; // 共享字体描述对象
static uint16_t g_airui_hzfont_render_size = 16; // 共享渲染字号
static const int g_airui_hzfont_extra_leading = 3; // 共享额外行高

// 字符串渲染耗时统计
typedef struct {
    uint8_t active;
    uint64_t start_us;
    uint32_t glyph_count;
    uint32_t cache_hit_count;
    uint32_t rasterized_count;
    uint64_t sum_lookup_us;
    uint64_t sum_load_us;
    uint64_t sum_raster_us;
    uint64_t sum_draw_us;
    char text_preview[64];
    uint8_t text_truncated;
} airui_hzfont_label_prof_t;

// 字符串渲染耗时统计全局变量
static airui_hzfont_label_prof_t g_airui_hzfont_label_prof;

// 获取当前时间戳
static uint64_t airui_hzfont_now_us(void) {
    int period = luat_mcu_us_period();
    if (period <= 0) {
        return luat_mcu_tick64_ms() * 1000ULL;
    }
    return luat_mcu_tick64() / (uint64_t)period;
}

// 计算时间差
static uint32_t airui_hzfont_elapsed_us(uint64_t start) {
    if (start == 0) {
        return 0;
    }
    uint64_t now = airui_hzfont_now_us();
    if (now <= start) {
        return 0;
    }
    uint64_t diff = now - start;
    if (diff > UINT32_MAX) {
        return UINT32_MAX;
    }
    return (uint32_t)diff;
}

// 构建日志预览
static int airui_hzfont_build_log_preview(const char *utf8, size_t utf8_len, char *out_buf, size_t buf_size, size_t max_chars) {
    if (!out_buf || buf_size == 0) {
        return 0;
    }
    if (!utf8 || utf8_len == 0 || max_chars == 0) {
        out_buf[0] = '\0';
        return 0;
    }
    const unsigned char *cursor = (const unsigned char *)utf8;
    const unsigned char *end = cursor + utf8_len;
    size_t len = 0;
    size_t chars = 0;
    while (cursor < end && chars < max_chars) {
        const unsigned char *segment_start = cursor;
        unsigned char c0 = *cursor++;
        if (c0 >= 0x80) {
            if ((c0 & 0xE0) == 0xC0) {
                if (cursor < end && ((*cursor & 0xC0) == 0x80)) {
                    cursor++;
                }
            }
            else if ((c0 & 0xF0) == 0xE0) {
                if (cursor < end && ((*cursor & 0xC0) == 0x80)) {
                    cursor++;
                }
                if (cursor < end && ((*cursor & 0xC0) == 0x80)) {
                    cursor++;
                }
            }
            else if ((c0 & 0xF8) == 0xF0) {
                if (cursor < end && ((*cursor & 0xC0) == 0x80)) {
                    cursor++;
                }
                if (cursor < end && ((*cursor & 0xC0) == 0x80)) {
                    cursor++;
                }
                if (cursor < end && ((*cursor & 0xC0) == 0x80)) {
                    cursor++;
                }
            }
        }
        size_t segment_len = cursor - segment_start;
        if (len + segment_len >= buf_size) {
            break;
        }
        memcpy(out_buf + len, segment_start, segment_len);
        len += segment_len;
        chars++;
    }
    if (len >= buf_size) {
        len = buf_size - 1;
    }
    out_buf[len] = '\0';
    return cursor < end;
}

// 开始一次 label 场景的 hzfont 调试统计会话
void airui_font_hzfont_prof_begin(const char *text) {
    memset(&g_airui_hzfont_label_prof, 0, sizeof(g_airui_hzfont_label_prof));
    if (!ttf_get_debug()) {
        return;
    }
    g_airui_hzfont_label_prof.active = 1;
    g_airui_hzfont_label_prof.start_us = airui_hzfont_now_us();
    if (text) {
        size_t text_len = strlen(text);
        g_airui_hzfont_label_prof.text_truncated = (uint8_t)airui_hzfont_build_log_preview(text, text_len,
            g_airui_hzfont_label_prof.text_preview, sizeof(g_airui_hzfont_label_prof.text_preview), 10);
    }
}

// 结束当前 label 场景的 hzfont 调试统计并打印汇总日志
void airui_font_hzfont_prof_end(void) {
    if (!g_airui_hzfont_label_prof.active || !ttf_get_debug()) {
        memset(&g_airui_hzfont_label_prof, 0, sizeof(g_airui_hzfont_label_prof));
        return;
    }
    uint32_t total_us = airui_hzfont_elapsed_us(g_airui_hzfont_label_prof.start_us);
    uint64_t used_us = g_airui_hzfont_label_prof.sum_lookup_us +
                       g_airui_hzfont_label_prof.sum_load_us +
                       g_airui_hzfont_label_prof.sum_raster_us +
                       g_airui_hzfont_label_prof.sum_draw_us;
    uint64_t other_us = total_us > used_us ? (uint64_t)total_us - used_us : 0;
    LLOGI("字符串=%s%s 绘制的字符数=%u 缓存获取的字符数=%u 栅格化获取的字符数=%u 字符绘制总耗时=%.3f ms 查找总耗时=%.3f ms 加载总耗时=%.3f ms 栅格化总耗时=%.3f ms lcd绘制总耗时=%.3f ms 其它耗时=%.3f ms",
          g_airui_hzfont_label_prof.text_preview,
          g_airui_hzfont_label_prof.text_truncated ? "***" : "",
          (unsigned)g_airui_hzfont_label_prof.glyph_count,
          (unsigned)g_airui_hzfont_label_prof.cache_hit_count,
          (unsigned)g_airui_hzfont_label_prof.rasterized_count,
          (double)total_us / 1000.0,
          (double)g_airui_hzfont_label_prof.sum_lookup_us / 1000.0,
          (double)g_airui_hzfont_label_prof.sum_load_us / 1000.0,
          (double)g_airui_hzfont_label_prof.sum_raster_us / 1000.0,
          (double)g_airui_hzfont_label_prof.sum_draw_us / 1000.0,
          (double)other_us / 1000.0);
    memset(&g_airui_hzfont_label_prof, 0, sizeof(g_airui_hzfont_label_prof));
}

// 计算默认 ascent
static uint16_t hzfont_default_ascent(uint16_t font_size) {
    if (font_size == 0) {
        return 0;
    }
    uint32_t asc = (uint32_t)font_size * 4u; // 0.8 = 4/5
    uint32_t value = (asc + 4u) / 5u;
    if (value == 0) {
        value = 1;
    }
    return (uint16_t)value;
}

// 获取共享渲染字号
static uint16_t hzfont_get_active_size(lv_font_hzfont_dsc_t *dsc) {
    if (dsc == NULL) {
        return 0;
    }
    if (dsc->render_size && *dsc->render_size > 0) {
        return *dsc->render_size;
    }
    return dsc->font_size;
}

/**
 * LVGL 获取字符描述回调 (Metrics)
 * @param font 字体指针
 * @param dsc_out 输出字符描述（宽高、偏移等）
 * @param letter 当前字符的 Unicode 码点
 * @param letter_next 下一个字符（用于 Kerning，暂未支持）
 * @return bool 是否成功获取
 */
static bool hzfont_get_glyph_dsc(const lv_font_t * font, lv_font_glyph_dsc_t * dsc_out, uint32_t letter, uint32_t letter_next) {
    bool ok = false;
    int timing_enabled = ttf_get_debug();
    uint64_t stage_start = 0;

    // 获取私有数据
    lv_font_hzfont_dsc_t * dsc = (lv_font_hzfont_dsc_t *)font->dsc;
    if (!dsc || !dsc->ttf) {
        goto profile_done;
    }

    // 重要：【修复点】必须先清空结构体，防止垃圾数据导致 LVGL 内部缓存系统崩溃
    // LVGL 9 的 dsc_out 包含 entry 指针，如果是随机值，回调一返回就会崩
    memset(dsc_out, 0, sizeof(lv_font_glyph_dsc_t));
    
    // 1. 码点转索引
    uint16_t glyph_index = 0;
    if (timing_enabled) {
        stage_start = airui_hzfont_now_us();
    }
    if (luat_hzfont_lookup_glyph_index(letter, &glyph_index) != TTF_OK) {
        if (timing_enabled) {
            uint32_t lookup_us = airui_hzfont_elapsed_us(stage_start);
            if (g_airui_hzfont_label_prof.active) {
                g_airui_hzfont_label_prof.sum_lookup_us += lookup_us;
            }
        }
        goto profile_done;
    }
    if (timing_enabled) {
        uint32_t lookup_us = airui_hzfont_elapsed_us(stage_start);
        if (g_airui_hzfont_label_prof.active) {
            g_airui_hzfont_label_prof.sum_lookup_us += lookup_us;
        }
    }

    // 2. 获取位图以获取精确度量 (Metrics)
    // 优先从底层引擎的 LRU 缓存中获取，避免重复渲染
    uint16_t render_size = hzfont_get_active_size(dsc);
    if (timing_enabled) {
        stage_start = airui_hzfont_now_us();
    }
    luat_hzfont_bitmap_profile_t bmp_prof;
    const TtfBitmap *bitmap = luat_hzfont_get_bitmap_profiled(glyph_index, render_size, dsc->antialias, &bmp_prof);
    if (timing_enabled) {
        (void)airui_hzfont_elapsed_us(stage_start);
        if (g_airui_hzfont_label_prof.active) {
            g_airui_hzfont_label_prof.sum_load_us += bmp_prof.load_us;
            g_airui_hzfont_label_prof.sum_raster_us += bmp_prof.raster_us;
            if (bmp_prof.cache_hit) {
                g_airui_hzfont_label_prof.cache_hit_count++;
            }
            if (bmp_prof.cache_miss && !bmp_prof.load_fail && !bmp_prof.raster_fail) {
                g_airui_hzfont_label_prof.rasterized_count++;
            }
        }
    }
    // 如果获取不到位图，则进行处理
    if (!bitmap) {
        // 空格和制表符特殊处理
        if (letter == ' ' || letter == '\t') {
            dsc_out->adv_w = render_size/2;
            dsc_out->box_w = 0;
            dsc_out->box_h = 0;
            dsc_out->format = LV_FONT_GLYPH_FORMAT_NONE;
            dsc_out->resolved_font = font;
            dsc_out->gid.index = glyph_index;
            ok = true;
            goto profile_done;
        } else {
            LLOGW("hzfont get bitmap failed");
            goto profile_done;
        }
    }

    // 3. 填充 LVGL 描述信息
    dsc_out->adv_w = (uint16_t)bitmap->width; 
    dsc_out->box_w = (uint16_t)bitmap->width;
    dsc_out->box_h = (uint16_t)bitmap->height;
    dsc_out->ofs_x = 0;
    
    // 设置每行字节数。对于 A8 格式，stride 等于像素宽度
    dsc_out->stride = dsc_out->box_w;

    // 设置解析字体，防止 Fallback 逻辑失效
    dsc_out->resolved_font = font;

    // 计算 Y 偏移。ofs_y 是字符顶端相对于基线的偏移。
    // 计算公式：字号 - 内部 originY (基线位置) - 位图高度
    dsc_out->ofs_y = (int16_t)((int32_t)bitmap->originY - (int32_t)bitmap->height);
    
    dsc_out->format = LV_FONT_GLYPH_FORMAT_A8; // HZFont 输出 A8 格式灰度图
    dsc_out->gid.index = glyph_index;

    ok = true;

profile_done:
    if (ok && timing_enabled && g_airui_hzfont_label_prof.active) {
        g_airui_hzfont_label_prof.glyph_count++;
    }
    return ok;
}

/**
 * LVGL 获取字符点阵回调 (Bitmap)
 * @param dsc_out 字符描述（包含 gid）
 * @param draw_buf 绘图缓冲区（暂未使用）
 * @return const void* 点阵数据指针
 */
static const void * hzfont_get_glyph_bitmap(lv_font_glyph_dsc_t * dsc_out, lv_draw_buf_t * draw_buf) {
    const void *result = NULL;
    int timing_enabled = ttf_get_debug();
    uint64_t stage_start = 0;

    const lv_font_t * font = dsc_out->resolved_font;
    lv_font_hzfont_dsc_t * dsc = (lv_font_hzfont_dsc_t *)font->dsc;
    if (!dsc || !dsc->ttf) {
        goto profile_done;
    }

    uint32_t glyph_index = dsc_out->gid.index;
    uint16_t render_size = hzfont_get_active_size(dsc);
    const TtfBitmap *bitmap = luat_hzfont_get_bitmap((uint16_t)glyph_index, render_size, dsc->antialias);
    if (!bitmap) {
        goto profile_done;
    }

    if (draw_buf && draw_buf->data) {
        if (timing_enabled) {
            stage_start = airui_hzfont_now_us();
        }
        uint32_t stride = draw_buf->header.stride;
        if (stride == 0) {
            stride = (uint32_t)bitmap->width;
        }
        if (stride < (uint32_t)bitmap->width) {
            stride = (uint32_t)bitmap->width;
        }

        uint32_t draw_rows = draw_buf->header.h;
        if (bitmap->height < (int32_t)draw_rows) {
            draw_rows = (uint32_t)bitmap->height;
        }

        for (uint32_t y = 0; y < draw_rows; ++y) {
            uint8_t *dst = draw_buf->data + (size_t)y * stride;
            memcpy(dst, bitmap->pixels + (size_t)y * bitmap->width, bitmap->width);
            if (stride > (uint32_t)bitmap->width) {
                memset(dst + bitmap->width, 0, stride - bitmap->width);
            }
        }

        if (draw_buf->header.h > draw_rows) {
            uint8_t *tail = draw_buf->data + (size_t)draw_rows * stride;
            size_t tail_size = (size_t)(draw_buf->header.h - draw_rows) * stride;
            memset(tail, 0, tail_size);
        }

        draw_buf->header.w = bitmap->width;
        draw_buf->header.h = bitmap->height;
        draw_buf->header.cf = LV_COLOR_FORMAT_A8;
        draw_buf->header.magic = LV_IMAGE_HEADER_MAGIC;
        draw_buf->header.stride = stride;

        if (timing_enabled && g_airui_hzfont_label_prof.active) {
            g_airui_hzfont_label_prof.sum_draw_us += airui_hzfont_elapsed_us(stage_start);
        }

        result = draw_buf;
        goto profile_done;
    }

    result = bitmap->pixels;

profile_done:
    return result;
}

/**
 * 创建 HZFont (TTF) 驱动字体对象
 * @param path TTF 文件路径（传 NULL 则尝试加载内置字库）
 * @param size 字号
 * @param cache_size 点阵缓存上限数量
 * @param antialias 抗锯齿等级 (-1: 自动, 1: 边界2x2, 2: 边界3x3, 3: 边界4x4)
 * @param load_to_psram 是否在初始化时将字库数据复制到 PSRAM（默认 false）
 * @return lv_font_t* 字体对象指针，失败返回 NULL
 */
lv_font_t * airui_font_hzfont_create(const char * path, uint16_t size, uint32_t cache_size, int antialias, bool load_to_psram) {
    uint8_t aa_mode = 1;
    // 1. 初始化底层引擎（单例模式）
    if (luat_hzfont_get_state() == LUAT_HZFONT_STATE_UNINIT) {
        if (!luat_hzfont_init(path, cache_size, (int)load_to_psram))
        {
            LLOGE("hzfont init failed: %s", path ? path : "builtin");
            return NULL;
        }
    }

    if (antialias < 0) {
        if (size <= 16) {
            aa_mode = 1;
        } else if (size <= 32) {
            aa_mode = 2;
        } else {
            aa_mode = 3;
        }
    } else if (antialias <= 1) {
        aa_mode = 1;
    } else if (antialias == 2) {
        aa_mode = 2;
    } else {
        aa_mode = 3;
    }

    // 如果共享字体对象已存在，则更新渲染字号
    if (g_airui_hzfont_font != NULL) {
        g_airui_hzfont_render_size = size;
        if (g_airui_hzfont_dsc) {
            g_airui_hzfont_dsc->antialias = aa_mode;
        }
        if (g_airui_hzfont_dsc && g_airui_hzfont_dsc->render_size) {
            *g_airui_hzfont_dsc->render_size = size;
        }
        (void)ttf_set_supersample_rate(aa_mode);
        return g_airui_hzfont_font;
    }

    // 2. 分配 LVGL 字体对象
    lv_font_t * font = lv_malloc(sizeof(lv_font_t));
    if (!font) return NULL;
    memset(font, 0, sizeof(lv_font_t));

    // 3. 构造私有描述上下文
    lv_font_hzfont_dsc_t * dsc = lv_malloc(sizeof(lv_font_hzfont_dsc_t));
    if (!dsc) {
        lv_free(font);
        LLOGI("hzfont malloc dsc failed");
        return NULL;
    }
    dsc->font_size = size;
    
    // 自动选择 AA 等级：小号 2x2，中号 3x3，大号 4x4
    dsc->antialias = aa_mode;
    (void)ttf_set_supersample_rate(dsc->antialias);
    LLOGI("hzfont antialias: %d", dsc->antialias);
    // 关联底层句柄
    dsc->ttf = luat_hzfont_get_ttf();
    // 4. 绑定 LVGL 回调
    font->dsc = dsc;
    font->get_glyph_dsc = hzfont_get_glyph_dsc;
    font->get_glyph_bitmap = hzfont_get_glyph_bitmap;
    uint16_t ascent = hzfont_default_ascent(size);
    font->line_height = size + g_airui_hzfont_extra_leading;
    font->base_line = (int32_t)font->line_height > ascent ? (int32_t)font->line_height - ascent : 0;
    font->fallback = lv_font_get_default(); //当有缺失字时，使用默认字体
    g_airui_hzfont_font = font;
    g_airui_hzfont_dsc = dsc;
    dsc->render_size = &g_airui_hzfont_render_size;
    g_airui_hzfont_render_size = size;
    return font;
}

// 获取共享字体对象
lv_font_t *airui_font_get_shared_hzfont(void)
{
    return g_airui_hzfont_font;
}

// 设置共享渲染字号
void airui_font_hzfont_set_render_size(uint16_t size)
{
    if (g_airui_hzfont_dsc == NULL || g_airui_hzfont_dsc->render_size == NULL || g_airui_hzfont_font == NULL) {
        return;
    }
    if (size == 0) {
        size = g_airui_hzfont_dsc->font_size;
    }
    *g_airui_hzfont_dsc->render_size = size;
    g_airui_hzfont_render_size = size;
    uint16_t ascent = hzfont_default_ascent(size);
    g_airui_hzfont_font->line_height = size + g_airui_hzfont_extra_leading;
    g_airui_hzfont_font->base_line = (int32_t)g_airui_hzfont_font->line_height > ascent ?
        (int32_t)g_airui_hzfont_font->line_height - ascent : 0;
}

#else

lv_font_t *airui_font_get_shared_hzfont(void)
{
    return NULL;
}

void airui_font_hzfont_set_render_size(uint16_t size)
{
    return;
}

void airui_font_hzfont_prof_begin(const char *text)
{
    (void)text;
}

void airui_font_hzfont_prof_end(void)
{
}

static bool hzfont_get_glyph_dsc(const lv_font_t * font, lv_font_glyph_dsc_t * dsc_out, uint32_t letter, uint32_t letter_next) {
    return false;
}

static const void * hzfont_get_glyph_bitmap(lv_font_glyph_dsc_t * dsc_out, lv_draw_buf_t * draw_buf) {
    return NULL;
}

lv_font_t * airui_font_hzfont_create(const char * path, uint16_t size, uint32_t cache_size, int antialias, bool load_to_psram) {
    LLOGW("该固件不支持HZFont字体");
    (void)path;
    (void)size;
    (void)cache_size;
    (void)antialias;
    (void)load_to_psram;
    return NULL;
}

#endif
