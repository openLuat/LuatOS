#ifndef __LUAT_AUDIO_DEFINE_H__
#define __LUAT_AUDIO_DEFINE_H__

#include "stdint.h"
/**
 * @file luat_audio_define.h
 * @brief LuatOS 音频框架通用定义头文件
 * 
 * 包含音频框架中使用的通用枚举定义和常量定义。
 * 
 * @defgroup luat_audio_define 音频通用定义
 * @ingroup audio
 * @{
 */

/**
 * @brief 音频通道模式枚举
 * 
 * 定义音频播放/录音时的声道配置模式。
 */
enum {
    LUAT_AUDIO_CHANNEL_MONO = 0,           /**< 单声道模式 */
    LUAT_AUDIO_CHANNEL_LEFT = LUAT_AUDIO_CHANNEL_MONO,  /**< 左声道模式 (等同于单声道) */
    LUAT_AUDIO_CHANNEL_RIGHT,              /**< 右声道模式 */
    LUAT_AUDIO_CHANNEL_STEREO,             /**< 立体声模式 (双声道) */

    LUAT_AUDIO_DRIVER_TYPE_NONE = 0,     /**< 无驱动类型 */
    LUAT_AUDIO_DRIVER_TYPE_I2S,        /**< I2S 接口驱动 */
    LUAT_AUDIO_DRIVER_TYPE_DAC,            /**< DAC 接口驱动（仅播放） */
    LUAT_AUDIO_DRIVER_TYPE_ADC,            /**< ADC 接口驱动（仅录音） */
    LUAT_AUDIO_DRIVER_TYPE_USB,            /**< USB 音频驱动 */
    LUAT_AUDIO_DRIVER_TYPE_MAX = 255,            /**< 最大驱动类型 */



    LUAT_AUDIO_DRIVER_CONFIG_PARAM_I2S_MODE = 0,       /**< I2S 模式参数 */
    LUAT_AUDIO_DRIVER_CONFIG_PARAM_I2S_FRAME_BITS,     /**< I2S 帧位宽参数 */
    LUAT_AUDIO_DRIVER_CONFIG_PARAM_I2S_CHANNEL_NUMS,     /**< I2S 通道数参数 */
    LUAT_AUDIO_DRIVER_CONFIG_PARAM_DAC_BIT_WIDTH,      /**< DAC 位宽参数 */

    LUAT_AUDIO_DRIVER_CONFIG_VALUE_I2S_MODE_I2S = 0,      // I2S 标准
    LUAT_AUDIO_DRIVER_CONFIG_VALUE_I2S_MODE_LSB,          // LSB 标准
    LUAT_AUDIO_DRIVER_CONFIG_VALUE_I2S_MODE_MSB,          // MSB 标准
    LUAT_AUDIO_DRIVER_CONFIG_VALUE_I2S_MODE_PCMS,         // PCM 短帧标准
    LUAT_AUDIO_DRIVER_CONFIG_VALUE_I2S_MODE_PCML,         // PCM 长帧标准

    LUAT_AUDIO_DRIVER_EVENT_TX_ONE_BLOCK_DONE = 0,     /**< 播放1个block完成事件 */
    LUAT_AUDIO_DRIVER_EVENT_RX_ONE_BLOCK_DONE,         /**< 录音1个block完成事件 */

    LUAT_AUDIO_DRIVER_STATE_IDLE = 0,      /**< 空闲状态 */
    LUAT_AUDIO_DRIVER_STATE_INITED,        /**< 初始化状态 */
    LUAT_AUDIO_DRIVER_STATE_ACTIVE,        /**< 激活状态 */
    LUAT_AUDIO_DRIVER_STATE_RUNNING,       /**< 运行状态 */

    LUAT_AUDIO_DRIVER_MODE_NONE = 0,       /**< 无模式 */
    LUAT_AUDIO_DRIVER_MODE_PLAY,           /**< 播放模式 */
    LUAT_AUDIO_DRIVER_MODE_RECORD,         /**< 录音模式 */
    LUAT_AUDIO_DRIVER_MODE_CALL,           /**< 通话模式 */
    LUAT_AUDIO_DRIVER_MODE_CALL_WITH_BUFFER,/**< 通话带缓冲区模式 */

