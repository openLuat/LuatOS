// 负责：TTF 字体加载、缓存与渲染（HzFont）
#include "luat_hzfont.h"

#include "ttf_parser.h"
#include "luat_lcd.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_fs.h"
#include "luat_rtos.h"

#include <math.h>
#include <stdio.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "luat_conf_bsp.h"

#define LUAT_LOG_TAG "hzfont"
#include "luat_log.h"
#include "hzfont_psram.h"

#define HZFONT_FONT_PATH_MAX   260   // 字体文件路径最大长度
#define HZFONT_ADVANCE_RATIO   0.4f  // 默认advance距离比例
#define HZFONT_ASCENT_RATIO    0.8f  // 默认水平基线高度比例
#define HZFONT_YIELD_THRESHOLD_US 1000000ULL // 渲染循环中默认的让出调度时间间隔

/* 默认/允许缓存容量集中定义，便于维护 */
#define HZFONT_CACHE_DEFAULT 256u
static const uint32_t HZFONT_CACHE_ALLOWED[] = {128u, 256u, 512u, 1024u, 2048u};
static const size_t   HZFONT_CACHE_ALLOWED_LEN = sizeof(HZFONT_CACHE_ALLOWED) / sizeof(HZFONT_CACHE_ALLOWED[0]);

#ifdef LUAT_CONF_USE_HZFONT_BUILTIN_TTF
extern const unsigned char hzfont_builtin_ttf[];
extern const unsigned int hzfont_builtin_ttf_len;
#endif

typedef struct {
    luat_hzfont_state_t state;
    TtfFont font;
    char font_path[HZFONT_FONT_PATH_MAX];
} hzfont_ctx_t;

typedef enum {
    HZFONT_GLYPH_OK = 0,
    HZFONT_GLYPH_LOOKUP_FAIL,
    HZFONT_GLYPH_LOAD_FAIL,
    HZFONT_GLYPH_RASTER_FAIL,
    HZFONT_GLYPH_DRAW_FAIL
} hzfont_glyph_status_t;

/**
 * @brief 单个字符(glyph)在渲染流程中的完整上下文结构体
 * 用于记录字体渲染过程中与单个字符有关的所有信息，包括缓存、计时、渲染状态等。
 */
typedef struct {
    TtfBitmap bitmap;          ///< 字符位图数据（若 from_cache=1 则指向缓存）
    uint32_t advance;          ///< 字形前进宽度（像素），用于确定下一个字符位置
    uint32_t codepoint;        ///< Unicode 编码点（UTF-32）
    uint32_t glyph_index;      ///< 当前字体中的 glyph 索引
    // 以下4项用于性能分析/调试，记录各阶段耗时（单位：微秒us）
    uint32_t time_lookup_us;   ///< 查找Unicode与glyph索引映射所花时间
    uint32_t time_load_us;     ///< 载入glyph（从ttf或缓存）耗时
    uint32_t time_raster_us;   ///< 栅格化（ttf向bitmap转化）耗时
    uint32_t time_draw_us;     ///< 绘制 bitmap 到 LCD 的耗时
    uint8_t from_cache;        ///< 位图是否来自于缓存（1=是, 0=新生成）
    uint8_t has_bitmap;        ///< 是否成功获得了有效位图（1=有, 0=无/失败）
    uint8_t status;            ///< 渲染流程状态, 参考 hzfont_glyph_status_t 枚举
} glyph_render_t;

typedef struct {
    uint8_t r;
    uint8_t g;
    uint8_t b;
} rgb24_t;

static hzfont_ctx_t g_ft_ctx = {
    .state = LUAT_HZFONT_STATE_UNINIT
};

typedef struct {
    uint16_t glyph_index;
    uint8_t font_size;
    uint8_t supersample;
    uint8_t in_use;
    uint32_t last_used;
    TtfBitmap bitmap;
} hzfont_cache_entry_t;

static hzfont_cache_entry_t *g_hzfont_cache = NULL;
static uint32_t g_hzfont_cache_capacity = 0;
static uint32_t g_hzfont_cache_stamp = 0;

typedef struct {
    uint32_t codepoint;
    uint16_t glyph_index;
    uint8_t in_use;
    uint32_t last_used;
} hzfont_cp_cache_entry_t;

static hzfont_cp_cache_entry_t *g_hzfont_cp_cache = NULL;
static uint32_t g_hzfont_cp_cache_size = 0; /* 必须为 2 的幂，便于掩码寻址 */
/* 单次告警开关，避免重复噪声 */
static uint8_t g_warn_fontsize = 0;
static uint8_t g_warn_cache_invalid = 0;
static uint8_t g_warn_cp_cache_full = 0;
static hzfont_psram_chain_t g_psram_chain;

extern luat_lcd_conf_t *lcd_dft_conf;
extern luat_color_t BACK_COLOR;

// 初始化 PSRAM 数据链，清空元数据便于后续写入。
void hzfont_psram_chain_init(hzfont_psram_chain_t *chain) {
    if (!chain) {
        return;
    }
    chain->head = NULL;
    chain->tail = NULL;
    chain->total_size = 0;
    chain->block_count = 0;
}

// 释放链上所有块，并重置链表状态。
void hzfont_psram_chain_clear(hzfont_psram_chain_t *chain) {
    if (!chain) {
        return;
    }
    hzfont_psram_block_t *block = chain->head;
    while (block) {
        // 逐块释放链表中的所有 PSRAM 内存。
        hzfont_psram_block_t *next = block->next;
        luat_heap_opt_free(LUAT_HEAP_PSRAM, block);
        block = next;
    }
    chain->head = NULL;
    chain->tail = NULL;
    chain->total_size = 0;
    chain->block_count = 0;
}

// 从 PSRAM 分配新的块并追加到链尾。
hzfont_psram_block_t *hzfont_psram_chain_alloc_block(hzfont_psram_chain_t *chain) {
    if (!chain) {
        return NULL;
    }
    hzfont_psram_block_t *block = (hzfont_psram_block_t *)luat_heap_opt_malloc(LUAT_HEAP_PSRAM, sizeof(hzfont_psram_block_t));
    if (!block) {
        return NULL;
    }
    memset(block, 0, sizeof(*block));
    if (!chain->head) {
        chain->head = block;
        chain->tail = block;
    } else {
        chain->tail->next = block;
        chain->tail = block;
    }
    chain->block_count++;
    return block;
}

// 将数据追加到链表末尾，必要时自动扩容块。
int hzfont_psram_chain_append_data(hzfont_psram_chain_t *chain, const uint8_t *source, size_t length) {
    if (!chain || !source || length == 0) {
        return 0;
    }
    size_t remaining = length;
    while (remaining > 0) {
        if (!chain->tail || chain->tail->used == HZFONT_PSRAM_BLOCK_SIZE) {
            if (!hzfont_psram_chain_alloc_block(chain)) {
                return 0;
            }
        }
        // 计算当前块剩余空间并决定拷贝量。
        size_t slot = HZFONT_PSRAM_BLOCK_SIZE - chain->tail->used;
        size_t copy = remaining < slot ? remaining : slot;
        memcpy(chain->tail->data + chain->tail->used, source, copy);
        chain->tail->used += copy;
        chain->total_size += copy;
        source += copy;
        remaining -= copy;
    }
    return 1;
}

