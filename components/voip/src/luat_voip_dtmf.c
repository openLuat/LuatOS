#include "luat_voip_dtmf.h"

#include <string.h>

static uint16_t rfc4733_be16(const uint8_t *p)
{
    return (uint16_t)(((uint16_t)p[0] << 8) | p[1]);
}

static uint32_t rfc4733_be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | p[3];
}

int voip_dtmf_rx_init(voip_dtmf_rx_t *state,
                             uint8_t payload_type, uint32_t clock_hz,
                             uint16_t event_mask)
{
    if (!state) return 0;
    memset(state, 0, sizeof(*state));
    if (payload_type > 127U || !clock_hz || !event_mask) return 0;
    state->clock_hz = clock_hz;
    state->event_mask = event_mask;
    state->payload_type = payload_type;
    state->configured = 1;
    return 1;
}

void voip_dtmf_rx_reset(voip_dtmf_rx_t *state)
{
    if (!state) return;
    state->ssrc = 0;
    state->timestamp = 0;
    state->event_serial = 0;
    state->duration = 0;
    state->have_source = 0;
    state->have_event = 0;
    state->event = 0;
    state->emitted = 0;
    state->ended = 0;
    state->segment_ticks = 0;
    state->duration_complete = 0;
    state->end_pending = 0;
    memset(&state->pending_end, 0, sizeof(state->pending_end));
}

char voip_dtmf_rx_feed(voip_dtmf_rx_t *state,
                              const uint8_t *rtp, size_t length)
{
    static const char symbols[] = "0123456789*#ABCD";
    size_t start, stop;
    uint32_t timestamp, ssrc, delta;
    uint16_t duration;
    uint8_t event, flags, inherited, continuation;
    char digit = 0;
    if (!state || !state->configured || !rtp || length < 12U) return 0;
    if ((rtp[0] >> 6) != 2U ||
        (rtp[1] & 127U) != state->payload_type) return 0;
    start = 12U + 4U * (rtp[0] & 15U);
    if (start > length) return 0;
    if (rtp[0] & 16U) {
        size_t words;
        if (length - start < 4U) return 0;
        words = rfc4733_be16(rtp + start + 2U);
        if (words > (length - start - 4U) / 4U) return 0;
        start += 4U + words * 4U;
    }
    stop = length;
    if (rtp[0] & 32U) {
        uint8_t padding = rtp[length - 1U];
        if (!padding || padding > length - start) return 0;
        stop -= padding;
    }
    if (stop - start != 4U) return 0;
    event = rtp[start];
    flags = rtp[start + 1U];
    duration = rfc4733_be16(rtp + start + 2U);
    if (event > 15U || !duration ||
        !(state->event_mask & (uint16_t)(1U << event))) return 0;
    timestamp = rfc4733_be32(rtp + 4U);
    ssrc = rfc4733_be32(rtp + 8U);
    if (state->have_source && state->ssrc != ssrc) return 0;
    if (state->have_event) {
        delta = timestamp - state->timestamp;
        if (!delta) {
            if (event != state->event || duration < state->duration) return 0;
            if (state->ended) return 0;
        } else {
            if (delta >= 0x80000000U) return 0;
            continuation = (uint8_t)(event == state->event &&
                !(rtp[1] & 128U) && !state->ended &&
                state->duration == UINT16_MAX && delta == UINT16_MAX);
            inherited = (uint8_t)(event == state->event &&
                !(rtp[1] & 128U) && !state->ended && state->emitted);
            if (continuation) {
                state->segment_ticks += UINT16_MAX;
            } else {
                state->segment_ticks = 0;
                state->duration_complete = (uint8_t)(event != state->event ||
                    (rtp[1] & 128U) || state->ended);
            }
            if (!continuation && !inherited) {
                if (!++state->event_serial) ++state->event_serial;
            }
            state->timestamp = timestamp;
            state->event = event;
            state->emitted = inherited;
            state->ended = 0;
        }
    } else {
        state->ssrc = ssrc;
        state->have_source = 1;
        state->timestamp = timestamp;
        state->event = event;
        state->have_event = 1;
        state->event_serial = 1;
        state->duration_complete = 1;
    }
    state->duration = duration;
    if (flags & 128U) state->ended = 1;
    if (!state->emitted &&
        (uint64_t)duration * 1000U >= (uint64_t)state->clock_hz * 40U) {
        state->emitted = 1;
        digit = symbols[event];
    }
    if (state->ended && state->emitted) {
        uint64_t ticks = state->segment_ticks + duration;
        state->pending_end.duration_ticks = ticks;
        /* Divide the whole seconds first so ticks * 1000 cannot overflow. */
        state->pending_end.duration_ms = (ticks / state->clock_hz) * 1000U +
            ((ticks % state->clock_hz) * 1000U) / state->clock_hz;
        state->pending_end.clock_hz = state->clock_hz;
        state->pending_end.digit = symbols[event];
        state->pending_end.complete = state->duration_complete;
        state->end_pending = 1;
    }
    return digit;
}

