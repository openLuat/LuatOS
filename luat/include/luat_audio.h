/*
 * Copyright (c) 2022 OpenLuat & AirM2M
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

#ifndef __LUAT_AUDIO_H__
#define __LUAT_AUDIO_H__
#include "luat_base.h"
#ifndef __BSP_COMMON_H__
#include "c_common.h"
#endif
#include "luat_rtos.h"
#include"luat_audio_codec.h"



typedef struct luat_audio_conf {
	uint64_t last_wakeup_time_ms;
	luat_audio_codec_conf_t codec_conf;
	void *hardware_data;
	luat_rtos_timer_t pa_delay_timer;
	uint16_t soft_vol;
    uint16_t speech_downlink_type;
    uint16_t speech_uplink_type;
    uint16_t i2s_rx_cb_save;
    uint8_t bus_type;
    uint8_t raw_mode;
    uint8_t debug_on_off;
    uint8_t is_sleep;
    uint8_t wakeup_ready;
    uint8_t pa_on_enable;
    uint8_t record_mode;
    uint8_t pa_pin;                                                     // pa pin
	uint8_t pa_on_level;                                                // pa 使能电平
    uint32_t after_sleep_ready_time;                                    // 
    uint32_t pa_delay_time;                                             // 
	uint8_t power_pin;													// 电源控制
	uint8_t power_on_level;                                             // 电源使能电平
	uint32_t power_off_delay_time;                                      // 电源关闭后延时时间 
} luat_audio_conf_t;

typedef enum{
    LUAT_AUDIO_PM_RESUME = 0,       /* 工作模式 */
    LUAT_AUDIO_PM_STANDBY,          /* 待机模式 */
    LUAT_AUDIO_PM_SHUTDOWN,         /* 关断模式 */
}luat_audio_pm_mode_t;


/**
 * @brief 设置音频硬件输出类型,后续初始化都会根据类型做不同处理，所以要首先使用此函数设置类型!!!
 *
 * @param bus_type 见MULTIMEDIA_AUDIO_BUS，目前只有0=DAC 1=I2S 2=SOFT_DAC
 */
int luat_audio_set_bus_type(uint8_t multimedia_id,uint8_t bus_type);

//此函数可获取multimedia_id对应的audio结构体,用于动态修改,如果有无法直接设置的函数可自行通过此方法修改结构体，一般不需要使用此函数
luat_audio_conf_t *luat_audio_get_config(uint8_t multimedia_id);

/**
 * @brief audio和codec绑定
 *
 * @param multimedia_id 多媒体通道，目前只有0
 * @param codec_conf codec信息
 * @return int =0成功，其他失败
 */
int luat_audio_setup_codec(uint8_t multimedia_id, const luat_audio_codec_conf_t *codec_conf);

/**
 * @brief 初始化audio
 *
 * @param multimedia_id 多媒体通道，目前只有0
 * @param init_vol 默认硬件音量
 * @param init_mic_vol 默认MIC音量
 * @return int =0成功，其他失败
 */
int luat_audio_init(uint8_t multimedia_id, uint16_t init_vol, uint16_t init_mic_vol);

/**
 * @brief audio休眠控制,注意，pm各个模式下功耗由具体audio硬件决定
 * 
 * @param multimedia_id 多媒体通道
 * @param mode 
 * @return int =0成功，其他失败
 */
int luat_audio_pm_request(uint8_t multimedia_id,luat_audio_pm_mode_t mode);

/**
 * @brief 播放空白音
 * 
 * @param multimedia_id 多媒体通道
 * @return int =0成功，其他失败
 */
int luat_audio_play_blank(uint8_t multimedia_id);

#ifdef __LUATOS__
/**
 * @brief 播放指定数量的文件或者ROM数组（文件数据直接写成数组形式）
 *
 * @param multimedia_id 多媒体通道，目前只有0
 * @param info 文件信息，文件路径信息
 * @param files_num 文件数量
 * @return int =0成功，其他失败
 */
