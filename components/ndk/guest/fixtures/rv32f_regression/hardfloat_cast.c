#include <stdint.h>

extern volatile uint32_t SYSCON;

static inline volatile uint32_t *exchange_base(void) {
    uintptr_t addr = 0;
    asm volatile("csrr %0, 0x139" : "=r"(addr));
    return (volatile uint32_t *)addr;
}

__attribute__((noinline))
static int cast_signed(float value) {
    return (int)value;
}

__attribute__((noinline))
static unsigned cast_unsigned(float value) {
    return (unsigned)value;
}

int main(void) {
    volatile float signed_input = 123.75f;
    volatile float unsigned_input = 42.0f;
    volatile uint32_t *exchange = exchange_base();

    exchange[0] = (uint32_t)cast_signed(signed_input);
    exchange[1] = cast_unsigned(unsigned_input);
    SYSCON = 0x5555;
    return 0;
}

__asm__(
".section .text.init\n"
".global _start\n"
".align 4\n"
"_start:\n"
" lui sp, %hi(_sstack)\n"
" addi sp, sp, %lo(_sstack)\n"
" call main\n"
" j .\n"
);
