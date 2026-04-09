/**
 * HzFont U8G2适配器实现
 * @file    hzfont_u8g2_adapter.c
 * @brief   为U8G2图形库提供HzFont矢量字体适配支持
 * @author  wjq
 * @date    2026-4-9
 * @version 1.0
 */

#include "hzfont_u8g2_adapter.h"
#include "luat_hzfont.h"
#include "luat_log.h"
#include "luat_mem.h"
#include <string.h>
#include <stdlib.h>

#define LUAT_LOG_TAG "hzfont_u8g2"

// 最小和最大字号
#define HZFONT_MIN_SIZE  12
#define HZFONT_MAX_SIZE  255

// 默认灰度阈值
#define HZFONT_DEFAULT_THRESHOLD 128

/**
 * U8G2用户数据结构
 * 用于在u8g2上下文中存储HzFont相关信息
 */
typedef struct {
    void* hzfont;                    /**< HzFont字体对象 */
    uint8_t is_hzfont_enabled;        /**< 是否启用HzFont */
} u8g2_hzfont_userdata_t;

/**
 * 初始化HzFont U8G2适配器
 */
int hzfont_u8g2_adapter_init(void) {
    LLOGD("HzFont U8G2 adapter initialized");
    return HZFONT_U8G2_ERR_OK;
}

/**
 * 反初始化HzFont U8G2适配器
 */
void hzfont_u8g2_adapter_deinit(void) {
    LLOGD("HzFont U8G2 adapter deinitialized");
}

/**
 * 创建HzFont字体对象
 */
void* hzfont_u8g2_create_font(const char* path, uint8_t size, uint8_t antialias) {
    // 检查HzFont是否已初始化
    if (luat_hzfont_get_state() != LUAT_HZFONT_STATE_READY) {
        LLOGE("HzFont not initialized");
        return NULL;
    }

    // 验证字号范围
    if (size < HZFONT_MIN_SIZE || size > HZFONT_MAX_SIZE) {
        LLOGE("Invalid font size: %d, expected %d-%d", size, HZFONT_MIN_SIZE, HZFONT_MAX_SIZE);
        return NULL;
    }

    // 分配字体对象
    hzfont_u8g2_font_t* font = (hzfont_u8g2_font_t*)luat_heap_malloc(sizeof(hzfont_u8g2_font_t));
    if (!font) {
        LLOGE("Out of memory when allocating HzFont object");
        return NULL;
    }

    memset(font, 0, sizeof(hzfont_u8g2_font_t));
    font->font_size = size;
    font->antialias = antialias;
    font->threshold = HZFONT_DEFAULT_THRESHOLD;
    font->inited = 1;
    font->ref_count = 1;

    // 复制字体路径
    if (path) {
        font->font_path = luat_heap_malloc(strlen(path) + 1);
        if (!font->font_path) {
            luat_heap_free(font);
            return NULL;
        }
        strcpy(font->font_path, path);
    }

    LLOGD("Created HzFont U8G2 font: size=%d, antialias=%d", size, antialias);
    return font;
}

/**
 * 释放HzFont字体对象
 */
void hzfont_u8g2_free_font(void* font_ptr) {
    if (!font_ptr) {
        return;
    }

    hzfont_u8g2_font_t* font = (hzfont_u8g2_font_t*)font_ptr;

    // 减少引用计数
    font->ref_count--;
    if (font->ref_count > 0) {
        return;  // 还有其他引用
    }

    // 释放字体路径
    if (font->font_path) {
        luat_heap_free(font->font_path);
    }

    // 释放字体对象
    luat_heap_free(font);

    LLOGD("Freed HzFont U8G2 font");
}

/**
 * 增加字体对象引用计数
 */
static void hzfont_u8g2_ref_font(void* font_ptr) {
    if (!font_ptr) {
        return;
    }

    hzfont_u8g2_font_t* font = (hzfont_u8g2_font_t*)font_ptr;
    font->ref_count++;
}

/**
 * 设置U8G2使用HzFont
 */
