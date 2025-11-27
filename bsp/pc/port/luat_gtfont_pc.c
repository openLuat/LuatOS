#ifdef LUAT_USE_GUI

#include <stdint.h>
#include <string.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "luat_base.h"
#include "GT5SLCD2E_1A.h"

// PC 仿真假 gtfont 字模：内置 TTF 解析+栅格逻辑 (参考 components/hzfont/src/ttf_parser.c)

#define GTFONT_TTF_CACHE_SIZE 2048

#define TTF_OK 0
#define TTF_ERR_IO -1
#define TTF_ERR_FORMAT -2
#define TTF_ERR_UNSUPPORTED -3
#define TTF_ERR_RANGE -4
#define TTF_ERR_OOM -5

#define TTF_TAG(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))
#define TTF_FIXED_SHIFT 8
#define TTF_FIXED_ONE   (1 << TTF_FIXED_SHIFT)
#define TTF_FIXED_HALF  (1 << (TTF_FIXED_SHIFT - 1))

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
    int16_t ascender;
    int16_t descender;
    uint16_t numOfLongHorMetrics;
    uint16_t *hmtxAdvance;
    uint8_t *cmapBuf;
    uint32_t cmapBufLen;
    uint16_t cmapFormat;
    uint32_t cmapBufOffset;
} GtTtfFont;

typedef struct {
    int16_t x;
    int16_t y;
    uint8_t onCurve;
} GtPoint;

typedef struct {
    int16_t minX;
    int16_t minY;
    int16_t maxX;
    int16_t maxY;
    uint16_t contourCount;
    uint16_t *contourEnds;
    uint16_t pointCount;
    GtPoint *points;
} GtGlyph;

typedef struct {
    uint32_t width;
    uint32_t height;
    int32_t originX;
    int32_t originY;
    float scale;
    uint8_t *pixels;
} GtBitmap;

static GtTtfFont s_gtfont = {0};
static int s_gtfont_ready = 0;
static int s_gtfont_supersample_rate = 1;

static inline uint16_t read_u16(const uint8_t *p) {
    return (uint16_t)((p[0] << 8) | p[1]);
}

static inline int16_t read_s16(const uint8_t *p) {
    return (int16_t)((p[0] << 8) | p[1]);
}

static inline uint32_t read_u32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static inline float read_f2dot14(const uint8_t *p) {
    int16_t value = read_s16(p);
    return (float)value / 16384.0f;
}

static inline int32_t round_to_int32(float value) {
    return (int32_t)(value >= 0.0f ? value + 0.5f : value - 0.5f);
}

static int ensure_range(const GtTtfFont *font, uint32_t offset, uint32_t length) {
    if (!font || !font->data) return 0;
    if (offset > font->size) return 0;
    if (length > font->size - offset) return 0;
    return 1;
}

static int gtfont_read_range(const GtTtfFont *font, uint32_t offset, uint32_t length, uint8_t *out) {
    if (!font || !font->data || !out || length == 0) return 0;
    if (!ensure_range(font, offset, length)) return 0;
    memcpy(out, font->data + offset, length);
    return 1;
}

typedef struct {
    uint32_t offset;
    uint32_t length;
} TableRecord;

typedef struct {
    uint32_t offset;
    uint32_t length;
} CmapSubtable;

static int read_u16_at(const GtTtfFont *font, uint32_t absOff, uint16_t *out) {
    uint8_t b[2];
    if (font && font->cmapBuf && absOff >= font->cmapBufOffset &&
        absOff + 2 <= font->cmapBufOffset + font->cmapBufLen) {
        const uint8_t *ptr = font->cmapBuf + (absOff - font->cmapBufOffset);
        *out = read_u16(ptr);
        return 1;
    }
    if (!gtfont_read_range(font, absOff, 2, b)) return 0;
    *out = read_u16(b);
    return 1;
}

static int read_u32_at(const GtTtfFont *font, uint32_t absOff, uint32_t *out) {
    uint8_t b[4];
    if (font && font->cmapBuf && absOff >= font->cmapBufOffset &&
        absOff + 4 <= font->cmapBufOffset + font->cmapBufLen) {
        const uint8_t *ptr = font->cmapBuf + (absOff - font->cmapBufOffset);
        *out = read_u32(ptr);
        return 1;
    }
    if (!gtfont_read_range(font, absOff, 4, b)) return 0;
    *out = read_u32(b);
    return 1;
}

static int find_cmap_format12(const GtTtfFont *font, CmapSubtable *out) {
    if (!font || !font->data) {
        return 0;
    }
    if (font->cmapLength < 4) {
        return 0;
    }
    uint32_t cmapBase = font->cmapOffset;
    uint16_t numTables = 0;
    if (!read_u16_at(font, cmapBase + 2, &numTables)) return 0;
    uint32_t recordsSize = 4u + (uint32_t)numTables * 8u;
    if (font->cmapLength < recordsSize) {
        return 0;
    }
    CmapSubtable chosen = {0};
    for (uint16_t i = 0; i < numTables; ++i) {
        uint32_t recOff = cmapBase + 4u + (uint32_t)i * 8u;
        uint16_t platformID = 0, encodingID = 0;
        uint32_t subOffRel = 0;
        if (!read_u16_at(font, recOff, &platformID)) return 0;
        if (!read_u16_at(font, recOff + 2, &encodingID)) return 0;
        if (!read_u32_at(font, recOff + 4, &subOffRel)) return 0;
        if (subOffRel >= font->cmapLength) continue;
        uint32_t subAbs = cmapBase + subOffRel;
        uint16_t format = 0;
        if (!read_u16_at(font, subAbs, &format)) continue;
        if (format == 12) {
            if (font->cmapLength - subOffRel < 16) continue;
            if (!chosen.offset || (platformID == 3 && encodingID == 10) || (platformID == 0)) {
                chosen.offset = subAbs;
                chosen.length = font->cmapLength - subOffRel;
                if (platformID == 3 && encodingID == 10) {
                    break;
                }
            }
        }
    }
    if (!chosen.offset) {
        return 0;
    }
    *out = chosen;
    return 1;
}

