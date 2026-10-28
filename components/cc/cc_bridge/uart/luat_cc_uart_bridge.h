#ifndef LUAT_CC_UART_BRIDGE_H
#define LUAT_CC_UART_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#include "luat_cc_uart_dtmf.h"
#include "luat_cc_uart_platform.h"

#define LUAT_CC_AUDIO_MODE_UART_PCM 2
#define LUAT_CC_UART_PATH_MAX 160
#define LUAT_CC_UART_NOTICE_DATA_MAX 256
typedef struct {
    char role;
    uint8_t dtmf_only; /* A-only diagnostics: no UART peer or media bridge. */
    int uart_id;
    uint32_t baud_rate;
    uint32_t min_free_bytes;
    int32_t clock_p_ppm, clock_i_ppm, clock_limit_ppm, clock_slew_ppm;
    char record_mount[LUAT_CC_UART_PATH_MAX];
} luat_cc_uart_config_t;
typedef struct {
    char event[24];
    uint64_t session;
    uint32_t sequence, value, epoch;
    luat_cc_uart_dtmf_end_t dtmf_end;
    char data[LUAT_CC_UART_NOTICE_DATA_MAX + 1];
} luat_cc_uart_notice_t;
typedef struct {
    uint64_t session;
    uint32_t link_ready, ready, active, connected, media_ready, media_epoch, wire_epoch, rate;
    uint32_t route, rx_frames, tx_frames, capture_dropped, tx_dropped;
    uint32_t capture_frames, dtmf_missing_frames, dtmf_enabled;
    uint32_t dtmf_only;
    uint32_t upload_errors, clock_skipped, notice_dropped, control_retries;
    uint32_t crc_errors, framing_errors, stale_packets, underflow, overflow;
    uint32_t queue_samples, record_active, record_frames, record_failed;
    int32_t correction_ppm;
    luat_cc_uart_dtmf_diag_t dtmf;
    luat_cc_uart_source_diag_t source;
    luat_cc_uart_network_dtmf_diag_t network_dtmf;
} luat_cc_uart_stats_t;
typedef void (*luat_cc_uart_notice_fn)(const luat_cc_uart_notice_t *notice);
enum { LUAT_CC_UART_ISOLATED, LUAT_CC_UART_PRIMING, LUAT_CC_UART_BRIDGE };

#ifdef LUAT_USE_CC_UART_BRIDGE
/* setup is immutable until reboot; notice runs on a notification task, never ISR. */
int luat_cc_uart_setup(const luat_cc_uart_config_t *config, luat_cc_uart_notice_fn notify);
int luat_cc_uart_setup_done(void);
int luat_cc_uart_active(void);
int luat_cc_uart_begin(uint64_t requested, uint64_t *session);
int luat_cc_uart_send(uint64_t session, const char *json, size_t length, uint32_t *sequence);
int luat_cc_uart_route(uint64_t session, unsigned mode);
int luat_cc_uart_play(uint64_t session, const char *path);
int luat_cc_uart_play_stop(uint64_t session);
int luat_cc_uart_dtmf(uint64_t session, int enabled);
int luat_cc_uart_record(uint64_t session, const char *path);
int luat_cc_uart_record_stop(uint64_t session);
int luat_cc_uart_finish(uint64_t session);
int luat_cc_uart_get_stats(luat_cc_uart_stats_t *stats);
/* HAL callback: copies at most 320 samples before returning, does not block. */
void luat_cc_uart_capture(const int16_t *pcm, uint16_t samples, uint32_t rate);
void luat_cc_uart_connected(int connected);
void luat_cc_uart_local_stop(void);
void luat_cc_uart_fault(const char *reason);
#endif
#endif
