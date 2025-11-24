// 刘斌修改 start - G711编解码实现
// 内存优化：使用动态分配查找表
// 支持μ-law和A-law编解码

#include "luat_base.h"
#include "luat_multimedia_codec.h"
#include "luat_mem.h"
#include <stdbool.h>

#define LUAT_LOG_TAG "g711"
#include "luat_log.h"

// G711编解码器结构体 - 包含动态分配的查找表
typedef struct {
    uint8_t type;        // ULAW or ALAW
    uint8_t is_encoder;  // 是否为编码器
    uint32_t sample_rate; // 采样率
    uint32_t frame_count; // 处理的帧数统计

    // 动态分配的查找表
    uint8_t* linear_to_alaw;    // A-law编码表
    uint8_t* linear_to_ulaw;    // μ-law编码表
    int16_t* ulaw_decode_table; // μ-law解码表
    int16_t* alaw_decode_table; // A-law解码表
    bool tables_initialized;    // 查找表是否已初始化
} g711_codec_t;

// μ-law编码函数 - 用于生成查找表
static int ulaw2linear(unsigned char u_val)
{
    int t;
    u_val = ~u_val;
    t = ((u_val & 0x0F) << 3) + 0x84;
    t <<= ((unsigned)u_val & 0x70) >> 4;
    return (u_val & 0x80) ? (0x84 - t) : (t - 0x84);
}

// A-law编码函数 - 用于生成查找表
static int alaw2linear(unsigned char a_val)
{
    int t;
    int seg;
    a_val ^= 0x55;
    t = a_val & 0x0F;
    seg = ((unsigned)a_val & 0x70) >> 4;
    if(seg)
        t = (t + t + 1 + 32) << (seg + 2);
    else
        t = (t + t + 1) << 3;
    return (a_val & 0x80) ? t : -t;
}

// 生成μ-law编码查找表
static void build_ulaw_table(uint8_t* linear_to_ulaw)
{
    int i, j, v, v1, v2;

    j = 1;
    linear_to_ulaw[8192] = 0xFF;

    for(i = 0; i < 127; i++) {
        v1 = ulaw2linear(i ^ 0xFF);
        v2 = ulaw2linear((i + 1) ^ 0xFF);
        v = (v1 + v2 + 4) >> 3;

        for(; j < v; j += 1) {
            linear_to_ulaw[8192 - j] = (i ^ (0xFF ^ 0x80));
            linear_to_ulaw[8192 + j] = (i ^ 0xFF);
        }
    }

    for(; j < 8192; j++) {
        linear_to_ulaw[8192 - j] = (127 ^ (0xFF ^ 0x80));
        linear_to_ulaw[8192 + j] = (127 ^ 0xFF);
    }

    linear_to_ulaw[0] = linear_to_ulaw[1];
}

// 生成A-law编码查找表
static void build_alaw_table(uint8_t* linear_to_alaw)
{
    int i, j, v, v1, v2;

    j = 1;
    linear_to_alaw[8192] = 0xD5;

    for(i = 0; i < 127; i++) {
        v1 = alaw2linear(i ^ 0xD5);
        v2 = alaw2linear((i + 1) ^ 0xD5);
        v = (v1 + v2 + 4) >> 3;

        for(; j < v; j += 1) {
            linear_to_alaw[8192 - j] = (i ^ (0xD5 ^ 0x80));
            linear_to_alaw[8192 + j] = (i ^ 0xD5);
        }
    }

    for(; j < 8192; j++) {
        linear_to_alaw[8192 - j] = (127 ^ (0xD5 ^ 0x80));
        linear_to_alaw[8192 + j] = (127 ^ 0xD5);
    }

    linear_to_alaw[0] = linear_to_alaw[1];
}

