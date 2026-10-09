#include "luat_conf_bsp.h"
#ifdef LUAT_SUPPORT_G729
/*
 * G.729A/Annex B legacy codec-module port: pure software encode/decode without
 * audio hardware, for VoIP/RTP style usage. 160 bytes PCM (80 samples, 10 ms)
 * per frame encode side. Bitstream frame is variable length when Annex B
 * VAD/DTX is enabled: 10 bytes voice / 2 bytes SID / 0 bytes not-transmitted.
 *
 * encode_level (3rd argument of codec.create) selects the mode:
 *   encoder: 0 = Annex A only (always 10-byte frames), 1 = Annex B VAD/DTX on
 *   decoder: 0 = raw 10-byte frames, 1 = length-prefixed container
 *            (1 byte length + payload per frame, as written by the upstream
 *            coder demo tool with VAD on)
 */
#include "luat_base.h"
#include "luat_multimedia_codec.h"
#include "luat_fs.h"
#include "luat_zbuff.h"
#include "luat_mem.h"
#include "g729a_interface.h"

#define LUAT_LOG_TAG "g729"
#include "luat_log.h"

#define G729_PCM_FRAME_BYTES    160 /* 80 samples * 2 bytes */
#define G729_BITSTREAM_BYTES    10  /* max frame: voice; SID is 2, NO_DATA 0 */

static void* g729_codec_create(luat_multimedia_codec_t* coder) {
    void *state;
    if (coder->is_decoder) {
        state = luat_heap_malloc(G729A_Decoder_Get_Size());
        if (!state) return NULL;
        if (G729A_Decoder_Init(state) != G729A_NO_ERROR) {
            luat_heap_free(state);
            return NULL;
        }
    } else {
        state = luat_heap_malloc(G729A_Encoder_Get_Size());
        if (!state) return NULL;
        if (G729A_Encoder_Init(state) != G729A_NO_ERROR) {
            luat_heap_free(state);
            return NULL;
        }
        if (coder->encode_level) {
            G729A_Encoder_Set_Vad(state, 1);
        }
    }
    return state;
}

static void g729_codec_destroy(luat_multimedia_codec_t* coder) {
    if (!coder || !coder->ctx) return;
    luat_heap_free(coder->ctx);
    coder->ctx = NULL;
}

static int g729_codec_get_info(luat_multimedia_codec_t* coder, FILE* fd) {
    (void)fd;

    // G.729A固定参数：8kHz采样率, 单声道, 解码输出16位PCM
    coder->sample_rate = 8000;
    coder->num_channels = 1;
    coder->bits_per_sample = 16;
    coder->audio_format = LUAT_MULTIMEDIA_DATA_TYPE_PCM;

    return 1;
}

