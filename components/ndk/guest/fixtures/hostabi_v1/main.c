/* main.c - NDK Host ABI Test Fixture */
#include "protocol.h"
#include "../../../include/luat_ndk_abi.h"

/* RVC smoke test - only present in compressed variant */
#ifdef __riscv_compressed
extern unsigned int rvc_smoke_test(void);
#endif

/* NDK builtin APIs from luat_ndk_builtin.h */
extern unsigned int ndk_exchange_base(void);
extern unsigned int ndk_memory_size(void);
extern void ndk_delay_us(unsigned int us);
extern unsigned int ndk_time_us_lo(void);
extern void ndk_event_enable(unsigned int enabled);
extern unsigned int ndk_event_pending(void);
extern unsigned int ndk_gpio_config(unsigned int pin, unsigned int mode, unsigned int pull, unsigned int irq_mode);
extern unsigned int ndk_gpio_config_host_fail(unsigned int pin, unsigned int pull, unsigned int irq_mode);
extern unsigned int ndk_gpio_write_v2(unsigned int pin, unsigned int level);
extern unsigned int ndk_gpio_write_v2_host_fail(unsigned int pin, unsigned int level);
extern unsigned int ndk_gpio_read_v2(unsigned int pin);
extern unsigned int ndk_gpio_irq_state(unsigned int pin);
extern unsigned int ndk_gpio_irq_clear(unsigned int pin);
extern unsigned int ndk_uart_config(unsigned int port, unsigned int cfg_offset);
extern unsigned int ndk_uart_tx(unsigned int port, unsigned int data_offset, unsigned int length);
extern unsigned int ndk_uart_rx_state(unsigned int port);
extern unsigned int ndk_uart_rx_read(unsigned int port, unsigned int data_offset, unsigned int length);
extern unsigned int ndk_uart_rx_clear(unsigned int port);
extern unsigned int ndk_crypto_md5(unsigned int input_offset, unsigned int input_len, unsigned int output_offset);
extern unsigned int ndk_crypto_crc32(unsigned int input_offset, unsigned int input_len);

/* NDK builtin host API (implemented in ndk_stubs.c) */
unsigned int ndk_host_magic(void);
unsigned int ndk_host_version(void);
unsigned int ndk_host_features(void);
unsigned int ndk_last_error(void);

static unsigned int ndk_read_misa(void) {
    unsigned int misa;
    __asm__ volatile(".option norvc\ncsrr %0, 0x301" : "=r"(misa));
    return misa;
}

/* Forward declaration of main */
int main(void);

static int hostabi_is_gpio_status(unsigned int value) {
    switch (value) {
    case HOSTABI_STATUS_BAD_PIN:
    case HOSTABI_STATUS_BAD_MODE:
    case HOSTABI_STATUS_BAD_PULL:
    case HOSTABI_STATUS_BAD_IRQ_MODE:
    case HOSTABI_STATUS_UNSUPPORTED:
    case HOSTABI_STATUS_HOST_ERROR:
        return 1;
    default:
        return 0;
    }
}

/* Memory-mapped control register */
#define CONTROL_STORE (*(volatile unsigned int*)0x11100000)

/* Command and result are in the exchange buffer at offset 0 and 16 bytes respectively */
static volatile hostabi_cmd_t* cmd_buf(void) {
    return (volatile hostabi_cmd_t*)ndk_exchange_base();
}

static volatile hostabi_result_t* result_buf(void) {
    return (volatile hostabi_result_t*)(ndk_exchange_base() + sizeof(hostabi_cmd_t));
}

/* _start - Entry point that initializes stack pointer before calling main */
__attribute__((naked, noreturn)) void _start(void) {
    __asm__ volatile(
        ".option norvc\n"
        /* Read memory size from CSR 0x13B */
        "csrr a0, 0x13B\n"
        /* Compute stack top: 0x80000000 + mem_size - 16 */
        "lui a1, 0x80000\n"
        "add a0, a0, a1\n"
        "addi a0, a0, -16\n"
        /* Initialize stack pointer */
        "mv sp, a0\n"
        /* Call main */
        "call main\n"
        /* Infinite loop if main returns */
        "1: wfi\n"
        "j 1b\n"
        : /* no outputs */
        : /* no inputs */
        : "a0", "a1"
    );
}