// 初始化μ-law解码查找表
static void build_ulaw_decode_table(int16_t* ulaw_decode_table)
{
    // 标准的μ-law解码表数据
    const int16_t ulaw_data[256] = {
        -32124, -31100, -30076, -29052, -28028, -27004, -25980, -24956,
        -23932, -22908, -21884, -20860, -19836, -18812, -17788, -16764,
        -15996, -15484, -14972, -14460, -13948, -13436, -12924, -12412,
        -11900, -11388, -10876, -10364, -9852, -9340, -8828, -8316,
        -7932, -7676, -7420, -7164, -6908, -6652, -6396, -6140,
        -5884, -5628, -5372, -5116, -4860, -4604, -4348, -4092,
        -3900, -3772, -3644, -3516, -3388, -3260, -3132, -3004,
        -2876, -2748, -2620, -2492, -2364, -2236, -2108, -1980,
        -1884, -1820, -1756, -1692, -1628, -1564, -1500, -1436,
        -1372, -1308, -1244, -1180, -1116, -1052, -988, -924,
        -876, -844, -812, -780, -748, -716, -684, -652,
        -620, -588, -556, -524, -492, -460, -428, -396,
        -372, -356, -340, -324, -308, -292, -276, -260,
        -244, -228, -212, -196, -180, -164, -148, -132,
        -120, -112, -104, -96, -88, -80, -72, -64,
        -56, -48, -40, -32, -24, -16, -8, 0,
        32124, 31100, 30076, 29052, 28028, 27004, 25980, 24956,
        23932, 22908, 21884, 20860, 19836, 18812, 17788, 16764,
        15996, 15484, 14972, 14460, 13948, 13436, 12924, 12412,
        11900, 11388, 10876, 10364, 9852, 9340, 8828, 8316,
        7932, 7676, 7420, 7164, 6908, 6652, 6396, 6140,
        5884, 5628, 5372, 5116, 4860, 4604, 4348, 4092,
        3900, 3772, 3644, 3516, 3388, 3260, 3132, 3004,
        2876, 2748, 2620, 2492, 2364, 2236, 2108, 1980,
        1884, 1820, 1756, 1692, 1628, 1564, 1500, 1436,
        1372, 1308, 1244, 1180, 1116, 1052, 988, 924,
        876, 844, 812, 780, 748, 716, 684, 652,
        620, 588, 556, 524, 492, 460, 428, 396,
        372, 356, 340, 324, 308, 292, 276, 260,
        244, 228, 212, 196, 180, 164, 148, 132,
        120, 112, 104, 96, 88, 80, 72, 64,
        56, 48, 40, 32, 24, 16, 8, 0
    };

    // 复制数据到动态分配的表
    for(int i = 0; i < 256; i++) {
        ulaw_decode_table[i] = ulaw_data[i];
    }
}

// 初始化A-law解码查找表
static void build_alaw_decode_table(int16_t* alaw_decode_table)
{
    // 标准的A-law解码表数据
    const int16_t alaw_data[256] = {
        -5504, -5248, -6016, -5760, -4480, -4224, -4992, -4736,
        -7552, -7296, -8064, -7808, -6528, -6272, -7040, -6784,
        -2752, -2624, -3008, -2880, -2240, -2112, -2496, -2368,
        -3776, -3648, -4032, -3904, -3264, -3136, -3520, -3392,
        -22016, -20992, -24064, -23040, -17920, -16896, -19968, -18944,
        -30208, -29184, -32256, -31232, -26112, -25088, -28160, -27136,
        -11008, -10496, -12032, -11520, -8960, -8448, -9984, -9472,
        -15104, -14592, -16128, -15616, -13056, -12544, -14080, -13568,
        -344, -328, -376, -360, -280, -264, -312, -296,
        -472, -456, -504, -488, -408, -392, -440, -424,
        -88, -72, -120, -104, -24, -8, -56, -40,
        -216, -200, -248, -232, -152, -136, -184, -168,
        -1376, -1312, -1504, -1440, -1120, -1056, -1248, -1184,
        -1888, -1824, -2016, -1952, -1632, -1568, -1760, -1696,
        -688, -656, -752, -720, -560, -528, -624, -592,
        -944, -912, -1008, -976, -816, -784, -880, -848,
        5504, 5248, 6016, 5760, 4480, 4224, 4992, 4736,
        7552, 7296, 8064, 7808, 6528, 6272, 7040, 6784,
        2752, 2624, 3008, 2880, 2240, 2112, 2496, 2368,
        3776, 3648, 4032, 3904, 3264, 3136, 3520, 3392,
        22016, 20992, 24064, 23040, 17920, 16896, 19968, 18944,
        30208, 29184, 32256, 31232, 26112, 25088, 28160, 27136,
        11008, 10496, 12032, 11520, 8960, 8448, 9984, 9472,
        15104, 14592, 16128, 15616, 13056, 12544, 14080, 13568,
        344, 328, 376, 360, 280, 264, 312, 296,
        472, 456, 504, 488, 408, 392, 440, 424,
        88, 72, 120, 104, 24, 8, 56, 40,
        216, 200, 248, 232, 152, 136, 184, 168,
        1376, 1312, 1504, 1440, 1120, 1056, 1248, 1184,
        1888, 1824, 2016, 1952, 1632, 1568, 1760, 1696,
        688, 656, 752, 720, 560, 528, 624, 592,
        944, 912, 1008, 976, 816, 784, 880, 848
    };

    // 复制数据到动态分配的表
    for(int i = 0; i < 256; i++) {
        alaw_decode_table[i] = alaw_data[i];
    }
}

