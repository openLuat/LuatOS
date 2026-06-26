/*
@module  miniz
@summary miniz库 C层utest —— 直接测试 miniz 低层 C API (tdefl/tinfl)
编译条件: LUAT_USE_UTEST=y (仅 PC 模拟器)
注意: 项目中定义了 MINIZ_NO_MALLOC, 所以 MZ_MALLOC(x) 展开为 NULL,
      高层便捷函数 (tdefl_compress_mem_to_mem 等) 内部依赖 MZ_MALLOC 会失败,
      因此本文件直接使用低层 API: tdefl_init/tdefl_compress_buffer / tinfl_init/tinfl_decompress,
      与 luat_lib_miniz.c 的 Lua binding 做法一致。
*/
#include "luat_base.h"
#include <string.h>
#include <stdlib.h>

#include "miniz.h"

/* miniz.h 的 flag 定义在多个匿名 enum 中, MSVC 对跨 enum OR 运算报 C5287, 忽略之 */
#if defined(_MSC_VER) && !defined(__clang__)
#pragma warning(disable: 5287)
#endif

/* =============== 自定义输出收集器(compress 用) =============== */
typedef struct {
    unsigned char *buf;    /* 输出缓冲区 */
    size_t  size;          /* 已写入字节数 */
    size_t  capacity;      /* 总容量 */
} putter_ctx_t;

static mz_bool my_putter(const void *pBuf, int len, void *pUser) {
    putter_ctx_t *ctx = (putter_ctx_t *)pUser;
    if (ctx->size + (size_t)len > ctx->capacity)
        return MZ_FALSE;
    memcpy(ctx->buf + ctx->size, pBuf, (size_t)len);
    ctx->size += (size_t)len;
    return MZ_TRUE;
}

/* =============== 压缩(返回实际长度, 0=失败) =============== */
static size_t do_compress(unsigned char *out, size_t out_cap,
                          const unsigned char *src, size_t src_len,
                          int flags) {
    tdefl_compressor *comp = (tdefl_compressor *)malloc(sizeof(tdefl_compressor));
    if (!comp) return 0;

    putter_ctx_t ctx;
    ctx.buf      = out;
    ctx.capacity = out_cap;
    ctx.size     = 0;

    mz_bool ok;
    ok  = (tdefl_init(comp, my_putter, &ctx, flags) == TDEFL_STATUS_OKAY);
    ok  = ok && (tdefl_compress_buffer(comp, src, src_len, TDEFL_FINISH) == TDEFL_STATUS_DONE);
    size_t written = ok ? ctx.size : 0;

    free(comp);
    return written;
}

/* =============== 解压(返回实际长度, -1=失败) =============== */
static size_t do_decompress(unsigned char *out, size_t out_cap,
                            const unsigned char *src, size_t src_len,
                            int flags) {
    tinfl_decompressor *decomp = (tinfl_decompressor *)malloc(sizeof(tinfl_decompressor));
    if (!decomp) return (size_t)-1;

    tinfl_init(decomp);
    size_t in_avail = src_len;
    size_t out_avail = out_cap;
    tinfl_status st = tinfl_decompress(decomp, src, &in_avail,
                                        out, out, &out_avail,
                                        (flags & ~TINFL_FLAG_HAS_MORE_INPUT)
                                        | TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF);
    size_t ret = (st != TINFL_STATUS_DONE) ? (size_t)-1 : out_avail;
    free(decomp);
    return ret;
}

/* =============== 往返测试 helper =============== */
#define COMPRESS_BOUND(n) ((size_t)((n) + ((n) >> 12) + ((n) >> 14) + 13))

