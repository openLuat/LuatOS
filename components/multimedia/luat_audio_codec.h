#ifndef _LUAT_AUDIO_CODEC_H_
#define _LUAT_AUDIO_CODEC_H_

#define LUAT_CODEC_MODE_MASTER               0x00
#define LUAT_CODEC_MODE_SLAVE                0x01

#define LUAT_CODEC_PA_OFF                    0x00
#define LUAT_CODEC_PA_ON                     0x01

typedef enum {
    LUAT_CODEC_CTL_MODE,        // 模式设置
    LUAT_CODEC_CTL_VOLUME,      // 音量设置
    LUAT_CODEC_CTL_MUTE,        // 静音设置
    LUAT_CODEC_CTL_RATE,        // 采样率设置
    LUAT_CODEC_CTL_BITS,        // 采样位设置
    LUAT_CODEC_CTL_CHANNEL,     // 通道设置
    LUAT_CODEC_CTL_PA,          // pa控制
} luat_audio_codec_ctl_t;

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
    int (*init)(luat_audio_codec_conf_t* conf);                         //初始化
    int (*deinit)(luat_audio_codec_conf_t* conf);                       //反初始化
    int (*control)(luat_audio_codec_conf_t* conf,luat_audio_codec_ctl_t cmd,uint32_t data); //控制函数
    int (*start)(luat_audio_codec_conf_t* conf);                        //停止
    int (*stop)(luat_audio_codec_conf_t* conf);                         //开始
} luat_audio_codec_opts_t;


extern const luat_audio_codec_opts_t codec_opts_es8311;


#endif
