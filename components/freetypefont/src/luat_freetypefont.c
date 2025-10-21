#include "luat_freetypefont.h"
#include "luat_lcd.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include "ttf_rasterizer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LUAT_LOG_TAG "freetype"
#include "luat_log.h"

// 字体缓存结构
typedef struct {
    struct TTF_Font *cached_font;     // 缓存的字体结构
    uint8_t *font_data;        // TTF文件数据缓存
    size_t font_size;          // 字体文件大小
    char *font_path;           // 当前字体路径
    uint8_t is_loaded;         // 加载状态
} luat_freetypefont_cache_t;

// 全局缓存实例
static luat_freetypefont_cache_t g_ft_cache = {0};

// 当前状态
static luat_freetypefont_state_t g_ft_state = LUAT_FREETYPEFONT_STATE_UNINIT;

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

// 初始化 FreeType 字体库
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
    
    // 检查文件是否存在
    FILE* fp = luat_fs_fopen(ttf_path, "rb");
    if (!fp) {
        LLOGE("Cannot open TTF file: %s", ttf_path);
        g_ft_state = LUAT_FREETYPEFONT_STATE_ERROR;
        return 0;
    }
    
    // 获取文件大小
    luat_fs_fseek(fp, 0, SEEK_END);
    long file_size = luat_fs_ftell(fp);
    luat_fs_fseek(fp, 0, SEEK_SET);
    
    if (file_size <= 0) {
        LLOGE("Invalid TTF file size: %s", ttf_path);
        luat_fs_fclose(fp);
        g_ft_state = LUAT_FREETYPEFONT_STATE_ERROR;
        return 0;
    }
    
    // 分配内存并缓存文件内容
    g_ft_cache.font_size = (size_t)file_size;
    g_ft_cache.font_data = (uint8_t*)luat_heap_malloc(g_ft_cache.font_size);
    if (!g_ft_cache.font_data) {
        LLOGE("Failed to allocate memory for font data");
        luat_fs_fclose(fp);
        g_ft_state = LUAT_FREETYPEFONT_STATE_ERROR;
        return 0;
    }
    
    // 读取文件内容
    size_t bytes_read = luat_fs_fread(g_ft_cache.font_data, 1, g_ft_cache.font_size, fp);
    luat_fs_fclose(fp);
    
    if (bytes_read != g_ft_cache.font_size) {
        LLOGE("Failed to read complete TTF file");
        luat_heap_free(g_ft_cache.font_data);
        g_ft_cache.font_data = NULL;
        g_ft_state = LUAT_FREETYPEFONT_STATE_ERROR;
        return 0;
    }
    
    // 解析字体数据
    TTF_Result result = ttf_load_font_from_memory(g_ft_cache.font_data, g_ft_cache.font_size, &g_ft_cache.cached_font);
    if (result != TTF_OK) {
        LLOGE("Failed to parse TTF file: %d", (int)result);
        luat_heap_free(g_ft_cache.font_data);
        g_ft_cache.font_data = NULL;
        g_ft_state = LUAT_FREETYPEFONT_STATE_ERROR;
        return 0;
    }
    
    // 保存字体路径
    size_t path_len = strlen(ttf_path);
    g_ft_cache.font_path = (char*)luat_heap_malloc(path_len + 1);
    if (g_ft_cache.font_path) {
        memcpy(g_ft_cache.font_path, ttf_path, path_len + 1);
    }
    
    g_ft_cache.is_loaded = 1;
    g_ft_state = LUAT_FREETYPEFONT_STATE_INITED;
    
    LLOGI("FreeType initialized with font: %s (size: %d bytes)", ttf_path, (int)file_size);
    return 1;
}

// 反初始化
void luat_freetypefont_deinit(void) {
    if (g_ft_cache.cached_font) {
        ttf_unload_font(g_ft_cache.cached_font);
        g_ft_cache.cached_font = NULL;
    }
    
    if (g_ft_cache.font_data) {
        luat_heap_free(g_ft_cache.font_data);
        g_ft_cache.font_data = NULL;
    }
    
    if (g_ft_cache.font_path) {
        luat_heap_free(g_ft_cache.font_path);
        g_ft_cache.font_path = NULL;
    }
    
    memset(&g_ft_cache, 0, sizeof(g_ft_cache));
    g_ft_state = LUAT_FREETYPEFONT_STATE_UNINIT;
    
    LLOGD("FreeType deinitialized");
}

// 获取当前状态
luat_freetypefont_state_t luat_freetypefont_get_state(void) {
    return g_ft_state;
}

