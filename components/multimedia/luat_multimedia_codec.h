/******************************************************************************
 *  multimedia 编解码抽象层
 *****************************************************************************/
#ifndef __LUAT_MULTIMEDIA_CODEC_H__
#define __LUAT_MULTIMEDIA_CODEC_H__

#include "luat_base.h"

#ifdef __LUATOS__
#include "luat_zbuff.h"

#define LUAT_M_CODE_TYPE "MCODER*"

#endif

#define MP3_FRAME_LEN 4 * 1152

#define MP3_MAX_CODED_FRAME_SIZE 1792

#define G711_PCM_SAMPLES 160

enum{
	LUAT_MULTIMEDIA_DATA_TYPE_NONE,
	LUAT_MULTIMEDIA_DATA_TYPE_PCM,
	LUAT_MULTIMEDIA_DATA_TYPE_MP3,
	LUAT_MULTIMEDIA_DATA_TYPE_WAV,
	LUAT_MULTIMEDIA_DATA_TYPE_AMR_NB,
	LUAT_MULTIMEDIA_DATA_TYPE_AMR_WB,
	LUAT_MULTIMEDIA_DATA_TYPE_ULAW,
	LUAT_MULTIMEDIA_DATA_TYPE_ALAW,
    LUAT_MULTIMEDIA_DATA_TYPE_OPUS,
    LUAT_MULTIMEDIA_DATA_TYPE_OGG,
    LUAT_MULTIMEDIA_DATA_TYPE_OGG_OPUS
};

enum{
	LUAT_MULTIMEDIA_CB_AUDIO_DECODE_START,	//开始解码文件
	LUAT_MULTIMEDIA_CB_AUDIO_OUTPUT_START,	//开始输出解码后的音数据
	LUAT_MULTIMEDIA_CB_AUDIO_NEED_DATA,		//底层驱动播放播放完一部分数据，需要更多数据
	LUAT_MULTIMEDIA_CB_AUDIO_DONE,			//底层驱动播放完全部数据了
	LUAT_MULTIMEDIA_CB_DECODE_DONE,			//音频解码完成
	LUAT_MULTIMEDIA_CB_TTS_INIT,			//TTS做完了必要的初始化，用户可以通过audio_play_tts_set_param做个性化配置
	LUAT_MULTIMEDIA_CB_TTS_DONE,			//TTS编码完成了。注意不是播放完成
	LUAT_MULTIMEDIA_CB_RECORD_DATA,			//录音数据
	LUAT_MULTIMEDIA_CB_RECORD_DONE,			//录音完成
};

enum{
	LUAT_CODEC_VDDA_3V3,
	LUAT_CODEC_VDDA_1V8,
};

#include <stddef.h>
#include <stdio.h>

#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif

typedef struct{
	union{
		void *mp3_decoder;
		uint32_t read_len;
		void *amr_coder;
		void *g711_codec;
        void *opus_coder;
	};
	FILE* fd;
#ifdef __LUATOS__
	luat_zbuff_t buff;
#endif
	Buffer_Struct file_data_buffer;
	Buffer_Struct audio_data_buffer;
	uint8_t type;
	uint8_t is_decoder;
    // audio_info
    uint8_t audio_format;
    uint8_t num_channels;
    uint8_t is_signed;
    uint32_t sample_rate;
    int bits_per_sample;
}luat_multimedia_codec_t;

typedef struct luat_multimedia_cb {
    int function_ref;
} luat_multimedia_cb_t;

int luat_codec_get_audio_info(const char *file_path, luat_multimedia_codec_t *coder);

// mp3
void *mp3_decoder_create(void);
void mp3_decoder_init(void *decoder);
void mp3_decoder_set_debug(void *decoder, uint8_t onoff);
int mp3_decoder_get_info(void *decoder, const uint8_t *input, uint32_t len, uint32_t *hz, uint8_t *channel);
int mp3_decoder_get_data(void *decoder, const uint8_t *input, uint32_t len, int16_t *pcm, uint32_t *out_len, uint32_t *hz, uint32_t *used);
// g711
void* g711_decoder_create(uint8_t type);
void g711_decoder_destroy(void* decoder);
int g711_decoder_get_data(void* decoder, const uint8_t* input, uint32_t len,
                          int16_t* pcm, uint32_t* out_len, uint32_t* used);
void* g711_encoder_create(uint8_t type);
void g711_encoder_destroy(void* encoder);
int g711_encoder_get_data(void* encoder, const int16_t* pcm, uint32_t len,
                          uint8_t* output, uint32_t* out_len);
void g711_get_stats(void* codec, uint32_t* sample_rate, uint32_t* frame_count);
void g711_reset_stats(void* codec);
void g711_set_sample_rate(void* codec, uint32_t sample_rate);
#ifdef LUAT_SUPPORT_OPUS
// opus
int luat_opus_decoder_create(luat_multimedia_codec_t *coder);
void luat_opus_decoder_destroy(luat_multimedia_codec_t *coder);
int luat_opus_decoder_get_data(luat_multimedia_codec_t *coder, const uint8_t* input, uint32_t len,
                          int16_t* pcm, uint32_t* out_len, uint32_t* used);

int luat_opus_encoder_create(luat_multimedia_codec_t *coder);
void luat_opus_encoder_destroy(luat_multimedia_codec_t *coder);
int luat_opus_encoder_get_data(luat_multimedia_codec_t *coder, const int16_t* pcm, uint32_t len,
                          uint8_t* output, uint32_t* out_len);

// ogg
// void* luat_ogg_opus_decoder_create(uint8_t type);
// void luat_ogg_opus_decoder_destroy(void* decoder);

// int luat_ogg_opus_encoder_create(luat_multimedia_codec_t *coder);

#endif


#include "dtmf_codec/dtmf_codec.h"

#ifdef __LUATOS__
int l_multimedia_raw_handler(lua_State *L, void* ptr);
#endif

#endif
