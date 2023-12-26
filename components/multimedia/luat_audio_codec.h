#ifndef _LUAT_AUDIO_CODEC_H_
#define _LUAT_AUDIO_CODEC_H_

#define LUAT_CODEC_MODE_MASTER               0x00
#define LUAT_CODEC_MODE_SLAVE                0x01

#define LUAT_CODEC_PA_OFF                    0x00
#define LUAT_CODEC_PA_ON                     0x01

#define LUAT_CODEC_CTL_MODE                  0x00
#define LUAT_CODEC_CTL_VOLUME                0x01
#define LUAT_CODEC_CTL_RATE                  0x02
#define LUAT_CODEC_CTL_BITS                  0x03
#define LUAT_CODEC_CTL_CHANNEL               0x04
#define LUAT_CODEC_CTL_PA                    0x05


struct luat_audio_codec_opts;

typedef struct luat_audio_codec_conf {
    int i2c_id;
    int samplerate;         //16k
    int bits;               //16
    int channels;           //1ch/2ch
    int pa_pin;
	uint8_t vol;
	uint8_t pa_on_level;
    uint32_t dummy_time_len;
    uint32_t pa_delay_time;
    const struct luat_audio_codec_opts* codec_opts;
} luat_audio_codec_conf_t;

typedef struct luat_audio_codec_opts{
    const char* name;
    int (*init)(luat_audio_codec_conf_t* conf);
    int (*deinit)(luat_audio_codec_conf_t* conf);
    int (*control)(luat_audio_codec_conf_t* conf,uint8_t cmd,int data);
    int (*start)(luat_audio_codec_conf_t* conf);
    int (*stop)(luat_audio_codec_conf_t* conf);
} luat_audio_codec_opts_t;


extern const luat_audio_codec_opts_t codec_opts_es8311;


#endif
