#ifdef __LUATOS__
#include "luat_base.h"
#endif

#ifdef LUAT_USE_CC_UART_BRIDGE
#include "luat_cc_uart_dtmf.h"
#include "dtmf_codec.h"

#include <string.h>
#if defined(_MSC_VER)
#include <intrin.h>
#endif

static void diag_count_inc(uint32_t *counter)
{
#if defined(_MSC_VER)
    (void)_InterlockedIncrement((volatile long *)counter);
#elif defined(__GNUC__)
    (void)__sync_fetch_and_add(counter, 1U);
#else
#error "UART CC counters require compiler atomics"
#endif
}

static void decode_opts(dtmf_decode_opts_t *opts, uint32_t frame_ms)
{
    uint32_t samples = frame_ms * 16U;
    dtmf_decode_opts_default(opts);
    opts->frame_ms = frame_ms;
    opts->step_ms = 20;
    opts->min_consecutive = 1;
    /* Goertzel power grows as N^2, whereas the codec's energy reference is
     * mean-square PCM (E/N). Require each selected row/column peak to carry
     * at least N*E/16. An equal-amplitude dual tone has about N*E/4 per peak;
     * broadband noise has only about E per bin and must not become a key.
     * Normalize both the confirmation and release windows identically. */
    opts->detect_ratio_q10 = samples * samples * 1024U / 16U;
}

static char decode_window(const int16_t *pcm, uint32_t samples)
{
    dtmf_decode_opts_t opts;
    char detected[2] = {0};
    uint64_t energy = 0;
    uint32_t i;
    for (i = 0; i < samples; ++i) {
        int32_t sample = pcm[i];
        energy += (uint64_t)((int64_t)sample * sample);
    }
    /* Below 8 LSB RMS (about -72 dBFS), fixed-point roundoff can dominate
     * the signal's Goertzel power. The relative purity test above remains
     * the primary rejection criterion at normal telephone audio levels. */
    if (energy < (uint64_t)samples * 64U) return 0;
    decode_opts(&opts, samples / 16U);
    (void)dtmf_decode_pcm16(pcm, samples, 16000, &opts,
                           detected, sizeof(detected), NULL, NULL, 0);
    return detected[0];
}

static void diagnose_level(luat_cc_uart_dtmf_diag_t *diag, const int16_t pcm[320])
{
    uint64_t energy = 0;
    uint32_t peak = 0;
    uint32_t i;
    for (i = 0; i < 320U; ++i) {
        int32_t sample = pcm[i];
        uint32_t magnitude = (uint32_t)(sample < 0 ? -sample : sample);
        energy += (uint64_t)((int64_t)sample * sample);
        if (magnitude > peak) peak = magnitude;
    }
    diag_count_inc(&diag->frames);
    diag->peak = peak;
    diag->mean_square = (uint32_t)(energy / 320U);
    if (peak > diag->max_peak) diag->max_peak = peak;
}

static void diagnose_loose(luat_cc_uart_dtmf_diag_t *diag, const int16_t pcm[640])
{
    dtmf_decode_opts_t opts;
    char detected[2] = {0};
    if (diag->frames % 5U != 0U) return;
    dtmf_decode_opts_default(&opts);
    /* One standalone window needs one hit. All spectral thresholds remain
     * the codec defaults; this result must never influence key emission. */
    opts.min_consecutive = 1;
    (void)dtmf_decode_pcm16(pcm, 640, 16000, &opts,
                           detected, sizeof(detected), NULL, NULL, 0);
    diag_count_inc(&diag->loose40_samples);
    diag->loose40 = detected[0];
    if (detected[0]) {
        diag_count_inc(&diag->loose40_hits);
        diag->last_loose40 = detected[0];
    }
}

void luat_cc_uart_dtmf_init(luat_cc_uart_dtmf_t *state)
{
    if (state) memset(state, 0, sizeof(*state));
}

char luat_cc_uart_dtmf_feed(luat_cc_uart_dtmf_t *state,
                           const int16_t pcm[320])
{
    char emitted = 0;
    char symbol, current20, previous20;
    if (!state || !pcm) return 0;
    diagnose_level(&state->diag, pcm);
    current20 = decode_window(pcm, 320);
    state->diag.current20 = current20;
    if (current20) diag_count_inc(&state->diag.current20_hits);
    if (!state->have_previous) {
        memcpy(state->window, pcm, 640);
        state->have_previous = 1;
        return 0;
    }
    memcpy(state->window + 320, pcm, 640);
    previous20 = decode_window(state->window, 320);
    state->diag.previous20 = previous20;
    if (previous20) diag_count_inc(&state->diag.previous20_hits);
    symbol = decode_window(state->window, 640);
    state->diag.strict40 = symbol;
    if (symbol) {
        diag_count_inc(&state->diag.strict40_hits);
        state->diag.last_strict40 = symbol;
    }
    diagnose_loose(&state->diag, state->window);
    /* Both halves must contain the same key. Otherwise an isolated 20/40 ms
     * burst can be counted twice by overlapping windows after it has stopped.
     * Two fully populated matching windows require three 20 ms tone hops. */
    if (!state->latched && symbol &&
        (current20 != symbol || previous20 != symbol)) {
        symbol = 0;
    }
    if (state->latched) {
        /* The confirmation window still contains the previous key during the
         * first silent 20 ms hop. Release observes only the current hop so
         * forty milliseconds of released key cannot turn into sixty. */
        symbol = current20;
        if (!symbol) {
            if (++state->release_windows >= 2U) {
                state->latched = 0;
                state->candidate = 0;
                state->consecutive = 0;
                state->release_windows = 0;
            }
        } else {
            state->release_windows = 0;
        }
    } else if (!symbol) {
        state->candidate = 0;
        state->consecutive = 0;
    } else {
        if (state->candidate != symbol) {
            state->candidate = symbol;
            state->consecutive = 1;
        } else if (state->consecutive < 2U) {
            ++state->consecutive;
        }
        if (state->consecutive == 2U) {
            state->latched = symbol;
            state->release_windows = 0;
            emitted = symbol;
            diag_count_inc(&state->diag.emitted);
        }
    }
    memcpy(state->window, state->window + 320, 640);
    return emitted;
}
#endif
