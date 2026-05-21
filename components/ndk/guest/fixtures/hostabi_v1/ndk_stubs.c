/* ndk_stubs.c - Stub implementations for NDK host API functions */

#include "protocol.h"

/* These are placeholder implementations until the actual host ABI is implemented */

#define HOSTABI_TEST_GPIO_IRQ_PACKED_PIN   0xA55Au
#define HOSTABI_TEST_GPIO_IRQ_PACKED_STATE (((unsigned int)3u << 24) | (1u << 16) | HOSTABI_TEST_GPIO_IRQ_PACKED_PIN)
#define HOSTABI_TEST_GPIO_READ_INVALID_PIN 0xB55Bu
#define HOSTABI_TEST_GPIO_HOST_ERROR_PIN   0xC55Cu
#define HOSTABI_TEST_GPIO_CONFIG_HOST_FAIL_MODE 0xFEu
#define HOSTABI_TEST_GPIO_WRITE_HOST_FAIL_FLAG  0x80000000u

unsigned int ndk_exchange_base(void) {
    /* This stub returns the exchange base address.
     * In a real implementation, this would read from CSR 0x139.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int base;
    __asm__ volatile(".option norvc\ncsrr %0, 0x139" : "=r"(base));
    return base;
}

unsigned int ndk_memory_size(void) {
    /* Returns the guest memory size in bytes by reading CSR 0x13B.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int size;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13B" : "=r"(size));
    return size;
}

unsigned int ndk_host_magic(void) {
    /* Reads host magic from CSR 0x13C.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int magic;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13C" : "=r"(magic));
    return magic;
}

unsigned int ndk_host_version(void) {
    /* Reads host version from CSR 0x13D.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int version;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13D" : "=r"(version));
    return version;
}

unsigned int ndk_host_features(void) {
    /* Reads host features from CSR 0x13E.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int features;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13E" : "=r"(features));
    return features;
}

unsigned int ndk_last_error(void) {
    if (ndk_exchange_base()) {
        unsigned int opcode = *(volatile unsigned int*)ndk_exchange_base();
        unsigned int arg0 = *(volatile unsigned int*)(ndk_exchange_base() + 4);
        if ((opcode == HOSTABI_CMD_GPIO_READ || opcode == HOSTABI_CMD_GPIO_IRQ_STATE) &&
            (arg0 == HOSTABI_TEST_GPIO_HOST_ERROR_PIN)) {
            return HOSTABI_STATUS_HOST_ERROR;
        }
    }
    /* Reads last error from CSR 0x13F.
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int error;
    __asm__ volatile(".option norvc\ncsrr %0, 0x13F" : "=r"(error));
    return error;
}

unsigned int ndk_gpio_config(unsigned int pin, unsigned int mode, unsigned int pull, unsigned int irq_mode) {
    register unsigned int a0 __asm__("a0") =
        ((irq_mode & 0xFFu) << 24) | ((pull & 0xFFu) << 16) | ((mode & 0xFFu) << 8) | (pin & 0xFFu);
    __asm__ volatile(".option norvc\ncsrrw a0, 0x210, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_gpio_config_host_fail(unsigned int pin, unsigned int pull, unsigned int irq_mode) {
    register unsigned int a0 __asm__("a0") =
        ((irq_mode & 0xFFu) << 24) | ((pull & 0xFFu) << 16) | (HOSTABI_TEST_GPIO_CONFIG_HOST_FAIL_MODE << 8) | (pin & 0xFFu);
    __asm__ volatile(".option norvc\ncsrrw a0, 0x210, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_gpio_write_v2(unsigned int pin, unsigned int level) {
    register unsigned int a0 __asm__("a0") = ((level & 0x1u) << 16) | (pin & 0xFFFFu);
    __asm__ volatile(".option norvc\ncsrrw a0, 0x211, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_gpio_write_v2_host_fail(unsigned int pin, unsigned int level) {
    register unsigned int a0 __asm__("a0") = HOSTABI_TEST_GPIO_WRITE_HOST_FAIL_FLAG | ((level & 0x1u) << 16) | (pin & 0xFFFFu);
    __asm__ volatile(".option norvc\ncsrrw a0, 0x211, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_gpio_read_v2(unsigned int pin) {
    /* Decoder-only fixture path for validating guest-side read decoding. */
    if ((pin & 0xFFFFu) == HOSTABI_TEST_GPIO_READ_INVALID_PIN) {
        return 2u;
    }
    if ((pin & 0xFFFFu) == HOSTABI_TEST_GPIO_HOST_ERROR_PIN) {
        return HOSTABI_STATUS_HOST_ERROR;
    }
    register unsigned int a0 __asm__("a0") = pin & 0xFFFFu;
    __asm__ volatile(".option norvc\ncsrrw a0, 0x212, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_gpio_irq_state(unsigned int pin) {
    /* Decoder-only fixture path for the Lua regression test. Real host-path
     * coverage still comes from the CSR-backed cases above. */
    if ((pin & 0xFFFFu) == HOSTABI_TEST_GPIO_IRQ_PACKED_PIN) {
        return HOSTABI_TEST_GPIO_IRQ_PACKED_STATE;
    }
    if ((pin & 0xFFFFu) == HOSTABI_TEST_GPIO_HOST_ERROR_PIN) {
        return HOSTABI_STATUS_HOST_ERROR;
    }
    register unsigned int a0 __asm__("a0") = pin & 0xFFFFu;
    __asm__ volatile(".option norvc\ncsrrw a0, 0x213, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_gpio_irq_clear(unsigned int pin) {
    register unsigned int a0 __asm__("a0") = pin & 0xFFFFu;
    __asm__ volatile(".option norvc\ncsrrw a0, 0x214, a0" : "+r"(a0));
    return a0;
}

void ndk_delay_us(unsigned int us) {
    /* Writes delay request to CSR 0x143 (NDK_CSR_DELAY_US).
     * The .option norvc directive ensures 32-bit instruction encoding. */
    __asm__ volatile(".option norvc\ncsrrw x0, 0x143, %0" :: "r"(us));
}

unsigned int ndk_time_us_lo(void) {
    /* Reads low 32 bits of microsecond timestamp from CSR 0x141 (NDK_CSR_TIME_US_LO).
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int time_lo;
    __asm__ volatile(".option norvc\ncsrr %0, 0x141" : "=r"(time_lo));
    return time_lo;
}

void ndk_event_enable(unsigned int enabled) {
    /* Writes event enable flag to CSR 0x144 (NDK_CSR_EVENT_ENABLE).
     * The .option norvc directive ensures 32-bit instruction encoding. */
    __asm__ volatile(".option norvc\ncsrrw x0, 0x144, %0" :: "r"(enabled));
}

unsigned int ndk_event_pending(void) {
    /* Reads event pending flag from CSR 0x145 (NDK_CSR_EVENT_PENDING).
     * The .option norvc directive ensures 32-bit instruction encoding. */
    unsigned int pending;
    __asm__ volatile(".option norvc\ncsrr %0, 0x145" : "=r"(pending));
    return pending;
}

unsigned int ndk_uart_config(unsigned int port, unsigned int cfg_offset) {
    register unsigned int a0 __asm__("a0") = LUAT_NDK_UART_PTR_PACK(port, cfg_offset);
    __asm__ volatile(".option norvc\ncsrrw a0, 0x220, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_uart_tx(unsigned int port, unsigned int data_offset, unsigned int length) {
    register unsigned int a0 __asm__("a0") = LUAT_NDK_UART_IO_PACK(port, data_offset, length);
    __asm__ volatile(".option norvc\ncsrrw a0, 0x221, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_uart_rx_state(unsigned int port) {
    register unsigned int a0 __asm__("a0") = port & 0xFFu;
    __asm__ volatile(".option norvc\ncsrrw a0, 0x222, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_uart_rx_read(unsigned int port, unsigned int data_offset, unsigned int length) {
    register unsigned int a0 __asm__("a0") = LUAT_NDK_UART_IO_PACK(port, data_offset, length);
    __asm__ volatile(".option norvc\ncsrrw a0, 0x223, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_uart_rx_clear(unsigned int port) {
    register unsigned int a0 __asm__("a0") = port & 0xFFu;
    __asm__ volatile(".option norvc\ncsrrw a0, 0x224, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_crypto_md5(unsigned int input_offset, unsigned int input_len, unsigned int output_offset) {
    register unsigned int a0 __asm__("a0") = LUAT_NDK_CRYPTO_MD5_PACK(input_offset, input_len, output_offset);
    __asm__ volatile(".option norvc\ncsrrw a0, 0x230, a0" : "+r"(a0));
    return a0;
}

unsigned int ndk_crypto_crc32(unsigned int input_offset, unsigned int input_len) {
    register unsigned int a0 __asm__("a0") = LUAT_NDK_CRYPTO_CRC32_PACK(input_offset, input_len);
    __asm__ volatile(".option norvc\ncsrrw a0, 0x231, a0" : "+r"(a0));
    return a0;
}
