#include "luat_base.h"
#include "luat_multimedia.h"
#include "luat_multimedia_codec.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include <stdint.h>

#define LUAT_LOG_TAG "codec_opus"
#include "luat_log.h"

#ifdef LUAT_SUPPORT_OPUS

#include "opus.h"
#include "opus_types.h"
#include "opus_private.h"
//#include "opus_multistream.h"
#include "opus_defines.h"

#define DELAY_SAMPLES 60
#define APPLICATION OPUS_APPLICATION_AUDIO
#define BITRATE 64000

#define MAX_PACKET_SIZE (3*1276)

int luat_opus_decoder_create(luat_multimedia_codec_t *coder){
    int error;
    coder->ctx = opus_decoder_create(coder->sample_rate, coder->num_channels, &error);
    if (!coder->ctx || error != OPUS_OK){
        LLOGE("opus_decoder_create failed: %d", error);
        coder->ctx = NULL;
        return -1;
    }
    return 0;
}

void luat_opus_decoder_destroy(luat_multimedia_codec_t *coder){
    if (coder->ctx) {
        opus_decoder_destroy(coder->ctx);
        coder->ctx = NULL;
    }
}

int luat_opus_decoder_get_data(luat_multimedia_codec_t *coder, const uint8_t* input, uint32_t len,
                                int16_t* pcm, uint32_t* out_len, uint32_t* used){
    if (!coder->ctx || !input || !pcm || !out_len || !used) return -1;
    int frame_size = opus_decode(coder->ctx, input, (opus_int32)len, pcm, (coder->sample_rate*DELAY_SAMPLES/1000), 0);
    // LLOGD("raw opus_decode returned frame_size=%d", frame_size);
    if (frame_size <= 0){
        LLOGE("opus_decode failed: %d", frame_size);
        return -1;
    }
    *out_len = (size_t)frame_size * coder->num_channels * sizeof(opus_int16);
    return 0;
}


int luat_opus_encoder_create(luat_multimedia_codec_t *coder){
    int error;
    coder->ctx = opus_encoder_create(coder->sample_rate, coder->num_channels, APPLICATION, &error);
    if (!coder->ctx || error != OPUS_OK){
        LLOGE("opus_encoder_create failed: %d", error);
        coder->ctx = NULL;
        return -1;
    }
    opus_encoder_ctl(coder->ctx, OPUS_SET_BITRATE(BITRATE));
    return 0;
}

void luat_opus_encoder_destroy(luat_multimedia_codec_t *coder){
    if (coder->ctx) {
        opus_encoder_destroy(coder->ctx);
        coder->ctx = NULL;
    }
}

int luat_opus_encoder_get_data(luat_multimedia_codec_t *coder, const int16_t* pcm, uint32_t len,
                                uint8_t* output, uint32_t* out_len){
    if (!coder->ctx || !pcm || !output || !out_len) return -1;
    unsigned char cbits[MAX_PACKET_SIZE];
    uint32_t frame_size = coder->sample_rate*DELAY_SAMPLES/1000;
    if (len < frame_size) return -1;

    int nbBytes = opus_encode(coder->ctx, pcm, frame_size, cbits, MAX_PACKET_SIZE);
    // LLOGD("raw opus_encode returned nbBytes=%d", nbBytes);
    if (nbBytes < 0){ LLOGE("opus_encode failed: %d", nbBytes); return -1; }
    // Write packet length (2 bytes, big-endian)
    uint16_t len_l = (uint16_t)nbBytes;
    uint8_t len_bytes[2];
    len_bytes[0] = (len_l >> 8) & 0xFF;
    len_bytes[1] = len_l & 0xFF;
    // LLOGD("nbBytes=%d, len=%u, len_bytes[0]=%d, len_bytes[1]=%d", nbBytes, len, len_bytes[0], len_bytes[1]);
    memcpy(output, len_bytes, 2);
    *out_len += 2;
    memcpy(output + 2, cbits, nbBytes);
    *out_len += nbBytes;
    return 0;
}

static void* opus_codec_create(luat_multimedia_codec_t* coder) {
    if (coder->is_decoder) {
        if (luat_opus_decoder_create(coder) != 0) {
            return NULL;
        }
    } else {
        if (luat_opus_encoder_create(coder) != 0) {
            return NULL;
        }
    }
    return coder->ctx;
}

static void opus_codec_destroy(luat_multimedia_codec_t* coder) {
    if (!coder) return;

    if (coder->is_decoder) {
        luat_opus_decoder_destroy(coder);
    } else {
        luat_opus_encoder_destroy(coder);
    }
}

static int opus_codec_get_info(luat_multimedia_codec_t* coder, FILE* fd) {
    (void)fd;

    if (!coder) return 0;

    // OPUS 不定长,分配最大packet size
    coder->buff.addr = luat_heap_malloc(MAX_PACKET_SIZE);
    if (!coder->buff.addr) {
        return 0;
    }

    coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;

    return 1;
}

static int opus_codec_decode_file_data(luat_multimedia_codec_t* coder, luat_zbuff_t* out_buff, uint32_t mini_output) {
    (void)mini_output;
    if (!coder || !coder->ctx || !coder->fd || !out_buff || !coder->buff.addr) return 0;

    FILE* fd = coder->fd;
    uint8_t len_bytes[2];

    size_t read_len = luat_fs_fread(len_bytes, 1, 2, fd);
    if (read_len != 2) return 0;

    uint16_t len = (len_bytes[0] << 8) | len_bytes[1];
    // LLOGD("len_bytes[0]=%d, len_bytes[1]=%d, len=%u", len_bytes[0], len_bytes[1], len);
    if (len > MAX_PACKET_SIZE) {
        LLOGE("packet too large: %u", len);
        return 0;
    }

    // Read packet data
    size_t bytes = luat_fs_fread(coder->buff.addr, 1, len, fd);
    if (bytes != len) {
        LLOGE("read packet data failed: %u/%u", (unsigned int)bytes, len);
        return 0;
    }

    uint32_t out_len = 0;
    uint32_t used = 0;
    int ret = luat_opus_decoder_get_data(coder, coder->buff.addr, len,
                                          (int16_t*)(out_buff->addr + out_buff->used),
                                          &out_len, &used);
    if (ret == 0) {
        out_buff->used += out_len;
        return 1;
    }

    return 0;
}

static int opus_codec_encode(luat_multimedia_codec_t* coder, luat_zbuff_t* in_buff, luat_zbuff_t* out_buff, int mode) {
    (void)mode;
    if (!coder || !coder->ctx || !in_buff || !out_buff) return -1;

    int16_t *pcm = (int16_t *)in_buff->addr;
    uint32_t pcm_len = in_buff->used >> 1;
    uint32_t done_len = 0;
    uint32_t frame_size = coder->sample_rate * DELAY_SAMPLES / 1000;
    while (pcm_len >= frame_size) {
        uint32_t out_len = 0;
        int ret = luat_opus_encoder_get_data(coder, pcm + done_len, frame_size, out_buff->addr + out_buff->used, &out_len);
        if (ret) {
            break;
        }
        out_buff->used += out_len;
        pcm_len -= frame_size;
        done_len += frame_size;
    }

    return 1;
}

const luat_codec_opts_t opus_codec_opts = {
    .create = opus_codec_create,
    .destroy = opus_codec_destroy,
    .get_info = opus_codec_get_info,
    .decode_file_data = opus_codec_decode_file_data,
    .encode = opus_codec_encode
};

#endif