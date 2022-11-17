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
	MULTIMEDIA_CB_AUDIO_DECODE_START,	//开始解码文件
	MULTIMEDIA_CB_AUDIO_OUTPUT_START,	//开始输出解码后的音数据
	MULTIMEDIA_CB_AUDIO_NEED_DATA,		//底层驱动播放播放完一部分数据，需要更多数据
	MULTIMEDIA_CB_AUDIO_DONE,			//底层驱动播放完全部数据了
	MULTIMEDIA_CB_DECODE_DONE,			//音频解码完成
	MULTIMEDIA_CB_TTS_INIT,				//TTS做完了必要的初始化，用户可以通过audio_play_tts_set_param做个性化配置
	MULTIMEDIA_CB_TTS_DONE,				//TTS编码完成了。注意不是播放完成
};
int l_multimedia_raw_handler(lua_State *L, void* ptr);
#endif