static int roundtrip_check(const unsigned char *src, size_t src_len,
                           int comp_flags, int decomp_flags) {
    /* ---- compress ---- */
    size_t bound = COMPRESS_BOUND(src_len);
    unsigned char *comp_buf = (unsigned char *)malloc(bound);
    if (!comp_buf) return -1;

    size_t comp_len = do_compress(comp_buf, bound, src, src_len, comp_flags);
    if (comp_len == 0) { free(comp_buf); return -1; }

    /* ---- decompress ---- */
    unsigned char *decomp_buf = (unsigned char *)malloc(src_len + 1024);
    if (!decomp_buf) { free(comp_buf); return -1; }

    size_t decomp_len = do_decompress(decomp_buf, src_len + 1024,
                                       comp_buf, comp_len, decomp_flags);
    int ok = 0;
    if (decomp_len == (size_t)-1 || decomp_len != src_len)
        ok = -1;                          /* 长度不匹配 */
    else if (memcmp(decomp_buf, src, src_len) != 0)
        ok = -1;                          /* 数据不一致 */

    free(comp_buf);
    free(decomp_buf);
    return ok;
}

#define ROUNDTRIP(str, cf, df) \
    roundtrip_check((const unsigned char *)(str), strlen(str), cf, df)

#define ROUNDTRIP_BIN(buf, len, cf, df) \
    roundtrip_check((const unsigned char *)(buf), len, cf, df)

/* ================================================================
 * 测试用例
 * ================================================================ */

