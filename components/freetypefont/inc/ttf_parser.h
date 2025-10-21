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

int ttf_lookup_glyph_index(const TtfFont *font, uint32_t codepoint, uint16_t *glyphIndex);
int ttf_load_glyph(const TtfFont *font, uint16_t glyphIndex, TtfGlyph *glyph);
void ttf_free_glyph(TtfGlyph *glyph);

int ttf_rasterize_glyph(const TtfFont *font, const TtfGlyph *glyph, int ppem, TtfBitmap *bitmap);
void ttf_free_bitmap(TtfBitmap *bitmap);

#ifdef __cplusplus
}
#endif

#endif /* TTF_PARSER_H */