int luat_audio_play_multi_files(uint8_t multimedia_id, uData_t *info, uint32_t files_num, uint8_t error_stop);
#endif
/**
 * @brief 播放指定的文件或
 *
 * @param multimedia_id 多媒体通道，目前只有0
 * @param path 文件路径
 * @return int =0成功，其他失败
 */
int luat_audio_play_file(uint8_t multimedia_id, const char *path);
/**
 * @brief 是否播放完全部数据
 *
 * @param multimedia_id multimedia_id 多媒体通道，目前只有0
 * @return uint8_t =1是，=0没有
 */
uint8_t luat_audio_is_finish(uint8_t multimedia_id);

/**
 * @brief 强制停止播放文件，但是不会停止已经输出到底层驱动的数据播放
 *
 * @param multimedia_id multimedia_id 多媒体通道，目前只有0
 * @return int =0成功，其他失败
 */
int luat_audio_play_stop(uint8_t multimedia_id);

/**
 * @brief 获取上一次播放结果，在MULTIMEDIA_CB_AUDIO_DONE回调时调用最佳
 *
 * @param multimedia_id multimedia_id 多媒体通道，目前只有0
 * @return int =0完整的播放完成，<0被用户停止了，>0 TTS失败，或者第几个音频文件解码失败（用户在play_info未设置了解码失败后继续，文件位置+1）
 */
int luat_audio_play_get_last_error(uint8_t multimedia_id);


/**
 * @brief 立刻初始化播放未编码的原始音频数据流
 *
 * @param multimedia_id multimedia_id 多媒体通道，目前只有0
 * @param audio_format 音频数据格式，目前只支持PCM，即需要手动解码
 * @param num_channels 声道数，目前只能1或2
 * @param sample_rate 采样率，注意只有8K,16K,32K,48K,96K,22.05K,44.1K这些能被支持
 * @param bits_per_sample 量化bit，只能是16
 * @param is_signed 量化数据是否带符号，只能是1
 * @return int =0成功，其他失败
 */
int luat_audio_start_raw(uint8_t multimedia_id, uint8_t audio_format, uint8_t num_channels, uint32_t sample_rate, uint8_t bits_per_sample, uint8_t is_signed);
/**
 * @brief 向底层驱动传入一段原始音频数据
 *
 * @param multimedia_id multimedia_id 多媒体通道，目前只有0
 * @param data 原始音频数据
 * @param len 原始音频数据长度
 * @return int =0成功，其他失败
 */
int luat_audio_write_raw(uint8_t multimedia_id, uint8_t *data, uint32_t len);
/**
 * @brief 强制停止所有播放，同时底层驱动也会停止输出，不要用于播放文件的结束
 *
 * @param multimedia_id multimedia_id 多媒体通道，目前只有0
 * @return int =0成功，其他失败
 */
int luat_audio_stop_raw(uint8_t multimedia_id);
/**
 * @brief 暂停/恢复播放
 *
 * @param multimedia_id multimedia_id 多媒体通道，目前只有0
 * @param is_pause 0恢复，其他暂停
 * @return int =0成功，其他失败
 */
int luat_audio_pause_raw(uint8_t multimedia_id, uint8_t is_pause);

/**
 * @brief 编码并播放一段文字
 *
 * @param multimedia_id multimedia_id 多媒体通道，目前只有0
 * @param text 文字数据
 * @param text_bytes 文字数据长度
 * @return int =0成功，其他失败
 */
int luat_audio_play_tts_text(uint8_t multimedia_id, void *text, uint32_t text_bytes);
/**
 * @brief 在收到MULTIMEDIA_CB_TTS_INIT回调时，可以设置TTS参数，等同于ivTTS_SetParam
 *
 * @param multimedia_id multimedia_id 多媒体通道，目前只有0
 * @param param_id 见ivTTS_PARAM_XXX
 * @param param_value param_id对应的value
 * @return int =0成功，其他失败
 */
