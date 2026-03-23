#include "luat_base.h"
#include "luat_multimedia_codec.h"
#include "luat_fs.h"
#include "luat_zbuff.h"
#include "luat_mem.h"
#include "g711_codec.h"

#ifndef G711_PCM_SAMPLES
#define G711_PCM_SAMPLES 160
#endif

static void* g711_codec_create(luat_multimedia_codec_t* coder) {
    if (coder->type != LUAT_MULTIMEDIA_DATA_TYPE_ULAW && coder->type != LUAT_MULTIMEDIA_DATA_TYPE_ALAW) {
        return NULL;
    }

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

static int g711_codec_get_info(luat_multimedia_codec_t* coder, FILE* fd, audio_info_t* info) {
    (void)coder;
    (void)fd;

    if (!info) return 0;

    info->sample_rate = 8000;
    info->num_channels = 1;
    info->bits_per_sample = 16;
    info->is_signed = 1;
    info->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;

    return 1;
}

static int g711_codec_decode_file_data(luat_multimedia_codec_t* coder, luat_zbuff_t* out_buff, uint32_t mini_output) {
    if (!coder || !coder->ctx || !coder->fd || !out_buff) return 0;

    (void)mini_output;  // G711每次只解码一帧

    FILE* fd = coder->fd;
    uint32_t out_len = 0;
    uint32_t used = 0;
    int result = 0;

    uint8_t in_buffer[G711_PCM_SAMPLES];

    int read_len = luat_fs_fread(in_buffer, G711_PCM_SAMPLES, 1, fd);
    if (read_len > 0) {
        result = g711_decoder_get_data(coder->ctx, in_buffer, read_len,
                                       (int16_t*)(out_buff->addr + out_buff->used),
                                       &out_len, &used);
        if (result > 0) {
            out_buff->used += out_len;
        }
    }

    return (out_buff->used > 0) ? 1 : 0;
}

static int g711_codec_encode(luat_multimedia_codec_t* coder, luat_zbuff_t* in_buff, luat_zbuff_t* out_buff, int mode) {
    (void)mode;
    if (!coder || !coder->ctx || !in_buff || !out_buff) return -1;

    int16_t *pcm = (int16_t *)in_buff->addr;
    uint32_t total_len = in_buff->used >> 1;  // 16位PCM样本数
    uint32_t done_len = 0;
    uint32_t frame_size = G711_PCM_SAMPLES;  // 每帧160个样本
    uint8_t outbuf[G711_PCM_SAMPLES];
    uint32_t out_len;

    // 处理完整的160样本帧
    while ((total_len - done_len) >= frame_size) {
        int result = g711_encoder_get_data(coder->ctx, &pcm[done_len], frame_size, outbuf, &out_len);

        if (result > 0 && out_len > 0) {
            if ((out_buff->len - out_buff->used) < out_len) {
                if (__zbuff_resize(out_buff, out_buff->len * 2 + out_len)) {
                    return -1;
                }
            }
            memcpy(out_buff->addr + out_buff->used, outbuf, out_len);
            out_buff->used += out_len;
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
            if ((out_buff->len - out_buff->used) < out_len) {
                if (__zbuff_resize(out_buff, out_buff->len * 2 + out_len)) {
                    return -1;
                }
            }
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