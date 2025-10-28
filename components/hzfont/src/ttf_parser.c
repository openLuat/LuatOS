#include "ttf_parser.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "luat_fs.h"
#define LUAT_LOG_TAG "ttf"
#include "luat_log.h"
static int g_ttf_debug = 1;

#define TTF_TAG(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))

#define TTF_ENABLE_SUPERSAMPLING

#ifndef TTF_SUPERSAMPLE_RATE
#ifdef TTF_ENABLE_SUPERSAMPLING
// 超采样率 目前推荐2或者4
#define TTF_SUPERSAMPLE_RATE 2
#else
#define TTF_SUPERSAMPLE_RATE 1
#endif
#endif

#define TTF_FIXED_SHIFT 8
#define TTF_FIXED_ONE   (1 << TTF_FIXED_SHIFT)
#define TTF_FIXED_HALF  (1 << (TTF_FIXED_SHIFT - 1))

int ttf_set_debug(int enable) { g_ttf_debug = enable ? 1 : 0; return g_ttf_debug; }
int ttf_get_debug(void) { return g_ttf_debug; }
int ttf_get_supersample_rate(void) { return TTF_SUPERSAMPLE_RATE; }

#define TTF_CMAP_CACHE_MAX   (512u * 1024u)

static void ttf_cache_cmap_subtable(TtfFont *font);

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

/* 1.0: 统一的按需读取封装（支持 data 整读或 file 流式） */
static int ttf_read_range(const TtfFont *font, uint32_t offset, uint32_t length, uint8_t *out) {
    if (!font || !out || length == 0) {
        return 0;
    }
    if (!ensure_range(font, offset, length)) {
        return 0;
    }
    if (font->data) {
        memcpy(out, font->data + offset, length);
        return 1;
    }
    if (font->file) {
        if (luat_fs_fseek((FILE*)font->file, (long)offset, SEEK_SET) != 0) {
            return 0;
        }
        size_t n = luat_fs_fread(out, 1, length, (FILE*)font->file);
        return n == length;
    }
    return 0;
}

typedef struct {
    uint32_t offset;
    uint32_t length;
} TableRecord;

