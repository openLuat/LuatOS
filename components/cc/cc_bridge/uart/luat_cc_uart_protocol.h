/* UART CC bridge wire protocol. No HAL, RTOS, Lua, or dynamic allocation. */
#ifndef LUAT_CC_UART_PROTOCOL_H
#define LUAT_CC_UART_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LUAT_CC_UART_VERSION 1U
#define LUAT_CC_UART_MAX_ENCODED 1024U /* Includes the trailing zero. */
#define LUAT_CC_UART_MAX_CONTROL 256U
#define LUAT_CC_UART_AUDIO_SAMPLES 320U
#define LUAT_CC_UART_AUDIO_BYTES 640U
#define LUAT_CC_UART_AUDIO_PAYLOAD 644U
#define LUAT_CC_UART_MAX_PAYLOAD LUAT_CC_UART_AUDIO_PAYLOAD
#define LUAT_CC_UART_HEADER_BYTES 16U
#define LUAT_CC_UART_CRC_BYTES 2U
#define LUAT_CC_UART_MAX_DECODED (LUAT_CC_UART_HEADER_BYTES + \
                                 LUAT_CC_UART_MAX_PAYLOAD + LUAT_CC_UART_CRC_BYTES)

#define LUAT_CC_UART_BAD_ARG (-1)
#define LUAT_CC_UART_NO_SPACE (-2)
#define LUAT_CC_UART_BAD_PACKET (-3)

enum {
    LUAT_CC_UART_HELLO = 1,
    LUAT_CC_UART_CONTROL = 2,
    LUAT_CC_UART_ACK = 3,
    LUAT_CC_UART_HEARTBEAT = 4,
    LUAT_CC_UART_AUDIO = 5
};

typedef struct {
    uint8_t type;
    uint64_t session;
    uint32_t sequence;
    uint16_t payload_len;
    const uint8_t *payload;
} luat_cc_uart_packet_t;

typedef struct {
    uint32_t packets;
    uint32_t crc_errors;
    uint32_t length_errors;
    uint32_t cobs_errors;
    uint32_t format_errors;
    uint32_t oversize_errors;
} luat_cc_uart_parser_stats_t;

typedef struct {
    uint8_t encoded[LUAT_CC_UART_MAX_ENCODED - 1U];
    uint8_t decoded[LUAT_CC_UART_MAX_DECODED];
    size_t used;
    uint8_t discard;
    luat_cc_uart_parser_stats_t counters;
} luat_cc_uart_parser_t;

/** Packet payload is borrowed and valid only until this callback returns.
 * Copy a packet before handing it to another task. Do not reenter its parser. */
typedef void (*luat_cc_uart_packet_cb_t)(void *userdata,
                                       const luat_cc_uart_packet_t *packet);

/** CRC-16/CCITT-FALSE: initial FFFF, polynomial 1021, no reflection/xorout. */
uint16_t luat_cc_uart_crc16(const uint8_t *bytes, size_t length);

/** Encode one validated packet, including COBS framing and trailing zero.
 * Returns encoded byte count or a negative error; no partial output on errors.
 * Non-AUDIO payloads are at most 256 bytes; AUDIO is exactly 644 bytes. */
int luat_cc_uart_encode(const luat_cc_uart_packet_t *packet,
                        uint8_t *out, size_t capacity);

/** Initialize before use. All parser operations and stats snapshots must be
 * serialized by its owner. No allocation, blocking, or retained caller data. */
void luat_cc_uart_parser_init(luat_cc_uart_parser_t *parser);

/** Feed arbitrary fragments. Invalid/oversized frames resynchronize at zero.
 * Returns the number of callbacks delivered or BAD_ARG. */
int luat_cc_uart_parser_feed(luat_cc_uart_parser_t *parser,
                             const uint8_t *bytes, size_t length,
                             luat_cc_uart_packet_cb_t callback, void *userdata);

/** Take this snapshot under the same owner lock as parser_feed. */
void luat_cc_uart_parser_get_stats(const luat_cc_uart_parser_t *parser,
                                   luat_cc_uart_parser_stats_t *out);

#ifdef __cplusplus
}
#endif
#endif
