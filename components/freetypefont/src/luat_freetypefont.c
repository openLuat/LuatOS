#include "luat_freetypefont.h"
#include "luat_lcd.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LUAT_LOG_TAG "freetype"
#include "luat_log.h"

#include <ft2build.h>
#include FT_FREETYPE_H
#include FT_GLYPH_H

// 全局 FreeType 库和字体面
static FT_Library g_ft_lib = NULL;
static FT_Face g_ft_face = NULL;
static luat_freetypefont_state_t g_ft_state = LUAT_FREETYPEFONT_STATE_UNINIT;
static char* g_font_path = NULL;

// 返回值缓存（用于 get_char_gray）
static unsigned int g_gray_result[2] = {0, 0};

// 内联辅助函数
static inline uint32_t min_u32(uint32_t a, uint32_t b) { return a < b ? a : b; }
static inline uint32_t max_u32(uint32_t a, uint32_t b) { return a > b ? a : b; }

// 设置 1bpp 位图的位
static inline void set_bit_1bpp(uint8_t* buf, uint32_t w, uint32_t x, uint32_t y) {
    uint32_t bytes_per_row = (w + 7) / 8;
    uint32_t byte_index = y * bytes_per_row + (x / 8);
    uint8_t bit_pos = 7 - (x % 8);
    buf[byte_index] |= (uint8_t)(1u << bit_pos);
}

// 设置灰度像素（2bpp/4bpp）
static inline void set_pix_gray(uint8_t* buf, uint32_t w, uint32_t x, uint32_t y, uint8_t bpp, uint8_t val) {
    if (bpp == 4) {
        uint32_t bytes_per_row = ((w + 7) / 8) * 4;
        uint32_t byte_index = y * bytes_per_row + (x / 2);
        uint8_t shift = (uint8_t)((1 - (x % 2)) * 4);
        uint8_t mask = (uint8_t)(0x0Fu << shift);
        buf[byte_index] = (uint8_t)((buf[byte_index] & ~mask) | ((uint8_t)(val & 0x0F) << shift));
    } else if (bpp == 2) {
        uint32_t bytes_per_row = ((w + 7) / 8) * 2;
        uint32_t byte_index = y * bytes_per_row + (x / 4);
        uint8_t shift = (uint8_t)((3 - (x % 4)) * 2);
        uint8_t mask = (uint8_t)(0x03u << shift);
        buf[byte_index] = (uint8_t)((buf[byte_index] & ~mask) | ((uint8_t)(val & 0x03) << shift));
    }
}

// UTF-8 解码
static uint32_t utf8_next_char(const char** str) {
    const uint8_t* s = (const uint8_t*)*str;
    uint32_t code = 0;
    
    if (s[0] == 0) {
        return 0xFFFFFFFF;
    }
    
    if (s[0] < 0x80) {
        code = s[0];
        *str += 1;
    } else if ((s[0] & 0xE0) == 0xC0) {
        code = ((s[0] & 0x1F) << 6) | (s[1] & 0x3F);
        *str += 2;
    } else if ((s[0] & 0xF0) == 0xE0) {
        code = ((s[0] & 0x0F) << 12) | ((s[1] & 0x3F) << 6) | (s[2] & 0x3F);
        *str += 3;
    } else if ((s[0] & 0xF8) == 0xF0) {
        code = ((s[0] & 0x07) << 18) | ((s[1] & 0x3F) << 12) | ((s[2] & 0x3F) << 6) | (s[3] & 0x3F);
        *str += 4;
    } else {
        *str += 1;
        return 0xFFFD; // 替换字符
    }
    
    return code;
}

int luat_freetypefont_init(const char* ttf_path) {
    if (g_ft_state == LUAT_FREETYPEFONT_STATE_INITED) {
        LLOGD("FreeType already initialized, deinit first");
        luat_freetypefont_deinit();
    }
    
    if (!ttf_path) {
        LLOGE("TTF path is NULL");
        g_ft_state = LUAT_FREETYPEFONT_STATE_ERROR;
        return 0;
    }
    
    // 检查文件是否存在 - 使用LuatOS文件系统接口
    FILE* fp = luat_fs_fopen(ttf_path, "rb");
    if (!fp) {
        LLOGE("Cannot open TTF file: %s", ttf_path);
        g_ft_state = LUAT_FREETYPEFONT_STATE_ERROR;
        return 0;
    }
    luat_fs_fclose(fp);
    
    // 初始化 FreeType 库
    if (FT_Init_FreeType(&g_ft_lib)) {
        LLOGE("Failed to initialize FreeType library");
        g_ft_state = LUAT_FREETYPEFONT_STATE_ERROR;
        return 0;
    }
    
    // 加载字体面
    if (FT_New_Face(g_ft_lib, ttf_path, 0, &g_ft_face)) {
        LLOGE("Failed to load font face: %s", ttf_path);
        FT_Done_FreeType(g_ft_lib);
        g_ft_lib = NULL;
        g_ft_state = LUAT_FREETYPEFONT_STATE_ERROR;
        return 0;
    }
    
    // 保存字体路径 - 使用LuatOS内存管理
    if (g_font_path) {
        luat_heap_free(g_font_path);
    }
    size_t path_len = strlen(ttf_path);
    g_font_path = (char*)luat_heap_malloc(path_len + 1);
    if (g_font_path) {
        memcpy(g_font_path, ttf_path, path_len + 1);
    }
    
    g_ft_state = LUAT_FREETYPEFONT_STATE_INITED;
    LLOGI("FreeType initialized with font: %s", ttf_path);
    return 1;
}

