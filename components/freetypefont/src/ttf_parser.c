#include "ttf_parser.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "luat_fs.h"

#define TTF_TAG(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))

#define TTF_ENABLE_SUPERSAMPLING

#ifndef TTF_SUPERSAMPLE_RATE
#ifdef TTF_ENABLE_SUPERSAMPLING
#define TTF_SUPERSAMPLE_RATE 4
#else
#define TTF_SUPERSAMPLE_RATE 1
#endif
#endif

static uint16_t read_u16(const uint8_t *p) {
    return (uint16_t)((p[0] << 8) | p[1]);
}

static int16_t read_s16(const uint8_t *p) {
    return (int16_t)((p[0] << 8) | p[1]);
}

static uint32_t read_u32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static float read_f2dot14(const uint8_t *p) {
    int16_t value = read_s16(p);
    return (float)value / 16384.0f;
}

static int32_t round_to_int32(float value) {
    return (int32_t)(value >= 0.0f ? value + 0.5f : value - 0.5f);
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

    uint8_t *buffer = NULL;
    size_t size_read = 0;

    do {
        FILE *vfp = luat_fs_fopen(path, "rb");
        if (!vfp) {
            break; // fallback to stdio
        }
        if (luat_fs_fseek(vfp, 0, SEEK_END) != 0) {
            luat_fs_fclose(vfp);
            return TTF_ERR_IO;
        }
        long vsize = luat_fs_ftell(vfp);
        if (vsize <= 0) {
            luat_fs_fclose(vfp);
            return TTF_ERR_IO;
        }
        if (luat_fs_fseek(vfp, 0, SEEK_SET) != 0) {
            luat_fs_fclose(vfp);
            return TTF_ERR_IO;
        }
        buffer = (uint8_t *)malloc((size_t)vsize);
        if (!buffer) {
            luat_fs_fclose(vfp);
            return TTF_ERR_OOM;
        }
        size_read = luat_fs_fread(buffer, 1, (size_t)vsize, vfp);
        luat_fs_fclose(vfp);
        if (size_read != (size_t)vsize) {
            free(buffer);
            buffer = NULL;
            return TTF_ERR_IO;
        }
    } while (0);

    if (!buffer) {
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
        buffer = (uint8_t *)malloc((size_t)fileSize);
        if (!buffer) {
            fclose(fp);
            return TTF_ERR_OOM;
        }
        size_read = fread(buffer, 1, (size_t)fileSize, fp);
        fclose(fp);
        if (size_read != (size_t)fileSize) {
            free(buffer);
            return TTF_ERR_IO;
        }
    }

    font->data = buffer;
    font->size = size_read;

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

static int find_cmap_format12(const TtfFont *font, CmapSubtable *out) {
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
        if (font->cmapLength - offset < 6) {
            record += 8;
            continue;
        }
        uint16_t format = read_u16(sub);
        if (format == 12) {
            if (font->cmapLength - offset < 16) {
                record += 8;
                continue;
            }
            if (!chosen.table || (platformID == 3 && encodingID == 10) || (platformID == 0)) {
                chosen.table = sub;
                chosen.length = font->cmapLength - offset;
                if (platformID == 3 && encodingID == 10) {
                    break;
                }
            }
        }
        record += 8;
    }
    if (!chosen.table) {
        return 0;
    }
    *out = chosen;
    return 1;
}

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

static int cmap_format12_lookup(const CmapSubtable *cmap, uint32_t codepoint, uint16_t numGlyphs, uint16_t *glyphIndex) {
    if (!cmap || !cmap->table || !glyphIndex) {
        return TTF_ERR_RANGE;
    }
    const uint8_t *data = cmap->table;
    if (cmap->length < 16) {
        return TTF_ERR_FORMAT;
    }
    uint32_t length = read_u32(data + 4);
    if (length > cmap->length) {
        return TTF_ERR_FORMAT;
    }
    uint32_t nGroups = read_u32(data + 12);
    if (nGroups == 0) {
        return TTF_ERR_RANGE;
    }
    uint64_t required = 16u + (uint64_t)nGroups * 12u;
    if (required > cmap->length) {
        return TTF_ERR_FORMAT;
    }
    const uint8_t *groups = data + 16;
    uint32_t lo = 0;
    uint32_t hi = nGroups;
    while (lo < hi) {
        uint32_t mid = lo + (hi - lo) / 2u;
        const uint8_t *group = groups + (size_t)mid * 12u;
        uint32_t startCode = read_u32(group);
        uint32_t endCode = read_u32(group + 4);
        if (codepoint < startCode) {
            hi = mid;
            continue;
        }
        if (codepoint > endCode) {
            lo = mid + 1u;
            continue;
        }
        uint32_t startGlyphId = read_u32(group + 8);
        uint64_t glyph = (uint64_t)startGlyphId + (uint64_t)(codepoint - startCode);
        if (glyph >= numGlyphs || glyph > 0xFFFFu) {
            return TTF_ERR_RANGE;
        }
        *glyphIndex = (uint16_t)glyph;
        return TTF_OK;
    }
    return TTF_ERR_RANGE;
}

