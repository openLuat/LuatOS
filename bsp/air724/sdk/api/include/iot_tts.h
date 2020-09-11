#ifndef __IOT_TTS_H__
#define __IOT_TTS_H__

#include "iot_os.h"

/**
 * @defgroup iot_sdk_audio 音频接口
 * @{
 */

	/**@example tts/demo_tts.c
	* tts接口示例
	*/ 

/**初始化tts引擎
*@param		cb:		TTS播放结果回调函数
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_tts_init(
                    TTS_PLAY_CB cb         
              );

/**tts播放文本
*@param		text:		待播放文本
*@param		len:		文本长度（字节）
*@return	TRUE: 	    成功
			FALSE:      失败
**/
BOOL iot_tts_play(                                   
                    char *text,u32 len                    
              );


/**tts停止播放
*@return	TRUE: 	    成功
			FALSE:      失败
**/
BOOL iot_tts_stop(      );


/**设置tts配置参数
*@param		flag:		参数标志
*@param		value:		参数值
*@return	TRUE: 	    成功
			FALSE:      失败
**/
BOOL iot_tts_set_param(
		OPENAT_TTS_PARAM_FLAG flag,u32 value
		);


/** @}*/
/** @}*/

#endif
