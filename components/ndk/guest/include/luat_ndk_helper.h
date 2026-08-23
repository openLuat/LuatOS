/*
 * luat_ndk_helper.h — NDK guest "standard library" (header-only)
 *
 * Include this in any NDK guest program. It depends on the host exposing the
 * NDK CSR/MMIO ABI defined in luat_ndk_abi.h. Link with the same link.ld and
 * the example build script; no extra sources are needed.
 *
 * This header is intentionally header-only: every wrapper is a static inline
 * that expands to 1-3 inline-asm instructions, so a separate translation unit
 * would add no value. Examples pick it up via the -I flag the build script
 * already uses for luat_ndk_builtin.h / luat_ndk_abi.h.
 *
 * Groups provided:
 *   - Constants and addresses (NDK_RAM_BASE, NDK_SYSCON_ADDR, NDK_DONE_MARKER)
 *   - Startup boilerplate (NDK_GUEST_START macro, ndk_exit, ndk_wfi_loop)
 *   - Typed exchange-buffer access (ndk_exchange_ptr, ndk_exchange_*_u32)
 *   - Little-endian byte-order helpers (ndk_load32_le, ndk_store32_le)
 *   - Log helpers (ndk_log_str/int/hex/ptr)
 *   - GPIO v2 request/response pack macros (NDK_GPIO_*_PACK)
 *   - Status code decoders (ndk_gpio_status_name, ndk_crypto_status_name, ...)
 *   - Host hash calls (ndk_hash_md5, ndk_hash_crc32)
 *   - Event ring consumer (ndk_event_peek)
 *   - Memory/string helpers (ndk_memcpy/memmove/memset/memcmp, ndk_strlen/...)
 *   - Optional freestanding libc symbols (memcpy/memmove/memset/memcmp) via
 *     NDK_GUEST_PROVIDE_LIBC — see the memory/string section below
 *
 * Intentionally NOT provided:
 *   - printf-style varargs formatting
 *   - RV32F floating-point helpers (removed — NDK only supports RV32IMA)
 *   - UART RX user-space buffers (use the existing ndk_uart_* CSRs)
 */
#pragma once

#include "luat_ndk_builtin.h"
#include "luat_ndk_abi.h"

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/* ------------------------------------------------------------------ */
/* Constants and addresses                                            */
/* ------------------------------------------------------------------ */

#ifndef NDK_RAM_BASE
#define NDK_RAM_BASE        0x80000000u
#endif

#ifndef NDK_SYSCON_ADDR
#define NDK_SYSCON_ADDR     0x11100000u
#endif

#ifndef NDK_DONE_MARKER
#define NDK_DONE_MARKER     0x5555u
#endif

/* ------------------------------------------------------------------ */
/* Startup boilerplate (replaces the per-example _start + wfi loop)   */
/* ------------------------------------------------------------------ */

static inline void ndk_exit(uint32_t code) {
    *(volatile uint32_t *)NDK_SYSCON_ADDR = code;
}

static inline void ndk_exit_ok(void) {
    ndk_exit(NDK_DONE_MARKER);
}

static inline uintptr_t ndk_stack_top(void) {
    /* The 16-byte red zone mirrors what the bare examples used; the host
     * returns the configured RAM size from CSR 0x13B. */
    return (uintptr_t)(NDK_RAM_BASE + ndk_memory_size() - 16u);
}

static inline void ndk_wfi_loop(void) {
    for (;;) {
        __asm__ volatile("wfi");
    }
}

/* Define the guest entry point. Use as the LAST line of a guest C file:
 *     static int main(void) { ... ; ndk_exit_ok(); return 0; }
 *     NDK_GUEST_START(main)
 * The function must have signature `int (void)`. main()'s return value is
 * ignored. After main() returns, the guest parks in wfi until the host
 * either reloads the image (ndk.reset) or deinits the context.
 *
 * main() may freely call non-inline helpers — the macro sets ra to the
 * wfi park loop so main's natural `ret` (or any return from a callee that
 * unwinds back to main) lands safely. Guests that just want a SYSCON exit
 * should still call ndk_exit_ok(); guests that return naturally should
 * configure ndk.exec with a finite step budget (steps > 0) so the host
 * can detect completion instead of spinning in the wfi loop.
 *
 * NOTE: `naked` is required so the compiler does not emit a function
 * prologue (sub sp / sw ra). At _start the host's sp is uninitialised
 * (often 0 or 0xFFFFFFFx), so any store to sp+offset would trap with
 * mcause=7 store access fault. We must set sp ourselves before the
 * first store.
 *
 * The wfi loop is inlined in asm rather than calling `ndk_wfi_loop` because
 * the latter is `static inline` and would not emit a definition when not
 * called directly from user code. */
