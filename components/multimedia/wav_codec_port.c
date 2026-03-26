#include "luat_base.h"
#include "luat_multimedia_codec.h"
#include "luat_fs.h"
#include "luat_zbuff.h"
#include "luat_mem.h"
#include <string.h>
#define LUAT_LOG_TAG "codec"
#include "luat_log.h"

typedef struct wav_decoder_ctx {
    uint32_t read_len;
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

static int wav_codec_get_info(luat_multimedia_codec_t* coder, FILE* fd) {
    if (!coder || !fd) return 0;

    uint8_t temp[32];
    uint32_t len;
    uint16_t align;
    int result = 0;

    // 读取 RIFF header
    luat_fs_fread(temp, 12, 1, fd);

    // 验证 RIFF/WAVE 标识
    if (!memcmp(temp, "RIFF", 4) || !memcmp(temp + 8, "WAVE", 4)) {
        luat_fs_fread(temp, 8, 1, fd);
        if (!memcmp(temp, "fmt ", 4)) {
            memcpy(&len, temp + 4, 4);
            coder->buff.addr = luat_heap_malloc(len);
            luat_fs_fread(coder->buff.addr, len, 1, fd);
            coder->audio_format = coder->buff.addr[0];
            coder->num_channels = coder->buff.addr[2];
            memcpy(&coder->sample_rate, coder->buff.addr + 4, 4);
            align = coder->buff.addr[12];
            coder->bits_per_sample = coder->buff.addr[14];
            wav_decoder_ctx_t* ctx = (wav_decoder_ctx_t*)coder->ctx;
            ctx->read_len = (align * coder->sample_rate >> 3) & ~(3);
            luat_heap_free(coder->buff.addr);
            coder->buff.addr = NULL;
            luat_fs_fread(temp, 8, 1, fd);
            if (!memcmp(temp, "fact", 4)) {
                memcpy(&len, temp + 4, 4);
                luat_fs_fseek(fd, len, SEEK_CUR);
                luat_fs_fread(temp, 8, 1, fd);
            }
            if (!memcmp(temp, "data", 4)) {
                result = 1;
            } else {
                LLOGD("no data");
                result = 0;
            }
        } else {
            LLOGD("no fmt");
        }
    } else {
        LLOGD("head error");
    }

    return result;
}

static int wav_codec_decode_file_data(luat_multimedia_codec_t* coder, luat_zbuff_t* out_buff, uint32_t mini_output) {
    if (!coder || !coder->ctx || !coder->fd || !out_buff) return 0;

    (void)mini_output;

    wav_decoder_ctx_t* ctx = (wav_decoder_ctx_t*)coder->ctx;
    int read_len = luat_fs_fread(out_buff->addr + out_buff->used, ctx->read_len, 1, coder->fd);
    if (read_len > 0) {
        out_buff->used += read_len;
        return 1;
    }
    return 0;
}

const luat_codec_opts_t wav_codec_opts = {
    .create = wav_codec_create,
    .destroy = wav_codec_destroy,
    .get_info = wav_codec_get_info,
    .decode_file_data = wav_codec_decode_file_data,
    .encode = NULL
};