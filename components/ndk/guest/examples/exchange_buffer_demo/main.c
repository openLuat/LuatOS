#include <stdint.h>

#define NDK_RAM_BASE    0x80000000u
#define NDK_EXCHANGE    0x11110000u
#define NDK_SYSCON      0x11100000u
#define NDK_DONE_MARKER 0x5555u

typedef struct {
    uint32_t a;
    uint32_t b;
    uint32_t control;
    uint32_t reserved;
} exchange_request_t;

typedef struct {
    uint32_t sum;
    uint32_t xorv;
    uint32_t verdict;
    uint32_t reserved;
} exchange_result_t;

static uint32_t ndk_memory_size(void) {
    uint32_t size = 0;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13B" : "=r"(size));
    return size;
}

static int main(void) {
    volatile exchange_request_t* req = (volatile exchange_request_t*)NDK_EXCHANGE;
    volatile exchange_result_t* out = (volatile exchange_result_t*)(NDK_EXCHANGE + 16u);

    req->a = 0x12345678u;
    req->b = 0x9ABCDEF0u;
    req->control = 0xA5A50001u;

    out->sum = req->a + req->b;
    out->xorv = req->a ^ req->b;
    out->verdict = (req->control == 0xA5A50001u) ? 0x900Du : 0xBADu;

    *(volatile uint32_t*)NDK_SYSCON = NDK_DONE_MARKER;
    return 0;
}

__attribute__((noreturn)) void _start(void) {
    uintptr_t sp_top = (uintptr_t)(NDK_RAM_BASE + ndk_memory_size() - 16u);
    __asm__ volatile("mv sp, %0" :: "r"(sp_top));
    (void)main();
    while (1) {
        __asm__ volatile("wfi");
    }
}

