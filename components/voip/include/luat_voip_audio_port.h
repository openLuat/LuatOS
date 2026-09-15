#ifndef LUAT_VOIP_AUDIO_PORT_H
#define LUAT_VOIP_AUDIO_PORT_H

#include <stdint.h>

struct luat_audio_driver_ctrl;

/* Optional Audio V2 port. start returns 1 to opt into PCM normalization and
 * explicit playback commits, 0 for the existing direct-buffer backend, <0 on
 * failure. It runs before activation/format negotiation, without starting DMA.
 * This lets the port negotiate its native capture format for the call. stop revokes
 * callbacks before driver deactivation; the port must keep its DMA events away
 * from the ordinary Audio V2 request callback until DMA has stopped. */
int luat_voip_audio_port_start(struct luat_audio_driver_ctrl *ctrl,
        uint32_t frame_samples, uint16_t frame_ms, uint8_t slots);
void luat_voip_audio_port_stop(struct luat_audio_driver_ctrl *ctrl);

/* Task context. PCM belongs to VoIP and is valid only during this call. The
 * port copies/converts it to its own DMA slot; it must never retain ownership
 * of, or free, VoIP's signed PCM ring. Return <0 if the slot cannot be committed. */
int luat_voip_audio_port_commit(struct luat_audio_driver_ctrl *ctrl,
        uint8_t slot, const int16_t *pcm, uint32_t samples);

/* ISR-safe, bounded copies, no allocation. Return 1 when the event belongs to
 * VoIP (including startup/shutdown drops), 0 otherwise. rendered must describe
 * the actual completed DMA slot, after volume/conversion, in signed PCM16.
 * capture accepts packed little-endian PCM16, channel 0 is the microphone;
 * each block is at most 20 ms at 8/16/48 kHz, mono/stereo. The caller retains
 * both input buffers. Timestamps are hardware block END times in milliseconds. */
int luat_voip_audio_rendered(struct luat_audio_driver_ctrl *ctrl, uint8_t slot,
        const int16_t *pcm, uint32_t samples, uint64_t end_tick_ms);
int luat_voip_audio_capture(struct luat_audio_driver_ctrl *ctrl, const void *pcm,
        uint32_t bytes, uint32_t sample_rate, uint8_t bytes_per_sample,
        uint8_t channels, uint64_t end_tick_ms);

/* Report one completed DMA slot that missed its required commit. Initial
 * playback silence while STARTING is excluded from the running underrun count. */
int luat_voip_audio_underrun(struct luat_audio_driver_ctrl *ctrl);

#ifdef LUAT_VOIP_AEC_PCM_DUMP
enum {
    LUAT_VOIP_TRACE_RAW_MIC = 1,
    LUAT_VOIP_TRACE_RENDER = 2,
    LUAT_VOIP_TRACE_MIC = 3,
    LUAT_VOIP_TRACE_TX = 4
};
/* Optional diagnostics. open/close run in the VoIP task, before DMA starts and
 * after it stops. RAW_MIC/RENDER run in ISR context; MIC/TX run in the task.
 * pcm must synchronously copy into bounded storage, without allocating,
 * blocking or writing files. PCM is signed little-endian 16-bit. Sequence is
 * per stream, and end_tick_ms is the hardware-derived block END time. */
void luat_voip_audio_trace_open(uint32_t input_rate, uint8_t input_channels);
void luat_voip_audio_trace_pcm(uint8_t kind, const void *pcm, uint32_t bytes,
        uint32_t rate, uint8_t channels, uint64_t end_tick_ms, uint32_t sequence);
void luat_voip_audio_trace_close(void);
#endif

/* Optional streaming resampler, called only by the VoIP task. Counts are
 * in/out values, mono signed PCM16; latency is in output (8 kHz) samples.
 * The platform reuses its existing DSP implementation. */
void *luat_voip_audio_resampler_create(uint32_t input_rate, uint32_t output_rate);
int luat_voip_audio_resampler_process(void *state, const int16_t *input,
        uint32_t *input_samples, int16_t *output, uint32_t *output_samples);
uint32_t luat_voip_audio_resampler_latency(void *state);
void luat_voip_audio_resampler_destroy(void *state);

#endif
