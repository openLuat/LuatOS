#include "luat_cc_uart_protocol.h"

#include <limits.h>
#include <string.h>
#if defined(_MSC_VER)
#include <intrin.h>
#endif

static void count_add(uint32_t *counter, uint32_t amount)
{
#if defined(_MSC_VER)
    (void)_InterlockedExchangeAdd((volatile long *)counter, (long)amount);
#elif defined(__GNUC__)
    (void)__sync_fetch_and_add(counter, amount);
#else
#error "UART CC counters require compiler atomics"
#endif
}

static void write16(uint8_t *p, uint16_t value)
{
    p[0] = (uint8_t)value;
    p[1] = (uint8_t)(value >> 8);
}

static void write32(uint8_t *p, uint32_t value)
{
    unsigned i;
    for (i = 0; i < 4U; ++i) p[i] = (uint8_t)(value >> (i * 8U));
}

static void write64(uint8_t *p, uint64_t value)
{
    unsigned i;
    for (i = 0; i < 8U; ++i) p[i] = (uint8_t)(value >> (i * 8U));
}

static uint16_t read16(const uint8_t *p)
{
    return (uint16_t)((uint16_t)p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t read32(const uint8_t *p)
{
    uint32_t value = 0;
    unsigned i;
    for (i = 0; i < 4U; ++i) value |= (uint32_t)p[i] << (i * 8U);
    return value;
}

static uint64_t read64(const uint8_t *p)
{
    uint64_t value = 0;
    unsigned i;
    for (i = 0; i < 8U; ++i) value |= (uint64_t)p[i] << (i * 8U);
    return value;
}

uint16_t luat_cc_uart_crc16(const uint8_t *bytes, size_t length)
{
    uint16_t crc = 0xffffU;
    size_t at;
    unsigned bit;
    if (!bytes && length) return 0;
    for (at = 0; at < length; ++at) {
        crc ^= (uint16_t)((uint16_t)bytes[at] << 8);
        for (bit = 0; bit < 8U; ++bit) {
            crc = (uint16_t)((crc & 0x8000U) ? (crc << 1) ^ 0x1021U : crc << 1);
        }
    }
    return crc;
}

static int valid_format(uint8_t type, uint16_t length)
{
    if (type < LUAT_CC_UART_HELLO || type > LUAT_CC_UART_AUDIO) return 0;
    if (type == LUAT_CC_UART_AUDIO) return length == LUAT_CC_UART_AUDIO_PAYLOAD;
    return length <= LUAT_CC_UART_MAX_CONTROL;
}

/* Temporary buffers bound the operation; capacity failures leave out intact. */
int luat_cc_uart_encode(const luat_cc_uart_packet_t *packet,
                        uint8_t *out, size_t capacity)
{
    uint8_t raw[LUAT_CC_UART_MAX_DECODED];
    uint8_t encoded[LUAT_CC_UART_MAX_ENCODED];
    size_t raw_length, read = 0, write = 1, code_at = 0;
    uint8_t code = 1;
    uint16_t crc;
    if (!packet || !out || (packet->payload_len && !packet->payload))
        return LUAT_CC_UART_BAD_ARG;
    if (!valid_format(packet->type, packet->payload_len)) return LUAT_CC_UART_BAD_PACKET;
    raw_length = LUAT_CC_UART_HEADER_BYTES + (size_t)packet->payload_len;
    raw[0] = LUAT_CC_UART_VERSION;
    raw[1] = packet->type;
    write16(raw + 2, packet->payload_len);
    write64(raw + 4, packet->session);
    write32(raw + 12, packet->sequence);
    if (packet->payload_len) memcpy(raw + LUAT_CC_UART_HEADER_BYTES,
                                    packet->payload, packet->payload_len);
    crc = luat_cc_uart_crc16(raw, raw_length);
    write16(raw + raw_length, crc);
    raw_length += LUAT_CC_UART_CRC_BYTES;
    while (read < raw_length) {
        if (raw[read] == 0) {
            encoded[code_at] = code;
            code_at = write++;
            code = 1;
        } else {
            encoded[write++] = raw[read];
            if (++code == 0xffU) {
                encoded[code_at] = code;
                code_at = write++;
                code = 1;
            }
        }
        ++read;
    }
    encoded[code_at] = code;
    encoded[write++] = 0;
    if (capacity < write) return LUAT_CC_UART_NO_SPACE;
    memcpy(out, encoded, write);
    return (int)write;
}

void luat_cc_uart_parser_init(luat_cc_uart_parser_t *parser)
{
    if (parser) memset(parser, 0, sizeof(*parser));
}

static size_t cobs_decode(luat_cc_uart_parser_t *parser)
{
    size_t read = 0, write = 0, run;
    uint8_t code;
    while (read < parser->used) {
        code = parser->encoded[read++];
        run = (size_t)code - 1U;
        if (!code || run > parser->used - read) return 0;
        if (run > sizeof(parser->decoded) - write) return 0;
        if (run) memcpy(parser->decoded + write, parser->encoded + read, run);
        read += run;
        write += run;
        if (code != 0xffU && read < parser->used) {
            if (write == sizeof(parser->decoded)) return 0;
            parser->decoded[write++] = 0;
        }
    }
    return write;
}

static int deliver(luat_cc_uart_parser_t *parser,
                    luat_cc_uart_packet_cb_t callback, void *userdata)
{
    luat_cc_uart_packet_t packet;
    size_t raw_length = cobs_decode(parser);
    if (!raw_length) {
        count_add(&parser->counters.cobs_errors, 1);
        return 0;
    }
    if (raw_length < LUAT_CC_UART_HEADER_BYTES + LUAT_CC_UART_CRC_BYTES) {
        count_add(&parser->counters.length_errors, 1);
        return 0;
    }
    packet.payload_len = read16(parser->decoded + 2);
    if ((size_t)packet.payload_len != raw_length -
            LUAT_CC_UART_HEADER_BYTES - LUAT_CC_UART_CRC_BYTES) {
        count_add(&parser->counters.length_errors, 1);
        return 0;
    }
    if (luat_cc_uart_crc16(parser->decoded, raw_length - LUAT_CC_UART_CRC_BYTES)
            != read16(parser->decoded + raw_length - LUAT_CC_UART_CRC_BYTES)) {
        count_add(&parser->counters.crc_errors, 1);
        return 0;
    }
    if (parser->decoded[0] != LUAT_CC_UART_VERSION ||
        !valid_format(parser->decoded[1], packet.payload_len)) {
        count_add(&parser->counters.format_errors, 1);
        return 0;
    }
    packet.type = parser->decoded[1];
    packet.session = read64(parser->decoded + 4);
    packet.sequence = read32(parser->decoded + 12);
    packet.payload = parser->decoded + LUAT_CC_UART_HEADER_BYTES;
    count_add(&parser->counters.packets, 1);
    callback(userdata, &packet);
    return 1;
}

int luat_cc_uart_parser_feed(luat_cc_uart_parser_t *parser,
                             const uint8_t *bytes, size_t length,
                             luat_cc_uart_packet_cb_t callback, void *userdata)
{
    size_t at;
    int delivered = 0;
    if (!parser || (!bytes && length) || !callback) return LUAT_CC_UART_BAD_ARG;
    for (at = 0; at < length; ++at) {
        if (bytes[at] == 0) {
            if (!parser->discard && parser->used) {
                int result = deliver(parser, callback, userdata);
                if (result && delivered != INT_MAX) ++delivered;
            }
            parser->used = 0;
            parser->discard = 0;
        } else if (!parser->discard) {
            if (parser->used == sizeof(parser->encoded)) {
                count_add(&parser->counters.oversize_errors, 1);
                parser->used = 0;
                parser->discard = 1;
            } else {
                parser->encoded[parser->used++] = bytes[at];
            }
        }
    }
    return delivered;
}

void luat_cc_uart_parser_get_stats(const luat_cc_uart_parser_t *parser,
                                   luat_cc_uart_parser_stats_t *out)
{
    if (parser && out) memcpy(out, &parser->counters, sizeof(*out));
}
