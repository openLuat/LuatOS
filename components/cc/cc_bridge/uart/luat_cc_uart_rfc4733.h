/* Negotiated RTP telephone-event receiver. No HAL, RTOS, Lua, or allocation. */
#ifndef LUAT_CC_UART_RFC4733_H
#define LUAT_CC_UART_RFC4733_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t duration_ticks;
    uint64_t duration_ms;
    uint32_t clock_hz;
    char digit;
    uint8_t complete;
} luat_cc_uart_dtmf_end_t;

typedef struct {
    uint64_t segment_ticks;
    luat_cc_uart_dtmf_end_t pending_end;
    uint32_t clock_hz;
    uint32_t ssrc;
    uint32_t timestamp;
    uint32_t event_serial; /* Stable through a held key; zero until first event. */
    uint16_t event_mask;
    uint16_t duration;
    uint8_t payload_type;
    uint8_t configured;
    uint8_t have_source;
    uint8_t have_event;
    uint8_t event;
    uint8_t emitted;
    uint8_t ended;
    uint8_t duration_complete;
    uint8_t end_pending;
} luat_cc_uart_rfc4733_t;

/** Configure with the negotiated dynamic payload type, RTP clock and fmtp
 * events 0..15 bit mask. Returns 1 on success; invalid arguments leave the
 * receiver disabled. Initialization, reset and feed must be serialized by
 * the owner. This object does not validate the call epoch or remote endpoint;
 * the caller must validate those before passing a datagram to feed. */
int luat_cc_uart_rfc4733_init(luat_cc_uart_rfc4733_t *state,
                             uint8_t payload_type, uint32_t clock_hz,
                             uint16_t event_mask);

/** Preserve negotiation and clear source/event history on a new call epoch
 * or an explicitly validated remote source change. Feed never changes SSRC
 * automatically once a valid event packet has bound the receiver. */
void luat_cc_uart_rfc4733_reset(luat_cc_uart_rfc4733_t *state);

/** Inspect one complete RTP datagram without modifying or retaining it.
 * Accepts RTPv2 CSRC/extension/padding and exactly one four-byte telephone
 * event payload. Returns 0 or one of 0..9,*,#,A..D once duration reaches 40ms.
 * A held key and repeated ending packets emit once. Older RTP timestamps
 * and decreasing durations are ignored. Same-key timestamp segments without
 * a new marker or a preceding end inherit the emission latch. A new marked
 * event, or a new timestamp following an end, may emit the same key again.
 * Timestamp ordering uses the RTP 32-bit serial-number half range. Call
 * take_end after every feed before passing the next datagram, so a second
 * completed event cannot replace an unconsumed end notification. */
char luat_cc_uart_rfc4733_feed(luat_cc_uart_rfc4733_t *state,
                              const uint8_t *rtp, size_t length);

/** Consume one end notification, produced only by a valid E packet after
 * the key has met the existing 40ms threshold. Repeated E packets emit no
 * further notification. Duration uses the negotiated RTP clock and includes
 * preceding strictly contiguous 65535-tick segments of a long event.
 * complete is false if an unmarked same-key timestamp transition could not
 * be established as such a continuation; duration then covers only the
 * confirmed tail. Missing E packets never synthesize an end notification.
 * Returns 1 when event was filled, 0 otherwise. Serialized with feed/reset. */
int luat_cc_uart_rfc4733_take_end(luat_cc_uart_rfc4733_t *state,
                                 luat_cc_uart_dtmf_end_t *event);

#ifdef __cplusplus
}
#endif
#endif