int voip_dtmf_rx_take_end(voip_dtmf_rx_t *state,
                                 voip_dtmf_end_t *event)
{
    if (!state || !event || !state->end_pending) return 0;
    *event = state->pending_end;
    state->end_pending = 0;
    return 1;
}

int voip_dtmf_digit_event(char digit)
{
    const char *symbols = "0123456789*#ABCD";
    const char *p = digit ? strchr(symbols, digit) : NULL;
    return p ? (int)(p - symbols) : -1;
}

int voip_dtmf_tx_init(voip_dtmf_tx_t *tx, char digit, uint16_t duration_ms,
                     uint32_t timestamp, uint64_t now_ms)
{
    int event = voip_dtmf_digit_event(digit);
    if (!tx || event < 0 || duration_ms < 100 || duration_ms > 1000) return 0;
    memset(tx, 0, sizeof(*tx));
    tx->event = (uint8_t)event;
    tx->duration_ms = duration_ms;
    tx->timestamp = timestamp;
    tx->started_ms = tx->next_ms = now_ms;
    tx->first = 1;
    return 1;
}

int voip_dtmf_tx_packet(voip_dtmf_tx_t *tx, uint8_t pt, uint16_t seq,
                       uint32_t ssrc, uint64_t now_ms, uint8_t packet[16])
{
    uint64_t elapsed;
    uint16_t ticks;
    uint8_t ended;
    if (!tx || !packet || pt < 96 || pt > 127 || tx->end_packets >= 3 ||
        now_ms < tx->next_ms) return 0;
    elapsed = now_ms - tx->started_ms;
    ended = elapsed >= tx->duration_ms;
    if (elapsed < 20) elapsed = 20;
    if (elapsed > tx->duration_ms) elapsed = tx->duration_ms;
    ticks = (uint16_t)(elapsed * 8U);
    packet[0] = 0x80;
    packet[1] = (uint8_t)(pt | (tx->first ? 0x80 : 0));
    packet[2] = (uint8_t)(seq >> 8); packet[3] = (uint8_t)seq;
    packet[4] = (uint8_t)(tx->timestamp >> 24);
    packet[5] = (uint8_t)(tx->timestamp >> 16);
    packet[6] = (uint8_t)(tx->timestamp >> 8);
    packet[7] = (uint8_t)tx->timestamp;
    packet[8] = (uint8_t)(ssrc >> 24); packet[9] = (uint8_t)(ssrc >> 16);
    packet[10] = (uint8_t)(ssrc >> 8); packet[11] = (uint8_t)ssrc;
    packet[12] = tx->event;
    packet[13] = (uint8_t)(10U | (ended ? 0x80U : 0));
    packet[14] = (uint8_t)(ticks >> 8); packet[15] = (uint8_t)ticks;
    tx->first = 0;
    tx->next_ms = now_ms + 20;
    if (ended) tx->end_packets++;
    return tx->end_packets == 3 ? 2 : 1;
}