static int find_cmap_format4(const GtTtfFont *font, CmapSubtable *out) {
    if (!font || !font->data) {
        return 0;
    }
    if (font->cmapLength < 4) {
        return 0;
    }
    uint32_t cmapBase = font->cmapOffset;
    uint16_t numTables = 0;
    if (!read_u16_at(font, cmapBase + 2, &numTables)) return 0;
    uint32_t recordsSize = 4u + (uint32_t)numTables * 8u;
    if (font->cmapLength < recordsSize) {
        return 0;
    }
    CmapSubtable chosen = {0};
    for (uint16_t i = 0; i < numTables; ++i) {
        uint32_t recOff = cmapBase + 4u + (uint32_t)i * 8u;
        uint16_t platformID = 0, encodingID = 0;
        uint32_t subOffRel = 0;
        if (!read_u16_at(font, recOff, &platformID)) return 0;
        if (!read_u16_at(font, recOff + 2, &encodingID)) return 0;
        if (!read_u32_at(font, recOff + 4, &subOffRel)) return 0;
        if (subOffRel >= font->cmapLength) continue;
        uint32_t subAbs = cmapBase + subOffRel;
        uint16_t format = 0;
        if (!read_u16_at(font, subAbs, &format)) continue;
        if (format == 4) {
            if (!chosen.offset || (platformID == 3 && (encodingID == 1 || encodingID == 10))) {
                chosen.offset = subAbs;
                chosen.length = font->cmapLength - subOffRel;
                if (platformID == 3 && encodingID == 1) {
                    break;
                }
            }
        }
    }
    if (!chosen.offset || chosen.length < 16) {
        return 0;
    }
    *out = chosen;
    return 1;
}

static void gtfont_cache_cmap_subtable(GtTtfFont *font) {
    if (!font || !font->data) {
        return;
    }
    if (font->cmapBuf) {
        return;
    }
    CmapSubtable chosen = {0};
    uint16_t format = 0;
    if (find_cmap_format12(font, &chosen)) {
        format = 12;
    } else if (find_cmap_format4(font, &chosen)) {
        format = 4;
    } else {
        return;
    }
    if (chosen.length == 0 || chosen.length > GTFONT_TTF_CACHE_SIZE) {
        return;
    }
    uint8_t *buf = (uint8_t *)malloc(chosen.length);
    if (!buf) {
        return;
    }
    if (!gtfont_read_range(font, chosen.offset, chosen.length, buf)) {
        free(buf);
        return;
    }
    font->cmapBuf = buf;
    font->cmapBufLen = chosen.length;
    font->cmapBufOffset = chosen.offset;
    font->cmapFormat = format;
}

static int gtfont_lookup_format12(const GtTtfFont *font, const CmapSubtable *cmap, uint32_t codepoint, uint16_t numGlyphs, uint16_t *glyphIndex) {
    if (!cmap || !glyphIndex) {
        return TTF_ERR_RANGE;
    }
    if (cmap->length < 16) {
        return TTF_ERR_FORMAT;
    }
    uint32_t length = 0;
    if (!read_u32_at(font, cmap->offset + 4, &length)) return TTF_ERR_IO;
    if (length > cmap->length) {
        return TTF_ERR_FORMAT;
    }
    uint32_t nGroups = 0;
    if (!read_u32_at(font, cmap->offset + 12, &nGroups)) return TTF_ERR_IO;
    if (nGroups == 0) {
        return TTF_ERR_RANGE;
    }
    uint64_t required = 16u + (uint64_t)nGroups * 12u;
    if (required > cmap->length) {
        return TTF_ERR_FORMAT;
    }
    uint32_t lo = 0;
    uint32_t hi = nGroups;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2u;
        uint32_t groupOff = cmap->offset + 16u + mid * 12u;
        uint32_t startCode = 0, endCode = 0;
        if (!read_u32_at(font, groupOff, &startCode)) return TTF_ERR_IO;
        if (!read_u32_at(font, groupOff + 4, &endCode)) return TTF_ERR_IO;
        if (codepoint < startCode) {
            hi = mid;
            continue;
        }
        if (codepoint > endCode) {
            lo = mid + 1u;
            continue;
        }
        uint32_t startGlyphId = 0;
        if (!read_u32_at(font, groupOff + 8, &startGlyphId)) return TTF_ERR_IO;
        uint64_t glyph = (uint64_t)startGlyphId + (uint64_t)(codepoint - startCode);
        if (glyph >= numGlyphs || glyph > 0xFFFFu) {
            return TTF_ERR_RANGE;
        }
        *glyphIndex = (uint16_t)glyph;
        return TTF_OK;
    }
    return TTF_ERR_RANGE;
}

static int gtfont_lookup_glyph_index(const GtTtfFont *font, uint32_t codepoint, uint16_t *glyphIndex) {
    if (!font || !glyphIndex) {
        return TTF_ERR_RANGE;
    }

    CmapSubtable cmap12 = {0};
    if (find_cmap_format12(font, &cmap12)) {
        int rc = gtfont_lookup_format12(font, &cmap12, codepoint, font->numGlyphs, glyphIndex);
        if (rc == TTF_OK) {
            return TTF_OK;
        }
        if (rc != TTF_ERR_RANGE) {
            return rc;
        }
    }

    CmapSubtable cmap4 = {0};
    if (!find_cmap_format4(font, &cmap4)) {
        return TTF_ERR_UNSUPPORTED;
    }
    uint16_t length = 0;
    if (!read_u16_at(font, cmap4.offset + 2, &length)) return TTF_ERR_IO;
    if (length > cmap4.length || length < 24) {
        return TTF_ERR_FORMAT;
    }
    uint16_t segCountX2 = 0;
    if (!read_u16_at(font, cmap4.offset + 6, &segCountX2)) return TTF_ERR_IO;
    if (segCountX2 == 0 || 14 + segCountX2 * 2 > length) {
        return TTF_ERR_FORMAT;
    }
    uint16_t segCount = segCountX2 / 2;
    uint32_t endCodes = cmap4.offset + 14;
    uint32_t startCodes = endCodes + segCount * 2 + 2;
    uint32_t idDeltas = startCodes + segCount * 2;
    uint32_t idRangeOffsets = idDeltas + segCount * 2;
    uint32_t glyphIdArray = idRangeOffsets + segCount * 2;
    if ((glyphIdArray - cmap4.offset) > cmap4.length) {
        return TTF_ERR_FORMAT;
    }

    for (uint16_t i = 0; i < segCount; ++i) {
        uint16_t endCode = 0, startCodeV = 0;
        if (!read_u16_at(font, endCodes + i * 2, &endCode)) return TTF_ERR_IO;
        if (!read_u16_at(font, startCodes + i * 2, &startCodeV)) return TTF_ERR_IO;
        if (codepoint < startCodeV || codepoint > endCode) {
            continue;
        }
        uint16_t idDeltaV = 0, idRangeOffsetV = 0;
        if (!read_u16_at(font, idDeltas + i * 2, &idDeltaV)) return TTF_ERR_IO;
        if (!read_u16_at(font, idRangeOffsets + i * 2, &idRangeOffsetV)) return TTF_ERR_IO;
        if (idRangeOffsetV == 0) {
            *glyphIndex = (uint16_t)((codepoint + idDeltaV) & 0xFFFF);
            if (*glyphIndex >= font->numGlyphs) {
                return TTF_ERR_RANGE;
            }
            return TTF_OK;
        }
        uint32_t p = idRangeOffsets + i * 2 + idRangeOffsetV + 2u * (codepoint - startCodeV);
        if ((p + 2) > (cmap4.offset + cmap4.length)) {
            return TTF_ERR_FORMAT;
        }
        uint16_t glyphId = 0;
        if (!read_u16_at(font, p, &glyphId)) return TTF_ERR_IO;
        if (glyphId == 0) {
            *glyphIndex = 0;
            return TTF_OK;
        }
        *glyphIndex = (uint16_t)((glyphId + idDeltaV) & 0xFFFF);
        if (*glyphIndex >= font->numGlyphs) {
            return TTF_ERR_RANGE;
        }
        return TTF_OK;
    }
    return TTF_ERR_RANGE;
}

