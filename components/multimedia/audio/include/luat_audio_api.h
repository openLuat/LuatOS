#ifndef __LUAT_AUDIO_API__
#define __LUAT_AUDIO_API__

/**
 * @file luat_audio_api.h
 * @brief LuatOS 音频框架公共API头文件
 * 
 * 提供音频框架的初始化和核心接口声明。
 * 
 * @defgroup luat_audio_api 音频公共API
 * @ingroup audio
 * @{
 */

#include "luat_audio_define.h"
#include "luat_audio_channel.h"
#include "luat_audio_data_codec.h"
#include "luat_audio_driver.h"

/**
 * @brief 初始化音频框架基础模块
 * 
 * 此函数负责初始化音频框架的核心组件，包括通道管理、编解码器注册等。
 * 应在系统启动时调用一次。
 */
void luat_audio_base_init(void);

#endif

/** @} */
