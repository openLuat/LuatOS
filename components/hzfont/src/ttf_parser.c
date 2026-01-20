// 负责：TTF 解析、流式读取与栅格化（ttf_parser）
#include "ttf_parser.h"

#include <math.h>
#include <string.h>
#include "luat_fs.h"
#include "luat_mem.h"
#include "luat_hzfont.h"

#define LUAT_LOG_TAG "ttf"
#include "luat_log.h"

/* 表格记录结构体 */
typedef struct {
    uint32_t offset;
    uint32_t length;
} TableRecord;

/* CMAP 子表结构体 */
typedef struct {
    uint32_t offset; /* 绝对偏移：font->cmapOffset + subtableOffset */
    uint32_t length; /* 剩余长度（可用时校验，不一定严格） */
} CmapSubtable;

static inline float ttf_compute_scale(const TtfFont *font, int ppem); // 计算缩放比例
static inline int32_t ttf_round_pixel(float value); // 四舍五入浮点到 int32
static int ttf_read_hhea_metrics(TtfFont *font, const TableRecord *hhea); // 读取 hhea 表的 metrics
int32_t ttf_scaled_value(const TtfFont *font, int32_t value, int ppem); // 按照字体 metrics 计算像素值
int32_t ttf_scaled_line_height(const TtfFont *font, int ppem); // 按照字体 metrics 计算行高
int32_t ttf_scaled_baseline(const TtfFont *font, int ppem); // 按照字体 metrics 计算基线

static int g_ttf_debug = 0;
/* 运行时可调的超采样率，默认取编译期宏 */
static int g_ttf_supersample_rate = 0;

/* 防御性释放，避免 free(NULL) 提示 */
// 可防御性释放（NULL 安全）
static inline void ttf_safe_free(void *p) {
    if (p) {
        luat_heap_free(p);
    }
}

#define TTF_TAG(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))

/* 仅运行时控制超采样，不再依赖编译期宏 */

#define TTF_FIXED_SHIFT 8
#define TTF_FIXED_ONE   (1 << TTF_FIXED_SHIFT)
#define TTF_FIXED_HALF  (1 << (TTF_FIXED_SHIFT - 1))

// 设置 ttf 解析器的调试输出
int ttf_set_debug(int enable) { g_ttf_debug = enable ? 1 : 0; return g_ttf_debug; }
// 获取当前的调试标志
int ttf_get_debug(void) { return g_ttf_debug; }
// 查询编译期定义的默认超采样率
static inline int ttf_supersample_default(void) {
#ifdef TTF_SUPERSAMPLE_RATE
    return TTF_SUPERSAMPLE_RATE;
#else
    return 1;
#endif
}
// 读取当前的超采样率，未初始化时返回默认值
int ttf_get_supersample_rate(void) {
    if (g_ttf_supersample_rate == 0) {
        g_ttf_supersample_rate = ttf_supersample_default();
    }
    return g_ttf_supersample_rate;
}
// 设置运行时的超采样率（自动限幅为 1/2/4）
int ttf_set_supersample_rate(int rate) {
    int newRate;
    if (rate <= 1) newRate = 1;
    else if (rate <= 2) newRate = 2;
    else newRate = 4; /* 3或更大按4x4 */
    g_ttf_supersample_rate = newRate;
    return g_ttf_supersample_rate;
}

#define TTF_CMAP_CACHE_MAX   (512u * 1024u)

static void ttf_cache_cmap_subtable(TtfFont *font);

// 从大端内存读取 unsigned 16
static uint16_t read_u16(const uint8_t *p) {
    return (uint16_t)((p[0] << 8) | p[1]);
}

// 从大端内存读取 signed 16
static int16_t read_s16(const uint8_t *p) {
    return (int16_t)((p[0] << 8) | p[1]);
}

// 从大端内存读取 unsigned 32
static uint32_t read_u32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

// 将 F2.14 定点数转换成浮点
static float read_f2dot14(const uint8_t *p) {
    int16_t value = read_s16(p);
    return (float)value / 16384.0f;
}

// 四舍五入浮点到 int32
static int32_t round_to_int32(float value) {
    return (int32_t)(value >= 0.0f ? value + 0.5f : value - 0.5f);
}

