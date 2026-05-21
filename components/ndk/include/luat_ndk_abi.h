#pragma once

#include <stdint.h>

// Host ABI Magic and Version
#define LUAT_NDK_HOST_MAGIC   0x4E444B31u  // "NDK1"
#define LUAT_NDK_HOST_VERSION 0x00010000u  // 1.0.0

// Discovery CSR addresses
#define NDK_CSR_HOST_MAGIC      0x13C
#define NDK_CSR_HOST_VERSION    0x13D
#define NDK_CSR_HOST_FEATURES   0x13E
#define NDK_CSR_HOST_LAST_ERROR 0x13F
#define NDK_CSR_EVENT_SLOTS     0x140

// Time and delay CSR addresses
#define NDK_CSR_TIME_US_LO      0x141
#define NDK_CSR_TIME_US_HI      0x142
#define NDK_CSR_DELAY_US        0x143

// Event CSR addresses
#define NDK_CSR_EVENT_ENABLE    0x144
#define NDK_CSR_EVENT_PENDING   0x145

// GPIO v2 CSR addresses
#define NDK_CSR_GPIO_CONFIG     0x210
#define NDK_CSR_GPIO_WRITE_V2   0x211
#define NDK_CSR_GPIO_READ_V2    0x212
#define NDK_CSR_GPIO_IRQ_STATE  0x213
#define NDK_CSR_GPIO_IRQ_CLEAR  0x214

// UART v1 CSR addresses
#define NDK_CSR_UART_CONFIG    0x220
#define NDK_CSR_UART_TX        0x221
#define NDK_CSR_UART_RX_STATE  0x222
#define NDK_CSR_UART_RX_READ   0x223
#define NDK_CSR_UART_RX_CLEAR  0x224

// CRYPTO v1 CSR addresses
#define NDK_CSR_CRYPTO_MD5     0x230
#define NDK_CSR_CRYPTO_CRC32   0x231

// Feature flags
#define LUAT_NDK_FEATURE_META   (1u << 0)
#define LUAT_NDK_FEATURE_TIME   (1u << 1)
#define LUAT_NDK_FEATURE_EVENT  (1u << 2)
#define LUAT_NDK_FEATURE_GPIO   (1u << 3)
#define LUAT_NDK_FEATURE_UART   (1u << 4)
#define LUAT_NDK_FEATURE_CRYPTO (1u << 5)

// Host ABI command opcodes (fixture protocol)
#define LUAT_NDK_CMD_QUERY_META       0x01u
#define LUAT_NDK_CMD_DELAY_US         0x02u
#define LUAT_NDK_CMD_EVENT_STATE      0x03u
#define LUAT_NDK_CMD_QUERY_RVC_STATUS 0x04u
#define LUAT_NDK_CMD_GPIO_CONFIG      0x10u
#define LUAT_NDK_CMD_GPIO_WRITE       0x11u
#define LUAT_NDK_CMD_GPIO_READ        0x12u
#define LUAT_NDK_CMD_GPIO_IRQ_STATE   0x13u
#define LUAT_NDK_CMD_GPIO_IRQ_CLEAR   0x14u
#define LUAT_NDK_CMD_UART_CONFIG      0x20u
#define LUAT_NDK_CMD_UART_TX          0x21u
#define LUAT_NDK_CMD_UART_RX_STATE    0x22u
#define LUAT_NDK_CMD_UART_RX_READ     0x23u
#define LUAT_NDK_CMD_UART_RX_CLEAR    0x24u
#define LUAT_NDK_CMD_CRYPTO_MD5       0x30u
#define LUAT_NDK_CMD_CRYPTO_CRC32     0x31u

// Host error codes
typedef enum {
    LUAT_NDK_HOST_ERR_NONE = 0,
    LUAT_NDK_HOST_ERR_BAD_OPCODE = 1,
    LUAT_NDK_HOST_ERR_PARAM = 2,
    LUAT_NDK_HOST_ERR_UNSUPPORTED = 3
} luat_ndk_host_err_t;

// Exchange buffer layout
#define LUAT_NDK_COMMAND_OFFSET  0
#define LUAT_NDK_COMMAND_SIZE    16
#define LUAT_NDK_RESULT_OFFSET   16
#define LUAT_NDK_RESULT_SIZE     16
#define LUAT_NDK_EVENT_HDR_OFFSET 32
#define LUAT_NDK_EVENT_HDR_SIZE  16

// Event types
#define LUAT_NDK_EVENT_NONE     0u
#define LUAT_NDK_EVENT_TIMER    1u
#define LUAT_NDK_EVENT_GPIO_IRQ 2u
#define LUAT_NDK_EVENT_UART_RX_READY 3u

typedef enum {
    LUAT_NDK_GPIO_MODE_INPUT = 0,
    LUAT_NDK_GPIO_MODE_OUTPUT = 1,
    LUAT_NDK_GPIO_MODE_IRQ = 2
} luat_ndk_gpio_mode_t;

