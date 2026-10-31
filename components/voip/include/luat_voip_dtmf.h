/* Negotiated RTP telephone-event receiver. No HAL, RTOS, Lua, or allocation. */
#ifndef LUAT_VOIP_DTMF_H
#define LUAT_VOIP_DTMF_H

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
} voip_dtmf_end_t;

typedef struct {
    uint64_t segment_ticks;
    voip_dtmf_end_t pending_end;
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
} voip_dtmf_rx_t;

/** Configure with the negotiated dynamic payload type, RTP clock and fmtp
 * events 0..15 bit mask. Returns 1 on success; invalid arguments leave the
 * receiver disabled. Initialization, reset and feed must be serialized by
 * the owner. This object does not validate the call epoch or remote endpoint;
 * the caller must validate those before passing a datagram to feed. */
int voip_dtmf_rx_init(voip_dtmf_rx_t *state,
                             uint8_t payload_type, uint32_t clock_hz,
                             uint16_t event_mask);

/** Preserve negotiation and clear source/event history on a new call epoch
 * or an explicitly validated remote source change. Feed never changes SSRC
 * automatically once a valid event packet has bound the receiver. */
void voip_dtmf_rx_reset(voip_dtmf_rx_t *state);

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
char voip_dtmf_rx_feed(voip_dtmf_rx_t *state,
                              const uint8_t *rtp, size_t length);

/** Consume one end notification, produced only by a valid E packet after
 * the key has met the existing 40ms threshold. Repeated E packets emit no
 * further notification. Duration uses the negotiated RTP clock and includes
 * preceding strictly contiguous 65535-tick segments of a long event.
 * complete is false if an unmarked same-key timestamp transition could not
 * be established as such a continuation; duration then covers only the
 * confirmed tail. Missing E packets never synthesize an end notification.
 * Returns 1 when event was filled, 0 otherwise. Serialized with feed/reset. */
int voip_dtmf_rx_take_end(voip_dtmf_rx_t *state,
                                 voip_dtmf_end_t *event);

/* One worker owns TX state. Timestamps remain fixed across a key, while
 * sequence numbers belong to the shared RTP audio/event stream. */
typedef struct {
    uint64_t started_ms;
    uint64_t next_ms;
    uint32_t timestamp;
    uint16_t duration_ms;
    uint8_t event;
    uint8_t end_packets;
    uint8_t first;
} voip_dtmf_tx_t;

int voip_dtmf_digit_event(char digit);
int voip_dtmf_tx_init(voip_dtmf_tx_t *tx, char digit, uint16_t duration_ms,
                     uint32_t timestamp, uint64_t now_ms);
/* Returns 0 before the next deadline, 1 for a packet, 2 for the last of
 * three end packets. Supports the negotiated 8000 Hz event clock. */
int voip_dtmf_tx_packet(voip_dtmf_tx_t *tx, uint8_t pt, uint16_t seq,
                       uint32_t ssrc, uint64_t now_ms, uint8_t packet[16]);

#ifdef __cplusplus
}
#endif
#endif
