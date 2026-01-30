#ifndef __DTMF_CODEC_H__
#define __DTMF_CODEC_H__

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    // 帧长与步进(毫秒)
    uint32_t frame_ms;
    uint32_t step_ms;
    // 能量门限与峰值比/扭曲容差
    // Q10 定点数(=值 * 1024)
    uint32_t detect_ratio_q10;
    uint32_t power_ratio_q10;
    // 扭曲容差(dB), 仅接受整数
    uint32_t twist_db;
    // 至少连续命中帧数
    uint32_t min_consecutive;
} dtmf_decode_opts_t;

typedef struct {
    // 单音时长与静默间隔(毫秒)
    uint32_t tone_ms;
    uint32_t pause_ms;
    // 幅度(Q15)
    uint16_t amplitude_q15;
} dtmf_encode_opts_t;

typedef struct {
    // 解码事件
    char symbol;
    uint32_t start_sample;
    uint32_t end_sample;
    uint32_t frames;
} dtmf_event_t;

// 默认解码参数
void dtmf_decode_opts_default(dtmf_decode_opts_t* opts);
// 默认编码参数
void dtmf_encode_opts_default(dtmf_encode_opts_t* opts);

// 计算编码后PCM样本数
uint32_t dtmf_encode_calc_samples(const char* digits, uint32_t sample_rate, const dtmf_encode_opts_t* opts);
// 编码DTMF为PCM16LE
int dtmf_encode_pcm16(const char* digits, uint32_t sample_rate, const dtmf_encode_opts_t* opts,
                      int16_t* out_samples, uint32_t max_samples, uint32_t* out_count);

// 从PCM16LE解码DTMF
int dtmf_decode_pcm16(const int16_t* samples, uint32_t sample_count, uint32_t sample_rate,
                      const dtmf_decode_opts_t* opts,
                      char* seq, uint32_t seq_size,
                      dtmf_event_t* events, uint32_t* event_count, uint32_t max_events);

#ifdef __cplusplus
}
#endif

#endif