typedef enum {
    LUAT_NDK_GPIO_PULL_DEFAULT = 0,
    LUAT_NDK_GPIO_PULL_UP = 1,
    LUAT_NDK_GPIO_PULL_DOWN = 2
} luat_ndk_gpio_pull_t;

typedef enum {
    LUAT_NDK_GPIO_IRQ_RISING = 0,
    LUAT_NDK_GPIO_IRQ_FALLING = 1,
    LUAT_NDK_GPIO_IRQ_BOTH = 2,
    LUAT_NDK_GPIO_IRQ_HIGH = 3,
    LUAT_NDK_GPIO_IRQ_LOW = 4
} luat_ndk_gpio_irq_mode_t;

typedef enum {
    LUAT_NDK_GPIO_STATUS_OK = 0u,
    LUAT_NDK_GPIO_STATUS_BAD_PIN = 10u,
    LUAT_NDK_GPIO_STATUS_BAD_MODE = 11u,
    LUAT_NDK_GPIO_STATUS_BAD_PULL = 12u,
    LUAT_NDK_GPIO_STATUS_BAD_IRQ_MODE = 13u,
    LUAT_NDK_GPIO_STATUS_UNSUPPORTED = 14u,
    LUAT_NDK_GPIO_STATUS_HOST_ERROR = 15u
} luat_ndk_gpio_status_t;

// Packed GPIO IRQ state/event payload layout
#define LUAT_NDK_GPIO_IRQ_STATE_PIN_SHIFT      0u
#define LUAT_NDK_GPIO_IRQ_STATE_PIN_MASK       0x0000FFFFu
#define LUAT_NDK_GPIO_IRQ_STATE_PENDING_SHIFT  16u
#define LUAT_NDK_GPIO_IRQ_STATE_PENDING_MASK   0x00010000u
#define LUAT_NDK_GPIO_IRQ_STATE_REASON_SHIFT   24u
#define LUAT_NDK_GPIO_IRQ_STATE_REASON_MASK    0xFF000000u

#define LUAT_NDK_GPIO_IRQ_STATE_PACK(pin, pending, reason) \
    ((((uint32_t)(pin)) << LUAT_NDK_GPIO_IRQ_STATE_PIN_SHIFT) & LUAT_NDK_GPIO_IRQ_STATE_PIN_MASK | \
     (((uint32_t)(pending)) << LUAT_NDK_GPIO_IRQ_STATE_PENDING_SHIFT) & LUAT_NDK_GPIO_IRQ_STATE_PENDING_MASK | \
     (((uint32_t)(reason)) << LUAT_NDK_GPIO_IRQ_STATE_REASON_SHIFT) & LUAT_NDK_GPIO_IRQ_STATE_REASON_MASK)

#define LUAT_NDK_GPIO_IRQ_STATE_PIN(value) \
    ((((uint32_t)(value)) & LUAT_NDK_GPIO_IRQ_STATE_PIN_MASK) >> LUAT_NDK_GPIO_IRQ_STATE_PIN_SHIFT)
#define LUAT_NDK_GPIO_IRQ_STATE_PENDING(value) \
    ((((uint32_t)(value)) & LUAT_NDK_GPIO_IRQ_STATE_PENDING_MASK) >> LUAT_NDK_GPIO_IRQ_STATE_PENDING_SHIFT)
#define LUAT_NDK_GPIO_IRQ_STATE_REASON(value) \
    ((((uint32_t)(value)) & LUAT_NDK_GPIO_IRQ_STATE_REASON_MASK) >> LUAT_NDK_GPIO_IRQ_STATE_REASON_SHIFT)

// Event header structure (16 bytes)
typedef struct {
    uint32_t host_write;   // Number of events written by host
    uint32_t guest_read;   // Number of events read by guest
    uint32_t slot_count;   // Total number of event slots available
    uint32_t overflow;     // Set to 1 if event was dropped due to full ring
} luat_ndk_event_header_t;

// Event structure (8 bytes)
typedef struct {
    uint16_t type;         // Event type (LUAT_NDK_EVENT_*)
    uint16_t source;       // Event source identifier
    uint32_t data;         // Event-specific data
} luat_ndk_event_t;

// ---------------------------------------------------------------------------
// UART v1 ABI definitions
// ---------------------------------------------------------------------------

typedef enum {
    LUAT_NDK_UART_STATUS_OK           = 0u,
    LUAT_NDK_UART_STATUS_BAD_PORT     = 20u,
    LUAT_NDK_UART_STATUS_BAD_CONFIG   = 21u,
    LUAT_NDK_UART_STATUS_BAD_LENGTH   = 22u,
    LUAT_NDK_UART_STATUS_BUSY         = 23u,
    LUAT_NDK_UART_STATUS_OVERFLOW     = 24u,
    LUAT_NDK_UART_STATUS_UNSUPPORTED  = 25u,
    LUAT_NDK_UART_STATUS_HOST_ERROR   = 26u
} luat_ndk_uart_status_t;

