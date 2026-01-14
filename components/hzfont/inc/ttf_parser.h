#ifndef TTF_PARSER_H
#define TTF_PARSER_H

#include <stdint.h>
#include <stddef.h>

#include "hzfont_psram.h"

#define TTF_OK 0
#define TTF_ERR_IO -1
#define TTF_ERR_FORMAT -2
#define TTF_ERR_UNSUPPORTED -3
#define TTF_ERR_RANGE -4
#define TTF_ERR_OOM -5

#define TTF_DATA_SOURCE_MEMORY      0
#define TTF_DATA_SOURCE_FILE        1
#define TTF_DATA_SOURCE_PSRAM_CHAIN 2

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    /** 基本字体结构体核心参数说明 */
    uint8_t *data;             // 指向字体文件内存数据的指针（全部映射或部分缓冲区）
    size_t size;               // 字体文件（TTF/OTF）的字节数
    uint16_t unitsPerEm;       // 字体缩放单位，每个 EM 的刻度数（通常为2048或1000）
    uint16_t numGlyphs;        // 字体中包含的 glyph 总数
    uint16_t indexToLocFormat; // loca 表存储格式：0=short（16位），1=long（32位）
    uint32_t cmapOffset;       // 字体文件内 cmap 表的偏移（查 Unicode -> glyph）
    uint32_t cmapLength;       // cmap 表的长度（字节）
    uint32_t glyfOffset;       // 字体文件内 glyf 表的偏移（矢量定义与描述）
    uint32_t locaOffset;       // loca 表的偏移，用于glyph查找（glyf表每个字形偏移表）
    uint32_t headOffset;       // head 表的偏移（全局font信息，如版式/边界等）
    /* 内存优化：流式读取支持与小表缓存 */
    void *file;           /* VFS 文件句柄 (luat_fs_fopen 返回的 FILE*)，无数据整读时有效 */
    size_t fileSize;      /* 字体文件大小 */
    uint8_t streaming;    /* 1 表示未整读，仅按需读取 */
    uint8_t ownsData;     /* 1 表示 data 由解析器分配并在 unload 释放；0 表示外部内存（不可释放） */
    uint8_t data_source;  /* 0=memory,1=file,2=psram_chain */
    hzfont_psram_chain_t *psram_chain; /* PSRAM 分段链，data_source=2 时有效 */
    uint8_t *cmapBuf;     /* 常驻内存的 cmap 子表数据（按需加载） */
    uint32_t cmapBufLen;  /* cmapBuf 长度 */
    uint16_t cmapFormat;  /* 4 或 12，标记当前常驻的 cmap 子表格式 */
    uint32_t cmapBufOffset; /* 缓存子表的绝对偏移，便于快速判断是否命中 */
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

// 从文件流式加载 TTF 字体，保留文件句柄以按需读取
int ttf_load_from_file(const char *path, TtfFont *font);
// 从内存读取 TTF 字体（不复制内容），适合内置字库
int ttf_load_from_memory(const uint8_t *data, size_t size, TtfFont *font);
int ttf_load_from_psram_chain(hzfont_psram_chain_t *chain, TtfFont *font);
// 释放字体结构的全部资源
void ttf_unload(TtfFont *font);

/* 调试开关：1 开启详细日志，0 关闭 */
// 设置调试日志开关
int ttf_set_debug(int enable);
// 查询当前调试设置
int ttf_get_debug(void);
// 读取当前超采样率
int ttf_get_supersample_rate(void);
/* 运行时设置超采样率：仅允许 1(无AA)、2(2x2)、4(4x4)，非法值将被修正到最近的允许值 */
// 设定超采样等级（会修正为 1/2/4）
int ttf_set_supersample_rate(int rate);

// 根据码点查询 glyph 索引
int ttf_lookup_glyph_index(const TtfFont *font, uint32_t codepoint, uint16_t *glyphIndex);
// 载入 glyph 轮廓数据
int ttf_load_glyph(const TtfFont *font, uint16_t glyphIndex, TtfGlyph *glyph);
// 释放 glyph 结构内部分配的内存
void ttf_free_glyph(TtfGlyph *glyph);

// 将 glyph 栅格化成灰度 bitmap（支持超采样）
int ttf_rasterize_glyph(const TtfFont *font, const TtfGlyph *glyph, int ppem, TtfBitmap *bitmap);
// 释放 bitmap 内的像素缓冲
void ttf_free_bitmap(TtfBitmap *bitmap);

#ifdef __cplusplus
}
#endif

#endif /* TTF_PARSER_H */
