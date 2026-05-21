#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "luat_rtos.h"

#ifndef LUAT_NDK_MAX_RAM_SIZE
#define LUAT_NDK_MAX_RAM_SIZE (32 * 1024)
#endif

#ifndef LUAT_NDK_DEFAULT_RAM_SIZE
#define LUAT_NDK_DEFAULT_RAM_SIZE (8 * 1024)
#endif

#ifndef LUAT_NDK_DEFAULT_EXCHANGE_SIZE
#define LUAT_NDK_DEFAULT_EXCHANGE_SIZE (4 * 1024)
#endif

#define LUAT_NDK_EXCHANGE_ALIGN 4
#define LUAT_NDK_GPIO_TRACK_BYTES 32
#define LUAT_NDK_UART_RX_CAPACITY 256
#define LUAT_NDK_ISA_NAME_MAX 8
#define LUAT_NDK_ISA_RV32IMA "rv32ima"
#define LUAT_NDK_ISA_RV32IMF "rv32imf"

struct MiniRV32IMAState;
typedef struct MiniRV32IMAState MiniRV32IMAState;

typedef struct {
    uint8_t  configured;
    uint8_t  rx_enable;
    uint8_t  pending;
    uint8_t  reason;
    uint8_t  owner;
    uint32_t port_id;
    uint32_t baud;
    uint16_t rx_head;
    uint16_t rx_tail;
    uint16_t rx_len;
    uint8_t  data_bits;
    uint8_t  stop_bits;
    uint8_t  parity;
    uint8_t  rx_buf[LUAT_NDK_UART_RX_CAPACITY];
} luat_ndk_uart_port_t;

typedef enum {
    LUAT_NDK_OK = 0,
    LUAT_NDK_ERR_PARAM = -1,
    LUAT_NDK_ERR_NOMEM = -2,
    LUAT_NDK_ERR_IO = -3,
    LUAT_NDK_ERR_IMAGE_TOO_LARGE = -4,
    LUAT_NDK_ERR_BUSY = -5,
    LUAT_NDK_ERR_TRAP = -6,
    LUAT_NDK_ERR_TIMEOUT = -7
} luat_ndk_err_t;

typedef enum {
    LUAT_NDK_STATE_IDLE = 0,
    LUAT_NDK_STATE_RUNNING = 1,
    LUAT_NDK_STATE_STOPPING = 2,
    LUAT_NDK_STATE_DEINIT = 3,
    LUAT_NDK_STATE_RESETTING = 4
} luat_ndk_state_t;

typedef struct luat_ndk {
    MiniRV32IMAState *core;
    uint8_t *ram;
    size_t ram_size;
    size_t image_size;
    size_t exchange_size;
    size_t exchange_offset;
    uint32_t last_mcause;
    uint32_t last_mtval;
    uint32_t last_trap;
    uint32_t fcsr;
    uint8_t trap_pending;
    uint8_t stop_request;
    uint8_t lock_closing;
    uint8_t flen;
    luat_ndk_state_t state;
    uint32_t lock_refs;
    luat_rtos_mutex_t lock;
    luat_rtos_task_handle worker;
    uint32_t thread_id;
    char *image_path;
    char isa[LUAT_NDK_ISA_NAME_MAX];
    // ABI state
    uint32_t abi_features;
    uint32_t last_error;
    uint16_t event_slots;
    uint16_t event_head;
    uint16_t event_tail;
    uint8_t event_enabled;
    uint8_t gpio_tracked[LUAT_NDK_GPIO_TRACK_BYTES];
    uint8_t gpio_irq_enabled[LUAT_NDK_GPIO_TRACK_BYTES];
    uint8_t gpio_irq_pending[LUAT_NDK_GPIO_TRACK_BYTES];
    uint8_t gpio_irq_reason[LUAT_NDK_GPIO_TRACK_BYTES * 8];
    luat_ndk_uart_port_t uart_ports[1];
} luat_ndk_t;

int luat_ndk_init(luat_ndk_t *ndk, const char *path, size_t mem_size, size_t exchange_size, const char *isa);
void luat_ndk_deinit(luat_ndk_t *ndk);
int luat_ndk_reset(luat_ndk_t *ndk);
int luat_ndk_set_data(luat_ndk_t *ndk, const void *data, size_t len, size_t offset);
int luat_ndk_get_data(luat_ndk_t *ndk, void *out, size_t len, size_t offset, size_t *actual);
int luat_ndk_exec(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us, int32_t *retval);
int luat_ndk_start_thread(luat_ndk_t *ndk, uint32_t step_budget, uint32_t elapsed_us);
int luat_ndk_stop_thread(luat_ndk_t *ndk, uint32_t wait_ms);
bool luat_ndk_is_busy(luat_ndk_t *ndk);
uint32_t luat_ndk_exchange_addr(const luat_ndk_t *ndk);