static int g729_codec_decode_file_data(luat_multimedia_codec_t* coder, luat_zbuff_t* out_buff, uint32_t mini_output) {
    if (!coder || !coder->ctx || !coder->fd || !out_buff) return 0;

    (void)mini_output;  // G.729每次只解码一帧(最多10字节码流 -> 160字节PCM)

    FILE* fd = coder->fd;

    if (coder->encode_level) {
        // Annex B 容器模式: 每帧 = 1字节长度前缀 + 负载(长度0/2/10)
        if (!coder->buff.addr) {
            coder->buff.addr = luat_heap_malloc(G729_BITSTREAM_BYTES + 1);
            if (!coder->buff.addr) return 0;
            coder->buff.len = G729_BITSTREAM_BYTES + 1;
            coder->buff.used = 0;
        }
        uint8_t *rec = coder->buff.addr;

        // 先读到长度前缀
        if (coder->buff.used == 0) {
            coder->buff.used += luat_fs_fread(rec, 1, 1, fd);
            if (coder->buff.used == 0) return 0;    // EOF
        }
        if (rec[0] > G729_BITSTREAM_BYTES) {
            // 损坏的流: 丢弃该记录, 让上层终止
            LLOGE("g729 container: bad frame length %d, abort", rec[0]);
            coder->buff.used = 0;
            return 0;
        }

        // 再读满负载(fread按字节计数, 支持跨调用续读)
        uint32_t need = 1 + rec[0];
        if (coder->buff.used < need) {
            coder->buff.used += luat_fs_fread(rec + coder->buff.used, 1, need - coder->buff.used, fd);
        }

        if (coder->buff.used >= need) {
            if (G729A_Decoder_Process(coder->ctx, rec + 1, rec[0],
                                      (G729_Word16*)(out_buff->addr + out_buff->used)) == G729A_NO_ERROR) {
                out_buff->used += G729_PCM_FRAME_BYTES;
            }
            coder->buff.used = 0;
        }
        return (out_buff->used > 0) ? 1 : 0;
    }

    // 裸流模式: 固定10字节一帧
    if (!coder->buff.addr) {
        coder->buff.addr = luat_heap_malloc(G729_BITSTREAM_BYTES);
        if (!coder->buff.addr) return 0;
        coder->buff.len = G729_BITSTREAM_BYTES;
        coder->buff.used = 0;
    }

    // 读满一帧(10字节)码流, fread按字节计数, 支持跨调用续读
    if (coder->buff.used < G729_BITSTREAM_BYTES) {
        coder->buff.used += luat_fs_fread(coder->buff.addr + coder->buff.used, 1, G729_BITSTREAM_BYTES - coder->buff.used, fd);
    }

    // 解码一帧为PCM
    if (coder->buff.used >= G729_BITSTREAM_BYTES) {
        if (G729A_Decoder_Process(coder->ctx, coder->buff.addr, G729_BITSTREAM_BYTES,
                                  (G729_Word16*)(out_buff->addr + out_buff->used)) == G729A_NO_ERROR) {
            out_buff->used += G729_PCM_FRAME_BYTES;
        }
        coder->buff.used = 0;
    }

    return (out_buff->used > 0) ? 1 : 0;
}

static int g729_codec_encode(luat_multimedia_codec_t* coder, luat_zbuff_t* in_buff, luat_zbuff_t* out_buff, int mode) {
    (void)mode;
    if (!coder || !coder->ctx || !in_buff || !out_buff) return -1;

    const uint8_t *pcm = in_buff->addr;
    uint32_t total_len = in_buff->used;
    uint32_t done_len = 0;
    G729_UWord32 out_len;

    // 处理完整的160字节PCM帧
    // Annex B (VAD开)时每帧输出0/2/10字节, 逐帧追加; 为保留帧边界,
    // 建议VAD开启时每次调用只喂一帧(160字节)
    while ((total_len - done_len) >= G729_PCM_FRAME_BYTES) {
        // 检查输出缓冲区空间(按最大帧长预留)
        if ((out_buff->len - out_buff->used) < G729_BITSTREAM_BYTES) {
            if (__zbuff_resize(out_buff, out_buff->len * 2 + G729_BITSTREAM_BYTES)) {
                return -1;
            }
        }
        if (G729A_Encoder_Process(coder->ctx, (const G729_Word16*)(pcm + done_len),
                                  out_buff->addr + out_buff->used, &out_len) != G729A_NO_ERROR) {
            return -1;
        }
        out_buff->used += out_len;
        done_len += G729_PCM_FRAME_BYTES;
    }

    // 不足一帧的部分用零填充（与g711 port行为一致）
    uint32_t remaining_len = total_len - done_len;
    if (remaining_len > 0) {
        uint8_t padded_frame[G729_PCM_FRAME_BYTES];
        memset(padded_frame, 0, G729_PCM_FRAME_BYTES);
        memcpy(padded_frame, pcm + done_len, remaining_len);

        if ((out_buff->len - out_buff->used) < G729_BITSTREAM_BYTES) {
            if (__zbuff_resize(out_buff, out_buff->len * 2 + G729_BITSTREAM_BYTES)) {
                return -1;
            }
        }
        if (G729A_Encoder_Process(coder->ctx, (const G729_Word16*)padded_frame,
                                  out_buff->addr + out_buff->used, &out_len) != G729A_NO_ERROR) {
            return -1;
        }
        out_buff->used += out_len;
    }

    return 1;
}

const luat_codec_opts_t g729_codec_opts = {
    .create = g729_codec_create,
    .destroy = g729_codec_destroy,
    .get_info = g729_codec_get_info,
    .decode_file_data = g729_codec_decode_file_data,
    .encode = g729_codec_encode
};
#endif
