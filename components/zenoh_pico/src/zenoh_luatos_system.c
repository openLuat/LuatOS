/* SPDX-License-Identifier: MIT */
#include "zenoh-pico/system/platform.h"
#include "luat_zenoh_pico.h"
#include "luat_malloc.h"
#include "luat_crypto.h"
#include "luat_mcu.h"
#include "luat_rtos.h"
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

void *z_malloc(size_t size) { return luat_heap_malloc(size); }
void *z_realloc(void *p, size_t size) { return luat_heap_realloc(p, size); }
void z_free(void *p) { luat_heap_free(p); }
/* RNG没有错误返回通道，失败置故障标记，所属任务关闭会话。 */
void z_random_fill(void *p, size_t n) {
    if (luat_crypto_trng(p, n) != 0) { memset(p, 0, n); luat_zenoh_pico_rng_fail(); }
}
uint8_t z_random_u8(void) { uint8_t n; z_random_fill(&n, sizeof(n)); return n; }
uint16_t z_random_u16(void) { uint16_t n; z_random_fill(&n, sizeof(n)); return n; }
uint32_t z_random_u32(void) { uint32_t n; z_random_fill(&n, sizeof(n)); return n; }
uint64_t z_random_u64(void) { uint64_t n; z_random_fill(&n, sizeof(n)); return n; }
z_result_t z_sleep_ms(size_t n) {
    if (n > UINT32_MAX) return Z_EINVAL;
    luat_rtos_task_sleep((uint32_t)n); return 0;
}
z_result_t z_sleep_us(size_t n) { return z_sleep_ms(n / 1000 + (n % 1000 != 0)); }
z_result_t z_sleep_s(size_t n) {
    if (n > UINT32_MAX / 1000) return Z_EINVAL;
    return z_sleep_ms(n * 1000);
}
z_clock_t z_clock_now(void) { return luat_mcu_tick64_ms() * UINT64_C(1000); }
static unsigned long elapsed(uint64_t now, uint64_t then, uint64_t unit) {
    uint64_t n = now > then ? (now - then) / unit : 0;
    return n > ULONG_MAX ? ULONG_MAX : (unsigned long)n;
}
unsigned long zp_clock_elapsed_us_since(z_clock_t *a, z_clock_t *b) { return elapsed(*a, *b, 1); }
unsigned long zp_clock_elapsed_ms_since(z_clock_t *a, z_clock_t *b) { return elapsed(*a, *b, 1000); }
unsigned long zp_clock_elapsed_s_since(z_clock_t *a, z_clock_t *b) { return elapsed(*a, *b, 1000000); }
unsigned long z_clock_elapsed_us(z_clock_t *p) { return elapsed(z_clock_now(), *p, 1); }
unsigned long z_clock_elapsed_ms(z_clock_t *p) { return elapsed(z_clock_now(), *p, 1000); }
unsigned long z_clock_elapsed_s(z_clock_t *p) { return elapsed(z_clock_now(), *p, 1000000); }
static void advance(z_clock_t *p, uint64_t n) { *p = UINT64_MAX - *p < n ? UINT64_MAX : *p + n; }
void z_clock_advance_us(z_clock_t *p, unsigned long n) { advance(p, n); }
void z_clock_advance_ms(z_clock_t *p, unsigned long n) { advance(p, (uint64_t)n * 1000); }
void z_clock_advance_s(z_clock_t *p, unsigned long n) { advance(p, (uint64_t)n * 1000000); }
/* 墙钟不用于lease超时；RTC未同步时不能提供有效epoch。 */
z_time_t z_time_now(void) { time_t t = time(NULL); return t > 0 ? (uint64_t)t * 1000000 : 0; }
unsigned long z_time_elapsed_us(z_time_t *p) { return elapsed(z_time_now(), *p, 1); }
unsigned long z_time_elapsed_ms(z_time_t *p) { return elapsed(z_time_now(), *p, 1000); }
unsigned long z_time_elapsed_s(z_time_t *p) { return elapsed(z_time_now(), *p, 1000000); }
const char *z_time_now_as_str(char *const p, unsigned long n) {
    if (n) snprintf(p, n, "%llu", (unsigned long long)(z_time_now() / 1000000));
    return p;
}
z_result_t _z_get_time_since_epoch(_z_time_since_epoch *t) {
    time_t now = time(NULL);
    if (now < 1577836800 || (uint64_t)now > UINT32_MAX) return _Z_ERR_SYSTEM_GENERIC;
    t->secs = (uint32_t)now; t->nanos = 0; return 0;
}