/* 1. 基础往返: zlib header */
static int case_compress_decompress_basic(void) {
    return ROUNDTRIP("Hello, miniz! This is a basic roundtrip test.",
                     TDEFL_WRITE_ZLIB_HEADER,
                     TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* 2. 空字符串 */
static int case_compress_decompress_empty(void) {
    return ROUNDTRIP("",
                     TDEFL_WRITE_ZLIB_HEADER,
                     TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* 3. 单字节 */
static int case_compress_decompress_single_byte(void) {
    return ROUNDTRIP("A",
                     TDEFL_WRITE_ZLIB_HEADER,
                     TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* 4. 含 \0 的二进制数据 */
static int case_compress_decompress_binary(void) {
    const unsigned char buf[] = {
        'A', 0x00, 0xFF, 0xAB, 0x00, 0x00, 0x12, 'Z',
        'H', 'e', 'l', 'l', 'o', 0x00, 'W', 'o', 'r', 'l', 'd'
    };
    return ROUNDTRIP_BIN(buf, sizeof(buf),
                         TDEFL_WRITE_ZLIB_HEADER,
                         TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* 5. 重复数据 + 压缩率验证 */
static int case_compress_decompress_repeated(void) {
    char buf[500];
    for (size_t i = 0; i < sizeof(buf); i++)
        buf[i] = (char)("ABCDEFGHIJKLMNOPQRSTUVWXYZ"[i % 26]);

    size_t bound = COMPRESS_BOUND(sizeof(buf));
    unsigned char *comp = (unsigned char *)malloc(bound);
    if (!comp) return -1;

    /* 加 TDEFL_DEFAULT_MAX_PROBES 让 LZ77 匹配生效, 否则默认 0 探头 = Huffman-only */
    /* 用 int 变量中转避免 MSVC C5287 匿名 enum 混合警告 */
    int cf = (int)TDEFL_WRITE_ZLIB_HEADER | (int)TDEFL_DEFAULT_MAX_PROBES;
    size_t clen = do_compress(comp, bound, (const unsigned char *)buf, sizeof(buf), cf);
    if (clen == 0) { free(comp); return -1; }
    /* 重复模式应压缩到 < 50% */
    if (clen >= sizeof(buf) / 2) { free(comp); return -1; }

    unsigned char *decomp = (unsigned char *)malloc(sizeof(buf) + 1024);
    if (!decomp) { free(comp); return -1; }
    size_t dlen = do_decompress(decomp, sizeof(buf) + 1024, comp, clen,
                                TINFL_FLAG_PARSE_ZLIB_HEADER);
    int ok = 0;
    if (dlen == (size_t)-1 || dlen != sizeof(buf)) ok = -1;
    else if (memcmp(decomp, buf, sizeof(buf)) != 0) ok = -1;

    free(comp); free(decomp);
    return ok;
}

/* 6. raw deflate (无 header) */
static int case_compress_decompress_raw(void) {
    return ROUNDTRIP("Raw deflate test data without zlib header.",
                     0, 0);
}

/* 7. COMPUTE_ADLER32 + 带 header 校验 */
static int case_compress_adler32(void) {
    int cf = TDEFL_WRITE_ZLIB_HEADER | TDEFL_COMPUTE_ADLER32;
    int df = TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_COMPUTE_ADLER32;
    return ROUNDTRIP("Testing adler32 during compress/decompress.",
                     cf, df);
}

/* 8. FORCE_ALL_RAW_BLOCKS (不做真正的压缩) */
static int case_compress_raw_blocks(void) {
    return ROUNDTRIP("Force all raw blocks.",
                     TDEFL_FORCE_ALL_RAW_BLOCKS, 0);
}

/* 9. FORCE_ALL_STATIC_BLOCKS */
static int case_compress_static_blocks(void) {
    return ROUNDTRIP("Force all static huffman blocks.",
                     TDEFL_WRITE_ZLIB_HEADER | TDEFL_FORCE_ALL_STATIC_BLOCKS,
                     TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* 10. GREEDY_PARSING_FLAG */
static int case_compress_greedy(void) {
    return ROUNDTRIP("Greedy parsing test data with enough repetition for greedy parser.",
                     TDEFL_WRITE_ZLIB_HEADER | TDEFL_GREEDY_PARSING_FLAG,
                     TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* 11. NONDETERMINISTIC_PARSING_FLAG */
static int case_compress_nondeterministic(void) {
    return ROUNDTRIP("Non-deterministic parsing test.",
                     TDEFL_WRITE_ZLIB_HEADER | TDEFL_NONDETERMINISTIC_PARSING_FLAG,
                     TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* 12. RLE_MATCHES */
static int case_compress_rle(void) {
    return ROUNDTRIP("AAAAABBBBBCCCCCDDDDDEEEEEAAAAABBBBBCCCCCDDDDDEEEEE",
                     TDEFL_WRITE_ZLIB_HEADER | TDEFL_RLE_MATCHES,
                     TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* 13. FILTER_MATCHES */
static int case_compress_filter_matches(void) {
    return ROUNDTRIP("Filter matches test data for filter matches flag.",
                     TDEFL_WRITE_ZLIB_HEADER | TDEFL_FILTER_MATCHES,
                     TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* 14. 组合多个 flag */
static int case_compress_combined_flags(void) {
    int cf = TDEFL_WRITE_ZLIB_HEADER | TDEFL_COMPUTE_ADLER32 | TDEFL_GREEDY_PARSING_FLAG;
    int df = TINFL_FLAG_PARSE_ZLIB_HEADER | TINFL_FLAG_COMPUTE_ADLER32;
    return ROUNDTRIP("Combined flags test.", cf, df);
}

/* 15. 非法数据 → 解压必须失败 */
static int case_decompress_invalid_data(void) {
    const unsigned char garbage[] = "This is not valid compressed data at all!!!!";
    unsigned char out[256];
    size_t out_len = do_decompress(out, sizeof(out),
                                   garbage, sizeof(garbage),
                                   TINFL_FLAG_PARSE_ZLIB_HEADER);
    return (out_len == (size_t)-1) ? 0 : -1;
}

/* 16. 边界: 1 字节 */
static int case_compress_1byte(void) {
    return ROUNDTRIP("X",
                     TDEFL_WRITE_ZLIB_HEADER,
                     TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* 17. 边界: 2 字节 */
static int case_compress_2bytes(void) {
    return ROUNDTRIP("AB",
                     TDEFL_WRITE_ZLIB_HEADER,
                     TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* 18. ~8 KB */
static int case_compress_8k(void) {
    size_t len = 8192;
    unsigned char *buf = (unsigned char *)malloc(len);
    if (!buf) return -1;
    for (size_t i = 0; i < len; i++) buf[i] = (unsigned char)(i & 0xFF);
    int ok = ROUNDTRIP_BIN(buf, len,
                           TDEFL_WRITE_ZLIB_HEADER,
                           TINFL_FLAG_PARSE_ZLIB_HEADER);
    free(buf);
    return ok;
}

/* 19. ~32 KB (Lua binding 的上限) */
static int case_compress_32k(void) {
    size_t len = 32768;
    unsigned char *buf = (unsigned char *)malloc(len);
    if (!buf) return -1;
    for (size_t i = 0; i < len; i++) buf[i] = (unsigned char)(i * 3 + 7);
    int ok = ROUNDTRIP_BIN(buf, len,
                           TDEFL_WRITE_ZLIB_HEADER,
                           TINFL_FLAG_PARSE_ZLIB_HEADER);
    free(buf);
    return ok;
}

/* 20. 纯重复 + GREEDY + 压缩率 < 10% */
static int case_compress_ratio_greedy(void) {
    char buf[1000];
    memset(buf, 'A', sizeof(buf));

    size_t bound = COMPRESS_BOUND(sizeof(buf));
    unsigned char *comp = (unsigned char *)malloc(bound);
    if (!comp) return -1;

    /* GREEDY + DEFAULT_PROBES 使 LZ77 能匹配重复内容 */
    int cf = (int)TDEFL_GREEDY_PARSING_FLAG | (int)TDEFL_DEFAULT_MAX_PROBES;
    size_t clen = do_compress(comp, bound, (const unsigned char *)buf, sizeof(buf), cf);
    if (clen == 0) { free(comp); return -1; }
    if (clen >= sizeof(buf) / 10) { free(comp); return -1; }

    unsigned char *decomp = (unsigned char *)malloc(sizeof(buf) + 1024);
    if (!decomp) { free(comp); return -1; }
    size_t dlen = do_decompress(decomp, sizeof(buf) + 1024, comp, clen, 0);
    int ok = 0;
    if (dlen == (size_t)-1 || dlen != sizeof(buf)) ok = -1;
    else if (memcmp(decomp, buf, sizeof(buf)) != 0) ok = -1;

    free(comp); free(decomp);
    return ok;
}

/* 21. 极小输入 + raw 模式 */
static int case_compress_tiny_raw(void) {
    return ROUNDTRIP("ab", 0, 0);
}

/* 22. 长英文文本 */
static int case_compress_lorem(void) {
    const char *text =
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod "
        "tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, "
        "quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.";
    return ROUNDTRIP(text,
                     TDEFL_WRITE_ZLIB_HEADER,
                     TINFL_FLAG_PARSE_ZLIB_HEADER);
}

/* ================================================================
 * 测试分发表
 * ================================================================ */
typedef struct {
    const char *name;
    int (*func)(void);
} utest_case_t;

static const utest_case_t case_list[] = {
    {"compress_decompress_basic",       case_compress_decompress_basic},
    {"compress_decompress_empty",       case_compress_decompress_empty},
    {"compress_decompress_single_byte", case_compress_decompress_single_byte},
    {"compress_decompress_binary",      case_compress_decompress_binary},
    {"compress_decompress_repeated",    case_compress_decompress_repeated},
    {"compress_decompress_raw",         case_compress_decompress_raw},
    {"compress_adler32",                case_compress_adler32},
    {"compress_raw_blocks",             case_compress_raw_blocks},
    {"compress_static_blocks",          case_compress_static_blocks},
    {"compress_greedy",                 case_compress_greedy},
    {"compress_nondeterministic",       case_compress_nondeterministic},
    {"compress_rle",                    case_compress_rle},
    {"compress_filter_matches",         case_compress_filter_matches},
    {"compress_combined_flags",         case_compress_combined_flags},
    {"decompress_invalid_data",         case_decompress_invalid_data},
    {"compress_1byte",                  case_compress_1byte},
    {"compress_2bytes",                 case_compress_2bytes},
    {"compress_8k",                     case_compress_8k},
    {"compress_32k",                    case_compress_32k},
    {"compress_ratio_greedy",           case_compress_ratio_greedy},
    {"compress_tiny_raw",               case_compress_tiny_raw},
    {"compress_lorem",                  case_compress_lorem},
    {NULL, NULL}
};

/* ================================================================
 * Lua 入口 — 同步, 返回布尔
 * ================================================================ */
int luat_miniz_utest(lua_State *L, const char *case_name) {
    if (case_name) {
        for (const utest_case_t *c = case_list; c->name; c++) {
            if (strcmp(case_name, c->name) == 0)
                return c->func();
        }
    }

    /* 未指定 / "all" → 跑第一个(基础) */
    if (!case_name || strcmp(case_name, "all") == 0)
        return case_compress_decompress_basic();

    return -1;  /* 未知用例 */
}