// 从链中的指定偏移读取固定长度数据。
int hzfont_psram_read_range(const hzfont_psram_chain_t *chain, uint32_t offset, uint32_t length, uint8_t *out) {
    if (!chain || !out || length == 0) {
        return 0;
    }
    size_t abs_offset = (size_t)offset;
    if (abs_offset + (size_t)length > chain->total_size) {
        return 0;
    }
    hzfont_psram_block_t *block = chain->head;
    size_t cursor = abs_offset;
    size_t need = length;
    while (block && need > 0) {
        if (cursor >= block->used) {
            cursor -= block->used;
            block = block->next;
            continue;
        }
        // 计算当前块可用数据并拷贝。
        size_t available = block->used - cursor;
        size_t chunk = available < need ? available : need;
        memcpy(out, block->data + cursor, chunk);
        out += chunk;
        need -= chunk;
        cursor = 0;
        block = block->next;
    }
    return need == 0;
}

// 获取当前精确的微秒级时间戳（兼容 tick 周期与 millisecond fallback）
static uint64_t hzfont_now_us(void) {
    int period = luat_mcu_us_period();
    if (period <= 0) {
        return luat_mcu_tick64_ms() * 1000ULL;
    }
    return luat_mcu_tick64() / (uint64_t)period;
}

// 计算当前时间与指定起点之间的延迟（取最大 UINT32）
static uint32_t hzfont_elapsed_from(uint64_t start) {
    if (start == 0) {
        return 0;
    }
    uint64_t now = hzfont_now_us();
    if (now <= start) {
        return 0;
    }
    uint64_t diff = now - start;
    if (diff > UINT32_MAX) {
        return UINT32_MAX;
    }
    return (uint32_t)diff;
}

// 获取距上一次时间点的差值并更新基准戳
static uint32_t hzfont_elapsed_step(uint64_t *stamp) {
    if (!stamp || *stamp == 0) {
        return 0;
    }
    uint64_t now = hzfont_now_us();
    uint64_t diff = (now > *stamp) ? (now - *stamp) : 0;
    *stamp = now;
    if (diff > UINT32_MAX) {
        return UINT32_MAX;
    }
    return (uint32_t)diff;
}

// 避免长时间循环导致调度器饿死，每隔一段时间让出一次 CPU
static inline void hzfont_maybe_yield(uint64_t *last_yield_us, uint64_t threshold_us) {
    if (!last_yield_us || threshold_us == 0) {
        return;
    }
    uint64_t now = hzfont_now_us();
    if (now >= *last_yield_us && now - *last_yield_us >= threshold_us) {
        if (ttf_get_debug()){ LLOGI("hzfont 长时间渲染，休息10ms，让出一次 CPU");}
        luat_rtos_task_sleep(10);
        *last_yield_us = hzfont_now_us();
    }
}

// 将 glyph 渲染状态转换为字符串用于日志输出
static const char *hzfont_status_text(uint8_t status) {
    switch (status) {
    case HZFONT_GLYPH_OK:
        return "ok";
    case HZFONT_GLYPH_LOOKUP_FAIL:
        return "lookup_fail";
    case HZFONT_GLYPH_LOAD_FAIL:
        return "load_fail";
    case HZFONT_GLYPH_RASTER_FAIL:
        return "raster_fail";
    case HZFONT_GLYPH_DRAW_FAIL:
        return "draw_fail";
    default:
        return "unknown";
    }
}

// 将 64 位延迟限制到 UInt32 上限
static uint32_t hzfont_clamp_u32(uint64_t value) {
    return value > UINT32_MAX ? UINT32_MAX : (uint32_t)value;
}

// 生成全局缓存时间戳（避免 0 重置）
static uint32_t hzfont_next_stamp(void) {
    g_hzfont_cache_stamp++;
    if (g_hzfont_cache_stamp == 0) {
        g_hzfont_cache_stamp = 1;
    }
    return g_hzfont_cache_stamp;
}

/* 判断缓存容量是否在允许列表 */
static int hzfont_is_allowed_capacity(uint32_t cap) {
    for (size_t i = 0; i < HZFONT_CACHE_ALLOWED_LEN; i++) {
        if (cap == HZFONT_CACHE_ALLOWED[i]) {
            return 1;
        }
    }
    return 0;
}

/* 将字体文件分块读入 PSRAM 链表 */
static int hzfont_load_file_to_ram(const char *path, hzfont_psram_chain_t *chain) {
    // 检查参数有效性
    if (!path || !chain) {
        return TTF_ERR_RANGE;
    }
    // 打开文件(只读二进制)
    FILE *fp = luat_fs_fopen(path, "rb");
    if (!fp) {
        return TTF_ERR_IO;
    }
    // 移动到文件末尾获取文件长度
    if (luat_fs_fseek(fp, 0, SEEK_END) != 0) {
        luat_fs_fclose(fp);
        return TTF_ERR_IO;
    }
    long vsize = luat_fs_ftell(fp);
    if (vsize <= 0) {
        luat_fs_fclose(fp);
        return TTF_ERR_IO;
    }
    // 恢复文件指针到起始
    if (luat_fs_fseek(fp, 0, SEEK_SET) != 0) {
        luat_fs_fclose(fp);
        return TTF_ERR_IO;
    }
    // 分块循环读取文件内容到 PSRAM 链表
    size_t remaining = (size_t)vsize;
    while (remaining > 0) {
        // 分配新块（如必要）
        if (!chain->tail || chain->tail->used == HZFONT_PSRAM_BLOCK_SIZE) {
            if (!hzfont_psram_chain_alloc_block(chain)) {
                luat_fs_fclose(fp);
                return TTF_ERR_OOM;
            }
        }
        size_t slot = HZFONT_PSRAM_BLOCK_SIZE - chain->tail->used; // 当前块剩余空间
        size_t need = remaining < slot ? remaining : slot;         // 本轮需读取字节数
        size_t read = luat_fs_fread(chain->tail->data + chain->tail->used, 1, need, fp);
        if (read == 0) { // 读失败
            luat_fs_fclose(fp);
            return TTF_ERR_IO;
        }
        // 更新时间及指针
        chain->tail->used += read;
        chain->total_size += read;
        remaining -= read;
    }
    luat_fs_fclose(fp); // 关闭文件
    return TTF_OK;
}

// 释放所有缓存条目与辅助哈希表
static void hzfont_cache_destroy(void) {
    if (g_hzfont_cache && g_hzfont_cache_capacity) {
        for (size_t i = 0; i < g_hzfont_cache_capacity; ++i) {
            hzfont_cache_entry_t *entry = &g_hzfont_cache[i];
            if (entry->in_use && entry->bitmap.pixels) {
                ttf_free_bitmap(&entry->bitmap);
            }
        }
        luat_heap_free(g_hzfont_cache);
    }
    g_hzfont_cache = NULL;
    g_hzfont_cache_capacity = 0;

    if (g_hzfont_cp_cache && g_hzfont_cp_cache_size) {
        luat_heap_free(g_hzfont_cp_cache);
    }
    g_hzfont_cp_cache = NULL;
    g_hzfont_cp_cache_size = 0;
    g_hzfont_cache_stamp = 0;
}

