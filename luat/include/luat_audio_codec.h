
#ifndef __LUAT_AUDIO_CODEC_H__
#define __LUAT_AUDIO_CODEC_H__

typedef enum {
    LUAT_CODEC_SET_MUTE = 0,        // 静音设置
    LUAT_CODEC_GET_MUTE,            // 获取静音状态
    LUAT_CODEC_SET_VOICE_VOL,       // 音量设置
    LUAT_CODEC_GET_VOICE_VOL,       // 获取音量
    LUAT_CODEC_SET_MIC_VOL,         // mic音量设置
    LUAT_CODEC_GET_MIC_VOL,         // 获取mic音量

    LUAT_CODEC_SET_FORMAT,          // codec数据格式设置
    LUAT_CODEC_SET_RATE,            // 采样率设置
    LUAT_CODEC_SET_BITS,            // 采样位设置
    LUAT_CODEC_SET_CHANNEL,         // 通道设置
    
    LUAT_CODEC_MODE_RESUME,
    LUAT_CODEC_MODE_STANDBY,
    LUAT_CODEC_MODE_PWRDOWN,
} luat_audio_codec_ctl_t;

typedef enum {
    LUAT_CODEC_MODE_SLAVE = 0,      // 默认从模式
    LUAT_CODEC_MODE_MASTER,

    LUAT_CODEC_MODE_ALL = 0,
    LUAT_CODEC_MODE_DAC,
    LUAT_CODEC_MODE_ADC,

    LUAT_CODEC_FORMAT_I2S = 0,
    LUAT_CODEC_FORMAT_LSB,
    LUAT_CODEC_FORMAT_MSB,
    LUAT_CODEC_FORMAT_PCMS,
    LUAT_CODEC_FORMAT_PCML,

}luat_audio_codec_ctl_param_t;

struct luat_audio_codec_opts;

typedef struct luat_audio_codec_conf {
    int i2c_id;                                                         // i2c id
    int i2s_id;                                                         // i2s id
    const struct luat_audio_codec_opts* codec_opts;                     // codec 驱动函数
    uint8_t multimedia_id;                                              // 多媒体id
} luat_audio_codec_conf_t;

typedef struct luat_audio_codec_opts{
    const char* name;
    int (*init)(luat_audio_codec_conf_t* conf,uint8_t mode);            //初始化
    int (*deinit)(luat_audio_codec_conf_t* conf);                       //反初始化
    int (*control)(luat_audio_codec_conf_t* conf,luat_audio_codec_ctl_t cmd,uint32_t data); //控制函数
    int (*start)(luat_audio_codec_conf_t* conf);                        //停止
    int (*stop)(luat_audio_codec_conf_t* conf);                         //开始
	uint8_t no_control;													//无法调节，只能开关
} luat_audio_codec_opts_t;

extern const luat_audio_codec_opts_t codec_opts_es8311;
extern const luat_audio_codec_opts_t codec_opts_tm8211;
extern const luat_audio_codec_opts_t codec_opts_common;
#endif
