#include "luat_conf_bsp.h"
#ifdef LUAT_SUPPORT_G722
/*
 * G.722 legacy codec-module port: pure software encode/decode without audio
 * hardware, for VoIP/RTP style usage. Wideband 16kHz/mono/16-bit PCM.
 * Stream codec without frame headers: 2 PCM samples (4 bytes) map to 1 byte
 * of bitstream at all three rates. Frame convention is 20 ms:
 * 640 bytes PCM <-> 160 bytes bitstream (64kbps).
 *
 * encode_level (3rd argument of codec.create) selects the bit rate:
 *   0 = 64000 bps (default), 1 = 56000 bps, 2 = 48000 bps
 */
#include "luat_base.h"
#include "luat_multimedia_codec.h"
#include "luat_fs.h"
#include "luat_zbuff.h"
#include "luat_mem.h"
#include "g722_codec.h"

#define LUAT_LOG_TAG "g722"
#include "luat_log.h"

#define G722_PCM_FRAME_BYTES    640 /* 320 samples * 2 bytes, 20ms @16kHz */
#define G722_BITSTREAM_BYTES    160 /* 64kbps: 8000字节/秒 * 20ms */
#define G722_DECODE_CHUNK       1024 /* 一次从文件读的码流字节数, 对应4KB PCM */

static int g722_rate_from_level(int level) {
    switch (level) {
    case 1: return 56000;
    case 2: return 48000;
    default: return 64000;
    }
}

static void* g722_codec_create(luat_multimedia_codec_t* coder) {
    int rate = g722_rate_from_level(coder->encode_level);
    if (coder->is_decoder) {
        return g722_decoder_new(rate, 0);
    }
    return g722_encoder_new(rate, 0);
}

static void g722_codec_destroy(luat_multimedia_codec_t* coder) {
    if (!coder || !coder->ctx) return;
    if (coder->is_decoder) {
        g722_decoder_destroy((G722_DEC_CTX*)coder->ctx);
    } else {
        g722_encoder_destroy((G722_ENC_CTX*)coder->ctx);
    }
    coder->ctx = NULL;
}

static int g722_codec_get_info(luat_multimedia_codec_t* coder, FILE* fd) {
    (void)fd;

    // G.722固定参数：16kHz采样率, 单声道, 解码输出16位PCM
    coder->sample_rate = 16000;
    coder->num_channels = 1;
    coder->bits_per_sample = 16;
    coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;

    return 1;
}

static int g722_codec_decode_file_data(luat_multimedia_codec_t* coder, luat_zbuff_t* out_buff, uint32_t mini_output) {
    if (!coder || !coder->ctx || !coder->fd || !out_buff) return 0;

    (void)mini_output;  // 按输出空间决定本次解码量

    FILE* fd = coder->fd;

    if (!coder->buff.addr) {
        coder->buff.addr = luat_heap_malloc(G722_DECODE_CHUNK);
        if (!coder->buff.addr) return 0;
        coder->buff.len = G722_DECODE_CHUNK;
        coder->buff.used = 0;
    }

    // 每字节码流产生2个采样(4字节PCM), 按输出空间截断本次读取量
    uint32_t room_pcm = out_buff->len - out_buff->used;
    uint32_t want = room_pcm / 4;
    if (want == 0) {
        return (out_buff->used > 0) ? 1 : 0;
    }
    if (want > G722_DECODE_CHUNK) want = G722_DECODE_CHUNK;

    // fread按字节计数, 支持跨调用续读
    if (coder->buff.used < want) {
        coder->buff.used += luat_fs_fread(coder->buff.addr + coder->buff.used, 1, want - coder->buff.used, fd);
    }
    if (coder->buff.used == 0) return 0;    // EOF

    int samples = g722_decode((G722_DEC_CTX*)coder->ctx, coder->buff.addr, coder->buff.used,
                              (int16_t*)(out_buff->addr + out_buff->used));
    if (samples > 0) {
        out_buff->used += samples * 2;
    }
    coder->buff.used = 0;

    return (out_buff->used > 0) ? 1 : 0;
}

static int g722_codec_encode(luat_multimedia_codec_t* coder, luat_zbuff_t* in_buff, luat_zbuff_t* out_buff, int mode) {
    (void)mode;
    if (!coder || !coder->ctx || !in_buff || !out_buff) return -1;

    const uint8_t *pcm = in_buff->addr;
    uint32_t total_len = in_buff->used;
    uint32_t samples = total_len / 2;
    uint32_t even_samples = samples & ~1U;
    // 每对采样输出1字节; 奇数尾采样补零后再编一对
    uint32_t need = even_samples / 2 + (samples & 1U ? 1 : 0);
    if (need == 0) return 1;

    if ((out_buff->len - out_buff->used) < need) {
        if (__zbuff_resize(out_buff, out_buff->len * 2 + need)) {
            return -1;
        }
    }

    if (even_samples > 0) {
        int produced = g722_encode((G722_ENC_CTX*)coder->ctx, (const int16_t*)pcm, even_samples,
                                   out_buff->addr + out_buff->used);
        if (produced < 0) return -1;
        out_buff->used += produced;
    }

    // 奇数尾采样补零（与g729 port的零填充行为一致）;
    // 上游16k模式按采样对处理, 直接传奇数长度会越界读
    if (samples & 1U) {
        int16_t tail[2];
        tail[0] = (int16_t)((uint16_t)pcm[even_samples * 2] | ((uint16_t)pcm[even_samples * 2 + 1] << 8));
        tail[1] = 0;
        int produced = g722_encode((G722_ENC_CTX*)coder->ctx, tail, 2,
                                   out_buff->addr + out_buff->used);
        if (produced < 0) return -1;
        out_buff->used += produced;
    }

    return 1;
}

const luat_codec_opts_t g722_codec_opts = {
    .create = g722_codec_create,
    .destroy = g722_codec_destroy,
    .get_info = g722_codec_get_info,
    .decode_file_data = g722_codec_decode_file_data,
    .encode = g722_codec_encode
};
#endif