static int get_glyph_offset(const GtTtfFont *font, uint16_t glyphIndex, uint32_t *offset, uint32_t *length) {
    if (!font || glyphIndex > font->numGlyphs) {
        return 0;
    }
    uint32_t glyphOffset = 0;
    uint32_t nextOffset = 0;
    if (font->indexToLocFormat == 0) {
        uint32_t entryOffset = font->locaOffset + glyphIndex * 2;
        uint32_t entryNext = font->locaOffset + (glyphIndex + 1) * 2;
        uint8_t buf[4];
        if (!gtfont_read_range(font, entryOffset, 2, buf)) return 0;
        if (!gtfont_read_range(font, entryNext, 2, buf + 2)) return 0;
        glyphOffset = (uint32_t)read_u16(buf) * 2;
        nextOffset = (uint32_t)read_u16(buf + 2) * 2;
    } else {
        uint32_t entryOffset = font->locaOffset + glyphIndex * 4;
        uint32_t entryNext = font->locaOffset + (glyphIndex + 1) * 4;
        uint8_t buf[8];
        if (!gtfont_read_range(font, entryOffset, 4, buf)) return 0;
        if (!gtfont_read_range(font, entryNext, 4, buf + 4)) return 0;
        glyphOffset = read_u32(buf);
        nextOffset = read_u32(buf + 4);
    }
    if (glyphOffset > nextOffset) {
        return 0;
    }
    if (!ensure_range(font, font->glyfOffset + glyphOffset, nextOffset - glyphOffset)) {
        return 0;
    }
    *offset = font->glyfOffset + glyphOffset;
    *length = nextOffset - glyphOffset;
    return 1;
}

static void gtfont_free_glyph(GtGlyph *glyph) {
    if (!glyph) {
        return;
    }
    free(glyph->contourEnds);
    free(glyph->points);
    memset(glyph, 0, sizeof(*glyph));
}

static int append_component_glyph(GtGlyph *dest, const GtGlyph *src,
                                  float m00, float m01, float m10, float m11,
                                  float dx, float dy) {
    if (!dest || !src) {
        return TTF_ERR_RANGE;
    }
    if (src->pointCount == 0 || src->contourCount == 0) {
        return TTF_OK;
    }
    uint32_t newPointCount = (uint32_t)dest->pointCount + (uint32_t)src->pointCount;
    if (newPointCount > 0xFFFFu) {
        return TTF_ERR_FORMAT;
    }
    uint32_t newContourCount = (uint32_t)dest->contourCount + (uint32_t)src->contourCount;
    if (newContourCount > 0xFFFFu) {
        return TTF_ERR_FORMAT;
    }

    GtPoint *points = (GtPoint *)realloc(dest->points, newPointCount * sizeof(GtPoint));
    if (!points) {
        return TTF_ERR_OOM;
    }
    dest->points = points;

    uint16_t *contours = (uint16_t *)realloc(dest->contourEnds, newContourCount * sizeof(uint16_t));
    if (!contours) {
        return TTF_ERR_OOM;
    }
    dest->contourEnds = contours;

    uint16_t basePoint = dest->pointCount;
    uint16_t baseContour = dest->contourCount;
    for (uint16_t i = 0; i < src->pointCount; ++i) {
        float x = (float)src->points[i].x;
        float y = (float)src->points[i].y;
        float tx = x * m00 + y * m01 + dx;
        float ty = x * m10 + y * m11 + dy;
        int32_t ix = round_to_int32(tx);
        int32_t iy = round_to_int32(ty);
        if (ix < -32768) {
            ix = -32768;
        } else if (ix > 32767) {
            ix = 32767;
        }
        if (iy < -32768) {
            iy = -32768;
        } else if (iy > 32767) {
            iy = 32767;
        }
        dest->points[basePoint + i].x = (int16_t)ix;
        dest->points[basePoint + i].y = (int16_t)iy;
        dest->points[basePoint + i].onCurve = src->points[i].onCurve;
    }
    for (uint16_t c = 0; c < src->contourCount; ++c) {
        uint32_t end = (uint32_t)basePoint + (uint32_t)src->contourEnds[c];
        if (end > 0xFFFFu) {
            return TTF_ERR_FORMAT;
        }
        dest->contourEnds[baseContour + c] = (uint16_t)end;
    }
    dest->pointCount = (uint16_t)newPointCount;
    dest->contourCount = (uint16_t)newContourCount;
    return TTF_OK;
}