int hzfont_u8g2_set_font(u8g2_t* u8g2, void* font_ptr) {
    if (!u8g2) {
        return HZFONT_U8G2_ERR_INVALID_PARAM;
    }

    // 检查HzFont是否已初始化
    if (luat_hzfont_get_state() != LUAT_HZFONT_STATE_READY) {
        LLOGE("HzFont not initialized");
        return HZFONT_U8G2_ERR_UNINIT;
    }

    // 创建或获取用户数据
    u8g2_hzfont_userdata_t* userdata = (u8g2_hzfont_userdata_t*)u8g2->u8x8.user_ptr;
    if (!userdata) {
        userdata = (u8g2_hzfont_userdata_t*)luat_heap_malloc(sizeof(u8g2_hzfont_userdata_t));
        if (!userdata) {
            return HZFONT_U8G2_ERR_NO_MEMORY;
        }
        memset(userdata, 0, sizeof(u8g2_hzfont_userdata_t));
        u8g2->u8x8.user_ptr = userdata;
    }

    // 释放旧的HzFont对象
    if (userdata->hzfont) {
        hzfont_u8g2_free_font(userdata->hzfont);
    }

    // 设置新的HzFont对象
    if (font_ptr) {
        hzfont_u8g2_ref_font(font_ptr);
        userdata->hzfont = font_ptr;
        userdata->is_hzfont_enabled = 1;
    } else {
        userdata->hzfont = NULL;
        userdata->is_hzfont_enabled = 0;
    }

    LLOGD("Set HzFont for U8G2: enabled=%d", userdata->is_hzfont_enabled);
    return HZFONT_U8G2_ERR_OK;
}

/**
 * 解码UTF-8字符
 */
