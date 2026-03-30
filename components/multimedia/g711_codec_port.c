#include "luat_base.h"
#include "luat_multimedia_codec.h"
#include "luat_fs.h"
#include "luat_zbuff.h"
#include "luat_mem.h"
#include "g711_codec/g711_codec.h"

#ifndef G711_PCM_SAMPLES
#define G711_PCM_SAMPLES 160
#endif

static void* g711_codec_create(luat_multimedia_codec_t* coder) {
    if (coder->is_decoder) {
        return g711_decoder_create(coder->type);
    } else {
        return g711_encoder_create(coder->type);
    }
}

static void g711_codec_destroy(luat_multimedia_codec_t* coder) {
    if (!coder || !coder->ctx) return;

    if (coder->is_decoder) {
        g711_decoder_destroy(coder->ctx);
    } else {
        g711_encoder_destroy(coder->ctx);
    }
    coder->ctx = NULL;
}

static int g711_codec_get_info(luat_multimedia_codec_t* coder, FILE* fd) {
    (void)fd;

    // G711固定参数：8kHz采样率, 单声道, 8位深度
    coder->sample_rate = 8000;
    coder->num_channels = 1;
    coder->bits_per_sample = 8;
    coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;

    return 1;
}

static int g711_codec_decode_file_data(luat_multimedia_codec_t* coder, luat_zbuff_t* out_buff, uint32_t mini_output) {
    if (!coder || !coder->ctx || !coder->fd || !out_buff) return 0;

    (void)mini_output;  // G711每次只解码一帧

    FILE* fd = coder->fd;
    uint32_t out_len = 0;
    uint32_t used = 0;
    int result = 0;

    // 动态分配缓冲区
    if (!coder->buff.addr) {
        coder->buff.addr = luat_heap_malloc(G711_PCM_SAMPLES);  // G711每帧160字节
        coder->buff.len = G711_PCM_SAMPLES;
        coder->buff.used = 0;
    }

    // 读取G711数据
    if (coder->buff.used < G711_PCM_SAMPLES) {
        int read_len = luat_fs_fread(coder->buff.addr + coder->buff.used, G711_PCM_SAMPLES, 1, fd);
        if (read_len > 0) {
            coder->buff.used += read_len;
        }
    }

    // 解码G711数据为PCM
    if (coder->buff.used >= G711_PCM_SAMPLES) {
        result = g711_decoder_get_data(coder->ctx, coder->buff.addr, coder->buff.used,
                                       (int16_t*)(out_buff->addr + out_buff->used),
                                       &out_len, &used);
        if (result > 0) {
            out_buff->used += out_len;
        }
        // 移动缓冲区数据
        memmove(coder->buff.addr, coder->buff.addr + used, coder->buff.used - used);
        coder->buff.used -= used;
    }

    return (out_buff->used > 0) ? 1 : 0;
}

static int g711_codec_encode(luat_multimedia_codec_t* coder, luat_zbuff_t* in_buff, luat_zbuff_t* out_buff, int mode) {
    (void)mode;
    if (!coder || !coder->ctx || !in_buff || !out_buff) return -1;

    // G711编码处理 - 使用栈上分配的临时缓冲区，避免长期占用堆内存
    uint8_t outbuf[G711_PCM_SAMPLES];  // 栈上分配，用完即释放
    int16_t *pcm = (int16_t *)in_buff->addr;
    uint32_t total_len = in_buff->used >> 1;  // 16位PCM转字节数
    uint32_t done_len = 0;
    uint32_t frame_size = G711_PCM_SAMPLES;  // G711每帧160个PCM样本
    uint32_t out_len;

    // 处理完整的160样本帧
    while ((total_len - done_len) >= frame_size) {
        // 编码一帧PCM数据为G711
        int result = g711_encoder_get_data(coder->ctx, &pcm[done_len], frame_size, outbuf, &out_len);

        if (result > 0 && out_len > 0) {
            // 检查输出缓冲区空间
            if ((out_buff->len - out_buff->used) < out_len) {
                if (__zbuff_resize(out_buff, out_buff->len * 2 + out_len)) {
                    return -1;
                }
            }
            // 复制编码后的数据到输出缓冲区
            memcpy(out_buff->addr + out_buff->used, outbuf, out_len);
            out_buff->used += out_len;
        } else {

        }
        done_len += frame_size;
    }

    // 处理剩余的PCM样本（不足160个样本的部分）
    uint32_t remaining_len = total_len - done_len;
    if (remaining_len > 0) {

        // 用零填充到160个样本
        int16_t padded_frame[G711_PCM_SAMPLES] = {0};
        memcpy(padded_frame, &pcm[done_len], remaining_len * sizeof(int16_t));

        int result = g711_encoder_get_data(coder->ctx, padded_frame, frame_size, outbuf, &out_len);

        if (result > 0 && out_len > 0) {
            // 检查输出缓冲区空间
            if ((out_buff->len - out_buff->used) < out_len) {
                if (__zbuff_resize(out_buff, out_buff->len * 2 + out_len)) {
                    return -1;
                }
            }
            // 复制编码后的数据到输出缓冲区
            memcpy(out_buff->addr + out_buff->used, outbuf, out_len);
            out_buff->used += out_len;
        }
    }

    return 1;
}

const luat_codec_opts_t g711_codec_opts = {
    .create = g711_codec_create,
    .destroy = g711_codec_destroy,
    .get_info = g711_codec_get_info,
    .decode_file_data = g711_codec_decode_file_data,
    .encode = g711_codec_encode
};