static int gtfont_load_glyph_internal(const GtTtfFont *font, uint16_t glyphIndex, GtGlyph *glyph, int depth) {
    if (!font || !glyph) {
        return TTF_ERR_RANGE;
    }
    if (depth > 16) {
        return TTF_ERR_UNSUPPORTED;
    }
    memset(glyph, 0, sizeof(*glyph));

    uint32_t offset = 0;
    uint32_t length = 0;
    if (!get_glyph_offset(font, glyphIndex, &offset, &length)) {
        return TTF_ERR_RANGE;
    }
    if (length == 0) {
        return TTF_OK;
    }
    if (!ensure_range(font, offset, length) || length < 10) {
        return TTF_ERR_FORMAT;
    }

    uint8_t *tmp = (uint8_t*)malloc(length);
    if (!tmp) {
        return TTF_ERR_OOM;
    }
    if (!gtfont_read_range(font, offset, length, tmp)) {
        free(tmp);
        return TTF_ERR_IO;
    }
    const uint8_t *ptr = tmp;
    const uint8_t *end = tmp + length;
    int16_t numberOfContours = read_s16(ptr);
    glyph->minX = read_s16(ptr + 2);
    glyph->minY = read_s16(ptr + 4);
    glyph->maxX = read_s16(ptr + 6);
    glyph->maxY = read_s16(ptr + 8);

    if (numberOfContours >= 0) {
        glyph->contourCount = (uint16_t)numberOfContours;
        uint32_t headerBytes = 10u + (uint32_t)glyph->contourCount * 2u + 2u;
        if (length < headerBytes) {
            free(tmp);
            return TTF_ERR_FORMAT;
        }

        glyph->contourEnds = (uint16_t *)calloc(glyph->contourCount, sizeof(uint16_t));
        if (!glyph->contourEnds) {
            free(tmp);
            return TTF_ERR_OOM;
        }
        const uint8_t *contourPtr = ptr + 10;
        for (uint16_t i = 0; i < glyph->contourCount; ++i) {
            glyph->contourEnds[i] = read_u16(contourPtr + i * 2);
        }

        uint16_t instructionLength = read_u16(contourPtr + glyph->contourCount * 2);
        const uint8_t *instructionPtr = contourPtr + glyph->contourCount * 2 + 2;
        if (instructionPtr + instructionLength > end) {
            gtfont_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_FORMAT;
        }
        const uint8_t *flagsPtr = instructionPtr + instructionLength;

        if (glyph->contourEnds[glyph->contourCount - 1] >= 0xFFFFu) {
            gtfont_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_FORMAT;
        }
        glyph->pointCount = glyph->contourEnds[glyph->contourCount - 1] + 1;
        if (glyph->pointCount == 0) {
            free(tmp);
            return TTF_OK;
        }

        uint8_t *flags = (uint8_t *)malloc(glyph->pointCount);
        if (!flags) {
            gtfont_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_OOM;
        }
        const uint8_t *cursor = flagsPtr;
        uint16_t flagIndex = 0;
        while (flagIndex < glyph->pointCount) {
            if (cursor >= end) {
                free(flags);
                gtfont_free_glyph(glyph);
                free(tmp);
                return TTF_ERR_FORMAT;
            }
            uint8_t flag = *cursor++;
            flags[flagIndex++] = flag;
            if (flag & 0x08) {
                if (cursor >= end) {
                    free(flags);
                    gtfont_free_glyph(glyph);
                    free(tmp);
                    return TTF_ERR_FORMAT;
                }
                uint8_t repeatCount = *cursor++;
                if (flagIndex + repeatCount > glyph->pointCount) {
                    free(flags);
                    gtfont_free_glyph(glyph);
                    free(tmp);
                    return TTF_ERR_FORMAT;
                }
                for (uint8_t r = 0; r < repeatCount; ++r) {
                    flags[flagIndex++] = flag;
                }
            }
        }

        glyph->points = (GtPoint *)calloc(glyph->pointCount, sizeof(GtPoint));
        if (!glyph->points) {
            free(flags);
            gtfont_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_OOM;
        }

        int16_t x = 0;
        flagIndex = 0;
        while (flagIndex < glyph->pointCount) {
            uint8_t flag = flags[flagIndex++];
            if (flag & 0x02) {
                if (cursor >= end) {
                    free(flags);
                    gtfont_free_glyph(glyph);
                    free(tmp);
                    return TTF_ERR_FORMAT;
                }
                uint8_t dx = *cursor++;
                x += (flag & 0x10) ? dx : -(int16_t)dx;
            } else if (!(flag & 0x10)) {
                if (cursor + 1 >= end) {
                    free(flags);
                    gtfont_free_glyph(glyph);
                    free(tmp);
                    return TTF_ERR_FORMAT;
                }
                int16_t dx = read_s16(cursor);
                cursor += 2;
                x += dx;
            }
            glyph->points[flagIndex - 1].x = x;
        }

        int16_t y = 0;
        flagIndex = 0;
        while (flagIndex < glyph->pointCount) {
            uint8_t flag = flags[flagIndex];
            if (flag & 0x04) {
                if (cursor >= end) {
                    free(flags);
                    gtfont_free_glyph(glyph);
                    free(tmp);
                    return TTF_ERR_FORMAT;
                }
                uint8_t dy = *cursor++;
                y += (flag & 0x20) ? dy : -(int16_t)dy;
            } else if (!(flag & 0x20)) {
                if (cursor + 1 >= end) {
                    free(flags);
                    gtfont_free_glyph(glyph);
                    free(tmp);
                    return TTF_ERR_FORMAT;
                }
                int16_t dy = read_s16(cursor);
                cursor += 2;
                y += dy;
            }
            glyph->points[flagIndex].y = y;
            glyph->points[flagIndex].onCurve = (flags[flagIndex] & 0x01) ? 1 : 0;
            ++flagIndex;
        }
        free(flags);
        free(tmp);
        return TTF_OK;
    }

    const uint8_t *cursor = ptr + 10;
    uint16_t flags = 0;
    do {
        if (cursor + 4 > end) {
            gtfont_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_FORMAT;
        }
        flags = read_u16(cursor);
        cursor += 2;
        uint16_t componentIndex = read_u16(cursor);
        cursor += 2;

        int16_t arg1 = 0;
        int16_t arg2 = 0;
        if (flags & 0x0001) {
            if (cursor + 4 > end) {
                gtfont_free_glyph(glyph);
                free(tmp);
                return TTF_ERR_FORMAT;
            }
            arg1 = read_s16(cursor);
            arg2 = read_s16(cursor + 2);
            cursor += 4;
        } else {
            if (cursor + 2 > end) {
                gtfont_free_glyph(glyph);
                free(tmp);
                return TTF_ERR_FORMAT;
            }
            arg1 = (int8_t)cursor[0];
            arg2 = (int8_t)cursor[1];
            cursor += 2;
        }

        float dx = 0.0f;
        float dy = 0.0f;
        if (flags & 0x0002) {
            dx = (float)arg1;
            dy = (float)arg2;
        } else {
            gtfont_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_UNSUPPORTED;
        }

        float m00 = 1.0f;
        float m01 = 0.0f;
        float m10 = 0.0f;
        float m11 = 1.0f;
        if (flags & 0x0008) {
            if (cursor + 2 > end) {
                gtfont_free_glyph(glyph);
                free(tmp);
                return TTF_ERR_FORMAT;
            }
            float scale = read_f2dot14(cursor);
            cursor += 2;
            m00 = scale;
            m11 = scale;
        } else if (flags & 0x0040) {
            if (cursor + 4 > end) {
                gtfont_free_glyph(glyph);
                free(tmp);
                return TTF_ERR_FORMAT;
            }
            m00 = read_f2dot14(cursor);
            m11 = read_f2dot14(cursor + 2);
            cursor += 4;
        } else if (flags & 0x0080) {
            if (cursor + 8 > end) {
                gtfont_free_glyph(glyph);
                free(tmp);
                return TTF_ERR_FORMAT;
            }
            m00 = read_f2dot14(cursor);
            m01 = read_f2dot14(cursor + 2);
            m10 = read_f2dot14(cursor + 4);
            m11 = read_f2dot14(cursor + 6);
            cursor += 8;
        }
        if (flags & 0x0800) {
            dx *= m00;
            dy *= m11;
        }

        GtGlyph componentGlyph;
        int rc = gtfont_load_glyph_internal(font, componentIndex, &componentGlyph, depth + 1);
        if (rc != TTF_OK) {
            gtfont_free_glyph(&componentGlyph);
            gtfont_free_glyph(glyph);
            free(tmp);
            return rc;
        }
        rc = append_component_glyph(glyph, &componentGlyph, m00, m01, m10, m11, dx, dy);
        gtfont_free_glyph(&componentGlyph);
        if (rc != TTF_OK) {
            gtfont_free_glyph(glyph);
            free(tmp);
            return rc;
        }
    } while (flags & 0x0020);

    if (flags & 0x0100) {
        if (cursor + 2 > end) {
            gtfont_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_FORMAT;
        }
        uint16_t instructionLength = read_u16(cursor);
        cursor += 2;
        if (cursor + instructionLength > end) {
            gtfont_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_FORMAT;
        }
        cursor += instructionLength;
    }

    free(tmp);
    return TTF_OK;
}