#define NDK_GUEST_START(fn)                                          \
    __attribute__((naked, noreturn)) void _start(void) {             \
        __asm__ volatile(                                            \
            "mv sp, %0\n"                                            \
            "mv t0, %1\n"                                            \
            "jalr ra, t0\n"        /* write ra = PC+4 so main()'s   */\
                                   /* ret lands in the wfi park loop */\
            "1: wfi\n"                                               \
            "j 1b\n"                                                  \
            :: "r"(ndk_stack_top()), "r"(fn)                         \
        );                                                           \
    }

/* ------------------------------------------------------------------ */
/* Typed exchange-buffer access                                       */
/* ------------------------------------------------------------------ */

static inline volatile uint8_t *ndk_exchange_ptr(void) {
    return (volatile uint8_t *)ndk_exchange_base();
}

static inline volatile uint32_t *ndk_exchange_u32(uint32_t offset) {
    return (volatile uint32_t *)(ndk_exchange_ptr() + offset);
}

static inline uint32_t ndk_exchange_read_u32(uint32_t offset) {
    return *ndk_exchange_u32(offset);
}

static inline void ndk_exchange_write_u32(uint32_t offset, uint32_t value) {
    *ndk_exchange_u32(offset) = value;
}

/* Byte-by-byte copy. Use this for ASCII strings: a naive uint32_t store
 * would lay the bytes out in little-endian order ("HELLO" would become
 * "OLLE"). */
static inline void ndk_exchange_write_bytes(uint32_t offset,
                                             const uint8_t *src,
                                             size_t n) {
    volatile uint8_t *dst = ndk_exchange_ptr() + offset;
    for (size_t i = 0; i < n; i++) {
        dst[i] = src[i];
    }
}

/* ------------------------------------------------------------------ */
/* Little-endian byte-order helpers                                   */
/* ------------------------------------------------------------------ */

static inline uint32_t ndk_load32_le(const uint8_t *p) {
    return  ((uint32_t)p[0])        |
           (((uint32_t)p[1]) <<  8) |
           (((uint32_t)p[2]) << 16) |
           (((uint32_t)p[3]) << 24);
}

static inline void ndk_store32_le(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)( v        & 0xFFu);
    p[1] = (uint8_t)((v >>  8) & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu);
    p[3] = (uint8_t)((v >> 24) & 0xFFu);
}

/* ------------------------------------------------------------------ */
/* Memory and string helpers (freestanding libc subset)               */
/* ------------------------------------------------------------------ */

/* Plain-C, header-only memory/string routines. Two ways to use them:
 *
 * 1. Call the ndk_* names directly — they are static inline and cost
 *    nothing when unused.
 *
 * 2. Define NDK_GUEST_PROVIDE_LIBC in EXACTLY ONE translation unit
 *    before including this header. That emits external-linkage
 *    definitions of memcpy/memmove/memset/memcmp. Do this when the
 *    guest uses struct assignment or large aggregate initializers:
 *    even with -ffreestanding -nostdlib the compiler is allowed (per
 *    the C standard and GCC/Clang docs) to emit calls to those four
 *    symbols for aggregate copies, and without a definition the link
 *    fails with "undefined reference to `memcpy'". The byte loops
 *    below are safe from being rewritten into self-recursive libcalls
 *    because freestanding builds disable loop-idiom libcall formation.
 */

static inline void *ndk_memcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    for (size_t i = 0; i < n; i++) {
        d[i] = s[i];
    }
    return dst;
}

