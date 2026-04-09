/**
 * HzFont EINK后端实现
 * @file    hzfont_eink_backend.c
 * @brief   为EINK墨水屏提供HzFont矢量字体渲染支持
 * @author  wjq
 * @date    2026-4-9
 * @version 1.0
 */
#ifdef LUAT_USE_HZFONT
#include "hzfont_eink_backend.h"
#include "luat_hzfont.h"
#include "luat_log.h"
#include "luat_mem.h"
#include <string.h>
#include <stdlib.h>

#define LUAT_LOG_TAG "hzfont_eink"

// 全局渲染上下文
static eink_hzfont_ctx_t g_eink_hzfont_ctx = {0};

// EINK颜色定义
#define EINK_COLORED    0   // 有色（黑色像素）
#define EINK_UNCOLORED  1   // 无色（白色像素）

// 最小和最大字号
#define HZFONT_MIN_SIZE  12
#define HZFONT_MAX_SIZE  255

// 默认灰度阈值
#define HZFONT_DEFAULT_THRESHOLD 128

/**
 * 初始化EINK HzFont后端
 */
int eink_hzfont_backend_init(void) {
    memset(&g_eink_hzfont_ctx, 0, sizeof(eink_hzfont_ctx_t));
    g_eink_hzfont_ctx.font_size = 16;
    g_eink_hzfont_ctx.antialias = -1;
    g_eink_hzfont_ctx.threshold = HZFONT_DEFAULT_THRESHOLD;
    g_eink_hzfont_ctx.fg_color = EINK_COLORED;
    g_eink_hzfont_ctx.bg_color = EINK_UNCOLORED;
    g_eink_hzfont_ctx.inited = 1;

    LLOGD("HzFont EINK backend initialized");
    return HZFONT_EINK_ERR_OK;
}

/**
 * 反初始化EINK HzFont后端
 */
void eink_hzfont_backend_deinit(void) {
    memset(&g_eink_hzfont_ctx, 0, sizeof(eink_hzfont_ctx_t));
    LLOGD("HzFont EINK backend deinitialized");
}

/**
 * 获取HzFont EINK后端渲染上下文
 */
eink_hzfont_ctx_t* eink_hzfont_get_ctx(void) {
    if (!g_eink_hzfont_ctx.inited) {
        return NULL;
    }
    return &g_eink_hzfont_ctx;
}

/**
 * 设置HzFont EINK渲染参数
 */
int eink_hzfont_set_params(uint8_t font_size, uint8_t antialias, uint8_t threshold) {
    if (!g_eink_hzfont_ctx.inited) {
        return HZFONT_EINK_ERR_UNINIT;
    }

    // 验证字号范围
    if (font_size < HZFONT_MIN_SIZE || font_size > HZFONT_MAX_SIZE) {
        LLOGE("Invalid font size: %d, expected %d-%d", font_size, HZFONT_MIN_SIZE, HZFONT_MAX_SIZE);
        return HZFONT_EINK_ERR_INVALID_SIZE;
    }

    g_eink_hzfont_ctx.font_size = font_size;
    g_eink_hzfont_ctx.antialias = antialias;
    g_eink_hzfont_ctx.threshold = threshold;

    return HZFONT_EINK_ERR_OK;
}

/**
 * 设置EINK绘制上下文
 */
int eink_hzfont_set_paint(Paint* paint) {
    if (!g_eink_hzfont_ctx.inited) {
        return HZFONT_EINK_ERR_UNINIT;
    }

    if (!paint) {
        return HZFONT_EINK_ERR_INVALID_PARAM;
    }

    g_eink_hzfont_ctx.paint = paint;
    return HZFONT_EINK_ERR_OK;
}

/**
 * 解码UTF-8字符
 * @param str UTF-8字符串指针
 * @param[out] codepoint 解码后的Unicode码点
 * @return 字符的字节数（1-4），0表示无效
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
 * 在EINK绘制上下文中绘制HzFont UTF-8文本
 */
int eink_hzfont_draw_utf8(Paint* paint, int x, int y,
                          const char* text, uint8_t font_size,
                          uint8_t antialias) {
    if (!paint || !text) {
        return HZFONT_EINK_ERR_INVALID_PARAM;
    }

    // 检查HzFont是否已初始化
    if (luat_hzfont_get_state() != LUAT_HZFONT_STATE_READY) {
        LLOGE("HzFont not initialized");
        return HZFONT_EINK_ERR_UNINIT;
    }

    // 验证字号范围
    if (font_size < HZFONT_MIN_SIZE || font_size > HZFONT_MAX_SIZE) {
        LLOGE("Invalid font size: %d", font_size);
        return HZFONT_EINK_ERR_INVALID_SIZE;
    }

    // 使用默认抗锯齿等级
    if (antialias == 0xFF) {
        antialias = -1;  // 自动模式
    }

    const char* p = text;
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
        const TtfBitmap* bitmap = luat_hzfont_get_bitmap(glyph_index, font_size, antialias);
        if (!bitmap || !bitmap->pixels) {
            LLOGW("Bitmap not available for glyph index: %d", glyph_index);
            p += bytes;
            continue;
        }

        // 将8位灰度位图转换为EINK格式并绘制
        for (int row = 0; row < (int)bitmap->height; row++) {
            for (int col = 0; col < (int)bitmap->width; col++) {
                uint8_t pixel = bitmap->pixels[row * bitmap->width + col];

                // 灰度阈值判断（转换为单色）
                int colored = (pixel > g_eink_hzfont_ctx.threshold) ?
                              g_eink_hzfont_ctx.fg_color : g_eink_hzfont_ctx.bg_color;

                Paint_DrawPixel(paint, current_x + col,
                               y - (int)bitmap->originY + row, colored);
            }
        }

        // 更新X坐标（TtfBitmap没有advance字段，使用bitmap宽度作为字符前进距离）
        current_x += (int)bitmap->width;
        p += bytes;
    }

    return HZFONT_EINK_ERR_OK;
}


/**
 * 获取错误描述
 */
const char* eink_hzfont_strerror(int err) {
    switch (err) {
        case HZFONT_EINK_ERR_OK:
            return "Success";
        case HZFONT_EINK_ERR_UNINIT:
            return "HzFont not initialized";
        case HZFONT_EINK_ERR_INVALID_PARAM:
            return "Invalid parameter";
        case HZFONT_EINK_ERR_NO_MEMORY:
            return "Out of memory";
        case HZFONT_EINK_ERR_GLYPH_NOT_FOUND:
            return "Glyph not found";
        case HZFONT_EINK_ERR_INVALID_SIZE:
            return "Invalid font size";
        default:
            return "Unknown error";
    }
}

/**
 * 自动初始化（在模块加载时调用）
 * 使用弱符号定义，允许在启动时自动初始化
 */
LUAT_WEAK int eink_hzfont_auto_init(void) {
    return eink_hzfont_backend_init();
}

#endif