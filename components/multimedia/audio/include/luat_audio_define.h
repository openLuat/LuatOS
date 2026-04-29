#ifndef __LUAT_AUDIO_DEFINE_H__
#define __LUAT_AUDIO_DEFINE_H__

/**
 * @file luat_audio_define.h
 * @brief LuatOS 音频框架通用定义头文件
 * 
 * 包含音频框架中使用的通用枚举定义和常量定义。
 */

/**
 * @brief 音频通道模式枚举
 * 
 * 定义音频播放/录音时的声道配置模式。
 */
enum {
    LUAT_AUDIO_CHANNEL_MONO = 0,    /**< 单声道模式 */
    LUAT_AUDIO_CHANNEL_LEFT = LUAT_AUDIO_CHANNEL_MONO,  /**< 左声道模式 (等同于单声道) */
    LUAT_AUDIO_CHANNEL_RIGHT,     /**< 右声道模式 */
    LUAT_AUDIO_CHANNEL_STEREO,    /**< 立体声模式 (双声道) */
};

#endif
