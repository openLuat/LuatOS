#if 0

#include <stdint.h>
#include <string.h>
#include <stdbool.h>

#include "luat_base.h"
#include "GT5SLCD2E_1A.h"

#include <ft2build.h>
#include FT_FREETYPE_H

// PC 仿真实现（FreeType 渲染）：
// - get_font: 用 FreeType 渲染到 8bpp，再阈值打包为 1bpp
// - get_Font_Gray: 用 FreeType 渲染到 8bpp，再量化为 2/4 阶灰度并打包
// - GT_Font_Init: 初始化 FreeType，加载字体文件
// - U2G: 为兼容 UTF8 流程，直接返回 unicode（等同于“U->G”的恒等映射）

static inline uint32_t min_u32(uint32_t a, uint32_t b) { return a < b ? a : b; }

static FT_Library s_ft_lib = NULL;
static FT_Face    s_ft_face = NULL;
static int        s_ft_ok   = 0;

static int file_accessible(const char* path) {
    if (!path || !*path) return 0;
    FILE* fp = fopen(path, "rb");
    if (fp) { fclose(fp); return 1; }
    return 0;
}

static const char* pick_default_font(void) {
#ifdef _WIN32
    static const char* cands[] = {
        "C:/Windows/Fonts/simhei.ttf",
        // "C:/Windows/Fonts/msyh.ttc",
        // "C:/Windows/Fonts/msyhbd.ttc",
        // "C:/Windows/Fonts/mingliu.ttc",
        NULL
    };
#elif __APPLE__
    static const char* cands[] = {
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/PingFang.ttc",
        NULL
    };
#else
    static const char* cands[] = {
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
        NULL
    };
#endif
    for (int i = 0; cands[i]; i++)
        if (file_accessible(cands[i])) return cands[i];
    return NULL;
}

int GT_Font_Init(void) {
    if (s_ft_ok) return 1;
    if (FT_Init_FreeType(&s_ft_lib)) return 0;
    // 等有了高通的字体专用库再制定，目前先根据平台用默认的
    const char* font_file = getenv("LUAT_GTFONT_FILE");
    if (!file_accessible(font_file)) font_file = pick_default_font();
    if (!font_file) return 0;
    if (FT_New_Face(s_ft_lib, font_file, 0, &s_ft_face)) return 0;
    s_ft_ok = 1;
    return 1;
}

// 将 (x,y) 位置对应的像素置 1（1bpp，MSB-first）
static inline void set_bit_1bpp(uint8_t* buf, uint32_t w, uint32_t x, uint32_t y) {
    uint32_t bytes_per_row = (w + 7) / 8;
    uint32_t byte_index = y * bytes_per_row + (x / 8);
    uint8_t  bit_pos = 7 - (x % 8);
    buf[byte_index] |= (uint8_t)(1u << bit_pos);
}

// 将 (x,y) 位置对应的像素写入 2bpp（每字节 4 像素，先高 2bit）
static inline void set_pix_2bpp(uint8_t* buf, uint32_t w, uint32_t x, uint32_t y, uint8_t v2) {
    // v2 仅取低 2bit；与固件保持一致：bytes_per_row = ((w+7)/8) * 2
    v2 &= 0x03;
    uint32_t bytes_per_row = ((w + 7) / 8) * 2; // 等价于 ceil(w/4)
    uint32_t byte_index = y * bytes_per_row + (x / 4);
    uint8_t shift = (uint8_t)((3 - (x % 4)) * 2);
    uint8_t mask  = (uint8_t)(0x03u << shift);
    buf[byte_index] = (uint8_t)((buf[byte_index] & ~mask) | ((uint8_t)(v2 << shift)));
}

unsigned int get_font(unsigned char *pBits,
                      unsigned char sty,
                      unsigned long fontCode,
                      unsigned char width,
                      unsigned char height,
                      unsigned char thick) {
    (void)sty; (void)thick;
    if (!pBits || width == 0 || height == 0 || !s_ft_ok) return 0;
    const uint32_t w = width;
    const uint32_t h = height;
    memset(pBits, 0, ((w + 7) / 8) * h);

    // 约定：fontCode 在 PC 仿真中视为 Unicode（UTF8 流程通过 U2G 恒等实现）
    uint32_t codepoint = (uint32_t)fontCode;
    if (FT_Set_Pixel_Sizes(s_ft_face, 0, h)) return 0;
    if (FT_Load_Char(s_ft_face, codepoint, FT_LOAD_RENDER)) return 0;
    FT_GlyphSlot slot = s_ft_face->glyph;
    FT_Bitmap*   bm   = &slot->bitmap;

    // 对齐方式：基线对齐（使用 ascender/bitmap_top）+ 左对齐
    int off_x = 0;
    int off_y = 0;
    int asc_px = (int)(s_ft_face->size->metrics.ascender >> 6);
    if (asc_px < 0) asc_px = 0;
    if (asc_px > (int)h) asc_px = (int)h;
    off_y = asc_px - (int)slot->bitmap_top;
    for (int yy = 0; yy < (int)bm->rows; yy++) {
        int dy = off_y + yy;
        if (dy < 0 || dy >= (int)h) continue;
        for (int xx = 0; xx < (int)bm->width; xx++) {
            int dx = off_x + xx;
            if (dx < 0 || dx >= (int)w) continue;
            uint8_t val = bm->buffer[yy * bm->pitch + xx];
            if (val > 127) set_bit_1bpp(pBits, w, (uint32_t)dx, (uint32_t)dy);
        }
    }
    uint32_t adv = (uint32_t)((slot->advance.x + 32) >> 6);
    if (adv > w) adv = w;                      // 不超过单元宽
    if (adv < (uint32_t)bm->width) adv = (uint32_t)bm->width; // 至少覆盖位图宽，避免字符被截断
    if (adv == 0) adv = (uint32_t)bm->width;   // 兜底
    return adv;
}