// 初始化所有查找表
static int g711_tables_init(g711_codec_t* codec)
{
    if (!codec || codec->tables_initialized) {
        return 0;
    }

    // 分配编码查找表内存
    codec->linear_to_alaw = (uint8_t*)luat_heap_malloc(16384);
    codec->linear_to_ulaw = (uint8_t*)luat_heap_malloc(16384);

    // 分配解码查找表内存
    codec->ulaw_decode_table = (int16_t*)luat_heap_malloc(256 * sizeof(int16_t));
    codec->alaw_decode_table = (int16_t*)luat_heap_malloc(256 * sizeof(int16_t));

    // 检查内存分配是否成功
    if (!codec->linear_to_alaw || !codec->linear_to_ulaw ||
        !codec->ulaw_decode_table || !codec->alaw_decode_table) {
        // 内存分配失败，清理已分配的内存
        if (codec->linear_to_alaw) luat_heap_free(codec->linear_to_alaw);
        if (codec->linear_to_ulaw) luat_heap_free(codec->linear_to_ulaw);
        if (codec->ulaw_decode_table) luat_heap_free(codec->ulaw_decode_table);
        if (codec->alaw_decode_table) luat_heap_free(codec->alaw_decode_table);

        codec->linear_to_alaw = NULL;
        codec->linear_to_ulaw = NULL;
        codec->ulaw_decode_table = NULL;
        codec->alaw_decode_table = NULL;

        LLOGE("G711 tables memory allocation failed");
        return -1;
    }

    // 生成查找表
    build_ulaw_table(codec->linear_to_ulaw);
    build_alaw_table(codec->linear_to_alaw);
    build_ulaw_decode_table(codec->ulaw_decode_table);
    build_alaw_decode_table(codec->alaw_decode_table);

    codec->tables_initialized = true;
    return 0;
}

// 释放查找表内存
static void g711_tables_cleanup(g711_codec_t* codec)
{
    if (codec) {
        if (codec->linear_to_alaw) {
            luat_heap_free(codec->linear_to_alaw);
            codec->linear_to_alaw = NULL;
        }
        if (codec->linear_to_ulaw) {
            luat_heap_free(codec->linear_to_ulaw);
            codec->linear_to_ulaw = NULL;
        }
        if (codec->ulaw_decode_table) {
            luat_heap_free(codec->ulaw_decode_table);
            codec->ulaw_decode_table = NULL;
        }
        if (codec->alaw_decode_table) {
            luat_heap_free(codec->alaw_decode_table);
            codec->alaw_decode_table = NULL;
        }
        codec->tables_initialized = false;
    }
}

// 优化的G711 μ-law编码函数 - 使用动态查找表
static inline uint8_t g711_ulaw_encode_optimized(g711_codec_t* codec, int16_t pcm_sample)
{
    int index = (pcm_sample + 32768) >> 2;
    if(index < 0) index = 0;
    if(index >= 16384) index = 16383;
    return codec->linear_to_ulaw[index];
}

// 优化的G711 A-law编码函数 - 使用动态查找表
static inline uint8_t g711_alaw_encode_optimized(g711_codec_t* codec, int16_t pcm_sample)
{
    int index = (pcm_sample + 32768) >> 2;
    if(index < 0) index = 0;
    if(index >= 16384) index = 16383;
    return codec->linear_to_alaw[index];
}

// 标准G711 μ-law解码函数 - 使用动态查找表
static inline int16_t g711_ulaw_decode_optimized(g711_codec_t* codec, uint8_t ulaw_byte) {
    return codec->ulaw_decode_table[ulaw_byte];
}

// 标准G711 A-law解码函数 - 使用动态查找表
static inline int16_t g711_alaw_decode_optimized(g711_codec_t* codec, uint8_t alaw_byte) {
    return codec->alaw_decode_table[alaw_byte];
}