void luat_freetypefont_deinit(void) {
    if (g_ft_face) {
        FT_Done_Face(g_ft_face);
        g_ft_face = NULL;
    }
    
    if (g_ft_lib) {
        FT_Done_FreeType(g_ft_lib);
        g_ft_lib = NULL;
    }
    
    if (g_font_path) {
        luat_heap_free(g_font_path);
        g_font_path = NULL;
    }
    
    g_ft_state = LUAT_FREETYPEFONT_STATE_UNINIT;
    LLOGD("FreeType deinitialized");
}

luat_freetypefont_state_t luat_freetypefont_get_state(void) {
    return g_ft_state;
}

unsigned int luat_freetypefont_get_char(
    unsigned char *pBits,
    unsigned char sty,
    unsigned long fontCode,
    unsigned char width,
    unsigned char height,
    unsigned char thick
) {
    (void)sty; (void)thick;
    
    if (!pBits || width == 0 || height == 0 || g_ft_state != LUAT_FREETYPEFONT_STATE_INITED) {
        return 0;
    }
    
    const uint32_t w = width;
    const uint32_t h = height;
    memset(pBits, 0, ((w + 7) / 8) * h);
    
    // 设置字体大小
    if (FT_Set_Pixel_Sizes(g_ft_face, 0, h)) {
        LLOGE("Failed to set pixel size");
        return 0;
    }
    
    // 加载字符
    if (FT_Load_Char(g_ft_face, fontCode, FT_LOAD_RENDER)) {
        // 字符不存在，尝试显示替换字符
        if (fontCode != 0xFFFD && FT_Load_Char(g_ft_face, 0xFFFD, FT_LOAD_RENDER)) {
            return 0;
        }
    }
    
    FT_GlyphSlot slot = g_ft_face->glyph;
    FT_Bitmap* bm = &slot->bitmap;
    
    // 基线对齐
    int off_x = 0;
    int off_y = 0;
    int asc_px = (int)(g_ft_face->size->metrics.ascender >> 6);
    if (asc_px < 0) asc_px = 0;
    if (asc_px > (int)h) asc_px = (int)h;
    off_y = asc_px - (int)slot->bitmap_top;
    
    // 渲染到位图
    for (int yy = 0; yy < (int)bm->rows; yy++) {
        int dy = off_y + yy;
        if (dy < 0 || dy >= (int)h) continue;
        for (int xx = 0; xx < (int)bm->width; xx++) {
            int dx = off_x + xx;
            if (dx < 0 || dx >= (int)w) continue;
            uint8_t val = bm->buffer[yy * bm->pitch + xx];
            if (val > 127) {  // 阈值
                set_bit_1bpp(pBits, w, (uint32_t)dx, (uint32_t)dy);
            }
        }
    }
    
    // 计算字符宽度
    uint32_t adv = (uint32_t)((slot->advance.x + 32) >> 6);
    if (adv > w) adv = w;
    if (adv < (uint32_t)bm->width) adv = (uint32_t)bm->width;
    if (adv == 0) adv = (uint32_t)bm->width;
    
    return adv;
}

