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
    void* coder;
} amr_codec_ctx_t;

typedef void (*amr_decode_fun_t)(void* state, const unsigned char* in, short* out, int bfi);

static void* amr_codec_create(luat_multimedia_codec_t* coder) {
    amr_codec_ctx_t* ctx = (amr_codec_ctx_t*)luat_heap_malloc(sizeof(amr_codec_ctx_t));
    if (!ctx) return NULL;

    memset(ctx, 0, sizeof(amr_codec_ctx_t));
    ctx->type = coder->type;

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

    luat_heap_free(coder->ctx);
    coder->ctx = NULL;
}

static int amr_codec_get_info(luat_multimedia_codec_t* coder, FILE* fd) {
    if (!coder || !coder->ctx || !fd) return 0;

    amr_codec_ctx_t* amr_ctx = (amr_codec_ctx_t*)coder->ctx;
    uint8_t temp[16];

    if (amr_ctx->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB) {
        if (luat_fs_fread(temp, 9, 1, fd) != 9 || memcmp(temp, "#!AMR-WB\n", 9) != 0) {
            return 0;
        }
        coder->buff.addr = luat_heap_malloc(640);
        if (!coder->buff.addr) {
            return 0;
        }
        coder->sample_rate = 16000;
        coder->num_channels = 1;
        coder->bits_per_sample = 16;
        coder->is_signed = 1;
        coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;
        return 1;
    } else {
        if (luat_fs_fread(temp, 6, 1, fd) != 6 || memcmp(temp, "#!AMR\n", 6) != 0) {
            return 0;
        }
        coder->buff.addr = luat_heap_malloc(320);
        if (!coder->buff.addr) {
            return 0;
        }
        coder->sample_rate = 8000;
        coder->num_channels = 1;
        coder->bits_per_sample = 16;
        coder->is_signed = 1;
        coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;
        return 1;
    }
}

static int amr_codec_decode_file_data(luat_multimedia_codec_t* coder, luat_zbuff_t* out_buff, uint32_t mini_output) {
    if (!coder || !coder->ctx || !coder->fd || !out_buff) return 0;

    amr_codec_ctx_t* amr_ctx = (amr_codec_ctx_t*)coder->ctx;
    FILE* fd = coder->fd;

    uint32_t frame_len;
    const uint8_t* size_table;
    amr_decode_fun_t decode_if;
    uint8_t temp[64];
    uint8_t size;
    int read_len;
    uint32_t is_not_end = 1;
    int result = 0;

    if (amr_ctx->type == LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB) {
        frame_len = 320;
        size_table = amr_nb_byte_len;
        decode_if = Decoder_Interface_Decode;
    } else {
        frame_len = 640;
        size_table = amr_wb_byte_len;
        decode_if = D_IF_decode;
    }

    while ((out_buff->used < mini_output) && is_not_end && ((out_buff->len - out_buff->used) >= frame_len)) {
        read_len = luat_fs_fread(temp, 1, 1, fd);
        if (read_len <= 0) {
            is_not_end = 0;
            break;
        }

        size = size_table[(temp[0] >> 3) & 0x0f];
        if (size > 0) {
            read_len = luat_fs_fread(temp + 1, 1, size, fd);
            if (read_len <= 0) {
                is_not_end = 0;
                break;
            }
        }

        decode_if(amr_ctx->coder, temp, (short*)coder->buff.addr, 0);
        memcpy(out_buff->addr + out_buff->used, coder->buff.addr, frame_len);
        out_buff->used += frame_len;
    }

    result = 1;
    return result;
}

static int amr_codec_encode(luat_multimedia_codec_t* coder, luat_zbuff_t* in_buff, luat_zbuff_t* out_buff, int mode) {
    if (!coder || !coder->ctx || !in_buff || !out_buff) return -1;

    amr_codec_ctx_t* amr_ctx = (amr_codec_ctx_t*)coder->ctx;

    if (!amr_ctx || !amr_ctx->coder || coder->is_decoder) return -1;

#ifdef LUAT_USE_INTER_AMR
    // AMR编码处理
    uint8_t outbuf[128];
    int16_t *pcm = (int16_t *)in_buff->addr;
    uint32_t total_len = in_buff->used >> 1;
    uint32_t done_len = 0;
    uint32_t pcm_len = (amr_ctx->type - LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB + 1) * 160;
    uint8_t out_len;

    while ((total_len - done_len) >= pcm_len)
    {
        luat_audio_inter_amr_coder_encode(amr_ctx->coder, &pcm[done_len], outbuf, &out_len);
        if (out_len <= 0)
        {
            LLOGE("encode error in %d,result %d", done_len, out_len);
        }
        else
        {
            if ((out_buff->len - out_buff->used) < out_len)
            {
                if (__zbuff_resize(out_buff, out_buff->len * 2 + out_len))
                {
                    return -1;
                }
            }
            memcpy(out_buff->addr + out_buff->used, outbuf, out_len);
            out_buff->used += out_len;
        }
        done_len += pcm_len;
    }
    return 1;
#else
    if (mode > MR122)
    {
        mode = MR475;
    }
    uint8_t outbuf[64];
    int16_t *pcm = (int16_t *)in_buff->addr;
    uint32_t total_len = in_buff->used >> 1;
    uint32_t done_len = 0;
    int out_len;
    while ((total_len - done_len) >= 160)
    {
        out_len = Encoder_Interface_Encode(amr_ctx->coder, mode, &pcm[done_len], outbuf, 0);
        if (out_len <= 0)
        {
            LLOGE("encode error in %d,result %d", done_len, out_len);
        }
        else
        {
            if ((out_buff->len - out_buff->used) < out_len)
            {
                if (__zbuff_resize(out_buff, out_buff->len * 2 + out_len))
                {
                    return -1;
                }
            }
            memcpy(out_buff->addr + out_buff->used, outbuf, out_len);
            out_buff->used += out_len;
        }
        done_len += 160;
    }
    return 1;
#endif
}

const luat_codec_opts_t amr_codec_opts = {
    .create = amr_codec_create,
    .destroy = amr_codec_destroy,
    .get_info = amr_codec_get_info,
    .decode_file_data = amr_codec_decode_file_data,
    .encode = amr_codec_encode
};