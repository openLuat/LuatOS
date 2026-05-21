#include <stdint.h>

#define NDK_RAM_BASE     0x80000000u
#define NDK_EXCHANGE     0x11110000u
#define NDK_SYSCON       0x11100000u
#define NDK_DONE_MARKER  0x5555u
#define NDK_GPIO_CFG_CSR 0x210
#define NDK_GPIO_WR_CSR  0x211
#define NDK_GPIO_RD_CSR  0x212

static uint32_t ndk_memory_size(void) {
    uint32_t size = 0;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13B" : "=r"(size));
    return size;
}

static uint32_t ndk_gpio_config(uint32_t pin, uint32_t mode, uint32_t pull, uint32_t irq_mode) {
    register uint32_t a0 __asm__("a0") =
        ((irq_mode & 0xFFu) << 24) | ((pull & 0xFFu) << 16) | ((mode & 0xFFu) << 8) | (pin & 0xFFu);
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_GPIO_CFG_CSR));
    return a0;
}

static uint32_t ndk_gpio_write(uint32_t pin, uint32_t level) {
    register uint32_t a0 __asm__("a0") = ((level & 0x1u) << 16) | (pin & 0xFFFFu);
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_GPIO_WR_CSR));
    return a0;
}

static uint32_t ndk_gpio_read(uint32_t pin) {
    register uint32_t a0 __asm__("a0") = pin & 0xFFFFu;
    __asm__ volatile(".option norvc\ncsrrw a0, %1, a0" : "+r"(a0) : "i"(NDK_GPIO_RD_CSR));
    return a0;
}

static int main(void) {
    volatile uint32_t* ex = (volatile uint32_t*)NDK_EXCHANGE;
    uint32_t pin = 5u;
    uint32_t mode = 1u;
    uint32_t pull = 0u;
    uint32_t irq_mode = 0u;
    uint32_t level = 1u;

    ex[0] = ndk_gpio_config(pin, mode, pull, irq_mode);
    ex[1] = ndk_gpio_write(pin, level);
    ex[2] = ndk_gpio_read(pin);
    ex[3] = pin;
    ex[4] = level;

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