// 获取字符位图（1bpp单色）
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
    
    // 使用缓存的字体数据
    TTF_Bitmap bitmap;
    TTF_Result result = ttf_load_glyph_bitmap_cached(g_ft_cache.cached_font, fontCode, (float)h, &bitmap);
    
    if (result != TTF_OK) {
        // 字符不存在，尝试显示替换字符
        if (fontCode != 0xFFFD) {
            result = ttf_load_glyph_bitmap_cached(g_ft_cache.cached_font, 0xFFFD, (float)h, &bitmap);
        }
        if (result != TTF_OK) {
            return 0;
        }
    }
    
    // 转换为 1bpp 格式（基线对齐）
    int off_x = 0;
    int off_y = 0;
    int asc_px = height - (height / 4); // 简单的基线估算
    if (asc_px < 0) asc_px = 0;
    if (asc_px > (int)h) asc_px = (int)h;
    off_y = asc_px - bitmap.top;
    
    // 渲染到位图
    for (int yy = 0; yy < bitmap.height; yy++) {
        int dy = off_y + yy;
        if (dy < 0 || dy >= (int)h) continue;
        for (int xx = 0; xx < bitmap.width; xx++) {
            int dx = off_x + xx;
            if (dx < 0 || dx >= (int)w) continue;
            uint8_t val = bitmap.pixels[yy * bitmap.width + xx];
            if (val > 127) {  // 阈值
                set_bit_1bpp(pBits, w, (uint32_t)dx, (uint32_t)dy);
            }
        }
    }
    
    // 计算字符宽度
    uint32_t adv = (uint32_t)(bitmap.advance + 0.5f);
    if (adv > w) adv = w;
    if (adv < (uint32_t)bitmap.width) adv = (uint32_t)bitmap.width;
    if (adv == 0) adv = (uint32_t)bitmap.width;
    
    ttf_free_bitmap(&bitmap);
    return adv;
}

// 获取字符位图（灰度）- 简化版，不支持
unsigned int* luat_freetypefont_get_char_gray(
    unsigned char *pBits,
    unsigned char sty,
    unsigned long fontCode,
    unsigned char fontSize,
    unsigned char thick
) {
    (void)sty; (void)thick; (void)pBits; (void)fontCode;
    
    // freetype_mini 不支持灰度，返回默认值
    g_gray_result[0] = fontSize;
    g_gray_result[1] = 1; // 1bpp
    
    if (g_ft_state != LUAT_FREETYPEFONT_STATE_INITED) {
        return g_gray_result;
    }
    
    return g_gray_result;
}

// 获取UTF-8字符串宽度
unsigned int luat_freetypefont_get_str_width(
    const char* str,
    unsigned char fontSize
) {
    if (!str || fontSize == 0 || g_ft_state != LUAT_FREETYPEFONT_STATE_INITED) {
        return 0;
    }
    
    unsigned int total_width = 0;
    const char* p = str;
    
    while (*p) {
        uint32_t code = utf8_next_char(&p);
        if (code == 0xFFFFFFFF) break;
        
        TTF_Bitmap bitmap;
        TTF_Result result = ttf_load_glyph_bitmap_cached(g_ft_cache.cached_font, code, (float)fontSize, &bitmap);
        
        if (result == TTF_OK) {
            total_width += (unsigned int)(bitmap.advance + 0.5f);
            ttf_free_bitmap(&bitmap);
        }
    }
    
    return total_width;
}

// 绘制UTF-8字符串到LCD
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
    
    int current_x = x;
    const char* p = str;
    
    while (*p) {
        uint32_t code = utf8_next_char(&p);
        if (code == 0xFFFFFFFF) break;
        
        TTF_Bitmap bitmap;
        TTF_Result result = ttf_load_glyph_bitmap_cached(g_ft_cache.cached_font, code, (float)fontSize, &bitmap);
        
        if (result == TTF_OK) {
            // 基线对齐
            int asc_px = fontSize - (fontSize / 4);
            if (asc_px < 0) asc_px = 0;
            int off_y = asc_px - bitmap.top;
            
            // 绘制到LCD
            for (int yy = 0; yy < bitmap.height; yy++) {
                int dy = y + off_y + yy;
                for (int xx = 0; xx < bitmap.width; xx++) {
                    uint8_t val = bitmap.pixels[yy * bitmap.width + xx];
                    if (val > 127) {
                        int dx = current_x + xx;
                        luat_lcd_draw_point(lcd_dft_conf, dx, dy, color);
                    }
                }
            }
            
            // 更新X位置
            current_x += (int)(bitmap.advance + 0.5f);
            ttf_free_bitmap(&bitmap);
        }
    }
    
    return 0;
}