/******************************************************************************
 *  multimedia设备操作抽象层
 *****************************************************************************/
#ifndef __LUAT_MULTIMEDIA_H__
#define __LUAT_MULTIMEDIA_H__

#include "luat_base.h"

enum
{
	MULTIMEDIA_DATA_TYPE_NONE,
	MULTIMEDIA_DATA_TYPE_PCM,
	MULTIMEDIA_DATA_TYPE_MP3,
	MULTIMEDIA_DATA_TYPE_WAV,
	MULTIMEDIA_DATA_TYPE_AMR_NB,
	MULTIMEDIA_DATA_TYPE_AMR_WB,
};

enum
{
	MULTIMEDIA_CB_AUDIO_NEED_DATA,
	MULTIMEDIA_CB_AUDIO_DONE,
	MULTIMEDIA_CB_AUDIO_DECODE_START,
	MULTIMEDIA_CB_AUDIO_OUTPUT_START,
	MULTIMEDIA_CB_AUDIO_OUTPUT_DATA,
	MULTIMEDIA_CB_DECODE_DONE,
	MULTIMEDIA_CB_TTS_INIT,
	MULTIMEDIA_CB_TTS_DONE,
};
int l_multimedia_raw_handler(lua_State *L, void* ptr);
#endif