static int gtfont_load_glyph(const GtTtfFont *font, uint16_t glyphIndex, GtGlyph *glyph) {
    return gtfont_load_glyph_internal(font, glyphIndex, glyph, 0);
}

typedef struct {
    float *data;
    size_t count;
    size_t capacity;
} SegmentList;

typedef struct {
    int32_t *data;
    size_t count;
} FixedSegmentList;

static int append_segment(SegmentList *segments, float x0, float y0, float x1, float y1) {
    if (!segments) {
        return 0;
    }
    if (fabsf(x0 - x1) < 1e-5f && fabsf(y0 - y1) < 1e-5f) {
        return 1;
    }
    if (segments->count * 4 + 4 > segments->capacity) {
        size_t newCapacity = segments->capacity ? segments->capacity * 2 : 128;
        while (segments->count * 4 + 4 > newCapacity) {
            newCapacity *= 2;
        }
        float *newData = (float *)realloc(segments->data, newCapacity * sizeof(float));
        if (!newData) {
            return 0;
        }
        segments->data = newData;
        segments->capacity = newCapacity;
    }
    float *dest = segments->data + segments->count * 4;
    dest[0] = x0;
    dest[1] = y0;
    dest[2] = x1;
    dest[3] = y1;
    segments->count += 1;
    return 1;
}

static inline int32_t float_to_fixed(float value) {
    float scaled = value * (float)TTF_FIXED_ONE;
    return (int32_t)lrintf(scaled);
}

static int convert_segments_to_fixed(const SegmentList *src, FixedSegmentList *dst) {
    if (!dst) {
        return 0;
    }
    dst->data = NULL;
    dst->count = 0;
    if (!src || src->count == 0) {
        return 1;
    }
    size_t total = src->count * 4;
    int32_t *buf = (int32_t *)malloc(total * sizeof(int32_t));
    if (!buf) {
        return 0;
    }
    for (size_t i = 0; i < src->count; ++i) {
        buf[i * 4 + 0] = float_to_fixed(src->data[i * 4 + 0]);
        buf[i * 4 + 1] = float_to_fixed(src->data[i * 4 + 1]);
        buf[i * 4 + 2] = float_to_fixed(src->data[i * 4 + 2]);
        buf[i * 4 + 3] = float_to_fixed(src->data[i * 4 + 3]);
    }
    dst->data = buf;
    dst->count = src->count;
    return 1;
}

static void free_fixed_segments(FixedSegmentList *segments) {
    if (!segments) {
        return;
    }
    free(segments->data);
    segments->data = NULL;
    segments->count = 0;
}

static int flatten_quadratic(SegmentList *segments, float x0, float y0, float cx, float cy, float x1, float y1, int steps) {
    float prevX = x0;
    float prevY = y0;
    for (int i = 1; i <= steps; ++i) {
        float t = (float)i / (float)steps;
        float mt = 1.0f - t;
        float x = mt * mt * x0 + 2.0f * mt * t * cx + t * t * x1;
        float y = mt * mt * y0 + 2.0f * mt * t * cy + t * t * y1;
        if (!append_segment(segments, prevX, prevY, x, y)) {
            return 0;
        }
        prevX = x;
        prevY = y;
    }
    return 1;
}

static GtPoint midpoint_point(const GtPoint *a, const GtPoint *b) {
    GtPoint result;
    result.x = (int16_t)((a->x + b->x) / 2);
    result.y = (int16_t)((a->y + b->y) / 2);
    result.onCurve = 1;
    return result;
}

static void transform_point(const GtGlyph *glyph, float scale, float offsetX, float offsetY,
                            const GtPoint *pt, float *outX, float *outY) {
    *outX = (pt->x - glyph->minX) * scale + offsetX;
    *outY = (glyph->maxY - pt->y) * scale + offsetY;
}

static int build_segments(const GtGlyph *glyph, float scale, float offsetX, float offsetY, SegmentList *segments) {
    uint16_t contourStart = 0;
    for (uint16_t contour = 0; contour < glyph->contourCount; ++contour) {
        uint16_t contourEnd = glyph->contourEnds[contour];
        if (contourEnd < contourStart || contourEnd >= glyph->pointCount) {
            return 0;
        }
        uint16_t count = (uint16_t)(contourEnd - contourStart + 1);
        if (count == 0) {
            contourStart = (uint16_t)(contourEnd + 1);
            continue;
        }

        const GtPoint *firstPoint = &glyph->points[contourStart];
        const GtPoint *lastPoint = &glyph->points[contourEnd];
        GtPoint startOn = *lastPoint;
        if (!lastPoint->onCurve) {
            if (firstPoint->onCurve) {
                startOn = *firstPoint;
            } else {
                startOn = midpoint_point(lastPoint, firstPoint);
            }
        }

        float prevX, prevY;
        transform_point(glyph, scale, offsetX, offsetY, &startOn, &prevX, &prevY);
        float startX = prevX;
        float startY = prevY;

        uint16_t index = contourStart;
        do {
            const GtPoint *current = &glyph->points[index];
            uint16_t nextIndex = (index == contourEnd) ? contourStart : (uint16_t)(index + 1);
            const GtPoint *nextPoint = &glyph->points[nextIndex];

            if (current->onCurve) {
                float currX, currY;
                transform_point(glyph, scale, offsetX, offsetY, current, &currX, &currY);
                if (!append_segment(segments, prevX, prevY, currX, currY)) {
                    return 0;
                }
                prevX = currX;
                prevY = currY;
            } else {
                GtPoint nextOn = *nextPoint;
                if (!nextPoint->onCurve) {
                    nextOn = midpoint_point(current, nextPoint);
                }
                float ctrlX, ctrlY, nextX, nextY;
                transform_point(glyph, scale, offsetX, offsetY, current, &ctrlX, &ctrlY);
                transform_point(glyph, scale, offsetX, offsetY, &nextOn, &nextX, &nextY);
                if (!flatten_quadratic(segments, prevX, prevY, ctrlX, ctrlY, nextX, nextY, 12)) {
                    return 0;
                }
                prevX = nextX;
                prevY = nextY;
            }

            index = nextIndex;
        } while (index != contourStart);

        if (!append_segment(segments, prevX, prevY, startX, startY)) {
            return 0;
        }

        contourStart = (uint16_t)(contourEnd + 1);
    }
    return 1;
}

