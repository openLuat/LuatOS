/*
 * mem_str_demo — exercise the freestanding libc subset in luat_ndk_helper.h.
 *
 * Covers two things:
 *  1. The ndk_memcpy/memmove/memset/memcmp + ndk_str* static inline helpers.
 *  2. NDK_GUEST_PROVIDE_LIBC: the plain struct assignment below forces the
 *     compiler to emit an external memcpy call even with -ffreestanding
 *     -nostdlib; without the macro this file would fail to link with
 *     "undefined reference to `memcpy'".
 *
 * Verdict is written to the exchange buffer: "MEMSTR_OK" on success,
 * "MEMSTR_Fxx" (xx = first failing check number) otherwise.
 */
#define NDK_GUEST_PROVIDE_LIBC
#include "luat_ndk_helper.h"

typedef struct {
    uint32_t words[12]; /* 48 bytes — big enough that the compiler lowers
                         * the assignment to a memcpy libcall */
} big_t;

static int fail(int n) {
    char buf[12] = "MEMSTR_F00";
    buf[8] = (char)('0' + (n / 10));
    buf[9] = (char)('0' + (n % 10));
    ndk_exchange_write_bytes(0, (const uint8_t *)buf, 10);
    ndk_exit_ok();
    return 0;
}

static int main(void) {
    static char buf[64];
    static const char src[] = "hello ndk world"; /* strlen == 15 */

    /* 1: struct assignment -> external memcpy (link-level proof) */
    big_t a, b;
    for (int i = 0; i < 12; i++) a.words[i] = 0xA5A50000u + (uint32_t)i;
    b = a;
    if (ndk_memcmp(&a, &b, sizeof(a)) != 0) return fail(1);

    /* 2: ndk_memset + ndk_memcpy */
    ndk_memset(buf, 0, sizeof(buf));
    ndk_memcpy(buf, src, sizeof(src));
    if (ndk_strcmp(buf, src) != 0) return fail(2);

    /* 3/4: ndk_memmove overlapping in both directions */
    ndk_memmove(buf + 2, buf, 15);
    if (ndk_strcmp(buf + 2, src) != 0) return fail(3);
    ndk_memmove(buf, buf + 2, 16);
    if (ndk_strcmp(buf, src) != 0) return fail(4);

    /* 5..10: strlen / strncmp / strchr */
    if (ndk_strlen(buf) != 15u) return fail(5);
    if (ndk_strncmp(buf, "hello XXX", 5) != 0) return fail(6);
    if (ndk_strncmp(buf, "hellp", 5) >= 0) return fail(7);
    if (ndk_strchr(buf, 'n') != buf + 6) return fail(8);
    if (ndk_strchr(buf, 'z') != NULL) return fail(9);
    if (*ndk_strchr(buf, '\0') != '\0') return fail(10);

    /* 11: strcpy + strcat */
    ndk_strcpy(buf, "abc");
    ndk_strcat(buf, "def");
    if (ndk_strcmp(buf, "abcdef") != 0) return fail(11);

    /* 12: strncpy with n > strlen(src) pads with NUL */
    ndk_memset(buf, 'X', sizeof(buf));
    ndk_strncpy(buf, "ab", 5);
    if (buf[0] != 'a' || buf[1] != 'b' || buf[2] != '\0' || buf[4] != '\0') return fail(12);

    /* 13: strncpy with n < strlen(src) does NOT append NUL */
    ndk_memset(buf, 0, sizeof(buf));
    ndk_strncpy(buf, "abcdefgh", 4);
    if (ndk_strncmp(buf, "abcd", 4) != 0 || buf[4] != '\0') return fail(13);

    /* 14/15: memset return value + contents */
    if (ndk_memset(buf, 0x5A, 8) != buf) return fail(14);
    if (buf[0] != 0x5A || buf[7] != 0x5A || buf[8] != 0) return fail(15);

    /* 16: memcpy return value */
    if (ndk_memcpy(buf, src, 4) != buf) return fail(16);

    ndk_exchange_write_bytes(0, (const uint8_t *)"MEMSTR_OK", 9);
    ndk_exit_ok();
    return 0;
}

NDK_GUEST_START(main)
