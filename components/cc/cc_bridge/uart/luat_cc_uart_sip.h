/* Passive, bounded SIP/SDP observer for one incoming or outgoing call. */
#ifndef LUAT_CC_UART_SIP_H
#define LUAT_CC_UART_SIP_H
#include <stddef.h>
#include <stdint.h>

#define LUAT_CC_UART_SIP_MESSAGE_MAX 8192U
#define LUAT_CC_UART_SIP_ID_MAX 192U
#define LUAT_CC_UART_SIP_TAG_MAX 96U
#define LUAT_CC_UART_SIP_FRESH_MS 15000U

typedef struct { uint8_t family, address[16]; uint16_t port; } luat_cc_uart_sip_endpoint_t;
typedef int (*luat_cc_uart_sip_addr_parse_fn)(const char *literal, uint8_t family, uint8_t address[16]);
typedef struct {
    luat_cc_uart_sip_endpoint_t local, remote;
    uint32_t generation, clock_hz;
    uint16_t event_mask;
    uint8_t payload_type;
} luat_cc_uart_sip_mapping_t;
typedef struct {
    uint32_t messages, errors, oversize, slots_full, unsupported, bindings, mappings;
} luat_cc_uart_sip_diag_t;
typedef struct { uint8_t payload_type; uint32_t clock_hz; uint16_t events; } luat_cc_uart_sip_format_t;
typedef struct {
    luat_cc_uart_sip_endpoint_t endpoint;
    luat_cc_uart_sip_format_t formats[4];
    uint8_t count;
} luat_cc_uart_sip_sdp_t;
typedef struct {
    int fd;
    uint16_t used[2];
    uint8_t occupied, poisoned[2];
    char bytes[2][LUAT_CC_UART_SIP_MESSAGE_MAX + 1U];
} luat_cc_uart_sip_stream_t;

/* Parser workspace belongs to each context: SDK socket tasks have small stacks.
 * body is borrowed only while processing one message and cleared before return. */
typedef struct { const char *p; size_t n; } luat_cc_uart_sip_span_t;
typedef struct {
    char id[LUAT_CC_UART_SIP_ID_MAX], from[LUAT_CC_UART_SIP_TAG_MAX], to[LUAT_CC_UART_SIP_TAG_MAX];
    uint32_t cseq;
    unsigned status, method;
    uint8_t response, sdp;
    luat_cc_uart_sip_span_t body;
} luat_cc_uart_sip_message_t;
typedef struct {
    luat_cc_uart_sip_message_t message;
    luat_cc_uart_sip_sdp_t sdp;
    uint8_t payloads[128], have_fmtp[128], bad_fmtp[128];
    uint16_t fmtp[128];
} luat_cc_uart_sip_scratch_t;
typedef struct {
    luat_cc_uart_sip_addr_parse_fn parse_address;
    luat_cc_uart_sip_stream_t streams[2];
    luat_cc_uart_sip_diag_t diag;
    luat_cc_uart_sip_mapping_t map;
    luat_cc_uart_sip_sdp_t offer;
    uint64_t session;
    uint32_t candidate_ms, cseq, generation, last_cseq[2];
    int dialog_fd[2]; /* receive/transmit; UDP may use separate SDK sockets */
    uint8_t candidate, bound, valid, offer_tx, method, answered, retired;
    uint8_t outgoing, outgoing_pending, incoming_pending, dialog_is_tcp;
    char call_id[LUAT_CC_UART_SIP_ID_MAX];
    char retired_id[LUAT_CC_UART_SIP_ID_MAX];
    char remote_tag[LUAT_CC_UART_SIP_TAG_MAX], local_tag[LUAT_CC_UART_SIP_TAG_MAX];
    luat_cc_uart_sip_scratch_t scratch;
} luat_cc_uart_sip_t;

/** Owner must serialize ALL APIs using one mutex, outside ISR/critical sections.
 * Feed only bytes actually sent/received, never MSG_PEEK. These functions do not
 * call sockets, retain input pointers, block, modify network data, or log SIP.
 * begin binds an already observed incoming INVITE, or reserves this session
 * for an initial incoming INVITE observed within FRESH_MS after accepting.
 * A successful begin accepts the reservation; mapping still requires SDP.
 * Repeating begin for the same session does not extend the waiting window.
 * begin_outgoing reserves a session before dialing and binds only a subsequent
 * local initial INVITE within FRESH_MS. Neither direction guesses a dialog.
 * SIP is plaintext TCP/UDP, one RTP/AVP audio section, numeric IPv4/IPv6 only.
 * Unsupported or ambiguous negotiation disables this observer, not the call. */
void luat_cc_uart_sip_init(luat_cc_uart_sip_t *ctx, luat_cc_uart_sip_addr_parse_fn parse_address);
void luat_cc_uart_sip_stream(luat_cc_uart_sip_t *ctx, int fd, int tx, int is_tcp,
                             const void *data, size_t length, uint32_t now_ms);
void luat_cc_uart_sip_close(luat_cc_uart_sip_t *ctx, int fd);
int luat_cc_uart_sip_begin(luat_cc_uart_sip_t *ctx, uint64_t session, uint32_t now_ms);
int luat_cc_uart_sip_begin_outgoing(luat_cc_uart_sip_t *ctx, uint64_t session, uint32_t now_ms);
void luat_cc_uart_sip_finish(luat_cc_uart_sip_t *ctx, uint64_t session);
int luat_cc_uart_sip_mapping(const luat_cc_uart_sip_t *ctx, uint64_t session,
                            luat_cc_uart_sip_mapping_t *out);
#endif