int luat_audio_play_tts_set_param(uint8_t multimedia_id, uint32_t param_id, uint32_t param_value);

/**
 * @brief pa引脚配置
 * 
 * @param multimedia_id multimedia_id 多媒体通道
 * @param pin pa pin
 * @param level pa使能电平
 * @param dummy_time_len 
 * @param pa_delay_time 
 */
void luat_audio_config_pa(uint8_t multimedia_id, uint32_t pin, int level, uint32_t dummy_time_len, uint32_t pa_delay_time);

/**
 * @brief power引脚配置
 * 
 * @param multimedia_id 多媒体通道
 * @param pin power pin
 * @param level 使能电平
 * @param dac_off_delay_time 
 */
void luat_audio_config_dac(uint8_t multimedia_id, int pin, int level, uint32_t dac_off_delay_time);

/**
 * @brief 音量控制
 * 
 * @param multimedia_id 多媒体通道
 * @param vol 音量，0-1000 0-100为硬件 100-1000为软件缩放，实际根据不同bsp不同硬件底层实现
 * @return uint16_t 音量，0-1000
 */
uint16_t luat_audio_vol(uint8_t multimedia_id, uint16_t vol);

/**
 * @brief mic音量控制
 * 
 * @param multimedia_id 多媒体通道
 * @param vol 音量，0-100
 * @return uint8_t 音量 0-100
 */
uint8_t luat_audio_mic_vol(uint8_t multimedia_id, uint16_t vol);

/**
 * @brief 调试开关
 * 
 * @param multimedia_id 多媒体通道
 * @param onoff 0关闭，1打开
 */
void luat_audio_play_debug_onoff(uint8_t multimedia_id, uint8_t onoff);

/**
 * @brief 检测音频是否准备就绪
 * 
 * @param multimedia_id 多媒体通道
 * @return int -1未就绪，0就绪
 */
int luat_audio_check_ready(uint8_t multimedia_id);

/**
 * @brief 录音并播放
 * 
 * @param multimedia_id 多媒体通道
 * @param sample_rate 采样率
 * @param play_buffer buffer
 * @param one_trunk_len 一次传输长度
 * @param total_trunk_cnt 传输次数
 * @return int 成功返回0，失败返回-1
 */
int luat_audio_record_and_play(uint8_t multimedia_id, uint32_t sample_rate, const uint8_t *play_buffer, uint32_t one_trunk_len, uint32_t total_trunk_cnt);

/**
 * @brief 录音停止
 * 
 * @param multimedia_id 多媒体通道
 * @return int 成功返回0，失败返回-1
 */
int luat_audio_record_stop(uint8_t multimedia_id);

/**
 * @brief 开始通话输出
 * 
 * @param multimedia_id 多媒体通道
 * @param is_downlink 通话是否连接
 * @param type 类型
 * @param downlink_buffer buffer
 * @param buffer_len buffer 长度
 * @param channel_num 通道
 * @return int 成功返回0，失败返回-1
 */
int luat_audio_speech(uint8_t multimedia_id, uint8_t is_downlink, uint8_t type, const uint8_t *downlink_buffer, uint32_t buffer_len, uint8_t channel_num);

/**
 * @brief 通话输出停止
 * 
 * @param multimedia_id 多媒体通道
 * @return int 成功返回0，失败返回-1
 */
int luat_audio_speech_stop(uint8_t multimedia_id);

/**
 * @brief pa控制函数，一般不需要使用，底层会自动调用
 * 
 * @param multimedia_id multimedia_id 多媒体通道
 * @param on 1开，0关
 * @param delay 延迟时间，非阻塞，不延迟写0
 */
void luat_audio_pa(uint8_t multimedia_id,uint8_t on, uint32_t delay);

/**
 * @brief power控制函数，一般不需要使用，底层会自动调用
 * 
 * @param multimedia_id 多媒体通道
 * @param on 1开，0关
 */
void luat_audio_power(uint8_t multimedia_id,uint8_t on);

#endif
