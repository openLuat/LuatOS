#include "luat_base.h"
#include "luat_multimedia.h"
#include "luat_multimedia_codec.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include <stdint.h>

#define LUAT_LOG_TAG "codec_speex"
#include "luat_log.h"

#ifdef LUAT_SUPPORT_SPEEX

#include "speex/speex.h"

/* Speex NB: 8kHz, 160 samples/frame, max encoded ~200 bytes
 * Speex WB: 16kHz, 320 samples/frame, max encoded ~400 bytes
 * Speex UWB: 32kHz, 640 samples/frame, max encoded ~800 bytes */
#define SPEEX_NB_FRAME_SAMPLES   160
#define SPEEX_WB_FRAME_SAMPLES   320
#define SPEEX_UWB_FRAME_SAMPLES  640

#define SPEEX_MAX_ENCODED_SIZE   800  /* UWB worst case */

typedef struct speex_codec_ctx {
    void *state;            /* SpeexEncoderState or SpeexDecoderState */
    SpeexBits bits;         /* bit-stream context */
    uint8_t mode;           /* 0=NB, 1=WB, 2=UWB */
    uint8_t is_decoder;
    uint32_t frame_size;    /* samples per frame (160/320/640) */
    int quality;            /* encode quality 0-10 */
} speex_codec_ctx_t;

static const SpeexMode* speex_get_mode(uint8_t mode) {
    switch (mode) {
        case 0: return &speex_nb_mode;
        case 1: return &speex_wb_mode;
        case 2: return &speex_uwb_mode;
        default: return &speex_nb_mode;
    }
}

static uint32_t speex_get_frame_samples(uint8_t mode) {
    switch (mode) {
        case 0: return SPEEX_NB_FRAME_SAMPLES;
        case 1: return SPEEX_WB_FRAME_SAMPLES;
        case 2: return SPEEX_UWB_FRAME_SAMPLES;
        default: return SPEEX_NB_FRAME_SAMPLES;
    }
}

static uint8_t speex_type_to_mode(uint8_t type) {
    switch (type) {
        case LUAT_MULTIMEDIA_DATA_TYPE_SPEEX_NB:  return 0;
        case LUAT_MULTIMEDIA_DATA_TYPE_SPEEX_WB:  return 1;
        case LUAT_MULTIMEDIA_DATA_TYPE_SPEEX_UWB: return 2;
        default: return 0;
    }
}

static void* speex_codec_create(luat_multimedia_codec_t* coder) {
    if (!coder) return NULL;

    speex_codec_ctx_t* ctx = (speex_codec_ctx_t*)luat_heap_malloc(sizeof(speex_codec_ctx_t));
    if (!ctx) return NULL;
    memset(ctx, 0, sizeof(speex_codec_ctx_t));

    ctx->mode = speex_type_to_mode(coder->type);
    ctx->is_decoder = coder->is_decoder;
    ctx->frame_size = speex_get_frame_samples(ctx->mode);
    ctx->quality = coder->encode_level;
    if (ctx->quality < 0 || ctx->quality > 10) ctx->quality = 8;

    const SpeexMode* spx_mode = speex_get_mode(ctx->mode);

    speex_bits_init(&ctx->bits);

    if (ctx->is_decoder) {
        ctx->state = speex_decoder_init(spx_mode);
        if (!ctx->state) {
            LLOGE("speex_decoder_init failed for mode %d", ctx->mode);
            speex_bits_destroy(&ctx->bits);
            luat_heap_free(ctx);
            return NULL;
        }
        /* Enable perceptual enhancement */
        int enh = 1;
        speex_decoder_ctl(ctx->state, SPEEX_SET_ENH, &enh);
    } else {
        ctx->state = speex_encoder_init(spx_mode);
        if (!ctx->state) {
            LLOGE("speex_encoder_init failed for mode %d", ctx->mode);
            speex_bits_destroy(&ctx->bits);
            luat_heap_free(ctx);
            return NULL;
        }
        /* Set encoding quality */
        speex_encoder_ctl(ctx->state, SPEEX_SET_QUALITY, &ctx->quality);
        /* Set complexity */
        int complexity = 3;
        speex_encoder_ctl(ctx->state, SPEEX_SET_COMPLEXITY, &complexity);
    }

    /* Update coder sample_rate for consistency */
    switch (ctx->mode) {
        case 0: coder->sample_rate = 8000; break;
        case 1: coder->sample_rate = 16000; break;
        case 2: coder->sample_rate = 32000; break;
    }
    coder->num_channels = 1;
    coder->bits_per_sample = 16;

    return ctx;
}

static void speex_codec_destroy(luat_multimedia_codec_t* coder) {
    if (!coder || !coder->ctx) return;

    speex_codec_ctx_t* ctx = (speex_codec_ctx_t*)coder->ctx;

    if (ctx->state) {
        if (ctx->is_decoder) {
            speex_decoder_destroy(ctx->state);
        } else {
            speex_encoder_destroy(ctx->state);
        }
        ctx->state = NULL;
    }

    speex_bits_destroy(&ctx->bits);
    luat_heap_free(ctx);
    coder->ctx = NULL;
}