// 批量μ-law编码 - 使用循环展开优化
static void g711_ulaw_encode_batch(g711_codec_t* codec, const int16_t* pcm, uint8_t* output, uint32_t len) {
    uint32_t i;
    // 循环展开优化，每次处理4个样本
    for (i = 0; i < len - 3; i += 4) {
        output[i] = g711_ulaw_encode_optimized(codec, pcm[i]);
        output[i+1] = g711_ulaw_encode_optimized(codec, pcm[i+1]);
        output[i+2] = g711_ulaw_encode_optimized(codec, pcm[i+2]);
        output[i+3] = g711_ulaw_encode_optimized(codec, pcm[i+3]);
    }
    // 处理剩余样本
    for (; i < len; i++) {
        output[i] = g711_ulaw_encode_optimized(codec, pcm[i]);
    }
}

// 批量A-law编码 - 使用循环展开优化
static void g711_alaw_encode_batch(g711_codec_t* codec, const int16_t* pcm, uint8_t* output, uint32_t len) {
    uint32_t i;
    // 循环展开优化，每次处理4个样本
    for (i = 0; i < len - 3; i += 4) {
        output[i] = g711_alaw_encode_optimized(codec, pcm[i]);
        output[i+1] = g711_alaw_encode_optimized(codec, pcm[i+1]);
        output[i+2] = g711_alaw_encode_optimized(codec, pcm[i+2]);
        output[i+3] = g711_alaw_encode_optimized(codec, pcm[i+3]);
    }
    // 处理剩余样本
    for (; i < len; i++) {
        output[i] = g711_alaw_encode_optimized(codec, pcm[i]);
    }
}

// 批量μ-law解码 - 使用循环展开优化
static void g711_ulaw_decode_batch(g711_codec_t* codec, const uint8_t* input, int16_t* pcm, uint32_t len) {
    uint32_t i;
    // 循环展开优化，每次处理4个样本
    for (i = 0; i < len - 3; i += 4) {
        pcm[i] = g711_ulaw_decode_optimized(codec, input[i]);
        pcm[i+1] = g711_ulaw_decode_optimized(codec, input[i+1]);
        pcm[i+2] = g711_ulaw_decode_optimized(codec, input[i+2]);
        pcm[i+3] = g711_ulaw_decode_optimized(codec, input[i+3]);
    }
    // 处理剩余样本
    for (; i < len; i++) {
        pcm[i] = g711_ulaw_decode_optimized(codec, input[i]);
    }
}

// 批量A-law解码 - 使用循环展开优化
static void g711_alaw_decode_batch(g711_codec_t* codec, const uint8_t* input, int16_t* pcm, uint32_t len) {
    uint32_t i;
    // 循环展开优化，每次处理4个样本
    for (i = 0; i < len - 3; i += 4) {
        pcm[i] = g711_alaw_decode_optimized(codec, input[i]);
        pcm[i+1] = g711_alaw_decode_optimized(codec, input[i+1]);
        pcm[i+2] = g711_alaw_decode_optimized(codec, input[i+2]);
        pcm[i+3] = g711_alaw_decode_optimized(codec, input[i+3]);
    }
    // 处理剩余样本
    for (; i < len; i++) {
        pcm[i] = g711_alaw_decode_optimized(codec, input[i]);
    }
}

// 创建G711解码器 - 优化内存分配
void* g711_decoder_create(uint8_t type) {
    // 验证类型
    if (type != LUAT_MULTIMEDIA_DATA_TYPE_ULAW && type != LUAT_MULTIMEDIA_DATA_TYPE_ALAW) {
        return NULL;
    }

    g711_codec_t* decoder = (g711_codec_t*)luat_heap_malloc(sizeof(g711_codec_t));
    if (decoder) {
        // 初始化结构体
        decoder->type = type;
        decoder->is_encoder = 0;
        decoder->sample_rate = 8000; // 默认采样率
        decoder->frame_count = 0;
        decoder->linear_to_alaw = NULL;
        decoder->linear_to_ulaw = NULL;
        decoder->ulaw_decode_table = NULL;
        decoder->alaw_decode_table = NULL;
        decoder->tables_initialized = false;

        // 初始化查找表
        if (g711_tables_init(decoder) != 0) {
            luat_heap_free(decoder);
            return NULL;
        }
    } else {
        LLOGE("G711 decoder memory allocation failed");
    }
    return decoder;
}

