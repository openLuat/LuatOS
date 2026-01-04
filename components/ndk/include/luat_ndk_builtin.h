#pragma once

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

// CSR numbers used for host interaction
#define NDK_CSR_PRINT_NUM 0x136
#define NDK_CSR_PRINT_PTR 0x137
#define NDK_CSR_PRINT_STR 0x138
#define NDK_CSR_EXCHANGE_BASE 0x139
#define NDK_CSR_EXCHANGE_SIZE 0x13A
#define NDK_CSR_MEMORY_SIZE  0x13B
#define NDK_CSR_GPIO_SET     0x200
#define NDK_CSR_GPIO_GET     0x201

static inline uint32_t ndk_exchange_base(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_EXCHANGE_BASE));
    return v;
}

static inline uint32_t ndk_exchange_size(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_EXCHANGE_SIZE));
    return v;
}

static inline uint32_t ndk_memory_size(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_MEMORY_SIZE));
    return v;
}

static inline void ndk_lprint(const char *s) {
    __asm__ volatile(".option norvc\ncsrrw x0, %0, %1" :: "i"(NDK_CSR_PRINT_STR), "r"(s));
}

static inline void ndk_pprint(uint32_t ptr) {
    __asm__ volatile(".option norvc\ncsrrw x0, %0, %1" :: "i"(NDK_CSR_PRINT_PTR), "r"(ptr));
}

static inline void ndk_nprint(uint32_t value) {
    __asm__ volatile(".option norvc\ncsrrw x0, %0, %1" :: "i"(NDK_CSR_PRINT_NUM), "r"(value));
}

// Write GPIO level: value = (level << 16) | pin
static inline void ndk_gpio_set(uint32_t pin, uint32_t level) {
    uint32_t v = (level << 16) | (pin & 0xFFFF);
    __asm__ volatile(".option norvc\ncsrrw x0, %0, %1" :: "i"(NDK_CSR_GPIO_SET), "r"(v));
}

// Read GPIO level: write pin via csrrw, then read result
static inline uint32_t ndk_gpio_get(uint32_t pin) {
    uint32_t v = pin & 0xFFFF;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_GPIO_GET));
    return v;
}

// Provide a familiar alias for the shared buffer base
#define USERDATA (ndk_exchange_base())