// 确保请求的段在字体文件有效范围内
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
// 读取指定偏移段，兼容 data 内存或流式 file
static int ttf_read_range(const TtfFont *font, uint32_t offset, uint32_t length, uint8_t *out) {
    if (!font || !out || length == 0) {
        return 0;
    }
    if (!ensure_range(font, offset, length)) {
        return 0;
    }
    if (font->data_source == TTF_DATA_SOURCE_PSRAM_CHAIN && font->psram_chain) {
        return hzfont_psram_read_range(font->psram_chain, offset, length, out);
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

// 在字体目录中查找指定表格并返回偏移长度
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

// 从 VFS 文件加载 TTF（默认流式读取，兼容非 luat_fs 的 WIN 标准 fopen 回退）
int ttf_load_from_file(const char *path, TtfFont *font) {
    if (!path || !font) {
        return TTF_ERR_RANGE;
    }
    memset(font, 0, sizeof(*font));

    /* 1.0: 默认开启流式读取以节省内存（不整读），若需要可切换到整读模式 */
    FILE *vfp = luat_fs_fopen(path, "rb");
    if (!vfp) {
        #ifdef LUA_USE_WINDOWS
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
        font->data = (uint8_t*)luat_heap_malloc((size_t)fileSize);
        if (!font->data) {
            fclose(fp);
            return TTF_ERR_OOM;
        }
        size_t n = fread(font->data, 1, (size_t)fileSize, fp);
        fclose(fp);
        if (n != (size_t)fileSize) {
            ttf_safe_free(font->data);
            memset(font, 0, sizeof(*font));
            return TTF_ERR_IO;
        }
        font->size = (size_t)fileSize;
        font->file = NULL;
        font->fileSize = (size_t)fileSize;
        font->streaming = 0;
        font->ownsData = 1;
        font->data_source = TTF_DATA_SOURCE_MEMORY;
        font->psram_chain = NULL;
        #else
        return TTF_ERR_IO;
        #endif
    } else {
        // 如果使用 luat_fs 成功打开，则执行流式读取
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
        font->data_source = TTF_DATA_SOURCE_FILE;
        font->psram_chain = NULL;
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

    TableRecord cmap = {0}, glyf = {0}, head = {0}, loca = {0}, maxp = {0}, hhea = {0};
    if (!find_table(font, TTF_TAG('c', 'm', 'a', 'p'), &cmap) ||
        !find_table(font, TTF_TAG('g', 'l', 'y', 'f'), &glyf) ||
        !find_table(font, TTF_TAG('l', 'o', 'c', 'a'), &loca) ||
        !find_table(font, TTF_TAG('h', 'e', 'a', 'd'), &head) ||
        !find_table(font, TTF_TAG('m', 'a', 'x', 'p'), &maxp) ||
        !find_table(font, TTF_TAG('h', 'h', 'e', 'a'), &hhea)) {
        if (g_ttf_debug) LLOGE("find table failed cmap=%u glyf=%u loca=%u head=%u maxp=%u hhea=%u",
            (unsigned)(cmap.length>0), (unsigned)(glyf.length>0), (unsigned)(loca.length>0), (unsigned)(head.length>0), (unsigned)(maxp.length>0), (unsigned)(hhea.length>0));
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

// 从已有内存数据初始化 TTF（不复制，不释放）
static int ttf_load_from_common(TtfFont *font) {
    if (!font || font->size < 12) {
        return TTF_ERR_RANGE;
    }

    uint8_t hdr4[4];
    if (!ttf_read_range(font, 0, 4, hdr4)) {
        return TTF_ERR_IO;
    }
    uint32_t scalerType = read_u32(hdr4);
    if (scalerType != 0x00010000 && scalerType != TTF_TAG('O', 'T', 'T', 'O')) {
        return TTF_ERR_UNSUPPORTED;
    }

    TableRecord cmap = {0}, glyf = {0}, head = {0}, loca = {0}, maxp = {0}, hhea = {0};
    if (!find_table(font, TTF_TAG('c', 'm', 'a', 'p'), &cmap) ||
        !find_table(font, TTF_TAG('g', 'l', 'y', 'f'), &glyf) ||
        !find_table(font, TTF_TAG('l', 'o', 'c', 'a'), &loca) ||
        !find_table(font, TTF_TAG('h', 'e', 'a', 'd'), &head) ||
        !find_table(font, TTF_TAG('m', 'a', 'x', 'p'), &maxp) ||
        !find_table(font, TTF_TAG('h', 'h', 'e', 'a'), &hhea)) {
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

    if (!ttf_read_hhea_metrics(font, &hhea)) {
        font->ascent = (int16_t)font->unitsPerEm;
        font->descent = 0;
        font->lineGap = 0;
    }

    ttf_cache_cmap_subtable(font);
    if (g_ttf_debug) LLOGI("font loaded from memory size=%u units_per_em=%u glyphs=%u indexToLocFormat=%u",
        (unsigned)font->size, (unsigned)font->unitsPerEm, (unsigned)font->numGlyphs, (unsigned)font->indexToLocFormat);
    return TTF_OK;
}

// 从内存数据加载 TTF 字体结构
int ttf_load_from_memory(const uint8_t *data, size_t size, TtfFont *font) {
    // 参数检查
    if (!data || !font || size < 12) {
        return TTF_ERR_RANGE;
    }
    // 初始化 font 结构体
    memset(font, 0, sizeof(*font));
    font->data = (uint8_t*)data;      
    font->size = size;
    font->file = NULL;
    font->fileSize = size;
    font->streaming = 0;
    font->ownsData = 0;               
    font->data_source = TTF_DATA_SOURCE_MEMORY;
    font->psram_chain = NULL;
    return ttf_load_from_common(font);
}

// 从PSRAM 链结构加载 TTF 字体结构

int ttf_load_from_psram_chain(struct hzfont_psram_chain *chain, TtfFont *font) {
    // 参数检查
    if (!chain || !font || chain->total_size < 12) {
        return TTF_ERR_RANGE;
    }
    // 初始化 font 结构体
    memset(font, 0, sizeof(*font));
    font->data = NULL;                
    font->size = chain->total_size;
    font->file = NULL;
    font->fileSize = chain->total_size;
    font->streaming = 0;
    font->ownsData = 0;               
    font->data_source = TTF_DATA_SOURCE_PSRAM_CHAIN;
    font->psram_chain = chain;        
    return ttf_load_from_common(font);
}
// 彻底释放 TtfFont 使用的所有动态资源
void ttf_unload(TtfFont *font) {
    if (!font) {
        return;
    }
    if (font->data && font->ownsData) ttf_safe_free(font->data);
    if (font->file) luat_fs_fclose((FILE*)font->file);
    ttf_safe_free(font->cmapBuf);
    memset(font, 0, sizeof(*font));
}
// 从 cached cmap 或文件中读取 16 位值
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
// 从 cached cmap 或文件中读取 32 位值
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

// 查找 CMAP 12 格式子表并返回偏移/长度
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

// 查找 CMAP 4 格式子表并返回偏移/长度
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

// 缓存优先级最高的 CMAP 子表到内存，避免后续频繁读取
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
    uint8_t *buf = (uint8_t *)luat_heap_malloc(chosen.length);
    if (!buf) {
        if (g_ttf_debug) {
            LLOGW("cmap cache malloc fail len=%u", (unsigned)chosen.length);
        }
        return;
    }
    if (!ttf_read_range(font, chosen.offset, chosen.length, buf)) {
        ttf_safe_free(buf);
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

// 在 CMAP format 12 子表内采用二分查找得到 glyph index
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

// 查询一个 codepoint 对应的 glyph index（尝试 format12/format4）
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

// 读取 loca 表获取指定 glyph 的 glyf 区段偏移与长度
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

// 释放 glyph 的轮廓点与轮廓数组
void ttf_free_glyph(TtfGlyph *glyph) {
    if (!glyph) {
        return;
    }
    ttf_safe_free(glyph->contourEnds);
    ttf_safe_free(glyph->points);
    memset(glyph, 0, sizeof(*glyph));
}

// 将复合 glyph 的组件 glyph 附加到目标 glyph，包含变换
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

    TtfPoint *points = (TtfPoint *)luat_heap_realloc(dest->points, newPointCount * sizeof(TtfPoint));
    if (!points) {
        return TTF_ERR_OOM;
    }
    dest->points = points;

    uint16_t *contours = (uint16_t *)luat_heap_realloc(dest->contourEnds, newContourCount * sizeof(uint16_t));
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

// 从 glyf 表递归读取 glyph 轮廓（支持复合 glyph）
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
    uint8_t *tmp = (uint8_t*)luat_heap_malloc(length);
    if (!tmp) {
        return TTF_ERR_OOM;
    }
    if (!ttf_read_range(font, offset, length, tmp)) {
        if (g_ttf_debug) LLOGE("read glyf failed gid=%u off=%u len=%u", (unsigned)glyphIndex, (unsigned)offset, (unsigned)length);
        ttf_safe_free(tmp);
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

        glyph->contourEnds = (uint16_t *)luat_heap_calloc(glyph->contourCount, sizeof(uint16_t));
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
            ttf_safe_free(tmp);
            return TTF_ERR_FORMAT;
        }
        const uint8_t *flagsPtr = instructionPtr + instructionLength;

        if (glyph->contourEnds[glyph->contourCount - 1] >= 0xFFFFu) {
            ttf_free_glyph(glyph);
            ttf_safe_free(tmp);
            return TTF_ERR_FORMAT;
        }
        glyph->pointCount = glyph->contourEnds[glyph->contourCount - 1] + 1;
        if (glyph->pointCount == 0) {
            return TTF_OK;
        }

        uint8_t *flags = (uint8_t *)luat_heap_malloc(glyph->pointCount);
        if (!flags) {
            ttf_free_glyph(glyph);
            ttf_safe_free(tmp);
            return TTF_ERR_OOM;
        }
        const uint8_t *cursor = flagsPtr;
        uint16_t flagIndex = 0;
        while (flagIndex < glyph->pointCount) {
            if (cursor >= end) {
                ttf_safe_free(flags);
                ttf_free_glyph(glyph);
                ttf_safe_free(tmp);
                return TTF_ERR_FORMAT;
            }
            uint8_t flag = *cursor++;
            flags[flagIndex++] = flag;
            if (flag & 0x08) {
                if (cursor >= end) {
                    ttf_safe_free(flags);
                    ttf_free_glyph(glyph);
                    ttf_safe_free(tmp);
                    return TTF_ERR_FORMAT;
                }
                uint8_t repeatCount = *cursor++;
                if (flagIndex + repeatCount > glyph->pointCount) {
                    ttf_safe_free(flags);
                    ttf_free_glyph(glyph);
                    ttf_safe_free(tmp);
                    return TTF_ERR_FORMAT;
                }
                for (uint8_t r = 0; r < repeatCount; ++r) {
                    flags[flagIndex++] = flag;
                }
            }
        }

        glyph->points = (TtfPoint *)luat_heap_calloc(glyph->pointCount, sizeof(TtfPoint));
        if (!glyph->points) {
            ttf_safe_free(flags);
            ttf_free_glyph(glyph);
            return TTF_ERR_OOM;
        }

        int16_t x = 0;
        flagIndex = 0;
        while (flagIndex < glyph->pointCount) {
            uint8_t flag = flags[flagIndex++];
            if (flag & 0x02) {
                if (cursor >= end) {
                    ttf_safe_free(flags);
                    ttf_free_glyph(glyph);
                    return TTF_ERR_FORMAT;
                }
                uint8_t dx = *cursor++;
                x += (flag & 0x10) ? dx : -(int16_t)dx;
            } else if (!(flag & 0x10)) {
                if (cursor + 1 >= end) {
                    ttf_safe_free(flags);
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
                    ttf_safe_free(flags);
                    ttf_free_glyph(glyph);
                    return TTF_ERR_FORMAT;
                }
                uint8_t dy = *cursor++;
                y += (flag & 0x20) ? dy : -(int16_t)dy;
            } else if (!(flag & 0x20)) {
                if (cursor + 1 >= end) {
                    ttf_safe_free(flags);
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

        ttf_safe_free(flags);
            ttf_safe_free(tmp);
            return TTF_OK;
    }


    const uint8_t *cursor = ptr + 10;
    uint16_t flags = 0;
    do {
        if (cursor + 4 > end) {
            ttf_free_glyph(glyph);
            ttf_safe_free(tmp);
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
            ttf_safe_free(tmp);
            return TTF_ERR_UNSUPPORTED;
        }

        float m00 = 1.0f;
        float m01 = 0.0f;
        float m10 = 0.0f;
        float m11 = 1.0f;
        if (flags & 0x0008) {
            if (cursor + 2 > end) {
                ttf_free_glyph(glyph);
                ttf_safe_free(tmp);
                return TTF_ERR_FORMAT;
            }
            float scale = read_f2dot14(cursor);
            cursor += 2;
            m00 = scale;
            m11 = scale;
        } else if (flags & 0x0040) {
            if (cursor + 4 > end) {
                ttf_free_glyph(glyph);
                ttf_safe_free(tmp);
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
            ttf_safe_free(tmp);
            return rc;
        }
        rc = append_component_glyph(glyph, &componentGlyph, m00, m01, m10, m11, dx, dy);
        ttf_free_glyph(&componentGlyph);
        if (rc != TTF_OK) {
            ttf_free_glyph(glyph);
            if (g_ttf_debug) LLOGE("append component rc=%d", rc);
            ttf_safe_free(tmp);
            return rc;
        }
    } while (flags & 0x0020);

    if (flags & 0x0100) {
        if (cursor + 2 > end) {
            ttf_free_glyph(glyph);
            ttf_safe_free(tmp);
            return TTF_ERR_FORMAT;
        }
        uint16_t instructionLength = read_u16(cursor);
        cursor += 2;
        if (cursor + instructionLength > end) {
            ttf_free_glyph(glyph);
            ttf_safe_free(tmp);
            return TTF_ERR_FORMAT;
        }
        cursor += instructionLength;
    }

    ttf_safe_free(tmp);
    return TTF_OK;
}

// 公开接口：载入 glyph 轮廓（内部委托递归实现）
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

// 向平面线段列表追加一段（自动扩容）
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
        float *newData = (float *)luat_heap_realloc(segments->data, newCapacity * sizeof(float));
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

// 将浮点坐标转换为定点值
static inline int32_t float_to_fixed(float value) {
    float scaled = value * (float)TTF_FIXED_ONE;
    return (int32_t)lrintf(scaled);
}

// 批量将浮点段转换为定点表示（供点内查询）
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
    int32_t *buf = (int32_t *)luat_heap_malloc(total * sizeof(int32_t));
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

// 清理定点段列表
static void free_fixed_segments(FixedSegmentList *segments) {
    if (!segments) {
        return;
    }
    ttf_safe_free(segments->data);
    segments->data = NULL;
    segments->count = 0;
}

// 将二次贝塞尔曲线离散为纯线段
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

// 计算两个控制点之间的中点（当缺少 on-curve 点时使用）
static TtfPoint midpoint_point(const TtfPoint *a, const TtfPoint *b) {
    TtfPoint result;
    result.x = (int16_t)((a->x + b->x) / 2);
    result.y = (int16_t)((a->y + b->y) / 2);
    result.onCurve = 1;
    return result;
}

// 将 glyph 中的点转换到栅格空间（含缩放与偏移）
static void transform_point(const TtfGlyph *glyph, float scale, float offsetX, float offsetY,
                            const TtfPoint *pt, float *outX, float *outY) {
    *outX = (pt->x - glyph->minX) * scale + offsetX;
    *outY = (glyph->maxY - pt->y) * scale + offsetY;
}

// 从 glyph 轮廓构建线段列表供填充使用
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

// 判断某点是否在 glyph 填充区域内（钟形绕组法）
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
/**
 * @brief 栅格化指定 glyph 到 bitmap 像素位图
 * @param font    指向 TtfFont 对象（字体描述结构）
 * @param glyph   指向 TtfGlyph 对象（待渲染的 glyph 信息）
 * @param ppem    字号（以 points-per-em 指定，控制缩放比例）
 * @param bitmap  输出参数，指向 TtfBitmap 结构体，将填充渲染后的位图数据
 * @return TTF_OK 成功，或返回错误码（TTF_ERR_*）
 */
int ttf_rasterize_glyph(const TtfFont *font, const TtfGlyph *glyph, int ppem, TtfBitmap *bitmap) {
    if (!font || !glyph || !bitmap || ppem <= 0) {
        return TTF_ERR_RANGE;
    }
    memset(bitmap, 0, sizeof(*bitmap));

    if (glyph->pointCount == 0 || glyph->contourCount == 0) {
        return TTF_OK;
    }

    // 计算 glyph 在指定字号下的像素尺寸
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

    uint8_t *pixels = (uint8_t *)luat_heap_calloc((size_t)width * height, sizeof(uint8_t));
    if (!pixels) {
        return TTF_ERR_OOM;
    }

    // 用扁平化的线段表示 glyph 轮廓
    SegmentList segments = {0};
    float offsetX = 1.0f;
    float offsetY = 1.0f;
    if (!build_segments(glyph, scale, offsetX, offsetY, &segments)) {
        ttf_safe_free(pixels);
        ttf_safe_free(segments.data);
        return TTF_ERR_FORMAT;
    }

    // 将线段转换为定点格式，便于点在轮廓内判断
    FixedSegmentList fixedSegments = {0};
    if (!convert_segments_to_fixed(&segments, &fixedSegments)) {
        ttf_safe_free(pixels);
        ttf_safe_free(segments.data);
        return TTF_ERR_OOM;
    }
    ttf_safe_free(segments.data);

    // 按当前超采样率采样每个像素（用于计算覆盖率）
    const int supersampleRate = ttf_get_supersample_rate();
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
    bitmap->originX = ttf_scaled_value(font, glyph->minX, ppem);
    bitmap->originY = ttf_scaled_value(font, glyph->maxY, ppem);
    bitmap->scale = scale;
    return TTF_OK;
}

// 计算缩放比例
static inline float ttf_compute_scale(const TtfFont *font, int ppem) {
    if (!font || font->unitsPerEm == 0 || ppem <= 0) {
        return 0.0f;
    }
    return (float)ppem / (float)font->unitsPerEm;
}

// 四舍五入浮点到 int32
static inline int32_t ttf_round_pixel(float value) {
    return (int32_t)roundf(value);
}

// 读取 hhea 表的 metrics
static int ttf_read_hhea_metrics(TtfFont *font, const TableRecord *hhea) {
    if (!font || !hhea || hhea->length < 10) {
        return 0;
    }
    uint8_t buf[10];
    if (!ttf_read_range(font, hhea->offset, 10, buf)) {
        return 0;
    }
    font->ascent = read_s16(buf + 4);
    font->descent = read_s16(buf + 6);
    font->lineGap = read_s16(buf + 8);
    return 1;
}

// 按照字体 metrics 计算像素值
int32_t ttf_scaled_value(const TtfFont *font, int32_t value, int ppem) {
    float scale = ttf_compute_scale(font, ppem);
    if (scale == 0.0f) {
        return 0;
    }
    return ttf_round_pixel((float)value * scale);
}

// 按照字体 metrics 计算行高
int32_t ttf_scaled_line_height(const TtfFont *font, int ppem) {
    float scale = ttf_compute_scale(font, ppem);
    if (scale == 0.0f) {
        return 0;
    }
    float ascent = (float)font->ascent * scale;
    float descent = (float)font->descent * scale;
    float lineGap = (float)font->lineGap * scale;
    return ttf_round_pixel(ascent - descent + lineGap);
}

// 按照字体 metrics 计算基线
int32_t ttf_scaled_baseline(const TtfFont *font, int ppem) {
    return ttf_scaled_value(font, font->ascent, ppem);
}

// 释放 bitmap 的像素缓冲
void ttf_free_bitmap(TtfBitmap *bitmap) {
    if (!bitmap) {
        return;
    }
    ttf_safe_free(bitmap->pixels);
    memset(bitmap, 0, sizeof(*bitmap));
}