static int speex_codec_get_info(luat_multimedia_codec_t* coder, FILE* fd) {
    (void)fd;
    if (!coder || !coder->ctx) return 0;

    speex_codec_ctx_t* ctx = (speex_codec_ctx_t*)coder->ctx;

    /* Allocate temp buffer for encoded frame data */
    coder->buff.addr = (uint8_t*)luat_heap_malloc(SPEEX_MAX_ENCODED_SIZE);
    if (!coder->buff.addr) {
        return 0;
    }

    /* Speex decodes to PCM */
    coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;
    coder->num_channels = 1;
    coder->bits_per_sample = 16;
    coder->is_signed = 1;

    switch (ctx->mode) {
        case 0: coder->sample_rate = 8000; break;
        case 1: coder->sample_rate = 16000; break;
        case 2: coder->sample_rate = 32000; break;
    }

    return 1;
}

static int speex_codec_decode_file_data(luat_multimedia_codec_t* coder, luat_zbuff_t* out_buff, uint32_t mini_output) {
    if (!coder || !coder->ctx || !coder->fd || !out_buff || !coder->buff.addr) return 0;

    speex_codec_ctx_t* ctx = (speex_codec_ctx_t*)coder->ctx;
    FILE* fd = coder->fd;
    uint8_t len_bytes[2];
    int decoded_any = 0;

    while (out_buff->used < mini_output) {
        /* Read 2-byte big-endian frame length header */
        size_t read_len = luat_fs_fread(len_bytes, 1, 2, fd);
        if (read_len != 2) break;

        uint16_t frame_len = (uint16_t)((len_bytes[0] << 8) | len_bytes[1]);
        if (frame_len == 0 || frame_len > SPEEX_MAX_ENCODED_SIZE) {
            LLOGE("speex frame too large or zero: %u", frame_len);
            break;
        }

        /* Read encoded frame data */
        size_t bytes = luat_fs_fread(coder->buff.addr, 1, frame_len, fd);
        if (bytes != frame_len) {
            LLOGE("speex read frame data failed: %u/%u", (unsigned int)bytes, frame_len);
            break;
        }

        /* Check output buffer space */
        uint32_t pcm_bytes = ctx->frame_size * sizeof(spx_int16_t);
        if ((out_buff->len - out_buff->used) < pcm_bytes) break;

        /* Decode */
        speex_bits_read_from(&ctx->bits, (const char*)coder->buff.addr, (int)frame_len);
        int ret = speex_decode_int(ctx->state, &ctx->bits,
                                   (spx_int16_t*)(out_buff->addr + out_buff->used));
        if (ret != 0) {
            LLOGE("speex_decode_int failed: %d", ret);
            break;
        }

        out_buff->used += pcm_bytes;
        decoded_any = 1;
    }

    return decoded_any;
}

static int speex_codec_encode(luat_multimedia_codec_t* coder, luat_zbuff_t* in_buff, luat_zbuff_t* out_buff, int mode) {
    (void)mode;
    if (!coder || !coder->ctx || !in_buff || !out_buff) return -1;

    speex_codec_ctx_t* ctx = (speex_codec_ctx_t*)coder->ctx;
    if (ctx->is_decoder) return -1;

    spx_int16_t *pcm = (spx_int16_t *)in_buff->addr;
    uint32_t pcm_samples = in_buff->used >> 1;  /* bytes to samples */
    uint32_t done_samples = 0;
    char encoded_buf[SPEEX_MAX_ENCODED_SIZE];

    while ((pcm_samples - done_samples) >= ctx->frame_size) {
        /* Reset bits for new frame */
        speex_bits_reset(&ctx->bits);

        /* Encode one frame */
        int ret = speex_encode_int(ctx->state, pcm + done_samples, &ctx->bits);
        if (ret < 0) {
            LLOGE("speex_encode_int failed: %d", ret);
            break;
        }

        /* Write encoded data to temp buffer */
        int nb_bytes = speex_bits_write(&ctx->bits, encoded_buf, SPEEX_MAX_ENCODED_SIZE);
        if (nb_bytes <= 0) {
            LLOGE("speex_bits_write failed: %d", nb_bytes);
            break;
        }

        /* Output: 2-byte big-endian length + encoded data */
        uint32_t total_out = 2 + (uint32_t)nb_bytes;
        if ((out_buff->len - out_buff->used) < total_out) {
            /* Try to resize */
            if (__zbuff_resize(out_buff, out_buff->len * 2 + total_out)) {
                LLOGE("speex encode out_buff resize failed");
                break;
            }
        }

        uint8_t* out_ptr = out_buff->addr + out_buff->used;
        out_ptr[0] = (uint8_t)((nb_bytes >> 8) & 0xFF);
        out_ptr[1] = (uint8_t)(nb_bytes & 0xFF);
        memcpy(out_ptr + 2, encoded_buf, nb_bytes);
        out_buff->used += total_out;

        done_samples += ctx->frame_size;
    }

    return 1;
}

const luat_codec_opts_t speex_codec_opts = {
    .create = speex_codec_create,
    .destroy = speex_codec_destroy,
    .get_info = speex_codec_get_info,
    .decode_file_data = speex_codec_decode_file_data,
    .encode = speex_codec_encode
};

#endif /* LUAT_SUPPORT_SPEEX */