static inline void *ndk_memmove(void *dst, const void *src, size_t n) {
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    if (d == s || n == 0) {
        return dst;
    }
    if ((uintptr_t)d < (uintptr_t)s) {
        for (size_t i = 0; i < n; i++) {
            d[i] = s[i];
        }
    } else {
        for (size_t i = n; i > 0; i--) {
            d[i - 1] = s[i - 1];
        }
    }
    return dst;
}

static inline void *ndk_memset(void *dst, int c, size_t n) {
    uint8_t *d = (uint8_t *)dst;
    for (size_t i = 0; i < n; i++) {
        d[i] = (uint8_t)c;
    }
    return dst;
}

static inline int ndk_memcmp(const void *a, const void *b, size_t n) {
    const uint8_t *pa = (const uint8_t *)a;
    const uint8_t *pb = (const uint8_t *)b;
    for (size_t i = 0; i < n; i++) {
        if (pa[i] != pb[i]) {
            return (int)pa[i] - (int)pb[i];
        }
    }
    return 0;
}

static inline size_t ndk_strlen(const char *s) {
    const char *p = s;
    while (*p) {
        p++;
    }
    return (size_t)(p - s);
}

static inline int ndk_strcmp(const char *a, const char *b) {
    while (*a && (*a == *b)) {
        a++;
        b++;
    }
    return (int)(uint8_t)*a - (int)(uint8_t)*b;
}

static inline int ndk_strncmp(const char *a, const char *b, size_t n) {
    for (size_t i = 0; i < n; i++) {
        uint8_t ca = (uint8_t)a[i];
        uint8_t cb = (uint8_t)b[i];
        if (ca != cb || ca == 0) {
            return (int)ca - (int)cb;
        }
    }
    return 0;
}

static inline char *ndk_strcpy(char *dst, const char *src) {
    char *d = dst;
    while ((*d++ = *src++) != '\0') {
    }
    return dst;
}

static inline char *ndk_strncpy(char *dst, const char *src, size_t n) {
    size_t i = 0;
    for (; i < n && src[i] != '\0'; i++) {
        dst[i] = src[i];
    }
    for (; i < n; i++) {
        dst[i] = '\0';
    }
    return dst;
}

static inline char *ndk_strcat(char *dst, const char *src) {
    ndk_strcpy(dst + ndk_strlen(dst), src);
    return dst;
}

static inline char *ndk_strchr(const char *s, int c) {
    for (;; s++) {
        if (*s == (char)c) {
            return (char *)s;
        }
        if (*s == '\0') {
            return NULL;
        }
    }
}

#ifdef NDK_GUEST_PROVIDE_LIBC
/* External-linkage freestanding libc symbols. See the section header
 * above for why these exist and why they must live in exactly one TU. */
void *memcpy(void *dst, const void *src, size_t n) {
    return ndk_memcpy(dst, src, n);
}

void *memmove(void *dst, const void *src, size_t n) {
    return ndk_memmove(dst, src, n);
}

void *memset(void *dst, int c, size_t n) {
    return ndk_memset(dst, c, n);
}

int memcmp(const void *a, const void *b, size_t n) {
    return ndk_memcmp(a, b, n);
}
#endif /* NDK_GUEST_PROVIDE_LIBC */

/* ------------------------------------------------------------------ */
/* Log helpers (CSR 0x136/0x137/0x138)                               */
/* ------------------------------------------------------------------ */

/* ndk_lprint / ndk_nprint / ndk_pprint are already provided by
 * luat_ndk_builtin.h; here we re-export them under friendlier names. */

static inline void ndk_log_str (const char *s)  { ndk_lprint(s); }
static inline void ndk_log_ptr (uint32_t ptr)  { ndk_pprint(ptr); }
static inline void ndk_log_int (uint32_t v)    { ndk_nprint(v);  }

/* ndk_pprint formats as hex ("vm ptr: 0x%08X"); re-purpose as log_hex. */
static inline void ndk_log_hex (uint32_t v)    { ndk_pprint(v);  }

/* ------------------------------------------------------------------ */
/* GPIO v2 request/response pack macros                              */
/* ------------------------------------------------------------------ */