static inline void set_pix_gray(uint8_t* buf, uint32_t w, uint32_t x, uint32_t y, uint8_t bpp, uint8_t val) {
    if (bpp == 4) {
        // 与固件保持一致：bytes_per_row = ((w+7)/8) * 4 （等价于 ceil(w/2)）
        uint32_t bytes_per_row = ((w + 7) / 8) * 4;
        uint32_t byte_index = y * bytes_per_row + (x / 2);
        uint8_t  shift = (uint8_t)((1 - (x % 2)) * 4);
        uint8_t  mask  = (uint8_t)(0x0Fu << shift);
        buf[byte_index] = (uint8_t)((buf[byte_index] & ~mask) | ((uint8_t)(val & 0x0F) << shift));
    } else if (bpp == 2) {
        // 与固件保持一致：bytes_per_row = ((w+7)/8) * 2 （等价于 ceil(w/4)）
        uint32_t bytes_per_row = ((w + 7) / 8) * 2;
        uint32_t byte_index = y * bytes_per_row + (x / 4);
        uint8_t  shift = (uint8_t)((3 - (x % 4)) * 2);
        uint8_t  mask  = (uint8_t)(0x03u << shift);
        buf[byte_index] = (uint8_t)((buf[byte_index] & ~mask) | ((uint8_t)(val & 0x03) << shift));
    }
}

// 渲染灰度字体，返回字形宽度和灰度阶数
unsigned int* get_Font_Gray(unsigned char *pBits,
                            unsigned char sty,
                            unsigned long fontCode,
                            unsigned char fontSize,
                            unsigned char thick) {
    (void)sty; (void)thick;
    static unsigned int re_buff[2];
    // 参数检查：pBits不能为空，fontSize不能为0，FreeType库必须初始化成功
    if (!pBits || fontSize == 0 || !s_ft_ok) {
        re_buff[0] = 0;
        re_buff[1] = 2; // 默认返回2阶
        return re_buff;
    }
    const uint32_t w = fontSize;
    const uint32_t h = fontSize;

    // 与固件约定：小号用 4 阶码流，大号用 2 阶码流（此处不做灰度量化，统一与 get_font 一致）
    uint8_t bpp = (fontSize >= 16 && fontSize < 34) ? 4 : 2;
    // 计算每行字节数，和固件保持一致
    uint32_t bytes_per_row = ((w + 7) / 8) * bpp;
    // 清空输出缓冲区
    memset(pBits, 0, bytes_per_row * h);

    // 字符编码，PC 仿真直接视为 Unicode
    uint32_t codepoint = (uint32_t)fontCode;
    // 设置字体像素大小
    if (FT_Set_Pixel_Sizes(s_ft_face, 0, h)) { re_buff[0] = 0; re_buff[1] = bpp; return re_buff; }
    // 加载并渲染字符
    if (FT_Load_Char(s_ft_face, codepoint, FT_LOAD_RENDER)) { re_buff[0] = 0; re_buff[1] = bpp; return re_buff; }
    FT_GlyphSlot slot = s_ft_face->glyph;
    FT_Bitmap*   bm   = &slot->bitmap;

    // 对齐方式：基线对齐（使用 ascender/bitmap_top）+ 左对齐
    int off_x = 0;
    int off_y = 0;
    int asc_px = (int)(s_ft_face->size->metrics.ascender >> 6);
    if (asc_px < 0) asc_px = 0;
    if (asc_px > (int)h) asc_px = (int)h;
    off_y = asc_px - (int)slot->bitmap_top;

    // 遍历位图像素，按阈值写入满强度 2/4 阶码流
    for (int yy = 0; yy < (int)bm->rows; yy++) {
        int dy = off_y + yy;
        if (dy < 0 || dy >= (int)h) continue;
        for (int xx = 0; xx < (int)bm->width; xx++) {
            int dx = off_x + xx;
            if (dx < 0 || dx >= (int)w) continue;
            uint8_t val = bm->buffer[yy * bm->pitch + xx]; // 0..255
            if (val > 127) {
                if (bpp == 4) {
                    set_pix_gray(pBits, w, (uint32_t)dx, (uint32_t)dy, 4, 0x0F);
                } else {
                    set_pix_gray(pBits, w, (uint32_t)dx, (uint32_t)dy, 2, 0x03);
                }
            }
        }
    }

    // 计算字形实际宽度（advance），兜底处理，避免被截断
    uint32_t adv = (uint32_t)((slot->advance.x + 32) >> 6);
    if (adv > w) adv = w;                                      // 不超过单元宽
    if (adv < (uint32_t)bm->width) adv = (uint32_t)bm->width;  // 至少覆盖位图宽
    if (adv == 0) adv = (uint32_t)bm->width;                   // 兜底
    re_buff[0] = adv;
    re_buff[1] = bpp; // 返回灰度阶数（2或4）
    return re_buff;
}

void Gray_Process(unsigned char *OutPutData ,int width,int High,unsigned char Grade) {
    (void)OutPutData; (void)width; (void)High; (void)Grade;
    // PC 仿真版：若 get_Font_Gray 已按目标阶写入，可不做任何处理
}

unsigned long U2G(unsigned int unicode) {
    // PC 仿真：直接返回 unicode，实现“恒等映射”，
    // 这样上层的 gt_unicode2gb18030(e) 得到的值仍可被本实现直接识别为 Unicode。
    return (unsigned long)unicode;
}

#endif // LUAT_USE_GUI


