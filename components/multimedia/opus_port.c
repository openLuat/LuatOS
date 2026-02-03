#include "luat_base.h"
#include "luat_multimedia.h"
#include "luat_msgbus.h"
#include "luat_zbuff.h"
#include "luat_fs.h"
#include "luat_mem.h"
#include <stdint.h>

#define LUAT_LOG_TAG "codec_opus"
#include "luat_log.h"

#include "opus.h"
#include "opus_types.h"
#include "opus_private.h"
//#include "opus_multistream.h"
#include "opus_defines.h"

#define DELAY_SAMPLES 60
#define SAMPLE_RATE 16000
#define FRAME_SIZE (SAMPLE_RATE*DELAY_SAMPLES/1000)
#define CHANNELS 1
#define APPLICATION OPUS_APPLICATION_AUDIO
#define BITRATE 64000

#define MAX_FRAME_SIZE 6*960
#define MAX_PACKET_SIZE (3*1276)

int luat_opus_decoder_create(luat_multimedia_codec_t *coder){
    int error;
    coder->opus_coder = opus_decoder_create(coder->sample_rate, coder->num_channels, &error);
    if (!coder->opus_coder || error != OPUS_OK){ 
        LLOGE("opus_decoder_create failed: %d", error); 
        coder->opus_coder = NULL;
        return -1; 
    }
    return 0;
}

void luat_opus_decoder_destroy(luat_multimedia_codec_t *coder){
    if (coder->opus_coder) opus_decoder_destroy(coder->opus_coder);
}

int luat_opus_decoder_get_data(luat_multimedia_codec_t *coder, const uint8_t* input, uint32_t len,
                                int16_t* pcm, uint32_t* out_len, uint32_t* used){
    if (!coder->opus_coder || !input || !pcm || !out_len || !used) return -1;
    int frame_size = opus_decode(coder->opus_coder , input, (opus_int32)len, pcm, (coder->sample_rate*DELAY_SAMPLES/1000), 0);
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
    coder->opus_coder = opus_encoder_create(coder->sample_rate, coder->num_channels, APPLICATION, &error);
    if (!coder->opus_coder || error != OPUS_OK){ 
        LLOGE("opus_encoder_create failed: %d", error); 
        coder->opus_coder = NULL;
        return -1; 
    }
    opus_encoder_ctl(coder->opus_coder, OPUS_SET_BITRATE(BITRATE));
    return 0;
}

void luat_opus_encoder_destroy(luat_multimedia_codec_t *coder){
    if (coder->opus_coder) opus_encoder_destroy(coder->opus_coder); 
}

int luat_opus_encoder_get_data(luat_multimedia_codec_t *coder, const int16_t* pcm, uint32_t len,
                                uint8_t* output, uint32_t* out_len){
    if (!coder->opus_coder || !pcm || !output || !out_len) return -1;
    unsigned char cbits[MAX_PACKET_SIZE];
    uint32_t frame_size = coder->sample_rate*DELAY_SAMPLES/1000;
    if (len < frame_size) return -1;

    int nbBytes = opus_encode(coder->opus_coder, pcm, frame_size, cbits, MAX_PACKET_SIZE);
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