    LUAT_AUDIO_DATA_CODEC_TYPE_RAW = 0,    /**< 原始音频数据编解码器 */
    LUAT_AUDIO_DATA_CODEC_TYPE_WAV,    /**< WAV 编解码器 */
    LUAT_AUDIO_DATA_CODEC_TYPE_AMR_NB,        /**< AMR 编解码器 */
    LUAT_AUDIO_DATA_CODEC_TYPE_AMR_WB,        /**< AMR 编解码器 */
    LUAT_AUDIO_DATA_CODEC_TYPE_TTS,        /**< TTS 编解码器 */
    LUAT_AUDIO_DATA_CODEC_TYPE_MP3,        /**< MP3 编解码器 */
    LUAT_AUDIO_DATA_CODEC_TYPE_OPUS,       /**< OPUS 编解码器 */
    LUAT_AUDIO_DATA_CODEC_TYPE_G711,       /**< G711 编解码器 */
    LUAT_AUDIO_DATA_CODEC_TYPE_MAX,        /**< 最大编解码器类型 */

    LUAT_AUDIO_TTS_EVENT_START = 0,        /**< TTS 开始事件 */
    LUAT_AUDIO_TTS_EVENT_NEW_DATA,         /**< TTS 新数据可用事件 */

    LUAT_AUDIO_REQUEST_EVENT_START = 0,                /**< 请求开始 */
    LUAT_AUDIO_REQUEST_EVENT_NEED_PLAY_INFO,          /**< 播放需要播放信息 */
    LUAT_AUDIO_REQUEST_EVENT_NEED_NEW_DATA,           /**< 播放需要新数据 */
    LUAT_AUDIO_REQUEST_EVENT_GET_NEW_DATA,            /**< 录音获取到新数据 */
    LUAT_AUDIO_REQUEST_EVENT_DECODE_DONE,             /**< 解码完成 */
    LUAT_AUDIO_REQUEST_EVENT_END,                     /**< 请求结束 */
    LUAT_AUDIO_REQUEST_EVENT_MAX = 255,
};

#ifndef LUAT_AUDIO_DATA_CACHE_LEN
#define LUAT_AUDIO_DATA_CACHE_LEN   8000
#endif
/**
 * @brief 最大支持的音频驱动数量
 * 
 * 系统最多支持同时注册的音频驱动实例数量。
 */
#ifndef LUAT_AUDIO_DRIVER_MAX
#define LUAT_AUDIO_DRIVER_MAX   4
#endif

/**
 * @brief 默认音频通道FIFO大小
 * 
 * 定义音频通道的默认FIFO大小，用于存储音频数据。默认是2^17字节，最小是2^16字节。
 * 
 * @note 这个值是2的幂次方，用于计算FIFO的大小。
 */
#ifndef LUAT_AUDIO_CHANNEL_FIFO_DEFAULT_SIZE_POWER
#define LUAT_AUDIO_CHANNEL_FIFO_DEFAULT_SIZE_POWER (17)
#endif

/**
 * @brief 默认音频数据编解码器输入FIFO大小
 * 
 * 定义音频数据编解码器的默认输入FIFO大小，用于存储音频数据。默认是2^14字节，最小是2^14字节。
 * 
 * @note 这个值是2的幂次方，用于计算FIFO的大小。
 */
#ifndef LUAT_AUDIO_DATA_CODEC_INPUT_FIFO_DEFAULT_SIZE_POWER
#define LUAT_AUDIO_DATA_CODEC_INPUT_FIFO_DEFAULT_SIZE_POWER (14)
#endif

#ifndef LUAT_AUDIO_TASK_STACK
#define LUAT_AUDIO_TASK_STACK 13 * 1024
#endif

#define LUAT_AUDIO_FRAME_LOOP_CNT   4
/**
 * @brief 音频驱动探测结构
 * 
 * 用于驱动匹配和探测的结构，实现设备树风格的驱动匹配机制。
 */
struct luat_audio_driver_probe;

/**
 * @brief 音频驱动控制器前向声明
 */
struct luat_audio_driver_ctrl;

/**
 * @brief 音频编解码器前向声明
 */
struct luat_audio_data_codec;

/**
 * @brief 音频DSP前向声明
 */
struct luat_audio_dsp;

/**
 * @brief 音频请求块前向声明
 */
struct luat_audio_request_block;

/**
 * @brief 音频通道前向声明
 */
struct luat_audio_channel;

extern unsigned char luat_audio_debug_flag;
#endif

/** @} */