// 根据期望容量分配或重置 glyph/cache 缓存
static int hzfont_setup_caches(uint32_t capacity) {
    uint32_t cap = hzfont_is_allowed_capacity(capacity) ? capacity : HZFONT_CACHE_DEFAULT;
    if (!hzfont_is_allowed_capacity(capacity) && !g_warn_cache_invalid) {
        LLOGW("hzfont event=init cache_size_invalid=%lu use_default=%lu", (unsigned long)capacity, (unsigned long)cap);
        g_warn_cache_invalid = 1;
    }

    if (g_hzfont_cache_capacity == cap && g_hzfont_cache && g_hzfont_cp_cache && g_hzfont_cp_cache_size == cap) {
        memset(g_hzfont_cache, 0, sizeof(hzfont_cache_entry_t) * cap);
        memset(g_hzfont_cp_cache, 0, sizeof(hzfont_cp_cache_entry_t) * cap);
        g_hzfont_cache_stamp = 0;
        return 1;
    }

    hzfont_cache_destroy();

    g_hzfont_cache = (hzfont_cache_entry_t *)luat_heap_malloc(sizeof(hzfont_cache_entry_t) * cap);
    if (!g_hzfont_cache) {
        return 0;
    }
    memset(g_hzfont_cache, 0, sizeof(hzfont_cache_entry_t) * cap);
    g_hzfont_cache_capacity = cap;

    /* 码点缓存大小与位图缓存容量保持一致，且为 2 的幂 */
    g_hzfont_cp_cache = (hzfont_cp_cache_entry_t *)luat_heap_malloc(sizeof(hzfont_cp_cache_entry_t) * cap);
    if (!g_hzfont_cp_cache) {
        luat_heap_free(g_hzfont_cache);
        g_hzfont_cache = NULL;
        g_hzfont_cache_capacity = 0;
        return 0;
    }
    memset(g_hzfont_cp_cache, 0, sizeof(hzfont_cp_cache_entry_t) * cap);
    g_hzfont_cp_cache_size = cap;
    g_hzfont_cache_stamp = 0;
    return 1;
}

// 清空码点到 glyph 索引的快速哈希
static void hzfont_cp_cache_clear(void) {
    if (g_hzfont_cp_cache && g_hzfont_cp_cache_size) {
        memset(g_hzfont_cp_cache, 0, sizeof(hzfont_cp_cache_entry_t) * g_hzfont_cp_cache_size);
    }
}

// 清空位图缓存并释放各条目 bitmap
static void hzfont_cache_clear(void) {
    if (g_hzfont_cache && g_hzfont_cache_capacity) {
        for (size_t i = 0; i < g_hzfont_cache_capacity; ++i) {
            hzfont_cache_entry_t *entry = &g_hzfont_cache[i];
            if (entry->in_use) {
                if (entry->bitmap.pixels) {
                    ttf_free_bitmap(&entry->bitmap);
                }
                memset(entry, 0, sizeof(*entry));
            }
        }
    }
    hzfont_cp_cache_clear();
    g_hzfont_cache_stamp = 0;
}

// 更新缓存条目的最近使用时间戳
static void hzfont_cache_touch(hzfont_cache_entry_t *entry) {
    if (!entry) {
        return;
    }
    entry->last_used = hzfont_next_stamp();
}

// 在缓存中查找匹配的 glyph 位图
static hzfont_cache_entry_t *hzfont_cache_find(uint16_t glyph_index, uint8_t font_size, uint8_t supersample) {
    if (!g_hzfont_cache || g_hzfont_cache_capacity == 0) {
        return NULL;
    }
    for (size_t i = 0; i < g_hzfont_cache_capacity; ++i) {
        hzfont_cache_entry_t *entry = &g_hzfont_cache[i];
        if (entry->in_use &&
            entry->glyph_index == glyph_index &&
            entry->font_size == font_size &&
            entry->supersample == supersample) {
            return entry;
        }
    }
    return NULL;
}

// 获取缓存条目并更新活跃度（命中则触发 touch）
static hzfont_cache_entry_t *hzfont_cache_get(uint16_t glyph_index, uint8_t font_size, uint8_t supersample) {
    hzfont_cache_entry_t *entry = hzfont_cache_find(glyph_index, font_size, supersample);
    if (entry) {
        hzfont_cache_touch(entry);
    }
    return entry;
}

// 分配新的缓存槽，必要时踢出最久未使用的条目
static hzfont_cache_entry_t *hzfont_cache_allocate_slot(void) {
    if (!g_hzfont_cache || g_hzfont_cache_capacity == 0) {
        return NULL;
    }
    for (size_t i = 0; i < g_hzfont_cache_capacity; ++i) {
        if (!g_hzfont_cache[i].in_use) {
            return &g_hzfont_cache[i];
        }
    }
    uint32_t oldest = UINT32_MAX;
    size_t oldest_index = 0;
    for (size_t i = 0; i < g_hzfont_cache_capacity; ++i) {
        if (g_hzfont_cache[i].last_used < oldest) {
            oldest = g_hzfont_cache[i].last_used;
            oldest_index = i;
        }
    }
    hzfont_cache_entry_t *entry = &g_hzfont_cache[oldest_index];
    if (entry->in_use && entry->bitmap.pixels) {
        ttf_free_bitmap(&entry->bitmap);
    }
    memset(entry, 0, sizeof(*entry));
    return entry;
}

// 插入新 bitmap 到缓存（支持替换现有条目）
static hzfont_cache_entry_t *hzfont_cache_insert(uint16_t glyph_index, uint8_t font_size,
                                                     uint8_t supersample, TtfBitmap *bitmap) {
    if (!bitmap || !bitmap->pixels) {
        return NULL;
    }
    // 先查找是否已在缓存中存在
    hzfont_cache_entry_t *entry = hzfont_cache_find(glyph_index, font_size, supersample);
    if (!entry) {
        // 不存在，则分配新的缓存槽
        entry = hzfont_cache_allocate_slot();
    } else {
        // 存在，则替换现有的 bitmap
        if (entry->bitmap.pixels) {
            ttf_free_bitmap(&entry->bitmap);
        }
        memset(&entry->bitmap, 0, sizeof(entry->bitmap));
    }
    entry->glyph_index = glyph_index;
    entry->font_size = font_size;
    entry->supersample = supersample;
    entry->bitmap = *bitmap;
    entry->in_use = 1;
    hzfont_cache_touch(entry);
    return entry;
}

// 从码点缓存快速找到 glyph 索引
static hzfont_cp_cache_entry_t *hzfont_cp_cache_lookup(uint32_t codepoint) {
    if (!g_hzfont_cp_cache || g_hzfont_cp_cache_size == 0) {
        return NULL;
    }
    uint32_t mask = g_hzfont_cp_cache_size - 1u;
    uint32_t start = (uint32_t)((codepoint * 2654435761u) & mask);
    for (uint32_t probe = 0; probe < g_hzfont_cp_cache_size; ++probe) {
        hzfont_cp_cache_entry_t *entry = &g_hzfont_cp_cache[(start + probe) & mask];
        if (!entry->in_use) {
            return NULL;
        }
        if (entry->codepoint == codepoint) {
            entry->last_used = hzfont_next_stamp();
            return entry;
        }
    }
    return NULL;
}

