// 刘斌修改 - G711编解码器头文件
// 定义G711编解码器的接口和数据结构

#ifndef G711_CODEC_H
#define G711_CODEC_H

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_log.h"

// G711编解码器类型
typedef enum {
    G711_TYPE_ULAW = 0,  // μ-law编码
    G711_TYPE_ALAW = 1   // A-law编码
} g711_codec_type_t;

// G711编解码器结构体
typedef struct {
    g711_codec_type_t type;  // 编解码器类型
    uint32_t sample_rate;    // 采样率（固定为8000Hz）
    uint32_t channels;       // 声道数（固定为1）
    uint32_t bits_per_sample; // 位深度（固定为16位PCM）
} g711_codec_t;

// 编解码器创建和销毁函数
void* g711_decoder_create(uint8_t type);
void g711_decoder_destroy(void* decoder);
void* g711_encoder_create(uint8_t type);
void g711_encoder_destroy(void* encoder);

// 编解码数据函数
int g711_decoder_get_data(void* decoder, const uint8_t* input, uint32_t len,
                          int16_t* pcm, uint32_t* out_len, uint32_t* used);
int g711_encoder_get_data(void* encoder, const int16_t* pcm, uint32_t len,
                          uint8_t* output, uint32_t* out_len);

// 底层编解码函数
uint8_t g711_ulaw_encode(int16_t pcm_sample);
uint8_t g711_alaw_encode(int16_t pcm_sample);
int16_t g711_ulaw_decode(uint8_t ulaw_byte);
int16_t g711_alaw_decode(uint8_t alaw_byte);

#endif // G711_CODEC_H
// 刘斌修改