#define NDK_GPIO_CONFIG_PACK(pin, mode, pull, irq_mode) \
    (( ((irq_mode) & 0xFFu) << 24) | \
     ( ((pull)     & 0xFFu) << 16) | \
     ( ((mode)     & 0xFFu) <<  8) | \
     ( ((pin)      & 0xFFu)       ))

#define NDK_GPIO_WRITE_PACK(pin, level) \
    (( ((level) & 0x1u) << 16) | ((pin) & 0xFFFFu))

/* IRQ state pack/unpack are already in luat_ndk_abi.h; alias for
 * discoverability: */
#define NDK_GPIO_IRQ_STATE_PIN_OF(v)     LUAT_NDK_GPIO_IRQ_STATE_PIN(v)
#define NDK_GPIO_IRQ_STATE_PENDING_OF(v) LUAT_NDK_GPIO_IRQ_STATE_PENDING(v)
#define NDK_GPIO_IRQ_STATE_REASON_OF(v)  LUAT_NDK_GPIO_IRQ_STATE_REASON(v)

/* ------------------------------------------------------------------ */
/* Status code decoders                                               */
/* ------------------------------------------------------------------ */

static inline const char *ndk_gpio_status_name(uint32_t s) {
    switch (s) {
        case LUAT_NDK_GPIO_STATUS_OK:            return "GPIO_OK";
        case LUAT_NDK_GPIO_STATUS_BAD_PIN:       return "GPIO_BAD_PIN";
        case LUAT_NDK_GPIO_STATUS_BAD_MODE:      return "GPIO_BAD_MODE";
        case LUAT_NDK_GPIO_STATUS_BAD_PULL:      return "GPIO_BAD_PULL";
        case LUAT_NDK_GPIO_STATUS_BAD_IRQ_MODE:  return "GPIO_BAD_IRQ_MODE";
        case LUAT_NDK_GPIO_STATUS_UNSUPPORTED:   return "GPIO_UNSUPPORTED";
        case LUAT_NDK_GPIO_STATUS_HOST_ERROR:    return "GPIO_HOST_ERROR";
        default:                                 return "GPIO_?";
    }
}

static inline const char *ndk_uart_status_name(uint32_t s) {
    switch (s) {
        case LUAT_NDK_UART_STATUS_OK:           return "UART_OK";
        case LUAT_NDK_UART_STATUS_BAD_PORT:     return "UART_BAD_PORT";
        case LUAT_NDK_UART_STATUS_BAD_CONFIG:   return "UART_BAD_CONFIG";
        case LUAT_NDK_UART_STATUS_BAD_LENGTH:   return "UART_BAD_LENGTH";
        case LUAT_NDK_UART_STATUS_BUSY:         return "UART_BUSY";
        case LUAT_NDK_UART_STATUS_OVERFLOW:     return "UART_OVERFLOW";
        case LUAT_NDK_UART_STATUS_UNSUPPORTED:  return "UART_UNSUPPORTED";
        case LUAT_NDK_UART_STATUS_HOST_ERROR:   return "UART_HOST_ERROR";
        default:                                return "UART_?";
    }
}

static inline const char *ndk_crypto_status_name(uint32_t s) {
    switch (s) {
        case LUAT_NDK_CRYPTO_STATUS_OK:          return "CRYPTO_OK";
        case LUAT_NDK_CRYPTO_STATUS_BAD_ARG:     return "CRYPTO_BAD_ARG";
        case LUAT_NDK_CRYPTO_STATUS_BAD_BOUNDS:  return "CRYPTO_BAD_BOUNDS";
        case LUAT_NDK_CRYPTO_STATUS_UNSUPPORTED: return "CRYPTO_UNSUPPORTED";
        case LUAT_NDK_CRYPTO_STATUS_HOST_ERROR:  return "CRYPTO_HOST_ERROR";
        default:                                 return "CRYPTO_?";
    }
}

static inline const char *ndk_host_error_name(uint32_t s) {
    switch (s) {
        case LUAT_NDK_HOST_ERR_NONE:        return "OK";
        case LUAT_NDK_HOST_ERR_BAD_OPCODE:  return "BAD_OPCODE";
        case LUAT_NDK_HOST_ERR_PARAM:       return "PARAM";
        case LUAT_NDK_HOST_ERR_UNSUPPORTED: return "UNSUPPORTED";
        default:                            return "?";
    }
}

