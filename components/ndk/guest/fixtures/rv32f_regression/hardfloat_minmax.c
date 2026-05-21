#include <stdint.h>

extern volatile uint32_t SYSCON;

static inline volatile uint32_t *exchange_base(void) {
    uintptr_t addr = 0;
    asm volatile("csrr %0, 0x139" : "=r"(addr));
    return (volatile uint32_t *)addr;
}

static inline uint32_t f32_bits(float value) {
    union {
        float f;
        uint32_t u;
    } conv = { value };
    return conv.u;
}

__attribute__((noinline))
static float min_only(float a, float b) {
    return __builtin_fminf(a, b);
}

__attribute__((noinline))
static float max_only(float a, float b) {
    return __builtin_fmaxf(a, b);
}

int main(void) {
    volatile float a = 1.5f;
    volatile float b = -2.0f;
    volatile float c = 0.5f;
    volatile float d = 4.0f;
    volatile uint32_t *exchange = exchange_base();

    exchange[0] = f32_bits(min_only(a, b));
    exchange[1] = f32_bits(max_only(c, d));
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
