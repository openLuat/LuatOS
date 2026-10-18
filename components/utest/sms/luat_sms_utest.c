/*
 * sms 模块 C 层单元测试 (仅 PC 模拟器, 由 LUAT_USE_UTEST=y 编译)
 *
 * 覆盖 UTF-8 -> UCS2 编码路径 luat_str_utf8_to_ucs2():
 *   - 1 字节(ASCII) / 2 字节(U+0080~U+07FF) / 3 字节(BMP 其余) 序列
 *   - 混合文本, 中文全角点号等实际用例
 *   - 非法/截断输入必须返回失败, 且不得越界读取
 *   - 编码 -> 解码 往返一致(解码侧复用 luat_str_ucs2_to_char)
 *
 * 背景: 历史上 luat_str_utf8_to_ucs2 用 (c & 0xE0) != 0 判断 3 字节序列,
 * 导致所有 2 字节 UTF-8 字符(如 "·" U+00B7)被当成 3 字节序列解码,
 * 发出去的短信码点错误, 接收端看到的就是乱码。
 */
#include "luat_base.h"
#include "luat_str.h"

#include <string.h>

static int expect_ucs2(const char *text, const uint8_t *want, size_t want_len) {
    uint8_t got[128] = {0};
    size_t outlen = 0;
    if (luat_str_utf8_to_ucs2(text, strlen(text), (char *)got, sizeof(got), &outlen) != 0) {
        return -1;
    }
    if (outlen != want_len) {
        return -1;
    }
    return memcmp(got, want, want_len) == 0 ? 0 : -1;
}

/* 编码必须失败(非法输入 / 缓冲区不足) */
static int expect_encode_fail(const char *text, size_t len, size_t dstlen) {
    uint8_t got[32] = {0};
    size_t outlen = 0;
    if (dstlen > sizeof(got)) {
        dstlen = sizeof(got);
    }
    return luat_str_utf8_to_ucs2(text, len, (char *)got, dstlen, &outlen) == 0 ? -1 : 0;
}

/* 编码后再解码, 结果必须与原文完全一致 */
static int expect_roundtrip(const char *text) {
    uint8_t ucs2[128] = {0};
    char hex[260] = {0};
    char back[160] = {0};
    size_t ucs2_len = 0;
    size_t back_len = 0;
    if (luat_str_utf8_to_ucs2(text, strlen(text), (char *)ucs2, sizeof(ucs2), &ucs2_len) != 0) {
        return -1;
    }
    luat_str_tohex((const char *)ucs2, ucs2_len, hex);
    luat_str_ucs2_to_char(hex, ucs2_len * 2, back, &back_len);
    if (back_len != strlen(text)) {
        return -1;
    }
    return memcmp(back, text, back_len) == 0 ? 0 : -1;
}

/* ASCII(1 字节)与 3 字节中文, 这是修复前就正常的基线 */
static int case_ucs2_encode_basic(void) {
    static const uint8_t want_ascii[] = {0x00, 'L', 0x00, 'u', 0x00, '1'};
    static const uint8_t want_cjk[] = {0x4F, 0x60, 0x59, 0x7D};  /* 你好 */
    if (expect_ucs2("Lu1", want_ascii, sizeof(want_ascii))) return -1;
    if (expect_ucs2("你好", want_cjk, sizeof(want_cjk))) return -1;
    return 0;
}

/* 2 字节 UTF-8 序列: 修复前全部编错 */
static int case_ucs2_encode_2byte(void) {
    static const uint8_t want_dot[] = {0x00, 0xB7};              /* ·  U+00B7 */
    static const uint8_t want_eacute[] = {0x00, 0xE9};           /* é  U+00E9 */
    static const uint8_t want_cyrillic[] = {                     /* Привет */
        0x04, 0x1F, 0x04, 0x40, 0x04, 0x38, 0x04, 0x32, 0x04, 0x35, 0x04, 0x42};
    static const uint8_t want_greek[] = {0x03, 0xB1, 0x03, 0xB2, 0x03, 0xB3}; /* αβγ */
    if (expect_ucs2("\xC2\xB7", want_dot, sizeof(want_dot))) return -1;
    if (expect_ucs2("\xC3\xA9", want_eacute, sizeof(want_eacute))) return -1;
    if (expect_ucs2("\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82",
                    want_cyrillic, sizeof(want_cyrillic))) return -1;
    if (expect_ucs2("\xCE\xB1\xCE\xB2\xCE\xB3", want_greek, sizeof(want_greek))) return -1;
    return 0;
}

