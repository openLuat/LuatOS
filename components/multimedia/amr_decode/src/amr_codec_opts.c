#include "luat_base.h"
#include "luat_multimedia_codec.h"
#include "luat_fs.h"
#include "luat_zbuff.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "amr"
#include "luat_log.h"

#include "interf_dec.h"
#include "interf_enc.h"
#include "dec_if.h"

#ifdef LUAT_USE_INTER_AMR
extern void* luat_audio_inter_amr_coder_init(int is_wb, int quality);
extern void luat_audio_inter_amr_coder_deinit(void* handler);
extern int luat_audio_inter_amr_coder_encode(void* handler, const short* pcm, uint8_t* out, uint8_t* out_len);
#endif

static const uint8_t amr_nb_byte_len[16] = {12, 13, 15, 17, 19, 20, 26, 31, 5, 0, 0, 0, 0, 0, 0, 0};
static const uint8_t amr_wb_byte_len[16] = {17, 23, 32, 36, 40, 46, 50, 58, 60, 5, 0, 0, 0, 0, 0, 0};

typedef struct amr_codec_ctx {
    uint8_t type;
    uint8_t is_decoder;
    void* coder;
    uint8_t* buffer;
    uint32_t buffer_size;
} amr_codec_ctx_t;

static void* amr_codec_create(luat_multimedia_codec_t* coder) {
    if (coder->type != LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB && coder->type != LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB) {
        return NULL;
    }

    amr_codec_ctx_t* ctx = (amr_codec_ctx_t*)luat_heap_malloc(sizeof(amr_codec_ctx_t));
    if (!ctx) return NULL;

    memset(ctx, 0, sizeof(amr_codec_ctx_t));
    ctx->type = coder->type;
    ctx->is_decoder = coder->is_decoder;

    if (coder->is_decoder) {
        if (coder->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB) {
            ctx->coder = Decoder_Interface_init();
        } else {
            ctx->coder = D_IF_init();
        }
    } else {
#ifdef LUAT_USE_INTER_AMR
        int is_wb = (coder->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB) ? 1 : 0;
        ctx->coder = luat_audio_inter_amr_coder_init(is_wb, coder->encode_level);
#else
        if (coder->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB) {
            ctx->coder = Encoder_Interface_init(0);
        } else {
            luat_heap_free(ctx);
            return NULL;
        }
#endif
    }

    if (!ctx->coder) {
        luat_heap_free(ctx);
        return NULL;
    }

    return ctx;
}

static void amr_codec_destroy(luat_multimedia_codec_t* coder) {
    if (!coder || !coder->ctx) return;

    amr_codec_ctx_t* amr_ctx = (amr_codec_ctx_t*)coder->ctx;

    if (amr_ctx->coder) {
        if (coder->is_decoder) {
            if (amr_ctx->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB) {
                Decoder_Interface_exit(amr_ctx->coder);
            } else {
                D_IF_exit(amr_ctx->coder);
            }
        } else {
#ifdef LUAT_USE_INTER_AMR
            luat_audio_inter_amr_coder_deinit(amr_ctx->coder);
#else
            if (amr_ctx->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB) {
                Encoder_Interface_exit(amr_ctx->coder);
            }
#endif
        }
    }

    if (amr_ctx->buffer) {
        luat_heap_free(amr_ctx->buffer);
    }

    luat_heap_free(coder->ctx);
    coder->ctx = NULL;
}

static int amr_codec_get_info(luat_multimedia_codec_t* coder, FILE* fd, audio_info_t* info) {
    if (!coder || !coder->ctx || !fd || !info) return 0;

    amr_codec_ctx_t* amr_ctx = (amr_codec_ctx_t*)coder->ctx;
    uint8_t temp[16];
    size_t read;

    if (amr_ctx->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB) {
        read = luat_fs_fread(temp, 9, 1, fd);
        if (read != 9 || memcmp(temp, "#!AMR-WB\n", 9) != 0) {
            return 0;
        }
        info->sample_rate = 16000;
        info->num_channels = 1;
        info->bits_per_sample = 16;
        info->is_signed = 1;
        info->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;
        return 1;
    } else {
        read = luat_fs_fread(temp, 6, 1, fd);
        if (read != 6 || memcmp(temp, "#!AMR\n", 6) != 0) {
            return 0;
        }
        info->sample_rate = 8000;
        info->num_channels = 1;
        info->bits_per_sample = 16;
        info->is_signed = 1;
        info->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;
        return 1;
    }
}