// 将 codepoint 与 glyph 索引写入哈希缓存（含 LRU 逻辑）
static void hzfont_cp_cache_insert(uint32_t codepoint, uint16_t glyph_index) {
    if (!g_hzfont_cp_cache || g_hzfont_cp_cache_size == 0) {
        return;
    }
    const uint32_t mask = g_hzfont_cp_cache_size - 1u;
    const uint32_t start = (uint32_t)((codepoint * 2654435761u) & mask);
    hzfont_cp_cache_entry_t *empty_slot = NULL;
    // 线性探测
    for (uint32_t probe = 0; probe < g_hzfont_cp_cache_size; ++probe) {
        hzfont_cp_cache_entry_t *entry = &g_hzfont_cp_cache[(start + probe) & mask];
        if (!entry->in_use) {
            // 发现空槽，记下来用于插入
            empty_slot = entry;
            break;
        }
        if (entry->codepoint == codepoint) {
            // 已存在则替换 glyph 并刷新 LRU
            entry->glyph_index = glyph_index;
            entry->last_used = hzfont_next_stamp();
            return;
        }
    }
    // 没有空槽，则通过插入时间来踢掉最久未使用的空槽
    hzfont_cp_cache_entry_t *target = empty_slot;
    if (!target) {
        // 全表已占用，发一次告警并踢掉最久未使用的 entry（LRU）
        LLOGW("hzfont缓存size=%lu已满，请提高缓存大小，否则会影响字符渲染性能", (unsigned long)g_hzfont_cp_cache_size);
        uint32_t oldest = UINT32_MAX;
        size_t oldest_idx = 0;
        for (size_t i = 0; i < g_hzfont_cp_cache_size; ++i) {
            if (g_hzfont_cp_cache[i].last_used < oldest) {
                oldest = g_hzfont_cp_cache[i].last_used;
                oldest_idx = i;
            }
        }
        target = &g_hzfont_cp_cache[oldest_idx];
    }
    // 写入新条目并更新状态/时间戳
    target->codepoint = codepoint;
    target->glyph_index = glyph_index;
    target->in_use = 1;
    target->last_used = hzfont_next_stamp();
}

// 根据字体大小估算一个默认 advance（用于缺失 glyph）
static uint32_t hzfont_calc_fallback_advance(unsigned char font_size) {
    float adv = (float)font_size * HZFONT_ADVANCE_RATIO;
    if (adv < 1.0f) {
        adv = 1.0f;
    }
    return (uint32_t)ceilf(adv);
}

// 计算默认的上升高度用于基线对齐
static uint32_t hzfont_default_ascent(unsigned char font_size) {
    float asc = (float)font_size * HZFONT_ASCENT_RATIO;
    if (asc < 1.0f) {
        asc = 1.0f;
    }
    return (uint32_t)ceilf(asc);
}

// 逐字符解码 UTF-8，遇错则返回占位符
static int utf8_decode_next(const unsigned char **cursor, const unsigned char *end, uint32_t *codepoint) {
    const unsigned char *ptr = *cursor;
    if (ptr >= end) {
        return 0;
    }
    unsigned char c0 = *ptr++;
    if (c0 < 0x80) {
        *codepoint = c0;
        *cursor = ptr;
        return 1;
    }
    if ((c0 & 0xE0) == 0xC0) {
        if (ptr < end) {
            unsigned char c1 = *ptr;
            if ((c1 & 0xC0) == 0x80) {
                *codepoint = ((uint32_t)(c0 & 0x1F) << 6) | (uint32_t)(c1 & 0x3F);
                *cursor = ptr + 1;
                return 1;
            }
        }
    } else if ((c0 & 0xF0) == 0xE0) {
        if (ptr + 1 < end) {
            unsigned char c1 = ptr[0];
            unsigned char c2 = ptr[1];
            if (((c1 & 0xC0) == 0x80) && ((c2 & 0xC0) == 0x80)) {
                *codepoint = ((uint32_t)(c0 & 0x0F) << 12) |
                             ((uint32_t)(c1 & 0x3F) << 6) |
                             (uint32_t)(c2 & 0x3F);
                *cursor = ptr + 2;
                return 1;
            }
        }
    } else if ((c0 & 0xF8) == 0xF0) {
        if (ptr + 2 < end) {
            unsigned char c1 = ptr[0];
            unsigned char c2 = ptr[1];
            unsigned char c3 = ptr[2];
            if (((c1 & 0xC0) == 0x80) && ((c2 & 0xC0) == 0x80) && ((c3 & 0xC0) == 0x80)) {
                *codepoint = ((uint32_t)(c0 & 0x07) << 18) |
                             ((uint32_t)(c1 & 0x3F) << 12) |
                             ((uint32_t)(c2 & 0x3F) << 6) |
                             (uint32_t)(c3 & 0x3F);
                *cursor = ptr + 3;
                return 1;
            }
        }
    }
    *codepoint = '?';
    *cursor = ptr;
    return 1;
}

// 从 RGB565 格式拆分出 RGB 分量（供颜色混合使用）
static void rgb_from_rgb565(uint16_t color, uint8_t *r, uint8_t *g, uint8_t *b) {
    *r = (uint8_t)(((color >> 11) & 0x1F) * 255 / 31);
    *g = (uint8_t)(((color >> 5) & 0x3F) * 255 / 63);
    *b = (uint8_t)((color & 0x1F) * 255 / 31);
}

// 将 24 位 RGB 值编码为 RGB565
static uint16_t rgb565_from_rgb(uint8_t r, uint8_t g, uint8_t b) {
    uint16_t rr = (uint16_t)((r * 31 + 127) / 255) << 11;
    uint16_t gg = (uint16_t)((g * 63 + 127) / 255) << 5;
    uint16_t bb = (uint16_t)((b * 31 + 127) / 255);
    return (uint16_t)(rr | gg | bb);
}

// 解码用户传入的 color，支持 RGB565/24bit/32bit格式
static rgb24_t hzfont_decode_input_color(uint32_t color) {
    rgb24_t out;
    if (color <= 0xFFFFu) {
        rgb_from_rgb565((uint16_t)color, &out.r, &out.g, &out.b);
    } else if (color <= 0xFFFFFFu) {
        out.r = (uint8_t)((color >> 16) & 0xFF);
        out.g = (uint8_t)((color >> 8) & 0xFF);
        out.b = (uint8_t)(color & 0xFF);
    } else {
        out.r = (uint8_t)((color >> 16) & 0xFF);
        out.g = (uint8_t)((color >> 8) & 0xFF);
        out.b = (uint8_t)(color & 0xFF);
    }
    return out;
}

// 从 LCD 配置中的颜色空间提取 RGB 分量
static rgb24_t hzfont_decode_luat_color(const luat_lcd_conf_t *conf, luat_color_t color) {
    rgb24_t out = {255, 255, 255};
    if (!conf) {
        return out;
    }
    switch (conf->bpp) {
    case 16:
        rgb_from_rgb565((uint16_t)color, &out.r, &out.g, &out.b);
        break;
    case 24:
        LLOGE("don't support rgb24 color=%u", color);
        break;
    case 32:
        LLOGE("don't support rgb32 color=%u", color);
        break;
    default:
        rgb_from_rgb565((uint16_t)color, &out.r, &out.g, &out.b);
        break;
    }
    return out;
}