typedef enum {
    LUAT_NDK_CRYPTO_STATUS_OK          = 0u,
    LUAT_NDK_CRYPTO_STATUS_BAD_ARG     = 30u,
    LUAT_NDK_CRYPTO_STATUS_BAD_BOUNDS  = 31u,
    LUAT_NDK_CRYPTO_STATUS_UNSUPPORTED = 32u,
    LUAT_NDK_CRYPTO_STATUS_HOST_ERROR  = 33u
} luat_ndk_crypto_status_t;

typedef struct {
    uint32_t baud;
    uint8_t  data_bits;
    uint8_t  stop_bits;
    uint8_t  parity;
    uint8_t  rx_enable;
} luat_ndk_uart_cfg_t;

// NDK_CSR_UART_CONFIG value: (cfg_offset << 8) | port
#define LUAT_NDK_UART_PTR_PACK(port, offset)   ((((uint32_t)(offset)) << 8) | ((uint32_t)(port) & 0xFFu))
#define LUAT_NDK_UART_PTR_PORT(value)           ((uint32_t)((value) & 0xFFu))
#define LUAT_NDK_UART_PTR_OFFSET(value)         ((uint32_t)(((value) >> 8) & 0x00FFFFFFu))

// NDK_CSR_UART_TX / NDK_CSR_UART_RX_READ value: (offset[11:0] << 20) | (length[11:0] << 8) | port
#define LUAT_NDK_UART_IO_PACK(port, offset, length) \
    ((((uint32_t)(offset)  & 0x0FFFu) << 20) | \
     (((uint32_t)(length)  & 0x0FFFu) <<  8) | \
     ((uint32_t)(port)     & 0xFFu))
#define LUAT_NDK_UART_IO_PORT(value)    ((uint32_t)((value) & 0xFFu))
#define LUAT_NDK_UART_IO_LENGTH(value)  ((uint32_t)(((value) >>  8) & 0x0FFFu))
#define LUAT_NDK_UART_IO_OFFSET(value)  ((uint32_t)(((value) >> 20) & 0x0FFFu))

// NDK_CSR_UART_RX_STATE return value: (buffered_len[15:0] << 16) | (reason << 8) | pending
#define LUAT_NDK_UART_RX_STATE_PACK(pending, buffered_len, reason) \
    ((((uint32_t)(buffered_len) & 0xFFFFu) << 16) | \
     (((uint32_t)(reason)       & 0xFFu)   <<  8) | \
     ((uint32_t)(pending)       & 0x1u))
#define LUAT_NDK_UART_RX_STATE_PENDING(value) ((uint32_t)((value) & 0x1u))
#define LUAT_NDK_UART_RX_STATE_REASON(value)  ((uint32_t)(((value) >>  8) & 0xFFu))
#define LUAT_NDK_UART_RX_STATE_LENGTH(value)  ((uint32_t)(((value) >> 16) & 0xFFFFu))

// NDK_CSR_CRYPTO_MD5 value: in_offset[31:22] | in_len[21:12] | out_offset[11:2]
#define LUAT_NDK_CRYPTO_MD5_PACK(in_offset, in_len, out_offset) \
    ((((uint32_t)(in_offset)  & 0x03FFu) << 22) | \
     (((uint32_t)(in_len)     & 0x03FFu) << 12) | \
     (((uint32_t)(out_offset) & 0x03FFu) <<  2))
#define LUAT_NDK_CRYPTO_MD5_INPUT_OFFSET(value)  ((uint32_t)(((value) >> 22) & 0x03FFu))
#define LUAT_NDK_CRYPTO_MD5_INPUT_LENGTH(value)  ((uint32_t)(((value) >> 12) & 0x03FFu))
#define LUAT_NDK_CRYPTO_MD5_OUTPUT_OFFSET(value) ((uint32_t)(((value) >>  2) & 0x03FFu))

// NDK_CSR_CRYPTO_CRC32 value: (in_offset[11:0] << 20) | (in_len[11:0] << 8)
#define LUAT_NDK_CRYPTO_CRC32_PACK(in_offset, in_len) \
    ((((uint32_t)(in_offset) & 0x0FFFu) << 20) | \
     (((uint32_t)(in_len)    & 0x0FFFu) <<  8))
#define LUAT_NDK_CRYPTO_CRC32_INPUT_OFFSET(value) ((uint32_t)(((value) >> 20) & 0x0FFFu))
#define LUAT_NDK_CRYPTO_CRC32_INPUT_LENGTH(value) ((uint32_t)(((value) >>  8) & 0x0FFFu))
