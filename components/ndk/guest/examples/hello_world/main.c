#include <stdint.h>

#define NDK_RAM_BASE    0x80000000u
#define NDK_SYSCON      0x11100000u
#define NDK_DONE_MARKER 0x5555u

static uint32_t ndk_memory_size(void) {
    uint32_t size = 0;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13B" : "=r"(size));
    return size;
}

static uint32_t ndk_exchange_base(void) {
    /* CSR 0x139 = NDK_CSR_EXCHANGE_BASE; csrr only accepts a 5-bit immediate,
     * so the CSR number must be baked into the asm template. */
    uint32_t base = 0;
    __asm__ volatile(".option norvc\ncsrr %0, 0x139" : "=r"(base));
    return base;
}

static int main(void) {
    /* Write the HELLO_NDK_DONE marker byte-by-byte: the guest CPU is
     * little-endian, so a naive uint32 write (e.g. 0x48454C4C) would lay
     * the bytes out as 4C 4C 45 48 ("LLEH") instead of "HELL". */
    volatile uint8_t* ex = (volatile uint8_t*)ndk_exchange_base();
    static const char msg[16] = {
        'H','E','L','L','O','_','N','D','K','_','D','O','N','E', 0, 0
    };
    for (int i = 0; i < 16; i++) {
        ex[i] = (uint8_t)msg[i];
    }
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

