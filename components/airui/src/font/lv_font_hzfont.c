// 负责：LVGL 适配 HZFont (TTF) 渲染驱动实现

#include "lvgl9/lvgl.h"
#include "luat_base.h"

#define LUAT_LOG_TAG "airui.hzfont"
#include "luat_log.h"

#ifdef LUAT_USE_HZFONT

#include "luat_hzfont.h"
#include "ttf_parser.h"


/** 
 * HZFont 字体描述私有数据结构 
 */
typedef struct {
    uint16_t font_size; /**< 当前字号 */
    uint8_t antialias;  /**< 抗锯齿等级 (1, 2, 4) */
    TtfFont *ttf;       /**< 底层 TTF 句柄引用 */
} lv_font_hzfont_dsc_t;

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

/**
 * LVGL 获取字符描述回调 (Metrics)
 * @param font 字体指针
 * @param dsc_out 输出字符描述（宽高、偏移等）
 * @param letter 当前字符的 Unicode 码点
 * @param letter_next 下一个字符（用于 Kerning，暂未支持）
 * @return bool 是否成功获取
 */
static bool hzfont_get_glyph_dsc(const lv_font_t * font, lv_font_glyph_dsc_t * dsc_out, uint32_t letter, uint32_t letter_next) {
    // 获取私有数据
    lv_font_hzfont_dsc_t * dsc = (lv_font_hzfont_dsc_t *)font->dsc;
    if (!dsc || !dsc->ttf) return false;

    // 重要：【修复点】必须先清空结构体，防止垃圾数据导致 LVGL 内部缓存系统崩溃
    // LVGL 9 的 dsc_out 包含 entry 指针，如果是随机值，回调一返回就会崩
    memset(dsc_out, 0, sizeof(lv_font_glyph_dsc_t));
    
    // 1. 码点转索引
    uint16_t glyph_index = 0;
    if (ttf_lookup_glyph_index(dsc->ttf, letter, &glyph_index) != TTF_OK) {
        return false;
    }

    // 2. 获取位图以获取精确度量 (Metrics)
    // 优先从底层引擎的 LRU 缓存中获取，避免重复渲染
    const TtfBitmap *bitmap = luat_hzfont_get_bitmap(glyph_index, dsc->font_size, dsc->antialias);
    // 如果获取不到位图，则进行处理
    if (!bitmap) {
        // 空格和制表符特殊处理
        if (letter == ' ' || letter == '\t') {
            dsc_out->adv_w = dsc->font_size/2;
            dsc_out->box_w = 0;
            dsc_out->box_h = 0;
            dsc_out->format = LV_FONT_GLYPH_FORMAT_NONE;
            dsc_out->resolved_font = font;
            dsc_out->gid.index = glyph_index;
            return true;
        }else{
            LLOGW("hzfont get bitmap failed");
            return false;
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

    return true;
}

/**
 * LVGL 获取字符点阵回调 (Bitmap)
 * @param dsc_out 字符描述（包含 gid）
 * @param draw_buf 绘图缓冲区（暂未使用）
 * @return const void* 点阵数据指针
 */
static const void * hzfont_get_glyph_bitmap(lv_font_glyph_dsc_t * dsc_out, lv_draw_buf_t * draw_buf) {
    const lv_font_t * font = dsc_out->resolved_font;
    lv_font_hzfont_dsc_t * dsc = (lv_font_hzfont_dsc_t *)font->dsc;
    if (!dsc || !dsc->ttf) return NULL;

    uint32_t glyph_index = dsc_out->gid.index;
    const TtfBitmap *bitmap = luat_hzfont_get_bitmap((uint16_t)glyph_index, dsc->font_size, dsc->antialias);
    if (!bitmap) return NULL;

    if (draw_buf && draw_buf->data) {
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

        return draw_buf;
    }

    return bitmap->pixels;
}

/**
 * 创建 HZFont (TTF) 驱动字体对象
 * @param path TTF 文件路径（传 NULL 则尝试加载内置字库）
 * @param size 字号
 * @param cache_size 点阵缓存上限数量
 * @param antialias 抗锯齿等级 (-1: 自动, 1: 无, 2: 2x2, 4: 4x4)
 * @return lv_font_t* 字体对象指针，失败返回 NULL
 */
lv_font_t * airui_font_hzfont_create(const char * path, uint16_t size, uint32_t cache_size, int antialias) {
    // 1. 初始化底层引擎（单例模式）
    if (luat_hzfont_get_state() == LUAT_HZFONT_STATE_UNINIT) {
        if (!luat_hzfont_init(path, cache_size, 0)) // 当前默认不将hzfont加载到psram中，TODO:打开会在模拟器中有问题需要后续修复
        {
            LLOGE("hzfont init failed: %s", path ? path : "builtin");
            return NULL;
        }
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
    
    // 自动选择 AA 等级：小号字体关闭以提高清晰度，大号开启
    if (antialias < 0) {
        dsc->antialias = (size <= 12) ? 1 : 2;
    } else {
        dsc->antialias = (uint8_t)antialias;
    }
    (void)ttf_set_supersample_rate(dsc->antialias);
    LLOGI("hzfont antialias: %d", dsc->antialias);
    // 关联底层句柄
    dsc->ttf = luat_hzfont_get_ttf();
    // 4. 绑定 LVGL 回调
    font->dsc = dsc;
    font->get_glyph_dsc = hzfont_get_glyph_dsc;
    font->get_glyph_bitmap = hzfont_get_glyph_bitmap;
    uint16_t ascent = hzfont_default_ascent(size);
    // 额外增加5像素行高，防止字体显示不全
    const int extra_leading = 3;
    font->line_height = size + extra_leading;
    font->base_line = (int32_t)font->line_height > ascent ? (int32_t)font->line_height - ascent : 0;
    font->fallback = lv_font_get_default(); //当有缺失字时，使用默认字体
    return font;
}

#else

static bool hzfont_get_glyph_dsc(const lv_font_t * font, lv_font_glyph_dsc_t * dsc_out, uint32_t letter, uint32_t letter_next) {
    return false;
}

static const void * hzfont_get_glyph_bitmap(lv_font_glyph_dsc_t * dsc_out, lv_draw_buf_t * draw_buf) {
    return NULL;
}

lv_font_t * airui_font_hzfont_create(const char * path, uint16_t size, uint32_t cache_size, int antialias) {
    LLOGW("该固件不支持HZFont字体");
    return NULL;
}

#endif