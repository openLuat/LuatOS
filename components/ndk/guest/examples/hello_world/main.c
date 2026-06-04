/* minimal hello — direct SYSCON write, no helper, no _start macro */
#include <stdint.h>

static int main(void) {
    /* Write 0x5555 to SYSCON directly. */
    *(volatile uint32_t *)0x11100000u = 0x5555u;
    return 0;
}

__attribute__((noreturn)) void _start(void) {
    /* Hand-rolled sp setup, no helper. */
    uintptr_t mem_size = 0;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13B" : "=r"(mem_size));
    uintptr_t sp_top = 0x80000000u + mem_size - 16u;
    __asm__ volatile("mv sp, %0" :: "r"(sp_top));
    (void)main();
    for (;;) {
        __asm__ volatile("wfi");
    }
}