static int utf8_decode_char(const char* str, uint32_t* codepoint) {
    if (!str || !codepoint) {
        return 0;
    }

    const unsigned char* p = (const unsigned char*)str;

    if (p[0] == 0) {
        return 0;
    }

    // 1字节字符（ASCII）
    if ((p[0] & 0x80) == 0) {
        *codepoint = p[0];
        return 1;
    }

    // 2字节字符
    if ((p[0] & 0xE0) == 0xC0) {
        if (p[1] == 0) return 0;
        *codepoint = ((p[0] & 0x1F) << 6) | (p[1] & 0x3F);
        return 2;
    }

    // 3字节字符
    if ((p[0] & 0xF0) == 0xE0) {
        if (p[1] == 0 || p[2] == 0) return 0;
        *codepoint = ((p[0] & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F);
        return 3;
    }

    // 4字节字符
    if ((p[0] & 0xF8) == 0xF0) {
        if (p[1] == 0 || p[2] == 0 || p[3] == 0) return 0;
        *codepoint = ((p[0] & 0x07) << 18) | ((p[1] & 0x3F) << 12) |
                     ((p[2] & 0x3F) << 6) | (p[3] & 0x3F);
        return 4;
    }

    return 0;
}

/**
 * 将HzFont灰度位图绘制到U8G2缓冲区
 */
static void draw_hzfont_bitmap_to_u8g2(u8g2_t* u8g2, int x, int y,
                                       const TtfBitmap* bitmap,
                                       uint8_t threshold) {
    if (!u8g2 || !bitmap || !bitmap->pixels) {
        return;
    }

    // 将8位灰度转换为单色并绘制到U8G2
    // 注意: u8g2_DrawPixel只有3个参数, 颜色通过u8g2_SetDrawColor控制
    for (int row = 0; row < (int)bitmap->height; row++) {
        for (int col = 0; col < (int)bitmap->width; col++) {
            uint8_t pixel = bitmap->pixels[row * bitmap->width + col];

            // 灰度阈值判断: 只有超过阈值的像素才绘制(作为前景色)
            if (pixel > threshold) {
                u8g2_SetDrawColor(u8g2, 1);  // 前景色
                u8g2_DrawPixel(u8g2, x + col, y - (int)bitmap->originY + row);
            }
            // 低于阈值的像素不绘制(保持背景色)
        }
    }
}

/**
 * 使用HzFont绘制文本到U8G2缓冲区
 * @param u8g2 U8G2上下文
 * @param x X坐标
 * @param y Y坐标
 * @param text UTF-8文本
 * @param font_size 字号（0表示使用SetHzFont设置的默认值）
 * @param antialias 抗锯齿等级（0xFF表示使用SetHzFont设置的默认值）
 * @return 渲染的字符数
 */
uint16_t hzfont_u8g2_draw_text(u8g2_t* u8g2, u8g2_uint_t x, u8g2_uint_t y, const char* text, uint8_t font_size, uint8_t antialias) {
    if (!u8g2 || !text) {
        return 0;
    }

    // 检查是否使用HzFont
    u8g2_hzfont_userdata_t* userdata = (u8g2_hzfont_userdata_t*)u8g2->u8x8.user_ptr;
    if (!userdata || !userdata->is_hzfont_enabled || !userdata->hzfont) {
        return 0;
    }

    hzfont_u8g2_font_t* font = (hzfont_u8g2_font_t*)userdata->hzfont;

    // 如果调用者指定了字号/抗锯齿，则使用调用者的值；否则使用SetHzFont设置的默认值
    uint8_t use_font_size = (font_size != 0) ? font_size : font->font_size;
    uint8_t use_antialias = (antialias != 0xFF) ? antialias : font->antialias;

    const char* p = text;
    uint16_t count = 0;
    int current_x = x;

    while (*p) {
        uint32_t codepoint = 0;
        int bytes = utf8_decode_char(p, &codepoint);

        if (bytes == 0) {
            LLOGW("Invalid UTF-8 sequence at position %ld", p - text);
            p++;
            continue;
        }

        // 查找glyph索引
        uint16_t glyph_index = 0;
        int ret = luat_hzfont_lookup_glyph_index(codepoint, &glyph_index);
        if (ret != 0) {
            LLOGW("Glyph not found for codepoint: 0x%X", codepoint);
            p += bytes;
            continue;
        }

        // 获取glyph位图
        const TtfBitmap* bitmap = luat_hzfont_get_bitmap(glyph_index, use_font_size, use_antialias);
        if (!bitmap || !bitmap->pixels) {
            LLOGW("Bitmap not available for glyph index: %d", glyph_index);
            p += bytes;
            continue;
        }

        // 绘制位图到U8G2
        draw_hzfont_bitmap_to_u8g2(u8g2, current_x, y, bitmap, font->threshold);

        // 更新X坐标（TtfBitmap没有advance字段，使用bitmap宽度作为字符前进距离）
        current_x += (int)bitmap->width;
        count++;
        p += bytes;
    }

    return count;
}

/**
 * 获取HzFont U8G2字体对象的属性
 */
int hzfont_u8g2_get_font_attr(void* font_ptr, uint8_t* font_size, uint8_t* antialias) {
    if (!font_ptr) {
        return HZFONT_U8G2_ERR_INVALID_PARAM;
    }

    hzfont_u8g2_font_t* font = (hzfont_u8g2_font_t*)font_ptr;

    if (font_size) {
        *font_size = font->font_size;
    }

    if (antialias) {
        *antialias = font->antialias;
    }

    return HZFONT_U8G2_ERR_OK;
}

/**
 * 设置HzFont U8G2字体对象的属性
 */
int hzfont_u8g2_set_font_attr(void* font_ptr, uint8_t font_size, uint8_t antialias, uint8_t threshold) {
    if (!font_ptr) {
        return HZFONT_U8G2_ERR_INVALID_PARAM;
    }

    // 验证字号范围
    if (font_size < HZFONT_MIN_SIZE || font_size > HZFONT_MAX_SIZE) {
        LLOGE("Invalid font size: %d", font_size);
        return HZFONT_U8G2_ERR_INVALID_SIZE;
    }

    hzfont_u8g2_font_t* font = (hzfont_u8g2_font_t*)font_ptr;

    font->font_size = font_size;
    font->antialias = antialias;
    font->threshold = threshold;

    return HZFONT_U8G2_ERR_OK;
}

/**
 * 获取错误描述
 */
const char* hzfont_u8g2_strerror(int err) {
    switch (err) {
        case HZFONT_U8G2_ERR_OK:
            return "Success";
        case HZFONT_U8G2_ERR_UNINIT:
            return "HzFont not initialized";
        case HZFONT_U8G2_ERR_INVALID_PARAM:
            return "Invalid parameter";
        case HZFONT_U8G2_ERR_NO_MEMORY:
            return "Out of memory";
        case HZFONT_U8G2_ERR_GLYPH_NOT_FOUND:
            return "Glyph not found";
        case HZFONT_U8G2_ERR_INVALID_SIZE:
            return "Invalid font size";
        case HZFONT_U8G2_ERR_NOT_READY:
            return "HzFont adapter not ready";
        default:
            return "Unknown error";
    }
}

/**
 * 检查U8G2是否使用HzFont
 */
int hzfont_u8g2_is_hzfont(u8g2_t* u8g2) {
    if (!u8g2) {
        return 0;
    }

    u8g2_hzfont_userdata_t* userdata = (u8g2_hzfont_userdata_t*)u8g2->u8x8.user_ptr;
    if (!userdata) {
        return 0;
    }

    return userdata->is_hzfont_enabled;
}

/**
 * 获取U8G2的HzFont对象
 */
hzfont_u8g2_font_t* hzfont_u8g2_get_font(u8g2_t* u8g2) {
    if (!u8g2) {
        return NULL;
    }

    u8g2_hzfont_userdata_t* userdata = (u8g2_hzfont_userdata_t*)u8g2->u8x8.user_ptr;
    if (!userdata) {
        return NULL;
    }

    return (hzfont_u8g2_font_t*)userdata->hzfont;
}

/**
 * 自动初始化（在模块加载时调用）
 */
LUAT_WEAK int hzfont_u8g2_auto_init(void) {
    return hzfont_u8g2_adapter_init();
}