static int point_inside_fixed(const FixedSegmentList *segments, int32_t px, int32_t py) {
    if (!segments || segments->count == 0) {
        return 0;
    }
    int winding = 0;
    for (size_t i = 0; i < segments->count; ++i) {
        int32_t x0 = segments->data[i * 4 + 0];
        int32_t y0 = segments->data[i * 4 + 1];
        int32_t x1 = segments->data[i * 4 + 2];
        int32_t y1 = segments->data[i * 4 + 3];
        if (y0 == y1) {
            continue;
        }
        int upward = (y0 <= py && y1 > py);
        int downward = (y1 <= py && y0 > py);
        if (!(upward || downward)) {
            continue;
        }
        int32_t dy = y1 - y0;
        if (dy == 0) {
            continue;
        }
        int64_t num = (int64_t)(py - y0) * (int64_t)(x1 - x0);
        int64_t den = (int64_t)dy;
        if (den > 0) {
            num += den / 2;
        } else if (den < 0) {
            num -= (-den) / 2;
        }
        int64_t x = (int64_t)x0 + num / den;
        if (x > (int64_t)px) {
            winding ^= 1;
        }
    }
    return winding;
}

static int gtfont_rasterize_glyph(const GtTtfFont *font, const GtGlyph *glyph, int ppem, GtBitmap *bitmap) {
    if (!font || !glyph || !bitmap || ppem <= 0) {
        return TTF_ERR_RANGE;
    }
    memset(bitmap, 0, sizeof(*bitmap));

    if (glyph->pointCount == 0 || glyph->contourCount == 0) {
        return TTF_OK;
    }

    float scale = (float)ppem / (float)font->unitsPerEm;
    float widthF = (glyph->maxX - glyph->minX) * scale + 2.0f;
    float heightF = (glyph->maxY - glyph->minY) * scale + 2.0f;
    if (widthF < 1.0f) widthF = 1.0f;
    if (heightF < 1.0f) heightF = 1.0f;
    uint32_t width = (uint32_t)ceilf(widthF);
    uint32_t height = (uint32_t)ceilf(heightF);

    uint8_t *pixels = (uint8_t *)calloc((size_t)width * height, sizeof(uint8_t));
    if (!pixels) {
        return TTF_ERR_OOM;
    }

    SegmentList segments = {0};
    float offsetX = 1.0f;
    float offsetY = 1.0f;
    if (!build_segments(glyph, scale, offsetX, offsetY, &segments)) {
        free(pixels);
        free(segments.data);
        return TTF_ERR_FORMAT;
    }

    FixedSegmentList fixedSegments = {0};
    if (!convert_segments_to_fixed(&segments, &fixedSegments)) {
        free(pixels);
        free(segments.data);
        return TTF_ERR_OOM;
    }
    free(segments.data);

    const int supersampleRate = s_gtfont_supersample_rate;
    const int sampleCount = supersampleRate * supersampleRate;
    int32_t step = (supersampleRate > 0) ? (TTF_FIXED_ONE / supersampleRate) : TTF_FIXED_ONE;
    int32_t subOffset = step / 2;
    for (uint32_t y = 0; y < height; ++y) {
        int32_t baseY = ((int32_t)y << TTF_FIXED_SHIFT);
        for (uint32_t x = 0; x < width; ++x) {
            int32_t baseX = ((int32_t)x << TTF_FIXED_SHIFT);
            int insideHits = 0;
            if (supersampleRate == 1) {
                int32_t px = baseX + TTF_FIXED_HALF;
                int32_t py = baseY + TTF_FIXED_HALF;
                insideHits = point_inside_fixed(&fixedSegments, px, py);
            } else {
                for (int sy = 0; sy < supersampleRate; ++sy) {
                    int32_t py = baseY + sy * step + subOffset;
                    for (int sx = 0; sx < supersampleRate; ++sx) {
                        int32_t px = baseX + sx * step + subOffset;
                        insideHits += point_inside_fixed(&fixedSegments, px, py);
                    }
                }
            }
            if (insideHits > 0) {
                uint8_t value = (uint8_t)((insideHits * 255 + sampleCount / 2) / sampleCount);
                pixels[y * width + x] = value;
            }
        }
    }

    free_fixed_segments(&fixedSegments);
    bitmap->width = width;
    bitmap->height = height;
    bitmap->pixels = pixels;
    bitmap->originX = (int32_t)lrintf(glyph->minX * scale);
    bitmap->originY = (int32_t)lrintf(glyph->maxY * scale);
    bitmap->scale = scale;
    return TTF_OK;
}

static void gtfont_free_bitmap(GtBitmap *bitmap) {
    if (!bitmap) {
        return;
    }
    free(bitmap->pixels);
    memset(bitmap, 0, sizeof(*bitmap));
}

static int gtfont_advance_px(const GtTtfFont *font, uint16_t glyphIndex, int ppem) {
    if (!font || glyphIndex >= font->numGlyphs || !font->hmtxAdvance) {
        return 0;
    }
    float scale = (float)ppem / (float)font->unitsPerEm;
    float advF = (float)font->hmtxAdvance[glyphIndex] * scale;
    int adv = (int)lrintf(advF);
    if (adv <= 0) {
        adv = (int)ceilf((glyphIndex < font->numGlyphs) ? floorf(scale) : 1.0f);
    }
    return adv;
}

static void gtfont_unload(GtTtfFont *font) {
    if (!font) return;
    free(font->data);
    free(font->cmapBuf);
    free(font->hmtxAdvance);
    memset(font, 0, sizeof(*font));
}