int main(void) {
    volatile hostabi_cmd_t* cmd = cmd_buf();
    volatile hostabi_result_t* out = result_buf();
    unsigned int rvc_result = 0;
    unsigned int misa = ndk_read_misa();
    
#ifdef __riscv_compressed
    /* Execute RVC smoke test in compressed variant */
    rvc_result = rvc_smoke_test();
#endif
    
    /* Initialize result to success */
    out->status = 0;
    out->value0 = 0;
    out->value1 = 0;
    out->value2 = 0;

    /* Process command */
    if (cmd->opcode == HOSTABI_CMD_QUERY_META) {
        out->value0 = ndk_host_magic();
        out->value1 = ndk_host_version();
        out->value2 = ndk_host_features();
    } else if (cmd->opcode == HOSTABI_CMD_QUERY_RVC_STATUS) {
        out->value0 = rvc_result;
        out->value1 = misa;
        out->value2 = ndk_host_features();
    } else if (cmd->opcode == HOSTABI_CMD_DELAY_US) {
        /* Enable events before delay */
        ndk_event_enable(1);
        /* Request delay */
        ndk_delay_us(cmd->arg0);
        /* Return timestamp and pending flag */
        out->value0 = ndk_time_us_lo();
        out->value1 = ndk_event_pending();
    } else if (cmd->opcode == HOSTABI_CMD_EVENT_STATE) {
        /* Query event state */
        out->value0 = ndk_event_pending();
    } else if (cmd->opcode == HOSTABI_CMD_GPIO_CONFIG) {
        if (HOSTABI_GPIO_TEST_FLAGS(cmd->arg2) & HOSTABI_GPIO_TEST_HOST_FAIL) {
            out->status = ndk_gpio_config_host_fail(
                cmd->arg0,
                HOSTABI_GPIO_CONFIG_PULL(cmd->arg2),
                HOSTABI_GPIO_CONFIG_IRQ_MODE(cmd->arg2)
            );
        } else {
            out->status = ndk_gpio_config(
                cmd->arg0,
                cmd->arg1,
                HOSTABI_GPIO_CONFIG_PULL(cmd->arg2),
                HOSTABI_GPIO_CONFIG_IRQ_MODE(cmd->arg2)
            );
        }
    } else if (cmd->opcode == HOSTABI_CMD_GPIO_WRITE) {
        if (HOSTABI_GPIO_TEST_FLAGS(cmd->arg2) & HOSTABI_GPIO_TEST_HOST_FAIL) {
            out->status = ndk_gpio_write_v2_host_fail(cmd->arg0, cmd->arg1);
        } else {
            out->status = ndk_gpio_write_v2(cmd->arg0, cmd->arg1);
        }
    } else if (cmd->opcode == HOSTABI_CMD_GPIO_READ) {
        unsigned int level = ndk_gpio_read_v2(cmd->arg0);
        unsigned int last_error = ndk_last_error();
        if (level <= 1u) {
            out->status = HOSTABI_STATUS_OK;
            out->value0 = level;
        } else if (hostabi_is_gpio_status(level) && last_error != 0u) {
            out->status = level;
            out->value0 = 0;
        } else {
            out->status = HOSTABI_STATUS_UNSUPPORTED;
            out->value0 = 0;
        }
    } else if (cmd->opcode == HOSTABI_CMD_GPIO_IRQ_STATE) {
        unsigned int packed = ndk_gpio_irq_state(cmd->arg0);
        unsigned int last_error = ndk_last_error();
        if (hostabi_is_gpio_status(packed) && last_error != 0u) {
            out->status = packed;
            out->value0 = 0;
            out->value1 = 0;
        } else {
            out->status = HOSTABI_STATUS_OK;
            out->value0 = LUAT_NDK_GPIO_IRQ_STATE_PENDING(packed);
            out->value1 = LUAT_NDK_GPIO_IRQ_STATE_REASON(packed);
        }
    } else if (cmd->opcode == HOSTABI_CMD_GPIO_IRQ_CLEAR) {
        out->status = ndk_gpio_irq_clear(cmd->arg0);
    } else if (cmd->opcode == HOSTABI_CMD_UART_CONFIG) {
        out->status = ndk_uart_config(cmd->arg0, cmd->arg1);
    } else if (cmd->opcode == HOSTABI_CMD_UART_TX) {
        out->status = ndk_uart_tx(cmd->arg0, (cmd->arg1 >> 16) & 0xFFFFu, cmd->arg1 & 0xFFFFu);
    } else if (cmd->opcode == HOSTABI_CMD_UART_RX_STATE) {
        uint32_t packed = ndk_uart_rx_state(cmd->arg0);
        unsigned int last_error = ndk_last_error();
        if (last_error != 0u && packed >= HOSTABI_STATUS_UART_BAD_PORT) {
            out->status = packed;
        } else {
            out->status = HOSTABI_STATUS_OK;
            out->value0 = LUAT_NDK_UART_RX_STATE_PENDING(packed);
            out->value1 = LUAT_NDK_UART_RX_STATE_LENGTH(packed);
            out->value2 = LUAT_NDK_UART_RX_STATE_REASON(packed);
        }
    } else if (cmd->opcode == HOSTABI_CMD_UART_RX_READ) {
        uint32_t copied = ndk_uart_rx_read(cmd->arg0, (cmd->arg1 >> 16) & 0xFFFFu, cmd->arg1 & 0xFFFFu);
        unsigned int last_error = ndk_last_error();
        if (last_error != 0u && copied >= HOSTABI_STATUS_UART_BAD_PORT) {
            out->status = copied;
        } else {
            out->status = HOSTABI_STATUS_OK;
            out->value0 = copied;
        }
    } else if (cmd->opcode == HOSTABI_CMD_UART_RX_CLEAR) {
        out->status = ndk_uart_rx_clear(cmd->arg0);
    } else if (cmd->opcode == HOSTABI_CMD_CRYPTO_MD5) {
        out->status = ndk_crypto_md5(cmd->arg0, cmd->arg1, cmd->arg2);
    } else if (cmd->opcode == HOSTABI_CMD_CRYPTO_CRC32) {
        uint32_t crc = ndk_crypto_crc32(cmd->arg0, cmd->arg1);
        unsigned int last_error = ndk_last_error();
        if (last_error != 0u && crc >= HOSTABI_STATUS_CRYPTO_BAD_ARG) {
            out->status = crc;
        } else {
            out->status = HOSTABI_STATUS_OK;
            out->value0 = crc;
        }
    } else {
        out->status = 1;
        out->value0 = ndk_last_error();
    }

    /* Signal completion */
    CONTROL_STORE = 0x5555;
    return 0;
}
