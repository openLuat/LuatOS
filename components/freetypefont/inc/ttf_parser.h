#ifndef TTF_PARSER_H
#define TTF_PARSER_H

#include <stdint.h>
#include <stddef.h>

#define TTF_OK 0
#define TTF_ERR_IO -1
#define TTF_ERR_FORMAT -2
#define TTF_ERR_UNSUPPORTED -3
#define TTF_ERR_RANGE -4
#define TTF_ERR_OOM -5

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t *data;
    size_t size;
    uint16_t unitsPerEm;
    uint16_t numGlyphs;
    uint16_t indexToLocFormat;
    uint32_t cmapOffset;
    uint32_t cmapLength;
    uint32_t glyfOffset;
    uint32_t locaOffset;
    uint32_t headOffset;
    /* 1.0 内存优化新增：流式读取支持与小表缓存 */
    void *file;           /* VFS 文件句柄 (luat_fs_fopen 返回的 FILE*)，无数据整读时有效 */
    size_t fileSize;      /* 字体文件大小 */
    uint8_t streaming;    /* 1 表示未整读，仅按需读取 */
    uint8_t *cmapBuf;     /* 常驻内存的 cmap 子表数据（按需加载） */
    uint32_t cmapBufLen;  /* cmapBuf 长度 */
    uint16_t cmapFormat;  /* 4 或 12，标记当前常驻的 cmap 子表格式 */
} TtfFont;

typedef struct {
    int16_t x;
    int16_t y;
    uint8_t onCurve;
} TtfPoint;

typedef struct {
    int16_t minX;
    int16_t minY;
    int16_t maxX;
    int16_t maxY;
    uint16_t contourCount;
    uint16_t *contourEnds;
    uint16_t pointCount;
    TtfPoint *points;
} TtfGlyph;

typedef struct {
    uint32_t width;
    uint32_t height;
    int32_t originX;
    int32_t originY;
    float scale;
    uint8_t *pixels;
} TtfBitmap;

int ttf_load_from_file(const char *path, TtfFont *font);
void ttf_unload(TtfFont *font);

/* 调试开关：1 开启详细日志，0 关闭 */
int ttf_set_debug(int enable);
int ttf_get_debug(void);
int ttf_get_supersample_rate(void);

int ttf_lookup_glyph_index(const TtfFont *font, uint32_t codepoint, uint16_t *glyphIndex);
int ttf_load_glyph(const TtfFont *font, uint16_t glyphIndex, TtfGlyph *glyph);
void ttf_free_glyph(TtfGlyph *glyph);

int ttf_rasterize_glyph(const TtfFont *font, const TtfGlyph *glyph, int ppem, TtfBitmap *bitmap);
void ttf_free_bitmap(TtfBitmap *bitmap);

#ifdef __cplusplus
}
#endif

#endif /* TTF_PARSER_H */