/* 全角点号: 。U+3002 / ．U+FF0E(3 字节), · U+00B7(2 字节) */
static int case_ucs2_encode_dots(void) {
    static const uint8_t want[] = {
        0x30, 0x02, 0xFF, 0x0E, 0x00, 0xB7};
    return expect_ucs2("\xE3\x80\x82\xEF\xBC\x8E\xC2\xB7", want, sizeof(want));
}

/* 1/2/3 字节混排: 2 字节字符之后的内容不能被错位 */
static int case_ucs2_encode_mixed(void) {
    static const uint8_t want[] = {
        0x00, '1', 0x00, 0xB7, 0x00, '2', 0x30, 0x02, 0x00, '3', 0x4F, 0x60};
    static const uint8_t want_dot_cjk[] = {0x00, 0xB7, 0x4F, 0x60};
    if (expect_ucs2("1\xC2\xB7" "2\xE3\x80\x82" "3\xE4\xBD\xA0", want, sizeof(want))) return -1;
    if (expect_ucs2("\xC2\xB7\xE4\xBD\xA0", want_dot_cjk, sizeof(want_dot_cjk))) return -1;
    return 0;
}

/* 非法/截断输入必须失败, 不能越界读取 */
static int case_ucs2_encode_invalid(void) {
    if (expect_encode_fail("\xC2", 1, 16)) return -1;                  /* 2 字节序列被截断 */
    if (expect_encode_fail("\xE3\x80", 2, 16)) return -1;              /* 3 字节序列被截断 */
    if (expect_encode_fail("\xB7", 1, 16)) return -1;                  /* 孤立续字节 */
    if (expect_encode_fail("\xC2\x41", 2, 16)) return -1;              /* 续字节格式非法 */
    if (expect_encode_fail("\xF0\x9F\x98\x80", 4, 16)) return -1;      /* 4 字节超出 UCS2 */
    if (expect_encode_fail("abc", 3, 5)) return -1;                    /* 输出缓冲区不足 */
    if (expect_encode_fail("abc", 3, 0)) return -1;
    return 0;
}

/* 空串合法, 输出 0 字节 */
static int case_ucs2_encode_empty(void) {
    uint8_t got[4] = {0};
    size_t outlen = 0;
    if (luat_str_utf8_to_ucs2("", 0, (char *)got, sizeof(got), &outlen) != 0) return -1;
    return outlen == 0 ? 0 : -1;
}

/* 编码 -> 解码 往返一致性 */
static int case_ucs2_roundtrip(void) {
    static const char *cases[] = {
        "hello", "\xE4\xBD\xA0\xE5\xA5\xBD",                  /* 你好 */
        "\xE3\x80\x82\xEF\xBC\x8E\xC2\xB7",                  /* 。．· */
        "1\xC2\xB7" "2\xE3\x80\x82" "3",                     /* 混合 */
        "\xD0\x9F\xD1\x80\xD0\xB8\xD0\xB2\xD0\xB5\xD1\x82",  /* Привет */
        "A\xC3\xA9\xCE\xB1",                                 /* Aéα */
    };
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        if (expect_roundtrip(cases[i])) {
            return -1;
        }
    }
    return 0;
}

int luat_sms_utest(lua_State *L, const char *case_name) {
    (void)L;
    if (case_name == NULL) return -1;
    if (strcmp(case_name, "ucs2_encode_basic") == 0)   return case_ucs2_encode_basic();
    if (strcmp(case_name, "ucs2_encode_2byte") == 0)   return case_ucs2_encode_2byte();
    if (strcmp(case_name, "ucs2_encode_dots") == 0)    return case_ucs2_encode_dots();
    if (strcmp(case_name, "ucs2_encode_mixed") == 0)   return case_ucs2_encode_mixed();
    if (strcmp(case_name, "ucs2_encode_invalid") == 0) return case_ucs2_encode_invalid();
    if (strcmp(case_name, "ucs2_encode_empty") == 0)   return case_ucs2_encode_empty();
    if (strcmp(case_name, "ucs2_roundtrip") == 0)      return case_ucs2_roundtrip();
    return -1;
}