static int amr_codec_decode_file_data(luat_multimedia_codec_t* coder, luat_zbuff_t* out_buff, uint32_t mini_output) {
    if (!coder || !coder->ctx || !coder->fd || !out_buff) return 0;

    amr_codec_ctx_t* amr_ctx = (amr_codec_ctx_t*)coder->ctx;
    FILE* fd = coder->fd;

    uint32_t pcm_frame_size = (amr_ctx->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB) ? 320 : 640;
    const uint8_t* frame_len_table = (amr_ctx->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB) ? amr_nb_byte_len : amr_wb_byte_len;

    if (!amr_ctx->buffer) {
        amr_ctx->buffer = (uint8_t*)luat_heap_malloc(pcm_frame_size);
        if (!amr_ctx->buffer) return 0;
        amr_ctx->buffer_size = pcm_frame_size;
    }

    uint8_t temp[64];
    uint8_t size;
    int read_len;
    uint32_t is_not_end = 1;

    while ((out_buff->used < mini_output) && is_not_end && ((out_buff->len - out_buff->used) >= pcm_frame_size)) {
        read_len = luat_fs_fread(temp, 1, 1, fd);
        if (read_len <= 0) {
            is_not_end = 0;
            break;
        }

        size = frame_len_table[(temp[0] >> 3) & 0x0f];
        if (size > 0) {
            read_len = luat_fs_fread(temp + 1, 1, size, fd);
            if (read_len <= 0) {
                is_not_end = 0;
                break;
            }
        }

        if (amr_ctx->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB) {
            Decoder_Interface_Decode(amr_ctx->coder, temp, (short*)amr_ctx->buffer, 0);
        } else {
            D_IF_decode(amr_ctx->coder, temp, (short*)amr_ctx->buffer, 0);
        }

        memcpy(out_buff->addr + out_buff->used, amr_ctx->buffer, pcm_frame_size);
        out_buff->used += pcm_frame_size;
    }

    return (out_buff->used > 0) ? 1 : 0;
}

static int amr_codec_encode(luat_multimedia_codec_t* coder, luat_zbuff_t* in_buff, luat_zbuff_t* out_buff, int mode) {
    if (!coder || !coder->ctx || !in_buff || !out_buff) return -1;

    amr_codec_ctx_t* amr_ctx = (amr_codec_ctx_t*)coder->ctx;

    if (amr_ctx->is_decoder || !amr_ctx->coder) return -1;

    int16_t *pcm = (int16_t *)in_buff->addr;
    uint32_t total_len = in_buff->used >> 1;
    uint32_t done_len = 0;

#ifdef LUAT_USE_INTER_AMR
    uint32_t frame_size = (amr_ctx->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB) ? 160 : 320;
#else
    uint32_t frame_size = 160;
    if (mode > MR122) {
        mode = MR475;
    }
#endif

    while ((total_len - done_len) >= frame_size) {
        uint8_t outbuf[128];
        uint8_t out_len = 0;

#ifdef LUAT_USE_INTER_AMR
        luat_audio_inter_amr_coder_encode(amr_ctx->coder, &pcm[done_len], outbuf, &out_len);
#else
        if (amr_ctx->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB) {
            int ret = Encoder_Interface_Encode(amr_ctx->coder, mode, &pcm[done_len], outbuf, 0);
            out_len = (ret > 0) ? ret : 0;
        }
#endif

        if (out_len <= 0) {
            LLOGE("encode error in %d,result %d", done_len, out_len);
        } else {
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

    return (out_buff->used > 0) ? 1 : -1;
}

const luat_codec_opts_t amr_codec_opts = {
    .create = amr_codec_create,
    .destroy = amr_codec_destroy,
    .get_info = amr_codec_get_info,
    .decode_file_data = amr_codec_decode_file_data,
    .encode = amr_codec_encode
};