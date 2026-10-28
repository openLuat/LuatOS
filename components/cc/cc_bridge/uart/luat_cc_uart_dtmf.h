#ifndef LUAT_CC_UART_DTMF_H
#define LUAT_CC_UART_DTMF_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** One streaming 16 kHz mono decoder. Owner must serialize init/feed and reset
 * the state when entering/leaving WAIT_EXTENSION or starting another call. */
typedef struct {
    uint32_t frames;
    uint32_t peak;
    uint32_t mean_square;
    uint32_t max_peak;
    uint32_t strict40_hits;
    uint32_t previous20_hits;
    uint32_t current20_hits;
    uint32_t loose40_samples;
    uint32_t loose40_hits;
    uint32_t emitted;
    char strict40;
    char previous20;
    char current20;
    char loose40;
    /* Last nonzero symbols survive key release, so a slow stats consumer
     * can inspect a brief key without retaining or recording audio. */
    char last_strict40;
    char last_loose40;
} luat_cc_uart_dtmf_diag_t;

typedef struct {
    int16_t window[640];
    char candidate;
    char latched;
    uint8_t have_previous;
    uint8_t consecutive;
    uint8_t release_windows;
    /* Caller may snapshot this under the same serialization as init/feed.
     * All counters reset on init. loose40 is diagnostic only and sampled
     * every fifth feed; loose40_samples counts completed loose checks. */
    luat_cc_uart_dtmf_diag_t diag;
} luat_cc_uart_dtmf_t;

void luat_cc_uart_dtmf_init(luat_cc_uart_dtmf_t *state);

/** Feed exactly 320 PCM16 samples (20 ms at 16 kHz). Uses a 40 ms window with
 * 20 ms overlap. Both 20 ms halves must contain the key before a window counts;
 * two matching windows confirm 60 ms of tone. Rejects sub-8-LSB-RMS input and
 * uses sample-count-normalized spectral purity gates for both confirmation
 * and release. Releases after two no-tone 20 ms hops (40 ms). A long key hold
 * emits once; it cannot repeat without release.
 * Returns a DTMF character or zero. Routing owners accept only digits 1..9.
 * No allocation, retained pointers, callbacks, or RTOS dependency. */
char luat_cc_uart_dtmf_feed(luat_cc_uart_dtmf_t *state,
                           const int16_t pcm[320]);

#ifdef __cplusplus
}
#endif
#endif
