#include <stdint.h>

#define NDK_RAM_BASE    0x80000000u
#define NDK_EXCHANGE    0x11110000u
#define NDK_SYSCON      0x11100000u
#define NDK_DONE_MARKER 0x5555u

static uint32_t ndk_memory_size(void) {
    uint32_t size = 0;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13B" : "=r"(size));
    return size;
}

static int main(void) {
    volatile uint32_t* ex = (volatile uint32_t*)NDK_EXCHANGE;
    ex[0] = 0x48454C4Cu;
    ex[1] = 0x4F5F4E44u;
    ex[2] = 0x4B5F444Fu;
    ex[3] = 0x4E450000u;
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

