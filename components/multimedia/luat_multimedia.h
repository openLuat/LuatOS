/******************************************************************************
 *  multimedia设备操作抽象层
 *****************************************************************************/
#ifndef __LUAT_MULTIMEDIA_H__
#define __LUAT_MULTIMEDIA_H__

#include "luat_base.h"
#include "luat_multimedia_codec.h"
#include "luat_audio.h"	// 音频设备
//预留
// #include "luat_video.h"	// 视频设备

//以下LUAT_MULTIMEDIA_AUDIO_BUS_XXX 枚举只做保留，不要再使用,使用 LUAT_AUDIO_BUS_XXX 
enum{
	LUAT_MULTIMEDIA_AUDIO_BUS_DAC=LUAT_AUDIO_BUS_DAC,
	LUAT_MULTIMEDIA_AUDIO_BUS_I2S=LUAT_AUDIO_BUS_I2S,
	LUAT_MULTIMEDIA_AUDIO_BUS_SOFT_DAC=LUAT_AUDIO_BUS_SOFT_DAC
};

// multimedia 相关api在此设计

#endif