static int find_table(const TtfFont *font, uint32_t tag, TableRecord *out) {
    if (!font || font->size < 12) {
        return 0;
    }
    uint8_t header[12];
    if (!ttf_read_range(font, 0, 12, header)) {
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
        if (!ttf_read_range(font, recOff, 16, rec)) {
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

int ttf_load_from_file(const char *path, TtfFont *font) {
    if (!path || !font) {
        return TTF_ERR_RANGE;
    }
    memset(font, 0, sizeof(*font));

    /* 1.0: 默认开启流式读取以节省内存（不整读），若需要可切换到整读模式 */
    FILE *vfp = luat_fs_fopen(path, "rb");
    if (!vfp) {
        /* 回退标准 fopen */
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
        font->data = (uint8_t*)malloc((size_t)fileSize);
        if (!font->data) {
            fclose(fp);
            return TTF_ERR_OOM;
        }
        size_t n = fread(font->data, 1, (size_t)fileSize, fp);
        fclose(fp);
        if (n != (size_t)fileSize) {
            free(font->data);
            memset(font, 0, sizeof(*font));
            return TTF_ERR_IO;
        }
        font->size = (size_t)fileSize;
        font->file = NULL;
        font->fileSize = (size_t)fileSize;
        font->streaming = 0;
        font->ownsData = 1;
    } else {
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
        font->data = NULL;            /* 不整读 */
        font->size = (size_t)vsize;
        font->file = vfp;             /* 保存 VFS 句柄 */
        font->fileSize = (size_t)vsize;
        font->streaming = 1;
        font->ownsData = 0;
    }

    if (font->size < 12) {
        ttf_unload(font);
        return TTF_ERR_FORMAT;
    }
    uint8_t hdr4[4];
    if (!ttf_read_range(font, 0, 4, hdr4)) {
        if (g_ttf_debug) LLOGE("ttf read header failed");
        ttf_unload(font);
        return TTF_ERR_IO;
    }
    uint32_t scalerType = read_u32(hdr4);
    if (scalerType != 0x00010000 && scalerType != TTF_TAG('O', 'T', 'T', 'O')) {
        if (g_ttf_debug) LLOGE("unsupported scalerType 0x%08X", (unsigned)scalerType);
        ttf_unload(font);
        return TTF_ERR_UNSUPPORTED;
    }

    TableRecord cmap = {0}, glyf = {0}, head = {0}, loca = {0}, maxp = {0};
    if (!find_table(font, TTF_TAG('c', 'm', 'a', 'p'), &cmap) ||
        !find_table(font, TTF_TAG('g', 'l', 'y', 'f'), &glyf) ||
        !find_table(font, TTF_TAG('l', 'o', 'c', 'a'), &loca) ||
        !find_table(font, TTF_TAG('h', 'e', 'a', 'd'), &head) ||
        !find_table(font, TTF_TAG('m', 'a', 'x', 'p'), &maxp)) {
        if (g_ttf_debug) LLOGE("find table failed cmap=%u glyf=%u loca=%u head=%u maxp=%u",
            (unsigned)(cmap.length>0), (unsigned)(glyf.length>0), (unsigned)(loca.length>0), (unsigned)(head.length>0), (unsigned)(maxp.length>0));
        ttf_unload(font);
        return TTF_ERR_FORMAT;
    }

    uint8_t headBuf[54];
    if (head.length < 54) {
        ttf_unload(font);
        return TTF_ERR_FORMAT;
    }
    if (!ttf_read_range(font, head.offset, 54, headBuf)) {
        if (g_ttf_debug) LLOGE("read head failed at %u", (unsigned)head.offset);
        ttf_unload(font);
        return TTF_ERR_IO;
    }
    font->unitsPerEm = read_u16(headBuf + 18);
    font->indexToLocFormat = read_u16(headBuf + 50);
    font->headOffset = head.offset;

    uint8_t maxpBuf[6];
    if (maxp.length < 6) {
        ttf_unload(font);
        return TTF_ERR_FORMAT;
    }
    if (!ttf_read_range(font, maxp.offset, 6, maxpBuf)) {
        if (g_ttf_debug) LLOGE("read maxp failed at %u", (unsigned)maxp.offset);
        ttf_unload(font);
        return TTF_ERR_IO;
    }
    font->numGlyphs = read_u16(maxpBuf + 4);
    if (g_ttf_debug) LLOGI("font loaded streaming=%d size=%u units_per_em=%u glyphs=%u indexToLocFormat=%u",
        (int)font->streaming, (unsigned)font->size, (unsigned)font->unitsPerEm, (unsigned)font->numGlyphs, (unsigned)font->indexToLocFormat);

    font->cmapOffset = cmap.offset;
    font->cmapLength = cmap.length;
    font->glyfOffset = glyf.offset;
    font->locaOffset = loca.offset;

    ttf_cache_cmap_subtable(font);

    return TTF_OK;
}

int ttf_load_from_memory(const uint8_t *data, size_t size, TtfFont *font) {
    if (!data || !font || size < 12) {
        return TTF_ERR_RANGE;
    }
    memset(font, 0, sizeof(*font));
    font->data = (uint8_t*)data; /* 外部常量内存，不复制，不释放 */
    font->size = size;
    font->file = NULL;
    font->fileSize = size;
    font->streaming = 0;
    font->ownsData = 0;

    uint8_t hdr4[4];
    if (!ttf_read_range(font, 0, 4, hdr4)) {
        return TTF_ERR_IO;
    }
    uint32_t scalerType = read_u32(hdr4);
    if (scalerType != 0x00010000 && scalerType != TTF_TAG('O', 'T', 'T', 'O')) {
        return TTF_ERR_UNSUPPORTED;
    }

    TableRecord cmap = {0}, glyf = {0}, head = {0}, loca = {0}, maxp = {0};
    if (!find_table(font, TTF_TAG('c', 'm', 'a', 'p'), &cmap) ||
        !find_table(font, TTF_TAG('g', 'l', 'y', 'f'), &glyf) ||
        !find_table(font, TTF_TAG('l', 'o', 'c', 'a'), &loca) ||
        !find_table(font, TTF_TAG('h', 'e', 'a', 'd'), &head) ||
        !find_table(font, TTF_TAG('m', 'a', 'x', 'p'), &maxp)) {
        return TTF_ERR_FORMAT;
    }

    uint8_t headBuf[54];
    if (head.length < 54) {
        return TTF_ERR_FORMAT;
    }
    if (!ttf_read_range(font, head.offset, 54, headBuf)) {
        return TTF_ERR_IO;
    }
    font->unitsPerEm = read_u16(headBuf + 18);
    font->indexToLocFormat = read_u16(headBuf + 50);
    font->headOffset = head.offset;

    uint8_t maxpBuf[6];
    if (maxp.length < 6) {
        return TTF_ERR_FORMAT;
    }
    if (!ttf_read_range(font, maxp.offset, 6, maxpBuf)) {
        return TTF_ERR_IO;
    }
    font->numGlyphs = read_u16(maxpBuf + 4);

    font->cmapOffset = cmap.offset;
    font->cmapLength = cmap.length;
    font->glyfOffset = glyf.offset;
    font->locaOffset = loca.offset;

    ttf_cache_cmap_subtable(font);
    if (g_ttf_debug) LLOGI("font loaded from memory size=%u units_per_em=%u glyphs=%u indexToLocFormat=%u",
        (unsigned)font->size, (unsigned)font->unitsPerEm, (unsigned)font->numGlyphs, (unsigned)font->indexToLocFormat);
    return TTF_OK;
}

void ttf_unload(TtfFont *font) {
    if (!font) {
        return;
    }
    if (font->data && font->ownsData) free(font->data);
    if (font->file) luat_fs_fclose((FILE*)font->file);
    if (font->cmapBuf) free(font->cmapBuf);
    memset(font, 0, sizeof(*font));
}

typedef struct {
    uint32_t offset; /* 绝对偏移：font->cmapOffset + subtableOffset */
    uint32_t length; /* 剩余长度（可用时校验，不一定严格） */
} CmapSubtable;

static int read_u16_at(const TtfFont *font, uint32_t absOff, uint16_t *out) {
    uint8_t b[2];
    if (font && font->cmapBuf && absOff >= font->cmapBufOffset &&
        absOff + 2 <= font->cmapBufOffset + font->cmapBufLen) {
        const uint8_t *ptr = font->cmapBuf + (absOff - font->cmapBufOffset);
        *out = read_u16(ptr);
        return 1;
    }
    if (!ttf_read_range(font, absOff, 2, b)) return 0;
    *out = read_u16(b);
    return 1;
}
static int read_u32_at(const TtfFont *font, uint32_t absOff, uint32_t *out) {
    uint8_t b[4];
    if (font && font->cmapBuf && absOff >= font->cmapBufOffset &&
        absOff + 4 <= font->cmapBufOffset + font->cmapBufLen) {
        const uint8_t *ptr = font->cmapBuf + (absOff - font->cmapBufOffset);
        *out = read_u32(ptr);
        return 1;
    }
    if (!ttf_read_range(font, absOff, 4, b)) return 0;
    *out = read_u32(b);
    return 1;
}

static int find_cmap_format12(const TtfFont *font, CmapSubtable *out) {
    if (!font || !font->data) {
        /* 支持 streaming：用 ttf_read_range 读取 */
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

static int find_cmap_format4(const TtfFont *font, CmapSubtable *out) {
    if (!font || !font->data) {
        /* 支持 streaming：用 ttf_read_range 读取 */
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

static void ttf_cache_cmap_subtable(TtfFont *font) {
    if (!font) {
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
    if (chosen.length == 0 || chosen.length > TTF_CMAP_CACHE_MAX) {
        return;
    }
    uint8_t *buf = (uint8_t *)malloc(chosen.length);
    if (!buf) {
        if (g_ttf_debug) {
            LLOGW("cmap cache malloc fail len=%u", (unsigned)chosen.length);
        }
        return;
    }
    if (!ttf_read_range(font, chosen.offset, chosen.length, buf)) {
        free(buf);
        if (g_ttf_debug) {
            LLOGW("cmap cache read fail off=%u len=%u", (unsigned)chosen.offset, (unsigned)chosen.length);
        }
        return;
    }
    font->cmapBuf = buf;
    font->cmapBufLen = chosen.length;
    font->cmapBufOffset = chosen.offset;
    font->cmapFormat = format;
    if (g_ttf_debug) {
        LLOGI("cmap cached format=%u size=%u", (unsigned)format, (unsigned)chosen.length);
    }
}

static int cmap_format12_lookup(const TtfFont *font, const CmapSubtable *cmap, uint32_t codepoint, uint16_t numGlyphs, uint16_t *glyphIndex) {
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

int ttf_lookup_glyph_index(const TtfFont *font, uint32_t codepoint, uint16_t *glyphIndex) {
    if (!font || !glyphIndex) {
        return TTF_ERR_RANGE;
    }

    CmapSubtable cmap12 = {0};
    if (find_cmap_format12(font, &cmap12)) {
        int rc = cmap_format12_lookup(font, &cmap12, codepoint, font->numGlyphs, glyphIndex);
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

static int get_glyph_offset(const TtfFont *font, uint16_t glyphIndex, uint32_t *offset, uint32_t *length) {
    if (!font || glyphIndex > font->numGlyphs) {
        return 0;
    }
    /* 1.0: loca 支持按需读取 */
    uint32_t glyphOffset = 0;
    uint32_t nextOffset = 0;
    if (font->indexToLocFormat == 0) {
        uint32_t entryOffset = font->locaOffset + glyphIndex * 2;
        uint32_t entryNext = font->locaOffset + (glyphIndex + 1) * 2;
        uint8_t buf[4];
        if (!ttf_read_range(font, entryOffset, 2, buf)) return 0;
        if (!ttf_read_range(font, entryNext, 2, buf + 2)) return 0;
        glyphOffset = (uint32_t)read_u16(buf) * 2;
        nextOffset = (uint32_t)read_u16(buf + 2) * 2;
    } else {
        uint32_t entryOffset = font->locaOffset + glyphIndex * 4;
        uint32_t entryNext = font->locaOffset + (glyphIndex + 1) * 4;
        uint8_t buf[8];
        if (!ttf_read_range(font, entryOffset, 4, buf)) return 0;
        if (!ttf_read_range(font, entryNext, 4, buf + 4)) return 0;
        glyphOffset = read_u32(buf);
        nextOffset = read_u32(buf + 4);
    }
    if (g_ttf_debug) LLOGD("loca gid=%u off=%u len=%u", (unsigned)glyphIndex, (unsigned)glyphOffset, (unsigned)(nextOffset - glyphOffset));
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

    /* 1.0: 按需把 glyph 数据读入临时缓冲 */
    uint8_t *tmp = (uint8_t*)malloc(length);
    if (!tmp) {
        return TTF_ERR_OOM;
    }
    if (!ttf_read_range(font, offset, length, tmp)) {
        if (g_ttf_debug) LLOGE("read glyf failed gid=%u off=%u len=%u", (unsigned)glyphIndex, (unsigned)offset, (unsigned)length);
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
            free(tmp);
            return TTF_ERR_FORMAT;
        }
        const uint8_t *flagsPtr = instructionPtr + instructionLength;

        if (glyph->contourEnds[glyph->contourCount - 1] >= 0xFFFFu) {
            ttf_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_FORMAT;
        }
        glyph->pointCount = glyph->contourEnds[glyph->contourCount - 1] + 1;
        if (glyph->pointCount == 0) {
            return TTF_OK;
        }

        uint8_t *flags = (uint8_t *)malloc(glyph->pointCount);
        if (!flags) {
            ttf_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_OOM;
        }
        const uint8_t *cursor = flagsPtr;
        uint16_t flagIndex = 0;
        while (flagIndex < glyph->pointCount) {
            if (cursor >= end) {
                free(flags);
                ttf_free_glyph(glyph);
                free(flags);
                free(tmp);
                return TTF_ERR_FORMAT;
            }
            uint8_t flag = *cursor++;
            flags[flagIndex++] = flag;
            if (flag & 0x08) {
                if (cursor >= end) {
                    free(flags);
                    ttf_free_glyph(glyph);
                    free(tmp);
                    return TTF_ERR_FORMAT;
                }
                uint8_t repeatCount = *cursor++;
                if (flagIndex + repeatCount > glyph->pointCount) {
                    free(flags);
                    ttf_free_glyph(glyph);
                    free(tmp);
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
            free(tmp);
            return TTF_OK;
    }


    const uint8_t *cursor = ptr + 10;
    uint16_t flags = 0;
    do {
        if (cursor + 4 > end) {
            ttf_free_glyph(glyph);
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
            free(tmp);
            return TTF_ERR_UNSUPPORTED;
        }

        float m00 = 1.0f;
        float m01 = 0.0f;
        float m10 = 0.0f;
        float m11 = 1.0f;
        if (flags & 0x0008) {
            if (cursor + 2 > end) {
                ttf_free_glyph(glyph);
                free(tmp);
                return TTF_ERR_FORMAT;
            }
            float scale = read_f2dot14(cursor);
            cursor += 2;
            m00 = scale;
            m11 = scale;
        } else if (flags & 0x0040) {
            if (cursor + 4 > end) {
                ttf_free_glyph(glyph);
                free(tmp);
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
            if (g_ttf_debug) LLOGE("load component glyph rc=%d", rc);
            free(tmp);
            return rc;
        }
        rc = append_component_glyph(glyph, &componentGlyph, m00, m01, m10, m11, dx, dy);
        ttf_free_glyph(&componentGlyph);
        if (rc != TTF_OK) {
            ttf_free_glyph(glyph);
            if (g_ttf_debug) LLOGE("append component rc=%d", rc);
            free(tmp);
            return rc;
        }
    } while (flags & 0x0020);

    if (flags & 0x0100) {
        if (cursor + 2 > end) {
            ttf_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_FORMAT;
        }
        uint16_t instructionLength = read_u16(cursor);
        cursor += 2;
        if (cursor + instructionLength > end) {
            ttf_free_glyph(glyph);
            free(tmp);
            return TTF_ERR_FORMAT;
        }
        cursor += instructionLength;
    }

    free(tmp);
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

    FixedSegmentList fixedSegments = {0};
    if (!convert_segments_to_fixed(&segments, &fixedSegments)) {
        free(pixels);
        free(segments.data);
        return TTF_ERR_OOM;
    }
    free(segments.data);

    const int supersampleRate = TTF_SUPERSAMPLE_RATE;
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
