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
};

enum
{
	MULTIMEDIA_CB_AUDIO_NEED_DATA,
	MULTIMEDIA_CB_AUDIO_DONE,
};
int l_multimedia_raw_handler(lua_State *L, void* ptr);
#endif