static int gtfont_load_from_file(const char *path, GtTtfFont *font) {
    if (!path || !font) {
        return TTF_ERR_RANGE;
    }
    gtfont_unload(font);
    FILE *fp = fopen(path, "rb");
    if (!fp) {
        return TTF_ERR_IO;
    }
    if (fseek(fp, 0, SEEK_END) != 0) { fclose(fp); return TTF_ERR_IO; }
    long size = ftell(fp);
    if (size <= 0) { fclose(fp); return TTF_ERR_IO; }
    if (fseek(fp, 0, SEEK_SET) != 0) { fclose(fp); return TTF_ERR_IO; }
    uint8_t *data = (uint8_t *)malloc((size_t)size);
    if (!data) { fclose(fp); return TTF_ERR_OOM; }
    size_t read = fread(data, 1, (size_t)size, fp);
    fclose(fp);
    if (read != (size_t)size) {
        free(data);
        return TTF_ERR_IO;
    }
    font->data = data;
    font->size = (size_t)size;

    if (font->size < 12) {
        gtfont_unload(font);
        return TTF_ERR_FORMAT;
    }
    uint8_t hdr4[4];
    if (!gtfont_read_range(font, 0, 4, hdr4)) {
        gtfont_unload(font);
        return TTF_ERR_IO;
    }
    uint32_t scalerType = read_u32(hdr4);
    if (scalerType != 0x00010000 && scalerType != TTF_TAG('O', 'T', 'T', 'O')) {
        gtfont_unload(font);
        return TTF_ERR_UNSUPPORTED;
    }

    TableRecord cmap = {0}, glyf = {0}, loca = {0}, head = {0}, maxp = {0}, hhea = {0}, hmtx = {0};
    if (!gtfont_find_table(font, TTF_TAG('c', 'm', 'a', 'p'), &cmap) ||
        !gtfont_find_table(font, TTF_TAG('g', 'l', 'y', 'f'), &glyf) ||
        !gtfont_find_table(font, TTF_TAG('l', 'o', 'c', 'a'), &loca) ||
        !gtfont_find_table(font, TTF_TAG('h', 'e', 'a', 'd'), &head) ||
        !gtfont_find_table(font, TTF_TAG('m', 'a', 'x', 'p'), &maxp) ||
        !gtfont_find_table(font, TTF_TAG('h', 'h', 'e', 'a'), &hhea) ||
        !gtfont_find_table(font, TTF_TAG('h', 'm', 't', 'x'), &hmtx)) {
        gtfont_unload(font);
        return TTF_ERR_FORMAT;
    }

    uint8_t headBuf[54];
    if (head.length < 54) {
        gtfont_unload(font);
        return TTF_ERR_FORMAT;
    }
    if (!gtfont_read_range(font, head.offset, 54, headBuf)) {
        gtfont_unload(font);
        return TTF_ERR_IO;
    }
    font->unitsPerEm = read_u16(headBuf + 18);
    font->indexToLocFormat = read_u16(headBuf + 50);
    font->headOffset = head.offset;

    uint8_t maxpBuf[6];
    if (maxp.length < 6) {
        gtfont_unload(font);
        return TTF_ERR_FORMAT;
    }
    if (!gtfont_read_range(font, maxp.offset, 6, maxpBuf)) {
        gtfont_unload(font);
        return TTF_ERR_IO;
    }
    font->numGlyphs = read_u16(maxpBuf + 4);

    uint8_t hheaBuf[36];
    if (hhea.length < 36) {
        gtfont_unload(font);
        return TTF_ERR_FORMAT;
    }
    if (!gtfont_read_range(font, hhea.offset, 36, hheaBuf)) {
        gtfont_unload(font);
        return TTF_ERR_IO;
    }
    font->ascender = read_s16(hheaBuf + 4);
    font->descender = read_s16(hheaBuf + 6);
    font->numOfLongHorMetrics = read_u16(hheaBuf + 34);
    if (font->numOfLongHorMetrics == 0 || font->numOfLongHorMetrics > font->numGlyphs) {
        gtfont_unload(font);
        return TTF_ERR_FORMAT;
    }

    uint64_t expected = (uint64_t)font->numOfLongHorMetrics * 4u;
    if (font->numGlyphs > font->numOfLongHorMetrics) {
        expected += (uint64_t)(font->numGlyphs - font->numOfLongHorMetrics) * 2u;
    }
    if ((uint64_t)hmtx.length < expected) {
        gtfont_unload(font);
        return TTF_ERR_FORMAT;
    }

    font->hmtxAdvance = (uint16_t *)malloc(font->numGlyphs * sizeof(uint16_t));
    if (!font->hmtxAdvance) {
        gtfont_unload(font);
        return TTF_ERR_OOM;
    }
    uint8_t *hmtxPtr = font->data + hmtx.offset;
    for (uint16_t i = 0; i < font->numOfLongHorMetrics; ++i) {
        font->hmtxAdvance[i] = read_u16(hmtxPtr + i * 4);
    }
    uint16_t lastAdvance = font->hmtxAdvance[font->numOfLongHorMetrics - 1];
    for (uint32_t i = font->numOfLongHorMetrics; i < font->numGlyphs; ++i) {
        font->hmtxAdvance[i] = lastAdvance;
    }

    font->cmapOffset = cmap.offset;
    font->cmapLength = cmap.length;
    font->glyfOffset = glyf.offset;
    font->locaOffset = loca.offset;

    gtfont_cache_cmap_subtable(font);
    return TTF_OK;
}

static int gtfont_find_table(const GtTtfFont *font, uint32_t tag, TableRecord *out) {
    if (!font || font->size < 12) {
        return 0;
    }
    uint8_t header[12];
    if (!gtfont_read_range(font, 0, 12, header)) {
        return 0;
    }
    uint16_t numTables = read_u16(header + 4);
    size_t directorySize = 12u + (size_t)numTables * 16u;
    if (directorySize > font->size) {
        return 0;
    }
    for (uint16_t i = 0; i < numTables; ++i) {
        uint8_t rec[16];
        uint32_t recOff = 12u + (uint32_t)i * 16u;
        if (!gtfont_read_range(font, recOff, 16, rec)) {
            return 0;
        }
        uint32_t recTag = read_u32(rec);
        if (recTag == tag) {
            uint32_t offset = read_u32(rec + 8);
            uint32_t length = read_u32(rec + 12);
            if (!ensure_range(font, offset, length)) {
                return 0;
            }
            out->offset = offset;
            out->length = length;
            return 1;
        }
    }
    return 0;
}

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
        "C:/Windows/Fonts/msyh.ttc",
        NULL
    };
#elif __APPLE__
    static const char* cands[] = {
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        NULL
    };
#else
    static const char* cands[] = {
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
        NULL
    };
#endif
    for (int i = 0; cands[i]; i++)
        if (file_accessible(cands[i])) return cands[i];
    return NULL;
}


int GT_Font_Init(void) {
    if (s_gtfont_ready) return 1;
    const char* font_file = getenv("LUAT_GTFONT_FILE");
    if (!file_accessible(font_file)) font_file = pick_default_font();
    if (!font_file) return 0;
    if (gtfont_load_from_file(font_file, &s_gtfont) != TTF_OK) {
        gtfont_unload(&s_gtfont);
        return 0;
    }
    s_gtfont_ready = 1;
    return 1;
}

// 将 (x,y) 位置对应的像素置 1（1bpp，MSB-first）
static inline void set_bit_1bpp(uint8_t* buf, uint32_t w, uint32_t x, uint32_t y) {
    uint32_t bytes_per_row = (w + 7) / 8;
    uint32_t byte_index = y * bytes_per_row + (x / 8);
    uint8_t  bit_pos = 7 - (x % 8);
    buf[byte_index] |= (uint8_t)(1u << bit_pos);
}