int ttf_lookup_glyph_index(const TtfFont *font, uint32_t codepoint, uint16_t *glyphIndex) {
    if (!font || !glyphIndex) {
        return TTF_ERR_RANGE;
    }

    CmapSubtable cmap12 = {0};
    if (find_cmap_format12(font, &cmap12)) {
        int rc = cmap_format12_lookup(&cmap12, codepoint, font->numGlyphs, glyphIndex);
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
    const uint8_t *data = cmap4.table;
    uint16_t length = read_u16(data + 2);
    if (length > cmap4.length || length < 24) {
        return TTF_ERR_FORMAT;
    }
    uint16_t segCountX2 = read_u16(data + 6);
    if (segCountX2 == 0 || 14 + segCountX2 * 2 > length) {
        return TTF_ERR_FORMAT;
    }
    uint16_t segCount = segCountX2 / 2;
    const uint8_t *endCodes = data + 14;
    const uint8_t *startCodes = endCodes + segCount * 2 + 2;
    const uint8_t *idDeltas = startCodes + segCount * 2;
    const uint8_t *idRangeOffsets = idDeltas + segCount * 2;
    const uint8_t *glyphIdArray = idRangeOffsets + segCount * 2;
    if ((size_t)(glyphIdArray - data) > cmap4.length) {
        return TTF_ERR_FORMAT;
    }

    for (uint16_t i = 0; i < segCount; ++i) {
        uint16_t endCode = read_u16(endCodes + i * 2);
        uint16_t startCode = read_u16(startCodes + i * 2);
        if (codepoint < startCode || codepoint > endCode) {
            continue;
        }
        uint16_t idDelta = read_u16(idDeltas + i * 2);
        uint16_t idRangeOffset = read_u16(idRangeOffsets + i * 2);
        if (idRangeOffset == 0) {
            *glyphIndex = (uint16_t)((codepoint + idDelta) & 0xFFFF);
            if (*glyphIndex >= font->numGlyphs) {
                return TTF_ERR_RANGE;
            }
            return TTF_OK;
        }
        const uint8_t *p = idRangeOffsets + i * 2 + idRangeOffset + 2u * (codepoint - startCode);
        if (p + 2 > data + cmap4.length) {
            return TTF_ERR_FORMAT;
        }
        uint16_t glyphId = read_u16(p);
        if (glyphId == 0) {
            *glyphIndex = 0;
            return TTF_OK;
        }
        *glyphIndex = (uint16_t)((glyphId + idDelta) & 0xFFFF);
        if (*glyphIndex >= font->numGlyphs) {
            return TTF_ERR_RANGE;
        }
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

static int append_component_glyph(TtfGlyph *dest, const TtfGlyph *src,
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

    TtfPoint *points = (TtfPoint *)realloc(dest->points, newPointCount * sizeof(TtfPoint));
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

static int load_glyph_internal(const TtfFont *font, uint16_t glyphIndex, TtfGlyph *glyph, int depth) {
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

    const uint8_t *ptr = font->data + offset;
    const uint8_t *end = ptr + length;
    int16_t numberOfContours = read_s16(ptr);
    glyph->minX = read_s16(ptr + 2);
    glyph->minY = read_s16(ptr + 4);
    glyph->maxX = read_s16(ptr + 6);
    glyph->maxY = read_s16(ptr + 8);

    if (numberOfContours >= 0) {
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
        if (instructionPtr + instructionLength > end) {
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
            if (cursor >= end) {
                free(flags);
                ttf_free_glyph(glyph);
                return TTF_ERR_FORMAT;
            }
            uint8_t flag = *cursor++;
            flags[flagIndex++] = flag;
            if (flag & 0x08) {
                if (cursor >= end) {
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
        flagIndex = 0;
        while (flagIndex < glyph->pointCount) {
            uint8_t flag = flags[flagIndex++];
            if (flag & 0x02) {
                if (cursor >= end) {
                    free(flags);
                    ttf_free_glyph(glyph);
                    return TTF_ERR_FORMAT;
                }
                uint8_t dx = *cursor++;
                x += (flag & 0x10) ? dx : -(int16_t)dx;
            } else if (!(flag & 0x10)) {
                if (cursor + 1 >= end) {
                    free(flags);
                    ttf_free_glyph(glyph);
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
                    ttf_free_glyph(glyph);
                    return TTF_ERR_FORMAT;
                }
                uint8_t dy = *cursor++;
                y += (flag & 0x20) ? dy : -(int16_t)dy;
            } else if (!(flag & 0x20)) {
                if (cursor + 1 >= end) {
                    free(flags);
                    ttf_free_glyph(glyph);
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
        return TTF_OK;
    }


    const uint8_t *cursor = ptr + 10;
    uint16_t flags = 0;
    do {
        if (cursor + 4 > end) {
            ttf_free_glyph(glyph);
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
                ttf_free_glyph(glyph);
                return TTF_ERR_FORMAT;
            }
            arg1 = read_s16(cursor);
            arg2 = read_s16(cursor + 2);
            cursor += 4;
        } else {
            if (cursor + 2 > end) {
                ttf_free_glyph(glyph);
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
            ttf_free_glyph(glyph);
            return TTF_ERR_UNSUPPORTED;
        }

        float m00 = 1.0f;
        float m01 = 0.0f;
        float m10 = 0.0f;
        float m11 = 1.0f;
        if (flags & 0x0008) {
            if (cursor + 2 > end) {
                ttf_free_glyph(glyph);
                return TTF_ERR_FORMAT;
            }
            float scale = read_f2dot14(cursor);
            cursor += 2;
            m00 = scale;
            m11 = scale;
        } else if (flags & 0x0040) {
            if (cursor + 4 > end) {
                ttf_free_glyph(glyph);
                return TTF_ERR_FORMAT;
            }
            m00 = read_f2dot14(cursor);
            m11 = read_f2dot14(cursor + 2);
            cursor += 4;
        } else if (flags & 0x0080) {
            if (cursor + 8 > end) {
                ttf_free_glyph(glyph);
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

        TtfGlyph componentGlyph;
        int rc = load_glyph_internal(font, componentIndex, &componentGlyph, depth + 1);
        if (rc != TTF_OK) {
            ttf_free_glyph(&componentGlyph);
            ttf_free_glyph(glyph);
            return rc;
        }
        rc = append_component_glyph(glyph, &componentGlyph, m00, m01, m10, m11, dx, dy);
        ttf_free_glyph(&componentGlyph);
        if (rc != TTF_OK) {
            ttf_free_glyph(glyph);
            return rc;
        }
    } while (flags & 0x0020);

    if (flags & 0x0100) {
        if (cursor + 2 > end) {
            ttf_free_glyph(glyph);
            return TTF_ERR_FORMAT;
        }
        uint16_t instructionLength = read_u16(cursor);
        cursor += 2;
        if (cursor + instructionLength > end) {
            ttf_free_glyph(glyph);
            return TTF_ERR_FORMAT;
        }
        cursor += instructionLength;
    }

    return TTF_OK;
}

int ttf_load_glyph(const TtfFont *font, uint16_t glyphIndex, TtfGlyph *glyph) {
    return load_glyph_internal(font, glyphIndex, glyph, 0);
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

    const int supersampleRate = TTF_SUPERSAMPLE_RATE;
    const int sampleCount = supersampleRate * supersampleRate;
    for (uint32_t y = 0; y < height; ++y) {
        for (uint32_t x = 0; x < width; ++x) {
            int insideHits = 0;
            if (supersampleRate == 1) {
                float px = (float)x + 0.5f;
                float py = (float)y + 0.5f;
                insideHits = point_inside(&segments, px, py);
            } else {
                for (int sy = 0; sy < supersampleRate; ++sy) {
                    for (int sx = 0; sx < supersampleRate; ++sx) {
                        float px = (float)x + ((float)sx + 0.5f) / (float)supersampleRate;
                        float py = (float)y + ((float)sy + 0.5f) / (float)supersampleRate;
                        insideHits += point_inside(&segments, px, py);
                    }
                }
            }
            if (insideHits > 0) {
                uint8_t value = (uint8_t)((insideHits * 255 + sampleCount / 2) / sampleCount);
                pixels[y * width + x] = value;
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