unsigned int* luat_freetypefont_get_char_gray(
    unsigned char *pBits,
    unsigned char sty,
    unsigned long fontCode,
    unsigned char fontSize,
    unsigned char thick
) {
    (void)sty; (void)thick;
    
    // 设置默认值
    g_gray_result[0] = 0;
    g_gray_result[1] = 2;
    
    if (!pBits || fontSize == 0 || g_ft_state != LUAT_FREETYPEFONT_STATE_INITED) {
        return g_gray_result;
    }
    
    const uint32_t w = fontSize;
    const uint32_t h = fontSize;
    
    // 根据字体大小选择灰度阶数
    uint8_t bpp = (fontSize >= 16 && fontSize < 34) ? 4 : 2;
    uint32_t bytes_per_row = ((w + 7) / 8) * bpp;
    memset(pBits, 0, bytes_per_row * h);
    
    // 设置字体大小
    if (FT_Set_Pixel_Sizes(g_ft_face, 0, h)) {
        g_gray_result[1] = bpp;
        return g_gray_result;
    }
    
    // 加载字符
    if (FT_Load_Char(g_ft_face, fontCode, FT_LOAD_RENDER)) {
        // 字符不存在，尝试显示替换字符
        if (fontCode != 0xFFFD && FT_Load_Char(g_ft_face, 0xFFFD, FT_LOAD_RENDER)) {
            g_gray_result[1] = bpp;
            return g_gray_result;
        }
    }
    
    FT_GlyphSlot slot = g_ft_face->glyph;
    FT_Bitmap* bm = &slot->bitmap;
    
    // 基线对齐
    int off_x = 0;
    int off_y = 0;
    int asc_px = (int)(g_ft_face->size->metrics.ascender >> 6);
    if (asc_px < 0) asc_px = 0;
    if (asc_px > (int)h) asc_px = (int)h;
    off_y = asc_px - (int)slot->bitmap_top;
    
    // 渲染灰度位图
    for (int yy = 0; yy < (int)bm->rows; yy++) {
        int dy = off_y + yy;
        if (dy < 0 || dy >= (int)h) continue;
        for (int xx = 0; xx < (int)bm->width; xx++) {
            int dx = off_x + xx;
            if (dx < 0 || dx >= (int)w) continue;
            uint8_t val = bm->buffer[yy * bm->pitch + xx];
            if (val > 127) {
                if (bpp == 4) {
                    set_pix_gray(pBits, w, (uint32_t)dx, (uint32_t)dy, 4, 0x0F);
                } else {
                    set_pix_gray(pBits, w, (uint32_t)dx, (uint32_t)dy, 2, 0x03);
                }
            }
        }
    }
    
    // 计算字符宽度
    uint32_t adv = (uint32_t)((slot->advance.x + 32) >> 6);
    if (adv > w) adv = w;
    if (adv < (uint32_t)bm->width) adv = (uint32_t)bm->width;
    if (adv == 0) adv = (uint32_t)bm->width;
    
    g_gray_result[0] = adv;
    g_gray_result[1] = bpp;
    return g_gray_result;
}

unsigned int luat_freetypefont_get_str_width(
    const char* str,
    unsigned char fontSize
) {
    if (!str || fontSize == 0 || g_ft_state != LUAT_FREETYPEFONT_STATE_INITED) {
        return 0;
    }
    
    if (FT_Set_Pixel_Sizes(g_ft_face, 0, fontSize)) {
        return 0;
    }
    
    unsigned int total_width = 0;
    const char* p = str;
    
    while (*p) {
        uint32_t code = utf8_next_char(&p);
        if (code == 0xFFFFFFFF) break;
        
        if (FT_Load_Char(g_ft_face, code, FT_LOAD_RENDER)) {
            continue;  // 跳过不存在的字符
        }
        
        uint32_t adv = (uint32_t)((g_ft_face->glyph->advance.x + 32) >> 6);
        total_width += adv;
    }
    
    return total_width;
}

int luat_freetypefont_draw_utf8(
    int x,
    int y,
    const char* str,
    unsigned char fontSize,
    uint32_t color
) {
    if (!str || g_ft_state != LUAT_FREETYPEFONT_STATE_INITED) {
        return -1;
    }
    
    // 获取LCD设备指针
    extern luat_lcd_conf_t* lcd_dft_conf;
    if (!lcd_dft_conf) {
        LLOGE("LCD not initialized");
        return -1;
    }
    
    if (FT_Set_Pixel_Sizes(g_ft_face, 0, fontSize)) {
        return -1;
    }
    
    int current_x = x;
    const char* p = str;
    
    while (*p) {
        uint32_t code = utf8_next_char(&p);
        if (code == 0xFFFFFFFF) break;
        
        if (FT_Load_Char(g_ft_face, code, FT_LOAD_RENDER)) {
            continue;  // 跳过不存在的字符
        }
        
        FT_GlyphSlot slot = g_ft_face->glyph;
        FT_Bitmap* bm = &slot->bitmap;
        
        // 基线对齐
        int asc_px = (int)(g_ft_face->size->metrics.ascender >> 6);
        if (asc_px < 0) asc_px = 0;
        int off_y = asc_px - (int)slot->bitmap_top;
        
        // 绘制到LCD
        for (int yy = 0; yy < (int)bm->rows; yy++) {
            int dy = y + off_y + yy;
            for (int xx = 0; xx < (int)bm->width; xx++) {
                uint8_t val = bm->buffer[yy * bm->pitch + xx];
                if (val > 127) {
                    int dx = current_x + xx;
                    luat_lcd_draw_point(lcd_dft_conf, dx, dy, color);
                }
            }
        }
        
        // 更新X位置
        current_x += (int)((slot->advance.x + 32) >> 6);
    }
    
    return 0;
}