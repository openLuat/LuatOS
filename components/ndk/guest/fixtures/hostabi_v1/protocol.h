/* protocol.h - NDK Host ABI Protocol Definition */
#ifndef HOSTABI_PROTOCOL_H
#define HOSTABI_PROTOCOL_H

#include <stdint.h>
#include "../../../include/luat_ndk_abi.h"

/* Command opcodes */
#define HOSTABI_CMD_QUERY_META  LUAT_NDK_CMD_QUERY_META
#define HOSTABI_CMD_DELAY_US    LUAT_NDK_CMD_DELAY_US
#define HOSTABI_CMD_EVENT_STATE LUAT_NDK_CMD_EVENT_STATE
#define HOSTABI_CMD_QUERY_RVC_STATUS LUAT_NDK_CMD_QUERY_RVC_STATUS

/* GPIO v2 command opcodes */
#define HOSTABI_CMD_GPIO_CONFIG     LUAT_NDK_CMD_GPIO_CONFIG
#define HOSTABI_CMD_GPIO_WRITE      LUAT_NDK_CMD_GPIO_WRITE
#define HOSTABI_CMD_GPIO_READ       LUAT_NDK_CMD_GPIO_READ
#define HOSTABI_CMD_GPIO_IRQ_STATE  LUAT_NDK_CMD_GPIO_IRQ_STATE
#define HOSTABI_CMD_GPIO_IRQ_CLEAR  LUAT_NDK_CMD_GPIO_IRQ_CLEAR

/* UART v1 command opcodes
 *   UART_CONFIG:  arg0=port, arg1=cfg_offset, arg2=cfg_len
 *                 exchange[cfg_offset..] holds hostabi_uart_cfg_t
 *   UART_TX:      arg0=port, arg1=(payload_offset & 0xFFFF)<<16 | (payload_len & 0xFFFF)
 *                 exchange[payload_offset..] holds bytes to transmit
 *   UART_RX_STATE: arg0=port  (returns value0=pending, value1=buffered_len, value2=reason)
 *   UART_RX_READ: arg0=port, arg1=(payload_offset & 0xFFFF)<<16 | (payload_len & 0xFFFF)
 *                 host copies received bytes into exchange[payload_offset..]
 *   UART_RX_CLEAR: arg0=port
 */
#define HOSTABI_CMD_UART_CONFIG    LUAT_NDK_CMD_UART_CONFIG
#define HOSTABI_CMD_UART_TX        LUAT_NDK_CMD_UART_TX
#define HOSTABI_CMD_UART_RX_STATE  LUAT_NDK_CMD_UART_RX_STATE
#define HOSTABI_CMD_UART_RX_READ   LUAT_NDK_CMD_UART_RX_READ
#define HOSTABI_CMD_UART_RX_CLEAR  LUAT_NDK_CMD_UART_RX_CLEAR

/* CRYPTO v1 command opcodes
 *   CRYPTO_MD5:   arg0=input_offset, arg1=input_len, arg2=output_offset(16 bytes)
 *                 output digest written to exchange[output_offset..output_offset+15]
 *   CRYPTO_CRC32: arg0=input_offset, arg1=input_len
 *                 return value0=crc32(start=0xFFFFFFFF, poly=0x04C11DB7)
 */
#define HOSTABI_CMD_CRYPTO_MD5    LUAT_NDK_CMD_CRYPTO_MD5
#define HOSTABI_CMD_CRYPTO_CRC32  LUAT_NDK_CMD_CRYPTO_CRC32

/* UART v1 buffer offsets */
#define HOSTABI_UART_CFG_OFFSET     128u
#define HOSTABI_UART_PAYLOAD_OFFSET 256u
#define HOSTABI_UART_PORT_LOOPBACK  0x20u

/* Status codes */
#define HOSTABI_STATUS_OK           LUAT_NDK_GPIO_STATUS_OK
#define HOSTABI_STATUS_BAD_PIN      LUAT_NDK_GPIO_STATUS_BAD_PIN
#define HOSTABI_STATUS_BAD_MODE     LUAT_NDK_GPIO_STATUS_BAD_MODE
#define HOSTABI_STATUS_BAD_PULL     LUAT_NDK_GPIO_STATUS_BAD_PULL
#define HOSTABI_STATUS_BAD_IRQ_MODE LUAT_NDK_GPIO_STATUS_BAD_IRQ_MODE
#define HOSTABI_STATUS_UNSUPPORTED  LUAT_NDK_GPIO_STATUS_UNSUPPORTED
#define HOSTABI_STATUS_HOST_ERROR   LUAT_NDK_GPIO_STATUS_HOST_ERROR

/* UART v1 status codes */
#define HOSTABI_STATUS_UART_BAD_PORT   20u
#define HOSTABI_STATUS_UART_BAD_CONFIG 21u
#define HOSTABI_STATUS_UART_BAD_LENGTH 22u
#define HOSTABI_STATUS_UART_BUSY       23u
#define HOSTABI_STATUS_UART_OVERFLOW   24u

/* CRYPTO v1 status codes */
#define HOSTABI_STATUS_CRYPTO_BAD_ARG      LUAT_NDK_CRYPTO_STATUS_BAD_ARG
#define HOSTABI_STATUS_CRYPTO_BAD_BOUNDS   LUAT_NDK_CRYPTO_STATUS_BAD_BOUNDS
#define HOSTABI_STATUS_CRYPTO_UNSUPPORTED  LUAT_NDK_CRYPTO_STATUS_UNSUPPORTED

/* Command structure (16 bytes) */
typedef struct {
    uint32_t opcode;
    uint32_t arg0;
    uint32_t arg1;
    uint32_t arg2; /* GPIO_CONFIG: pull[7:0] | irq_mode[15:8] | private test flags[31:16] */
} hostabi_cmd_t;

#define HOSTABI_GPIO_CONFIG_PULL(arg2)     ((uint32_t)((arg2) & 0xFFu))
#define HOSTABI_GPIO_CONFIG_IRQ_MODE(arg2) ((uint32_t)(((arg2) >> 8) & 0xFFu))
#define HOSTABI_GPIO_TEST_FLAGS(arg2)      ((uint32_t)((arg2) & 0xFFFF0000u))
#define HOSTABI_GPIO_TEST_HOST_FAIL        (1u << 16)

/* Result structure (16 bytes) */
typedef struct {
    uint32_t status;   /* 0 = success, non-zero = error */
    uint32_t value0;
    uint32_t value1;
    uint32_t value2;
} hostabi_result_t;

/* UART v1 configuration structure (placed at HOSTABI_UART_CFG_OFFSET in the exchange buffer) */
typedef struct {
    uint32_t baud;
    uint8_t  data_bits;
    uint8_t  stop_bits;
    uint8_t  parity;
    uint8_t  rx_enable;
} hostabi_uart_cfg_t;

#endif /* HOSTABI_PROTOCOL_H */