/* Generic dispatcher: returns a string for any status code in the GPIO,
 * UART, or Crypto range, or the host error range. */
static inline const char *ndk_status_name(uint32_t s) {
    if (s < 10u) return ndk_host_error_name(s);
    if (s < 20u) return ndk_gpio_status_name(s);
    if (s < 30u) return ndk_uart_status_name(s);
    if (s < 40u) return ndk_crypto_status_name(s);
    return "?";
}

/* ------------------------------------------------------------------ */
/* Host hash calls (CSR 0x230 MD5 / 0x231 CRC32)                      */
/* ------------------------------------------------------------------ */

/* ndk_hash_md5: host computes MD5(in_off..in_off+in_len) and writes
 * the 16-byte digest to out_off in guest RAM. Returns a status code:
 *   - LUAT_NDK_CRYPTO_STATUS_OK on success
 *   - LUAT_NDK_CRYPTO_STATUS_BAD_BOUNDS if any range escapes the exchange buffer
 *   - LUAT_NDK_CRYPTO_STATUS_UNSUPPORTED / HOST_ERROR if the host backend fails */
static inline uint32_t ndk_hash_md5(uint32_t in_off, uint32_t in_len, uint32_t out_off) {
    register uint32_t a0 __asm__("a0") =
        LUAT_NDK_CRYPTO_MD5_PACK(in_off, in_len, out_off);
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_CRYPTO_MD5));
    return a0;
}

/* ndk_hash_crc32: host computes IEEE CRC32(in_off..in_off+in_len) and
 * returns the value DIRECTLY (not a status code). The host also stashes
 * the last error via ndk_last_error(); guests that want to distinguish
 * "compute failed" from "compute ok" should check that. The CRC32 itself
 * is the full 32-bit polynomial remainder; range errors are signalled
 * via LUAT_NDK_HOST_ERR_PARAM in ndk_last_error(). */
static inline uint32_t ndk_hash_crc32(uint32_t in_off, uint32_t in_len) {
    register uint32_t a0 __asm__("a0") =
        LUAT_NDK_CRYPTO_CRC32_PACK(in_off, in_len);
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_CSR_CRYPTO_CRC32));
    return a0;
}

/* ------------------------------------------------------------------ */
/* Event ring consumer                                                */
/* ------------------------------------------------------------------ */

/* Peek the next event from the host event ring into *out.
 * Returns the event type (LUAT_NDK_EVENT_*) or LUAT_NDK_EVENT_NONE
 * (0) if no events are pending. Does NOT bump guest_read. */
static inline uint32_t ndk_event_peek(luat_ndk_event_t *out) {
    if (!ndk_event_pending()) return LUAT_NDK_EVENT_NONE;
    /* The host publishes event_slots via CSR 0x140; we use it to bound
     * our read of the head index in the event header at +LUAT_NDK_EVENT_HDR_OFFSET. */
    uint32_t slots = ndk_exchange_read_u32(LUAT_NDK_EVENT_HDR_OFFSET + 8);
    if (slots == 0) slots = 1;
    /* event_head (host_write counter) lives at +0 of the event header.
     * The next unread slot index is event_head - 1 in a "consumed" sense;
     * the host has already advanced the head before marking pending. */
    uint32_t head = ndk_exchange_read_u32(LUAT_NDK_EVENT_HDR_OFFSET + 0);
    uint32_t idx = (head == 0) ? (slots - 1) : ((head - 1) % slots);
    const volatile uint8_t *p = ndk_exchange_ptr() + LUAT_NDK_EVENT_HDR_OFFSET + 16u + idx * 8u;
    if (out) {
        out->type   = (uint16_t)((uint32_t)p[0] | ((uint32_t)p[1] << 8));
        out->source = (uint16_t)((uint32_t)p[2] | ((uint32_t)p[3] << 8));
        out->data   = ((uint32_t)p[4])        |
                      ((uint32_t)p[5] <<  8) |
                      ((uint32_t)p[6] << 16) |
                      ((uint32_t)p[7] << 24);
    }
    return (out ? out->type : LUAT_NDK_EVENT_NONE);
}
