#ifndef LUAT_CC_UART_PLATFORM_H
#define LUAT_CC_UART_PLATFORM_H

#include <stdint.h>
#include "luat_cc_uart_rfc4733.h"

#define LUAT_CC_AUDIO_MODE_UART_PCM 2

#ifdef LUAT_USE_CC_UART_BRIDGE
/** Numeric-only source diagnostics, reset at each native session begin.
 * speech_rate/bits/len retain the last SDK callback's raw metadata. Peaks
 * and mean squares describe the last valid PCM frame; max peaks span the
 * session. speech_bytes counts declared callback bytes, including formats
 * that are not inspected. No PCM data is retained by these diagnostics. */
typedef struct {
    uint32_t speech_calls;
    uint32_t speech_bytes;
    uint32_t speech_rate;
    uint32_t speech_bits;
    uint32_t speech_len;
    uint32_t speech_peak;
    uint32_t speech_max_peak;
    uint32_t speech_mean_square;
    uint32_t hal_frames;
    uint32_t hal_peak;
    uint32_t hal_max_peak;
    uint32_t hal_mean_square;
} luat_cc_uart_source_diag_t;

/** Passive negotiated telephone-event reception; no SIP text or addresses. */
typedef struct {
    uint32_t supported, active, enabled, mapped, network_mode;
    uint32_t generation, payload_type, clock_hz, local_port;
    uint32_t sip_messages, sip_errors, sip_oversize;
    uint32_t rtp_packets, source_rejected, events, delivered, dropped;
} luat_cc_uart_network_dtmf_diag_t;

int luat_cc_uart_platform_rx_setup(char role);
void luat_cc_uart_platform_rx_begin(uint64_t session);
void luat_cc_uart_platform_rx_stop(uint64_t session);
void luat_cc_uart_platform_rx_enable(uint64_t session, int enabled);
int luat_cc_uart_platform_rx_poll(uint64_t session, char *digit);
int luat_cc_uart_platform_rx_poll_end(uint64_t session, luat_cc_uart_dtmf_end_t *event);
int luat_cc_uart_platform_rx_network_mode(void);
int luat_cc_uart_platform_rx_stats(luat_cc_uart_network_dtmf_diag_t *diag);

/** Copy a consistent source snapshot. Returns -1 for a NULL destination. */
int luat_cc_uart_platform_source_diag(luat_cc_uart_source_diag_t *diag);
/** Select the permanent headless UART PCM owner while CC is idle. */
int luat_cc_uart_platform_init(void);
/** Prepare the native media gates before accepting or placing a call. */
int luat_cc_uart_platform_begin(void);
/** Close native capture/upload gates without changing backend selection. */
int luat_cc_uart_platform_stop(void);
/** Hang up from a task context after a native bridge fault. */
void luat_cc_uart_platform_hangup(void);
int luat_cc_uart_selected(void);
/** Native call and capture owner are both idle; task context only. */
int luat_cc_uart_platform_idle(void);
uint32_t luat_cc_uart_platform_rate(void);
/** Query the physical UART shift register; used together with sent callback. */
int luat_cc_uart_platform_uart_tx_idle(int uart_id);
void luat_cc_uart_platform_mobile_event(uint8_t index, uint8_t status);
#else
static inline int luat_cc_uart_selected(void) { return 0; }
#endif

#endif
