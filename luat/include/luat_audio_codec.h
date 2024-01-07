
#ifndef __LUAT_AUDIO_CODEC_H__
#define __LUAT_AUDIO_CODEC_H__

typedef enum {
    LUAT_CODEC_MODE_MASTER = 0,
    LUAT_CODEC_MODE_SLAVE,

    LUAT_CODEC_MODE_ALL = 0,
    LUAT_CODEC_MODE_DAC,
    LUAT_CODEC_MODE_ADC,
    
    LUAT_CODEC_FORMAT_I2S = 0,
    LUAT_CODEC_FORMAT_LSB,
    LUAT_CODEC_FORMAT_MSB,
    LUAT_CODEC_FORMAT_PCMS,
    LUAT_CODEC_FORMAT_PCML,

    LUAT_CODEC_SET_MUTE = 0,        // 静音设置
    LUAT_CODEC_GET_MUTE,            // 
    LUAT_CODEC_SET_VOICE_VOL,   // 音量设置
    LUAT_CODEC_GET_VOICE_VOL,       // 
    LUAT_CODEC_SET_MIC_VOL,     // 音量设置
    LUAT_CODEC_GET_MIC_VOL,         //

    LUAT_CODEC_SET_FORMAT,              //
    LUAT_CODEC_SET_RATE,        // 采样率设置
    LUAT_CODEC_SET_BITS,            // 采样位设置
    LUAT_CODEC_SET_CHANNEL,         // 通道设置
    LUAT_CODEC_SET_PA,              // pa控制
    
    LUAT_CODEC_MODE_NORMAL,
    LUAT_CODEC_MODE_STANDBY,
    LUAT_CODEC_MODE_PWRDOWN,
    LUAT_CODEC_PA_NONE  = 255,
} luat_audio_codec_ctl_t;

struct luat_audio_codec_opts;

typedef struct luat_audio_codec_conf {
    int i2c_id;                                                         // i2c id
    int i2s_id;                                                         // i2s id
    uint8_t pa_pin;                                                     // pa pin
	uint8_t pa_on_level;                                                // pa 使能电平
    uint32_t dummy_time_len;                                            // pa使能前延迟时间
    uint32_t pa_delay_time;                                             // pa使能后延迟时间
    struct luat_audio_codec_opts* codec_opts;
} luat_audio_codec_conf_t;

typedef struct luat_audio_codec_opts{
    const char* name;
    int (*init)(luat_audio_codec_conf_t* conf,uint8_t mode);            //初始化
    int (*deinit)(luat_audio_codec_conf_t* conf);                       //反初始化
    int (*control)(luat_audio_codec_conf_t* conf,luat_audio_codec_ctl_t cmd,uint32_t data); //控制函数
    int (*start)(luat_audio_codec_conf_t* conf);                        //停止
    int (*stop)(luat_audio_codec_conf_t* conf);                         //开始
} luat_audio_codec_opts_t;

extern luat_audio_codec_opts_t codec_opts_es8311;

#endif