// 根据 LCD bpp 将 RGB 分量重新组合成目标颜色值
static luat_color_t hzfont_encode_color(const luat_lcd_conf_t *conf, uint8_t r, uint8_t g, uint8_t b) {
    if (!conf) {
        return rgb565_from_rgb(r, g, b);
    }
    switch (conf->bpp) {
    case 16:
        return rgb565_from_rgb(r, g, b);
    case 24:
        return (luat_color_t)(((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b);
    case 32:
        return (luat_color_t)(0xFF000000u | ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b);
    default:
        return rgb565_from_rgb(r, g, b);
    }
}

// 根据子像素覆盖率在 fg/bg 之间混色，输出对应 LCD 格式值
static luat_color_t hzfont_coverage_to_color(uint8_t coverage, const luat_lcd_conf_t *conf,
                                               const rgb24_t *fg, const rgb24_t *bg) {
    if (coverage == 0) {
        return 0;
    }
    uint32_t inv = 255u - (uint32_t)coverage;
    uint32_t rr = ((uint32_t)fg->r * coverage + (uint32_t)bg->r * inv) / 255u;
    uint32_t gg = ((uint32_t)fg->g * coverage + (uint32_t)bg->g * inv) / 255u;
    uint32_t bb = ((uint32_t)fg->b * coverage + (uint32_t)bg->b * inv) / 255u;
    return hzfont_encode_color(conf, (uint8_t)rr, (uint8_t)gg, (uint8_t)bb);
}

/* 初始化字体库
 * What: 加载 TTF（外部/内置），可选整包读入 PSRAM，建立码点与位图缓存。
 * Pre: 需要有效的 ttf_path 或启用内置字库宏；cache_size 仅允许 128/256/512/1024/2048；load_to_psram=1 时需有足够 RAM。
 * Post: 状态置为 READY，后续方可测宽/绘制；失败时状态为 ERROR。
 */
int luat_hzfont_init(const char *ttf_path, uint32_t cache_size, int load_to_psram) {
    // 已初始化直接返回
    if (g_ft_ctx.state == LUAT_HZFONT_STATE_READY) {
        LLOGE("font already initialized");
        return 0;
    }

    // 分配并重置缓存
    if (!hzfont_setup_caches(cache_size)) {
        LLOGE("cache alloc fail size=%lu", (unsigned long)cache_size);
        return 0;
    }
    hzfont_cache_clear();
    memset(&g_ft_ctx.font, 0, sizeof(g_ft_ctx.font));

    int rc = TTF_ERR_RANGE;
    // 加载 TTF 字体主分支
    if (ttf_path && ttf_path[0]) {
        if (load_to_psram) {
            // 使用 PSRAM 链，将字体文件读入 psram 并通过链表结构操作
            hzfont_psram_chain_clear(&g_psram_chain);
            hzfont_psram_chain_init(&g_psram_chain);
            rc = hzfont_load_file_to_ram(ttf_path, &g_psram_chain);
            if (rc == TTF_OK) {
                rc = ttf_load_from_psram_chain(&g_psram_chain, &g_ft_ctx.font);
                if (rc == TTF_OK) {
                    // 记录成功并保存字体路径
                    g_ft_ctx.font_path[0] = 0;
                    strncpy(g_ft_ctx.font_path, ttf_path, sizeof(g_ft_ctx.font_path) - 1);
                    g_ft_ctx.font_path[sizeof(g_ft_ctx.font_path) - 1] = 0;
                    LLOGI("psram loaded ttf size=%zu bytes, blocks=%u", g_psram_chain.total_size, g_psram_chain.block_count);
                } else {
                    // 加载失败，释放链
                    hzfont_psram_chain_clear(&g_psram_chain);
                }
            }
        } else {
            // 直接从文件加载，不经过psram
            rc = ttf_load_from_file(ttf_path, &g_ft_ctx.font);
            if (rc == TTF_OK) {
                strncpy(g_ft_ctx.font_path, ttf_path, sizeof(g_ft_ctx.font_path) - 1);
                g_ft_ctx.font_path[sizeof(g_ft_ctx.font_path) - 1] = 0;
            }
        }
    } else {
#ifdef LUAT_CONF_USE_HZFONT_BUILTIN_TTF
        if (load_to_psram) {
            // 加载内置 TTF 到 psram
            hzfont_psram_chain_clear(&g_psram_chain);
            hzfont_psram_chain_init(&g_psram_chain);
            if (!hzfont_psram_chain_append_data(&g_psram_chain, hzfont_builtin_ttf, (size_t)hzfont_builtin_ttf_len)) {
                LLOGE("load builtin ttf to psram failed");
                rc = TTF_ERR_OOM;
            } else {
                rc = ttf_load_from_psram_chain(&g_psram_chain, &g_ft_ctx.font);
                if (rc == TTF_OK) {
                    g_ft_ctx.font_path[0] = '\0';
                    LLOGI("psram loaded ttf size=%zu bytes, blocks=%u", g_psram_chain.total_size, g_psram_chain.block_count);
                } else {
                    // 内置ttf加载失败
                    LLOGE("load builtin ttf to ram failed rc=%d", rc);
                    hzfont_psram_chain_clear(&g_psram_chain);
                }
            }
        } else {
            // 从内存直接加载内置 TTF
            rc = ttf_load_from_memory(hzfont_builtin_ttf, (size_t)hzfont_builtin_ttf_len, &g_ft_ctx.font);
            if (rc == TTF_OK) {
                g_ft_ctx.font_path[0] = '\0';
            }
        }
#else
        // 无 TTF 文件、也没开内置字体
        LLOGE("empty ttf path and no builtin ttf");
        rc = TTF_ERR_RANGE;
#endif
    }

    // 加载结果处理
    if (rc != TTF_OK) {
        LLOGE("load font fail rc=%d", rc);
        ttf_unload(&g_ft_ctx.font);
        g_ft_ctx.state = LUAT_HZFONT_STATE_ERROR;
        return 0;
    }
    g_ft_ctx.state = LUAT_HZFONT_STATE_READY;
    LLOGI("font loaded units_per_em=%u glyphs=%u", g_ft_ctx.font.unitsPerEm, g_ft_ctx.font.numGlyphs);
    return 1;
}

// 释放 hzfont 上下文并重置缓存状态
void luat_hzfont_deinit(void) {
    if (g_ft_ctx.state == LUAT_HZFONT_STATE_UNINIT) {
        return;
    }
    hzfont_cache_clear();
    ttf_unload(&g_ft_ctx.font);
    hzfont_psram_chain_clear(&g_psram_chain);
    hzfont_cache_destroy();
    memset(&g_ft_ctx, 0, sizeof(g_ft_ctx));
    g_ft_ctx.state = LUAT_HZFONT_STATE_UNINIT;
}

// 查询 hzfont 当前状态
luat_hzfont_state_t luat_hzfont_get_state(void) {
    return g_ft_ctx.state;
}

// 估算 glyph 渲染后的宽度（用于宽度计算逻辑）
static uint32_t hzfont_glyph_estimate_width_px(const TtfGlyph *glyph, float scale) {
    if (!glyph || glyph->pointCount == 0 || glyph->contourCount == 0) {
        return 0;
    }
    float widthF = (glyph->maxX - glyph->minX) * scale + 2.0f;
    if (widthF < 1.0f) {
        widthF = 1.0f;
    }
    return (uint32_t)ceilf(widthF);
}

// 估算 UTF-8 字符串的渲染宽度（不实际绘制）
uint32_t luat_hzfont_get_str_width(const char *utf8, unsigned char font_size) {
    if (!utf8 || font_size == 0 || g_ft_ctx.state != LUAT_HZFONT_STATE_READY) {
        return 0;
    }
    if (g_ft_ctx.font.unitsPerEm == 0) {
        return 0;
    }

    const unsigned char *cursor = (const unsigned char *)utf8;
    const unsigned char *end = cursor + strlen(utf8);
    uint32_t total = 0;
    float scale = (float)font_size / (float)g_ft_ctx.font.unitsPerEm;
    if (scale <= 0.0f) {
        scale = 1.0f;
    }

    while (cursor < end) {
        uint32_t cp = 0;
        if (!utf8_decode_next(&cursor, end, &cp)) {
            break;
        }
        if (cp == '\r' || cp == '\n') {
            continue;
        }
        uint16_t glyph_index = 0;
        if (ttf_lookup_glyph_index(&g_ft_ctx.font, cp, &glyph_index) != TTF_OK) {
            if (cp == ' ' || cp == '\t') {
                total += hzfont_calc_fallback_advance(font_size);
                continue;
            }
            uint16_t star_index = 0;
            if (ttf_lookup_glyph_index(&g_ft_ctx.font, (uint32_t)'*', &star_index) == TTF_OK) {
                TtfGlyph star_glyph;
                int rc2 = ttf_load_glyph(&g_ft_ctx.font, star_index, &star_glyph);
                if (rc2 == TTF_OK) {
                    uint32_t width = hzfont_glyph_estimate_width_px(&star_glyph, scale);
                    ttf_free_glyph(&star_glyph);
                    if (width == 0) {
                        width = hzfont_calc_fallback_advance(font_size);
                    }
                    total += width;
                    continue;
                }
            }
            total += hzfont_calc_fallback_advance(font_size);
            continue;
        }

        TtfGlyph glyph;
        int rc = ttf_load_glyph(&g_ft_ctx.font, glyph_index, &glyph);
        if (rc != TTF_OK) {
            total += hzfont_calc_fallback_advance(font_size);
            continue;
        }
        uint32_t width = hzfont_glyph_estimate_width_px(&glyph, scale);
        ttf_free_glyph(&glyph);
        if (width == 0) {
            width = hzfont_calc_fallback_advance(font_size);
        }
        total += width;
    }
    return total;
}

// 清理临时 glyph 渲染结构，释放非缓存 bitmap
static void hzfont_release_glyphs(glyph_render_t *glyphs, size_t count) {
    if (!glyphs) {
        return;
    }
    for (size_t i = 0; i < count; i++) {
        if (glyphs[i].bitmap.pixels && !glyphs[i].from_cache) {
            ttf_free_bitmap(&glyphs[i].bitmap);
        }
    }
    luat_heap_free(glyphs);
}

// 根据字号决定默认的抗锯齿等级
static inline int hzfont_pick_antialias_auto(unsigned char font_size) {
    /* 规则：<=12 无抗锯齿 ，>12 用2x2超采样抗锯齿 */
    return (font_size <= 12) ? 1 : 2;
}



/**
 * 在屏幕上绘制 UTF-8 文本（带缓存和抗锯齿控制）
 * @param x         绘制起始 X 坐标
 * @param y         绘制起始 Y 坐标
 * @param utf8      待绘制的 UTF-8 字符串
 * @param font_size 字号（像素值）
 * @param color     文本颜色（ARGB/RGB 格式，依赖底层 LCD 驱动）
 * @param antialias 抗锯齿等级：-1=自动, 1=无AA, 2=2x2, 4=4x4
 * @return 绘制成功返回0，失败返回负值
 */
int luat_hzfont_draw_utf8(int x, int y, const char *utf8, unsigned char font_size, uint32_t color, int antialias) {
    // 检查font_size参数有效性
    if (!utf8 || font_size == 0) {
        if (!g_warn_fontsize) {
            LLOGE("hzfont event=draw invalid_font_size=%u range=1..255", (unsigned)font_size);
            g_warn_fontsize = 1;
        }
        return -1;
    }
    // 检查字体状态,看是否成功加载
    if (g_ft_ctx.state != LUAT_HZFONT_STATE_READY) {
        LLOGE("font not ready");
        return -1;
    }
    // 检查LCD是否初始化
    if (!lcd_dft_conf) {
        LLOGE("lcd not init");
        return -1;
    }
    // 检查字体长度,看是否为空
    size_t utf8_len = strlen(utf8);
    if (utf8_len == 0) {
        return 0;
    }

    // 检查调试开关,看是否开启，当前主要效果为打印渲染时间
    int timing_enabled = ttf_get_debug();
    // 检查抗锯齿等级
    int prev_rate = ttf_get_supersample_rate();
    int new_rate = prev_rate;
    if (antialias < 0) { // -1时自动选择抗锯齿等级
        new_rate = hzfont_pick_antialias_auto(font_size); 
    } else if (antialias <= 1) { // 1时无抗锯齿
        new_rate = 1;
    } else if (antialias == 2) { // 2时2x2超采样抗锯齿
        new_rate = 2;
    } else { // 4时4x4超采样抗锯齿
        new_rate = 4;
    }
    // 检查抗锯齿等级是否发生变化，如果发生变化，则设置新的抗锯齿等级
    if (new_rate != prev_rate) {
        (void)ttf_set_supersample_rate(new_rate);
    }

    // 记录渲染开始时间
    uint64_t func_start_ts = timing_enabled ? hzfont_now_us() : 0;
    uint64_t sum_lookup_us = 0;
    uint64_t sum_load_us = 0;
    uint64_t sum_raster_us = 0;
    uint64_t sum_draw_us = 0;
    uint64_t sum_total_us = 0;
    uint64_t sum_rendered_total_us = 0;
    size_t rendered_count = 0;
    size_t profiled_glyphs = 0;
    uint32_t max_glyph_total_us = 0;
    glyph_render_t max_slot_snapshot;
    memset(&max_slot_snapshot, 0, sizeof(max_slot_snapshot));
    int result = 0; // 使用 result 传递绘制错误码，默认 0 表示成功

    // 解码前景/背景颜色用于抗锯齿混合
    rgb24_t fg = hzfont_decode_input_color(color);
    rgb24_t bg = hzfont_decode_luat_color(lcd_dft_conf, BACK_COLOR); // 当前背景色默认为白色

    // 遍历UTF-8字符串，边解码边绘制
    const unsigned char *cursor = (const unsigned char *)utf8;
    const unsigned char *end = cursor + utf8_len;
    size_t glyph_count = 0;
    // 按照字体 metrics 计算基线
    int32_t font_baseline = ttf_scaled_baseline(&g_ft_ctx.font, font_size);
    // 如果基线计算失败，则使用默认的上升高度
    if (font_baseline <= 0) {
        LLOGW("ttf_scaled_baseline failed : %d, use default_ascent", font_baseline);
        font_baseline = (int32_t)hzfont_default_ascent(font_size);
    }
    int pen_x = x;
    const uint64_t yield_threshold_us = HZFONT_YIELD_THRESHOLD_US; // 让出阈值（可通过宏统一调整）
    uint64_t yield_last_ts = timing_enabled ? func_start_ts : hzfont_now_us();

    // 逐字符解析 UTF-8 并按顺序渲染
    while (cursor < end && glyph_count < utf8_len) {
        // 避免长时间循环导致调度器饿死，每隔一段时间让出一次 CPU
        hzfont_maybe_yield(&yield_last_ts, yield_threshold_us);
        // 解码下一个字符
        uint32_t cp = 0;
        if (!utf8_decode_next(&cursor, end, &cp)) {
            break;
        }
        if (cp == '\r' || cp == '\n') {
            continue; // 跳过换行符，不在此函数内换行
        }

        glyph_render_t slot;
        memset(&slot, 0, sizeof(slot));
        slot.advance = hzfont_calc_fallback_advance(font_size);
        slot.codepoint = cp;
        slot.status = HZFONT_GLYPH_LOOKUP_FAIL; // 默认先假设查找失败

        uint64_t glyph_stamp = timing_enabled ? hzfont_now_us() : 0;
        uint16_t glyph_index = 0;
        int rc = TTF_OK;
        // 优先查找 code point 缓存，加快常用字符的查询
        hzfont_cp_cache_entry_t *cp_entry = hzfont_cp_cache_lookup(cp);
        if (cp_entry) { 
            // 命中 code point 缓存，直接使用缓存的 glyph 索引
            glyph_index = cp_entry->glyph_index;
            if (timing_enabled) {
                slot.time_lookup_us = glyph_stamp ? hzfont_elapsed_step(&glyph_stamp) : 0;
                sum_lookup_us += slot.time_lookup_us;
            }
        } else { 
            // 未命中 code point 缓存，则查找 glyph 索引
            rc = ttf_lookup_glyph_index(&g_ft_ctx.font, cp, &glyph_index);
            if (timing_enabled) {
                slot.time_lookup_us = glyph_stamp ? hzfont_elapsed_step(&glyph_stamp) : 0;
                sum_lookup_us += slot.time_lookup_us;
            }
            if (rc != TTF_OK) {
                uint16_t star_index = 0;
                if (ttf_lookup_glyph_index(&g_ft_ctx.font, (uint32_t)'*', &star_index) == TTF_OK) {
                    glyph_index = star_index; // 用替代字符保证不存在的字符渲染不会中断
                } else {
                    glyph_count++;
                    continue;
                }
            } else {
                // 缓存查到的索引，未来直接复用
                hzfont_cp_cache_insert(cp, glyph_index); 
            }
        }

        slot.glyph_index = glyph_index;
        slot.status = HZFONT_GLYPH_LOAD_FAIL; // 加载前保持失效状态

        // 先查 glyph bitmap 缓存，命中时直接复用以节省 raster 开销
        uint8_t supersample = (uint8_t)ttf_get_supersample_rate();
        hzfont_cache_entry_t *cache_entry = hzfont_cache_get(glyph_index, (uint8_t)font_size, supersample);
        if (cache_entry) { 
            // 命中 glyph bitmap 缓存，直接使用缓存的 bitmap
            slot.bitmap = cache_entry->bitmap;
            slot.from_cache = 1;
            slot.status = HZFONT_GLYPH_OK;
        } else { 
            // 未命中 glyph bitmap 缓存，则加载 glyph
            TtfGlyph glyph;
            rc = ttf_load_glyph(&g_ft_ctx.font, glyph_index, &glyph);
            if (timing_enabled) {
                slot.time_load_us = glyph_stamp ? hzfont_elapsed_step(&glyph_stamp) : 0;
                sum_load_us += slot.time_load_us;
            }
            if (rc != TTF_OK) {
                glyph_count++;
                continue;
            }

            // 尝试栅格化 glyph
            slot.status = HZFONT_GLYPH_RASTER_FAIL;
            rc = ttf_rasterize_glyph(&g_ft_ctx.font, &glyph, font_size, &slot.bitmap);
            if (timing_enabled) {
                slot.time_raster_us = glyph_stamp ? hzfont_elapsed_step(&glyph_stamp) : 0;
                sum_raster_us += slot.time_raster_us;
            }
            ttf_free_glyph(&glyph);
            if (rc != TTF_OK) {
                glyph_count++;
                continue;
            }

            // 栅格化成功，尝试缓存，便于下一次直接复用
            slot.status = HZFONT_GLYPH_OK;
            hzfont_cache_entry_t *new_entry = hzfont_cache_insert(glyph_index, (uint8_t)font_size, supersample, &slot.bitmap);
            if (new_entry) {
                slot.from_cache = 1;
                slot.bitmap = new_entry->bitmap;
            }
        }

        // 调整高度
        if (slot.bitmap.width > 0 && slot.bitmap.height > 0 && slot.bitmap.pixels) {
            slot.has_bitmap = 1;
            slot.advance = slot.bitmap.width;
            if (slot.advance == 0) {
                slot.advance = hzfont_calc_fallback_advance(font_size);
            }
        } else {
            slot.bitmap.originY = font_baseline;
        }

        // 调整宽度
        size_t slot_index = glyph_count;
        if (!slot.has_bitmap) { // 没有位图时只调整笔锋位置即可
            if (slot.bitmap.originY == 0) {
                slot.bitmap.originY = font_baseline;
            }
            if (timing_enabled) {
                slot.time_draw_us = 0;
            }
            pen_x += (int)slot.advance;
            goto glyph_timing_update;
        }

        // 检查字体宽度
        uint64_t draw_stamp = timing_enabled ? hzfont_now_us() : 0;
        int draw_x = pen_x;
        int draw_y_base = y - (int)slot.bitmap.originY;
        size_t row_buf_capacity = (size_t)slot.bitmap.width;
        if (row_buf_capacity == 0) {
            if (timing_enabled && draw_stamp) {
                slot.time_draw_us = hzfont_elapsed_from(draw_stamp);
                sum_draw_us += slot.time_draw_us;
            }
            pen_x += (int)slot.advance;
            goto glyph_timing_update;
        }

        // 按行缓存像素数据，避免频繁申请内存
        luat_color_t *row_buf = (luat_color_t *)luat_heap_malloc(row_buf_capacity * sizeof(luat_color_t));
        if (!row_buf) {
            if (timing_enabled && draw_stamp) {
                slot.time_draw_us = hzfont_elapsed_from(draw_stamp);
                sum_draw_us += slot.time_draw_us;
            }
            slot.status = HZFONT_GLYPH_DRAW_FAIL;
            pen_x += (int)slot.advance;
            result = -5;
            LLOGE("luat_heap_malloc row buffer failed");
            goto glyph_timing_update;
        }
        for (uint32_t row = 0; row < slot.bitmap.height; row++) {
            const uint8_t *row_pixels = slot.bitmap.pixels + row * slot.bitmap.width;
            uint32_t col = 0;
            while (col < slot.bitmap.width) {
                while (col < slot.bitmap.width && row_pixels[col] == 0) {
                    col++;
                }
                if (col >= slot.bitmap.width) {
                    break;
                }
                uint32_t run_start = col;
                size_t run_len = 0;
                while (col < slot.bitmap.width && row_pixels[col] != 0) {
                    // 非零 coverage 需要转换为 LCD 支持的颜色格式
                    row_buf[run_len++] = hzfont_coverage_to_color(row_pixels[col], lcd_dft_conf, &fg, &bg);
                    col++;
                }
                if (run_len > 0) {
                    int y_draw = draw_y_base + (int)row;
                    int x_start = draw_x + (int)run_start;
                    int x_end = x_start + (int)run_len - 1;
                    luat_lcd_draw(lcd_dft_conf, (int16_t)x_start, (int16_t)y_draw, (int16_t)x_end, (int16_t)y_draw, row_buf);
                }
            }
        }
        luat_heap_free(row_buf);
        if (timing_enabled && draw_stamp) {
            slot.time_draw_us = hzfont_elapsed_from(draw_stamp);
            sum_draw_us += slot.time_draw_us;
        }
        pen_x += (int)slot.advance;
        rendered_count++;

glyph_timing_update:
        if (timing_enabled) {
            uint64_t glyph_total64 = (uint64_t)slot.time_lookup_us +
                                     (uint64_t)slot.time_load_us +
                                     (uint64_t)slot.time_raster_us +
                                     (uint64_t)slot.time_draw_us;
            sum_total_us += glyph_total64;
            if (slot.has_bitmap && slot.status == HZFONT_GLYPH_OK) {
                sum_rendered_total_us += glyph_total64;
            }
            uint32_t glyph_total32 = hzfont_clamp_u32(glyph_total64);
            if (glyph_total32 > max_glyph_total_us) {
                max_glyph_total_us = glyph_total32;
                max_slot_snapshot = slot;
            }
            // LLOGI("glyph[%u] UTF-32编码=U+%04lX idx=%u status=%s 单个字绘制总耗时=%.3f ms 查找耗时=%.3f ms 加载耗时=%.3f ms 栅格化耗时=%.3f ms 绘制耗时=%.3f ms",
            //     (unsigned)slot_index,
            //     (unsigned long)slot.codepoint,
            //     (unsigned)slot.glyph_index,
            //     hzfont_status_text(slot.status),
            //     (double)glyph_total32 / 1000.0, // 总耗时
            //     (double)slot.time_lookup_us / 1000.0, // 查找耗时
            //     (double)slot.time_load_us / 1000.0, // 加载耗时
            //     (double)slot.time_raster_us / 1000.0, // 栅格化耗时
            //     (double)slot.time_draw_us / 1000.0); // 绘制耗时
            profiled_glyphs++;
        }

        if (slot.bitmap.pixels && !slot.from_cache) {
            ttf_free_bitmap(&slot.bitmap);
        }
        if (result != 0) {
            break;
        }
        glyph_count++;
    }

    // 记录总用时
    if (timing_enabled) {
        uint32_t total_us = hzfont_elapsed_from(func_start_ts);
        uint32_t sum_lookup32 = hzfont_clamp_u32(sum_lookup_us);
        uint32_t sum_load32 = hzfont_clamp_u32(sum_load_us);
        uint32_t sum_raster32 = hzfont_clamp_u32(sum_raster_us);
        uint32_t sum_draw32 = hzfont_clamp_u32(sum_draw_us);
        uint32_t avg_all_us = profiled_glyphs ? hzfont_clamp_u32(sum_total_us / profiled_glyphs) : 0;
        uint32_t avg_rendered_us = rendered_count ? hzfont_clamp_u32(sum_rendered_total_us / rendered_count) : 0;
        LLOGI("字符串绘制总耗时=%.3f ms 绘制的字符数=%u 分析的字符数=%u 渲染的字符数=%u 平均单字符耗时=%.3f ms 平均渲染耗时=%.3f ms 查找总耗时=%.3f ms 加载总耗时=%.3f ms 栅格化总耗时=%.3f ms 绘制总耗时=%.3f ms 其它耗时=%.3f ms",
              (double)total_us / 1000.0, // 总耗时
              (unsigned)glyph_count, // 绘制的字符数
              (unsigned)profiled_glyphs, // 已分析的字符数
              (unsigned)rendered_count, // 已渲染的字符数
              (double)avg_all_us / 1000.0, // 平均单字符耗时
              (double)avg_rendered_us / 1000.0, // 平均渲染耗时
              (double)sum_lookup32 / 1000.0, // 查找耗时
              (double)sum_load32 / 1000.0, // 加载耗时
              (double)sum_raster32 / 1000.0, // 栅格化耗时
              (double)sum_draw32 / 1000.0, // 绘制耗时
              (double)(total_us - sum_lookup32 - sum_load32 - sum_raster32 - sum_draw32) / 1000.0 // 其它耗时
              );
    }

    // 返回结果
    return result;
}

#ifdef LUAT_USE_AIRUI

// 获取底层 TTF 对象供 airui 或其他模块使用
TtfFont * luat_hzfont_get_ttf(void) {
    if (g_ft_ctx.state == LUAT_HZFONT_STATE_READY) {
        return &g_ft_ctx.font;
    }
    return NULL;
}

/**
 * 用于airui，获取指定 glyph 的缓存位图（如不存在则实时渲染）
 * @param glyph_index 目标 glyph 的索引
 * @param font_size   渲染字号
 * @param supersample 超采样等级（1/2/4）
 * @return 指向缓存中的 TtfBitmap，失败返回 NULL
 * @note 本函数内部会先查 Cache 结构，未命中时调 glyph 加载 + rasterize，
 *       渲染完成后将结果插入缓存并返回；若缓存已满或渲染失败则返回 NULL。
 */
// 获取或渲染特定 glyph 的缓存位图
const TtfBitmap * luat_hzfont_get_bitmap(uint16_t glyph_index, uint8_t font_size, uint8_t supersample) {
    if (g_ft_ctx.state != LUAT_HZFONT_STATE_READY) return NULL;
    
    // 先查 cache
    hzfont_cache_entry_t *entry = hzfont_cache_get(glyph_index, font_size, supersample);
    if (entry) {
        return &entry->bitmap;
    }
    
    // 如果未命中，尝试加载并渲染
    TtfGlyph glyph;
    if (ttf_load_glyph(&g_ft_ctx.font, glyph_index, &glyph) != TTF_OK) {
        return NULL;
    }
    
    TtfBitmap bitmap;
    memset(&bitmap, 0, sizeof(TtfBitmap));
    if (ttf_rasterize_glyph(&g_ft_ctx.font, &glyph, font_size, &bitmap) != TTF_OK) {
        ttf_free_glyph(&glyph);
        return NULL;
    }
    ttf_free_glyph(&glyph);
    
    hzfont_cache_entry_t *new_entry = hzfont_cache_insert(glyph_index, font_size, supersample, &bitmap);
    if (new_entry) {
        return &new_entry->bitmap;
    }
    
    // 插入失败（可能缓存已满且无法替换），则需要释放并返回 NULL，或者直接返回临时的？
    // 实际上 hzfont_cache_insert 会处理淘汰
    ttf_free_bitmap(&bitmap);
    return NULL;
}
#endif

