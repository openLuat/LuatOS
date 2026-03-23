#include "luat_base.h"
#include "luat_multimedia_codec.h"
#include "luat_fs.h"
#include "luat_zbuff.h"
#include "luat_mem.h"
#include <string.h>
#define LUAT_LOG_TAG "codec"
#include "luat_log.h"

// WAV 文件解析状态
typedef struct wav_decoder_ctx {
    uint32_t read_len;      // 每次读取的字节数 (align * sample_rate / 8)
    uint8_t bits_per_sample;
    uint8_t num_channels;
    uint32_t sample_rate;
} wav_decoder_ctx_t;

static void* wav_codec_create(luat_multimedia_codec_t* coder) {
    if (!coder->is_decoder) {
        return NULL;  // WAV 只支持解码
    }
    wav_decoder_ctx_t* ctx = luat_heap_malloc(sizeof(wav_decoder_ctx_t));
    if (ctx) {
        memset(ctx, 0, sizeof(wav_decoder_ctx_t));
    }
    return ctx;
}

static void wav_codec_destroy(luat_multimedia_codec_t* coder) {
    if (coder && coder->ctx) {
        luat_heap_free(coder->ctx);
        coder->ctx = NULL;
    }
}

static int wav_codec_get_info(luat_multimedia_codec_t* coder, FILE* fd, audio_info_t* info) {
    if (!fd || !info) return 0;

    uint8_t temp[32];
    uint32_t len;
    uint16_t align;
    int result = 0;

    // 读取 RIFF header
    if (luat_fs_fread(temp, 12, 1, fd) != 12) {
        return 0;
    }

    // 验证 RIFF/WAVE 标识
    if (memcmp(temp, "RIFF", 4) != 0 || memcmp(temp + 8, "WAVE", 4) != 0) {
        LLOGD("head error");
        return 0;
    }

    // 查找 fmt chunk
    if (luat_fs_fread(temp, 8, 1, fd) != 8) {
        return 0;
    }

    if (memcmp(temp, "fmt ", 4) != 0) {
        LLOGD("no fmt");
        return 0;
    }

    // 读取 fmt chunk 数据
    memcpy(&len, temp + 4, 4);
    uint8_t* fmt_data = luat_heap_malloc(len);
    if (!fmt_data) {
        return 0;
    }

    if (luat_fs_fread(fmt_data, len, 1, fd) != len) {
        luat_heap_free(fmt_data);
        return 0;
    }

    // 解析 fmt chunk
    uint16_t audio_format = fmt_data[0] | (fmt_data[1] << 8);
    uint16_t num_channels = fmt_data[2] | (fmt_data[3] << 8);
    uint32_t sample_rate = fmt_data[4] | (fmt_data[5] << 8) | (fmt_data[6] << 16) | (fmt_data[7] << 24);
    uint16_t bits_per_sample = fmt_data[14] | (fmt_data[15] << 8);
    align = fmt_data[12] | (fmt_data[13] << 8);

    luat_heap_free(fmt_data);

    // 保存解码参数到 ctx
    if (coder->ctx) {
        wav_decoder_ctx_t* ctx = (wav_decoder_ctx_t*)coder->ctx;
        ctx->bits_per_sample = bits_per_sample;
        ctx->num_channels = num_channels;
        ctx->sample_rate = sample_rate;
        ctx->read_len = (align * sample_rate >> 3) & ~(3);
        if (ctx->read_len == 0) {
            ctx->read_len = 4096;  // 默认读取大小
        }
    }

    // 查找 data chunk
    while (1) {
        if (luat_fs_fread(temp, 8, 1, fd) != 8) {
            LLOGD("no data");
            return 0;
        }

        if (memcmp(temp, "data", 4) == 0) {
            result = 1;
            break;
        }

        // 跳过其他 chunk
        memcpy(&len, temp + 4, 4);
        if (len > 0) {
            luat_fs_fseek(fd, len, SEEK_CUR);
        }
    }

    if (result) {
        info->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;
        info->num_channels = num_channels;
        info->sample_rate = sample_rate;
        info->bits_per_sample = bits_per_sample;
        info->is_signed = (bits_per_sample > 8) ? 1 : 0;  // 8位WAV是无符号的，其他是有符号的
    }

    return result;
}

static int wav_codec_decode_file_data(luat_multimedia_codec_t* coder, luat_zbuff_t* out_buff, uint32_t mini_output) {
    if (!coder || !coder->ctx || !coder->fd || !out_buff) return 0;

    wav_decoder_ctx_t* ctx = (wav_decoder_ctx_t*)coder->ctx;
    FILE* fd = coder->fd;

    uint32_t read_len = ctx->read_len;
    if (read_len == 0) {
        read_len = 4096;
    }

    // 确保 mini_output 不超过缓冲区大小
    if (mini_output > out_buff->len) {
        mini_output = out_buff->len;
    }

    int ret = 0;
    while (out_buff->used < mini_output) {
        int space = out_buff->len - out_buff->used;
        int to_read = (read_len < space) ? read_len : space;

        int actual_read = luat_fs_fread(out_buff->addr + out_buff->used, to_read, 1, fd);
        if (actual_read > 0) {
            out_buff->used += actual_read;
            ret = 1;
        } else {
            break;
        }
    }

    return ret;
}

const luat_codec_opts_t wav_codec_opts = {
    .create = wav_codec_create,
    .destroy = wav_codec_destroy,
    .get_info = wav_codec_get_info,
    .decode_file_data = wav_codec_decode_file_data,
    .encode = NULL
};