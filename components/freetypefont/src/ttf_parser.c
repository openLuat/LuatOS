#include "ttf_parser.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TTF_TAG(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))

static uint16_t read_u16(const uint8_t *p) {
    return (uint16_t)((p[0] << 8) | p[1]);
}

static int16_t read_s16(const uint8_t *p) {
    return (int16_t)((p[0] << 8) | p[1]);
}

static uint32_t read_u32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static int ensure_range(const TtfFont *font, uint32_t offset, uint32_t length) {
    if (offset > font->size) {
        return 0;
    }
    if (length > font->size - offset) {
        return 0;
    }
    return 1;
}

typedef struct {
    uint32_t offset;
    uint32_t length;
} TableRecord;

static int find_table(const TtfFont *font, uint32_t tag, TableRecord *out) {
    if (!font || !font->data || font->size < 12) {
        return 0;
    }
    uint16_t numTables = read_u16(font->data + 4);
    size_t directorySize = 12u + (size_t)numTables * 16u;
    if (directorySize > font->size) {
        return 0;
    }
    const uint8_t *records = font->data + 12;
    for (uint16_t i = 0; i < numTables; ++i) {
        const uint8_t *rec = records + i * 16;
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

int ttf_load_from_file(const char *path, TtfFont *font) {
    if (!path || !font) {
        return TTF_ERR_RANGE;
    }
    memset(font, 0, sizeof(*font));

    FILE *fp = fopen(path, "rb");
    if (!fp) {
        return TTF_ERR_IO;
    }
    if (fseek(fp, 0, SEEK_END) != 0) {
        fclose(fp);
        return TTF_ERR_IO;
    }
    long fileSize = ftell(fp);
    if (fileSize <= 0) {
        fclose(fp);
        return TTF_ERR_IO;
    }
    if (fseek(fp, 0, SEEK_SET) != 0) {
        fclose(fp);
        return TTF_ERR_IO;
    }

    uint8_t *buffer = (uint8_t *)malloc((size_t)fileSize);
    if (!buffer) {
        fclose(fp);
        return TTF_ERR_OOM;
    }
    size_t readCount = fread(buffer, 1, (size_t)fileSize, fp);
    fclose(fp);
    if (readCount != (size_t)fileSize) {
        free(buffer);
        return TTF_ERR_IO;
    }

    font->data = buffer;
    font->size = (size_t)fileSize;

    if (font->size < 12) {
        ttf_unload(font);
        return TTF_ERR_FORMAT;
    }
    uint32_t scalerType = read_u32(buffer);
    if (scalerType != 0x00010000 && scalerType != TTF_TAG('O', 'T', 'T', 'O')) {
        ttf_unload(font);
        return TTF_ERR_UNSUPPORTED;
    }

    TableRecord cmap = {0}, glyf = {0}, head = {0}, loca = {0}, maxp = {0};
    if (!find_table(font, TTF_TAG('c', 'm', 'a', 'p'), &cmap) ||
        !find_table(font, TTF_TAG('g', 'l', 'y', 'f'), &glyf) ||
        !find_table(font, TTF_TAG('l', 'o', 'c', 'a'), &loca) ||
        !find_table(font, TTF_TAG('h', 'e', 'a', 'd'), &head) ||
        !find_table(font, TTF_TAG('m', 'a', 'x', 'p'), &maxp)) {
        ttf_unload(font);
        return TTF_ERR_FORMAT;
    }

    const uint8_t *headPtr = font->data + head.offset;
    if (head.length < 54) {
        ttf_unload(font);
        return TTF_ERR_FORMAT;
    }
    font->unitsPerEm = read_u16(headPtr + 18);
    font->indexToLocFormat = read_u16(headPtr + 50);
    font->headOffset = head.offset;

    const uint8_t *maxpPtr = font->data + maxp.offset;
    if (maxp.length < 6) {
        ttf_unload(font);
        return TTF_ERR_FORMAT;
    }
    font->numGlyphs = read_u16(maxpPtr + 4);

    font->cmapOffset = cmap.offset;
    font->cmapLength = cmap.length;
    font->glyfOffset = glyf.offset;
    font->locaOffset = loca.offset;

    return TTF_OK;
}

void ttf_unload(TtfFont *font) {
    if (!font) {
        return;
    }
    free(font->data);
    memset(font, 0, sizeof(*font));
}

typedef struct {
    const uint8_t *table;
    uint32_t length;
} CmapSubtable;

static int find_cmap_format4(const TtfFont *font, CmapSubtable *out) {
    if (!font || !font->data) {
        return 0;
    }
    if (font->cmapLength < 4) {
        return 0;
    }
    const uint8_t *cmap = font->data + font->cmapOffset;
    uint16_t numTables = read_u16(cmap + 2);
    uint32_t recordsSize = 4u + (uint32_t)numTables * 8u;
    if (font->cmapLength < recordsSize) {
        return 0;
    }
    const uint8_t *record = cmap + 4;
    CmapSubtable chosen = {0};
    for (uint16_t i = 0; i < numTables; ++i) {
        uint16_t platformID = read_u16(record);
        uint16_t encodingID = read_u16(record + 2);
        uint32_t offset = read_u32(record + 4);
        if (offset >= font->cmapLength) {
            record += 8;
            continue;
        }
        const uint8_t *sub = cmap + offset;
        if (font->cmapLength - offset < 2) {
            record += 8;
            continue;
        }
        uint16_t format = read_u16(sub);
        if (format == 4) {
            if (!chosen.table || (platformID == 3 && (encodingID == 1 || encodingID == 10))) {
                chosen.table = sub;
                chosen.length = font->cmapLength - offset;
                if (platformID == 3 && encodingID == 1) {
                    break;
                }
            }
        }
        record += 8;
    }
    if (!chosen.table || chosen.length < 16) {
        return 0;
    }
    *out = chosen;
    return 1;
}

int ttf_lookup_glyph_index(const TtfFont *font, uint32_t codepoint, uint16_t *glyphIndex) {
    if (!font || !glyphIndex) {
        return TTF_ERR_RANGE;
    }
    CmapSubtable cmap = {0};
    if (!find_cmap_format4(font, &cmap)) {
        return TTF_ERR_UNSUPPORTED;
    }
    const uint8_t *data = cmap.table;
    uint16_t length = read_u16(data + 2);
    if (length > cmap.length || length < 24) {
        return TTF_ERR_FORMAT;
    }
    uint16_t segCountX2 = read_u16(data + 6);
    if (segCountX2 == 0 || 14 + segCountX2 * 2 > length) {
        return TTF_ERR_FORMAT;
    }
    uint16_t segCount = segCountX2 / 2;
    const uint8_t *endCodes = data + 14;
    const uint8_t *startCodes = endCodes + segCount * 2 + 2; // +2 reservedPad
    const uint8_t *idDeltas = startCodes + segCount * 2;
    const uint8_t *idRangeOffsets = idDeltas + segCount * 2;
    const uint8_t *glyphIdArray = idRangeOffsets + segCount * 2;
    if ((size_t)(glyphIdArray - data) > cmap.length) {
        return TTF_ERR_FORMAT;
    }

    for (uint16_t i = 0; i < segCount; ++i) {
        uint16_t endCode = read_u16(endCodes + i * 2);
        uint16_t startCode = read_u16(startCodes + i * 2);
        if (codepoint < startCode) {
            continue;
        }
        if (codepoint > endCode) {
            continue;
        }
        uint16_t idDelta = read_u16(idDeltas + i * 2);
        uint16_t idRangeOffset = read_u16(idRangeOffsets + i * 2);
        if (idRangeOffset == 0) {
            *glyphIndex = (uint16_t)((codepoint + idDelta) & 0xFFFF);
            return TTF_OK;
        }
        const uint8_t *p = idRangeOffsets + i * 2 + idRangeOffset + 2 * (codepoint - startCode);
        if (p + 2 > data + cmap.length) {
            return TTF_ERR_FORMAT;
        }
        uint16_t glyphId = read_u16(p);
        if (glyphId == 0) {
            *glyphIndex = 0;
            return TTF_OK;
        }
        *glyphIndex = (uint16_t)((glyphId + idDelta) & 0xFFFF);
        return TTF_OK;
    }
    return TTF_ERR_RANGE;
}

static int get_glyph_offset(const TtfFont *font, uint16_t glyphIndex, uint32_t *offset, uint32_t *length) {
    if (!font || glyphIndex > font->numGlyphs) {
        return 0;
    }
    const uint8_t *loca = font->data + font->locaOffset;
    uint32_t glyphOffset = 0;
    uint32_t nextOffset = 0;
    if (font->indexToLocFormat == 0) {
        uint32_t entryOffset = glyphIndex * 2;
        uint32_t entryNext = (glyphIndex + 1) * 2;
        if (!ensure_range(font, font->locaOffset + entryNext, 0)) {
            return 0;
        }
        glyphOffset = (uint32_t)read_u16(loca + entryOffset) * 2;
        nextOffset = (uint32_t)read_u16(loca + entryNext) * 2;
    } else {
        uint32_t entryOffset = glyphIndex * 4;
        uint32_t entryNext = (glyphIndex + 1) * 4;
        if (!ensure_range(font, font->locaOffset + entryNext, 0)) {
            return 0;
        }
        glyphOffset = read_u32(loca + entryOffset);
        nextOffset = read_u32(loca + entryNext);
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

void ttf_free_glyph(TtfGlyph *glyph) {
    if (!glyph) {
        return;
    }
    free(glyph->contourEnds);
    free(glyph->points);
    memset(glyph, 0, sizeof(*glyph));
}

int ttf_load_glyph(const TtfFont *font, uint16_t glyphIndex, TtfGlyph *glyph) {
    if (!font || !glyph) {
        return TTF_ERR_RANGE;
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

    const uint8_t *ptr = font->data + offset;
    int16_t numberOfContours = read_s16(ptr);
    glyph->minX = read_s16(ptr + 2);
    glyph->minY = read_s16(ptr + 4);
    glyph->maxX = read_s16(ptr + 6);
    glyph->maxY = read_s16(ptr + 8);

    if (numberOfContours < 0) {
        return TTF_ERR_UNSUPPORTED; // composite glyphs not supported yet
    }
    if (numberOfContours == 0) {
        return TTF_OK;
    }

    glyph->contourCount = (uint16_t)numberOfContours;
    uint32_t headerBytes = 10u + (uint32_t)glyph->contourCount * 2u + 2u;
    if (length < headerBytes) {
        return TTF_ERR_FORMAT;
    }

    glyph->contourEnds = (uint16_t *)calloc(glyph->contourCount, sizeof(uint16_t));
    if (!glyph->contourEnds) {
        return TTF_ERR_OOM;
    }
    const uint8_t *contourPtr = ptr + 10;
    for (uint16_t i = 0; i < glyph->contourCount; ++i) {
        glyph->contourEnds[i] = read_u16(contourPtr + i * 2);
    }

    uint16_t instructionLength = read_u16(contourPtr + glyph->contourCount * 2);
    const uint8_t *instructionPtr = contourPtr + glyph->contourCount * 2 + 2;
    if (instructionPtr + instructionLength > ptr + length) {
        ttf_free_glyph(glyph);
        return TTF_ERR_FORMAT;
    }
    const uint8_t *flagsPtr = instructionPtr + instructionLength;

    if (glyph->contourEnds[glyph->contourCount - 1] >= 0xFFFFu) {
        ttf_free_glyph(glyph);
        return TTF_ERR_FORMAT;
    }
    glyph->pointCount = glyph->contourEnds[glyph->contourCount - 1] + 1;
    if (glyph->pointCount == 0) {
        return TTF_OK;
    }

    uint8_t *flags = (uint8_t *)malloc(glyph->pointCount);
    if (!flags) {
        ttf_free_glyph(glyph);
        return TTF_ERR_OOM;
    }
    const uint8_t *cursor = flagsPtr;
    uint16_t flagIndex = 0;
    while (flagIndex < glyph->pointCount) {
        if (cursor >= ptr + length) {
            free(flags);
            ttf_free_glyph(glyph);
            return TTF_ERR_FORMAT;
        }
        uint8_t flag = *cursor++;
        flags[flagIndex++] = flag;
        if (flag & 0x08) {
            if (cursor >= ptr + length) {
                free(flags);
                ttf_free_glyph(glyph);
                return TTF_ERR_FORMAT;
            }
            uint8_t repeatCount = *cursor++;
            if (flagIndex + repeatCount > glyph->pointCount) {
                free(flags);
                ttf_free_glyph(glyph);
                return TTF_ERR_FORMAT;
            }
            for (uint8_t r = 0; r < repeatCount; ++r) {
                flags[flagIndex++] = flag;
            }
        }
    }

    glyph->points = (TtfPoint *)calloc(glyph->pointCount, sizeof(TtfPoint));
    if (!glyph->points) {
        free(flags);
        ttf_free_glyph(glyph);
        return TTF_ERR_OOM;
    }

    int16_t x = 0;
    for (uint16_t i = 0; i < glyph->pointCount; ++i) {
        uint8_t flag = flags[i];
        if (flag & 0x02) {
            if (cursor >= ptr + length) {
                free(flags);
                ttf_free_glyph(glyph);
                return TTF_ERR_FORMAT;
            }
            uint8_t dx = *cursor++;
            if (flag & 0x10) {
                x += dx;
            } else {
                x -= dx;
            }
        } else {
            if (flag & 0x10) {
                // same as previous
            } else {
                if (cursor + 1 >= ptr + length) {
                    free(flags);
                    ttf_free_glyph(glyph);
                    return TTF_ERR_FORMAT;
                }
                int16_t dx = read_s16(cursor);
                cursor += 2;
                x += dx;
            }
        }
        glyph->points[i].x = x;
    }

    int16_t y = 0;
    for (uint16_t i = 0; i < glyph->pointCount; ++i) {
        uint8_t flag = flags[i];
        if (flag & 0x04) {
            if (cursor >= ptr + length) {
                free(flags);
                ttf_free_glyph(glyph);
                return TTF_ERR_FORMAT;
            }
            uint8_t dy = *cursor++;
            if (flag & 0x20) {
                y += dy;
            } else {
                y -= dy;
            }
        } else {
            if (flag & 0x20) {
                // same as previous
            } else {
                if (cursor + 1 >= ptr + length) {
                    free(flags);
                    ttf_free_glyph(glyph);
                    return TTF_ERR_FORMAT;
                }
                int16_t dy = read_s16(cursor);
                cursor += 2;
                y += dy;
            }
        }
        glyph->points[i].y = y;
        glyph->points[i].onCurve = (flags[i] & 0x01) ? 1 : 0;
    }

    free(flags);
    return TTF_OK;
}

typedef struct {
    float *data;
    size_t count;
    size_t capacity;
} SegmentList;

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

static TtfPoint midpoint_point(const TtfPoint *a, const TtfPoint *b) {
    TtfPoint result;
    result.x = (int16_t)((a->x + b->x) / 2);
    result.y = (int16_t)((a->y + b->y) / 2);
    result.onCurve = 1;
    return result;
}

static void transform_point(const TtfGlyph *glyph, float scale, float offsetX, float offsetY,
                            const TtfPoint *pt, float *outX, float *outY) {
    *outX = (pt->x - glyph->minX) * scale + offsetX;
    *outY = (glyph->maxY - pt->y) * scale + offsetY;
}

static int build_segments(const TtfGlyph *glyph, float scale, float offsetX, float offsetY, SegmentList *segments) {
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

        const TtfPoint *firstPoint = &glyph->points[contourStart];
        const TtfPoint *lastPoint = &glyph->points[contourEnd];
        TtfPoint startOn = *lastPoint;
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
            const TtfPoint *current = &glyph->points[index];
            uint16_t nextIndex = (index == contourEnd) ? contourStart : (uint16_t)(index + 1);
            const TtfPoint *nextPoint = &glyph->points[nextIndex];

            if (current->onCurve) {
                float currX, currY;
                transform_point(glyph, scale, offsetX, offsetY, current, &currX, &currY);
                if (!append_segment(segments, prevX, prevY, currX, currY)) {
                    return 0;
                }
                prevX = currX;
                prevY = currY;
            } else {
                TtfPoint nextOn = *nextPoint;
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

static int point_inside(const SegmentList *segments, float px, float py) {
    int winding = 0;
    for (size_t i = 0; i < segments->count; ++i) {
        float x0 = segments->data[i * 4 + 0];
        float y0 = segments->data[i * 4 + 1];
        float x1 = segments->data[i * 4 + 2];
        float y1 = segments->data[i * 4 + 3];
        if (fabsf(y0 - y1) < 1e-6f) {
            continue;
        }
        int upward = (y0 <= py && y1 > py);
        int downward = (y1 <= py && y0 > py);
        if (!(upward || downward)) {
            continue;
        }
        float t = (py - y0) / (y1 - y0);
        if (t < 0.0f || t > 1.0f) {
            continue;
        }
        float x = x0 + t * (x1 - x0);
        if (x > px) {
            winding ^= 1;
        }
    }
    return winding;
}

int ttf_rasterize_glyph(const TtfFont *font, const TtfGlyph *glyph, int ppem, TtfBitmap *bitmap) {
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
    if (widthF < 1.0f) {
        widthF = 1.0f;
    }
    if (heightF < 1.0f) {
        heightF = 1.0f;
    }
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

    for (uint32_t y = 0; y < height; ++y) {
        for (uint32_t x = 0; x < width; ++x) {
            float px = (float)x + 0.5f;
            float py = (float)y + 0.5f;
            if (point_inside(&segments, px, py)) {
                pixels[y * width + x] = 255;
            }
        }
    }

    free(segments.data);
    bitmap->width = width;
    bitmap->height = height;
    bitmap->pixels = pixels;
    bitmap->originX = (int32_t)floorf(glyph->minX * scale);
    bitmap->originY = (int32_t)floorf(glyph->maxY * scale);
    bitmap->scale = scale;
    return TTF_OK;
}

void ttf_free_bitmap(TtfBitmap *bitmap) {
    if (!bitmap) {
        return;
    }
    free(bitmap->pixels);
    memset(bitmap, 0, sizeof(*bitmap));
}