// 销毁G711解码器 - 安全释放内存
void g711_decoder_destroy(void* decoder) {
    if (decoder) {
        g711_codec_t* g711 = (g711_codec_t*)decoder;
        g711_tables_cleanup(g711);
        luat_heap_free(decoder);
    }
}

// G711解码数据 - 批量处理提高效率
int g711_decoder_get_data(void* decoder, const uint8_t* input, uint32_t len,
                           int16_t* pcm, uint32_t* out_len, uint32_t* used) {
    g711_codec_t* g711 = (g711_codec_t*)decoder;

    // 参数验证
    if (!g711 || !input || !pcm || !out_len || !used) {
        LLOGE("G711 decoder invalid parameters");
        return -1;
    }

    if (len == 0) {
        *out_len = 0;
        *used = 0;
        return 0;
    }

    *out_len = 0;
    *used = len;

    // 批量解码G711数据为PCM
    if (g711->type == LUAT_MULTIMEDIA_DATA_TYPE_ULAW) {
        g711_ulaw_decode_batch(g711, input, pcm, len);
    } else if (g711->type == LUAT_MULTIMEDIA_DATA_TYPE_ALAW) {
        g711_alaw_decode_batch(g711, input, pcm, len);
    } else {
        return -1;
    }

    *out_len = len * 2;  // 16位PCM，每样本2字节

    return 1;
}

// 创建G711编码器 - 优化内存分配
void* g711_encoder_create(uint8_t type) {
    // 验证类型
    if (type != LUAT_MULTIMEDIA_DATA_TYPE_ULAW && type != LUAT_MULTIMEDIA_DATA_TYPE_ALAW) {
        return NULL;
    }

    g711_codec_t* encoder = (g711_codec_t*)luat_heap_malloc(sizeof(g711_codec_t));
    if (encoder) {
        // 初始化结构体
        encoder->type = type;
        encoder->is_encoder = 1;
        encoder->sample_rate = 8000; // 默认采样率
        encoder->frame_count = 0;
        encoder->linear_to_alaw = NULL;
        encoder->linear_to_ulaw = NULL;
        encoder->ulaw_decode_table = NULL;
        encoder->alaw_decode_table = NULL;
        encoder->tables_initialized = false;

        // 初始化查找表
        if (g711_tables_init(encoder) != 0) {
            luat_heap_free(encoder);
            return NULL;
        }
    } else {
        LLOGE("G711 encoder memory allocation failed");
    }
    return encoder;
}

// 销毁G711编码器 - 安全释放内存
void g711_encoder_destroy(void* encoder) {
    if (encoder) {
        g711_codec_t* g711 = (g711_codec_t*)encoder;
        g711_tables_cleanup(g711);
        luat_heap_free(encoder);
    }
}

// G711编码数据 - 批量处理提高效率，仅支持16位PCM输入
int g711_encoder_get_data(void* encoder, const int16_t* pcm, uint32_t len,
                           uint8_t* output, uint32_t* out_len) {
    g711_codec_t* g711 = (g711_codec_t*)encoder;

    // 参数验证
    if (!g711 || !pcm || !output || !out_len) {
        return -1;
    }

    if (len == 0) {
        *out_len = 0;
        return 0;
    }

    *out_len = 0;

    // 批量编码PCM数据为G711
    if (g711->type == LUAT_MULTIMEDIA_DATA_TYPE_ULAW) {
        g711_ulaw_encode_batch(g711, pcm, output, len);
    } else if (g711->type == LUAT_MULTIMEDIA_DATA_TYPE_ALAW) {
        g711_alaw_encode_batch(g711, pcm, output, len);
    } else {
        return -1;
    }

    *out_len = len;  // 8位G711，每样本1字节

    return 1;
}

// 性能统计函数
void g711_get_stats(void* codec, uint32_t* sample_rate, uint32_t* frame_count) {
    g711_codec_t* g711 = (g711_codec_t*)codec;
    if (g711) {
        if (sample_rate) *sample_rate = g711->sample_rate;
        if (frame_count) *frame_count = g711->frame_count;
    }
}

// 重置统计信息
void g711_reset_stats(void* codec) {
    g711_codec_t* g711 = (g711_codec_t*)codec;
    if (g711) {
        g711->frame_count = 0;
    }
}

// 设置采样率
void g711_set_sample_rate(void* codec, uint32_t sample_rate) {
    g711_codec_t* g711 = (g711_codec_t*)codec;
    if (g711) {
        g711->sample_rate = sample_rate;
    }
}

// 刘斌修改 end
