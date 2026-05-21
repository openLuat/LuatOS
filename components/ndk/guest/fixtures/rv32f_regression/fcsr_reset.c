#include <stdint.h>

extern volatile uint32_t SYSCON;

int main(void) {
    register uint32_t value = 0x21;
    asm volatile("csrrw x0, 0x003, %0" :: "r"(value));
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