static inline void set_pix_gray(uint8_t* buf, uint32_t w, uint32_t x, uint32_t y, uint8_t bpp, uint8_t val) {
    if (bpp == 4) {
        uint32_t bytes_per_row = ((w + 7) / 8) * 4;
        uint32_t byte_index = y * bytes_per_row + (x / 2);
        uint8_t  shift = (uint8_t)((1 - (x % 2)) * 4);
        uint8_t  mask  = (uint8_t)(0x0Fu << shift);
        buf[byte_index] = (uint8_t)((buf[byte_index] & ~mask) | ((uint8_t)(val & 0x0F) << shift));
    } else if (bpp == 2) {
        uint32_t bytes_per_row = ((w + 7) / 8) * 2;
        uint32_t byte_index = y * bytes_per_row + (x / 4);
        uint8_t  shift = (uint8_t)((3 - (x % 4)) * 2);
        uint8_t  mask  = (uint8_t)(0x03u << shift);
        buf[byte_index] = (uint8_t)((buf[byte_index] & ~mask) | ((uint8_t)(val & 0x03) << shift));
    }
}

unsigned int get_font(unsigned char *pBits,
                      unsigned char sty,
                      unsigned long fontCode,
                      unsigned char width,
                      unsigned char height,
                      unsigned char thick) {
    (void)sty; (void)thick;
    if (!pBits || width == 0 || height == 0 || !s_gtfont_ready) return 0;
    const uint32_t w = width;
    const uint32_t h = height;
    memset(pBits, 0, ((w + 7) / 8) * h);

    uint32_t codepoint = (uint32_t)fontCode;
    uint16_t glyphIndex = 0;
    if (gtfont_lookup_glyph_index(&s_gtfont, codepoint, &glyphIndex) != TTF_OK) {
        glyphIndex = 0;
    }
    GtGlyph glyph;
    if (gtfont_load_glyph(&s_gtfont, glyphIndex, &glyph) != TTF_OK) {
        gtfont_free_glyph(&glyph);
        return 0;
    }

    GtBitmap bitmap;
    int rc = gtfont_rasterize_glyph(&s_gtfont, &glyph, (int)h, &bitmap);
    gtfont_free_glyph(&glyph);
    if (rc != TTF_OK) {
        gtfont_free_bitmap(&bitmap);
        return 0;
    }

    int asc_px = (int)lrintf((float)s_gtfont.ascender * (float)h / (float)s_gtfont.unitsPerEm);
    if (asc_px < 0) asc_px = 0;
    if (asc_px > (int)h) asc_px = (int)h;
    int off_x = 0;
    int off_y = asc_px - bitmap.originY;

    for (uint32_t yy = 0; yy < bitmap.height; yy++) {
        int dy = off_y + (int)yy;
        if (dy < 0 || dy >= (int)h) continue;
        for (uint32_t xx = 0; xx < bitmap.width; xx++) {
            int dx = off_x + (int)xx;
            if (dx < 0 || dx >= (int)w) continue;
            uint8_t val = bitmap.pixels[yy * bitmap.width + xx];
            if (val > 127) {
                set_bit_1bpp(pBits, w, (uint32_t)dx, (uint32_t)dy);
            }
        }
    }

    int adv = gtfont_advance_px(&s_gtfont, glyphIndex, (int)h);
    if (adv > (int)w) adv = (int)w;
    if (adv < (int)bitmap.width) adv = (int)bitmap.width;
    if (adv == 0) adv = (int)bitmap.width;

    gtfont_free_bitmap(&bitmap);
    return (unsigned int)adv;
}

unsigned int* get_Font_Gray(unsigned char *pBits,
                            unsigned char sty,
                            unsigned long fontCode,
                            unsigned char fontSize,
                            unsigned char thick) {
    (void)sty; (void)thick;
    static unsigned int re_buff[2];
    if (!pBits || fontSize == 0 || !s_gtfont_ready) {
        re_buff[0] = 0;
        re_buff[1] = 2;
        return re_buff;
    }
    const uint32_t w = fontSize;
    const uint32_t h = fontSize;
    uint8_t bpp = (fontSize >= 16 && fontSize < 34) ? 4 : 2;
    uint32_t bytes_per_row = ((w + 7) / 8) * bpp;
    memset(pBits, 0, bytes_per_row * h);

    uint32_t codepoint = (uint32_t)fontCode;
    uint16_t glyphIndex = 0;
    if (gtfont_lookup_glyph_index(&s_gtfont, codepoint, &glyphIndex) != TTF_OK) {
        glyphIndex = 0;
    }
    GtGlyph glyph;
    if (gtfont_load_glyph(&s_gtfont, glyphIndex, &glyph) != TTF_OK) {
        gtfont_free_glyph(&glyph);
        re_buff[0] = 0;
        re_buff[1] = bpp;
        return re_buff;
    }
    GtBitmap bitmap;
    int rc = gtfont_rasterize_glyph(&s_gtfont, &glyph, (int)h, &bitmap);
    gtfont_free_glyph(&glyph);
    if (rc != TTF_OK) {
        gtfont_free_bitmap(&bitmap);
        re_buff[0] = 0;
        re_buff[1] = bpp;
        return re_buff;
    }

    int asc_px = (int)lrintf((float)s_gtfont.ascender * (float)h / (float)s_gtfont.unitsPerEm);
    if (asc_px < 0) asc_px = 0;
    if (asc_px > (int)h) asc_px = (int)h;
    int off_x = 0;
    int off_y = asc_px - bitmap.originY;

    for (uint32_t yy = 0; yy < bitmap.height; yy++) {
        int dy = off_y + (int)yy;
        if (dy < 0 || dy >= (int)h) continue;
        for (uint32_t xx = 0; xx < bitmap.width; xx++) {
            int dx = off_x + (int)xx;
            if (dx < 0 || dx >= (int)w) continue;
            uint8_t val = bitmap.pixels[yy * bitmap.width + xx];
            if (val > 127) {
                set_pix_gray(pBits, w, (uint32_t)dx, (uint32_t)dy, bpp, bpp == 4 ? 0x0F : 0x03);
            }
        }
    }

    int adv = gtfont_advance_px(&s_gtfont, glyphIndex, (int)h);
    if (adv > (int)w) adv = (int)w;
    if (adv < (int)bitmap.width) adv = (int)bitmap.width;
    if (adv == 0) adv = (int)bitmap.width;

    gtfont_free_bitmap(&bitmap);
    re_buff[0] = (unsigned int)adv;
    re_buff[1] = bpp;
    return re_buff;
}

void Gray_Process(unsigned char *OutPutData ,int width,int High,unsigned char Grade) {
    (void)OutPutData; (void)width; (void)High; (void)Grade;
    // PC 仿真版：若 get_Font_Gray 已按目标阶写入，可不做任何处理
}

unsigned long U2G(unsigned int unicode) {
    return (unsigned long)unicode;
}

#endif // LUAT_USE_GUI


