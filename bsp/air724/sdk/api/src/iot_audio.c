#include "iot_audio.h"

/****************************** AUDIO ******************************/
/**打开语音
*@note  在通话开始时调用
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_auido_open_tch(                                           
                        VOID
                )
{
    return IVTBL(open_tch)();
}

/**关闭语音
*@note  通话结束时调用
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_close_tch(                                          
                        VOID
                 )
{
    return IVTBL(close_tch)();
}

/**播放TONE音
*@param  toneType:      TONE音类型
*@param  duration:      播放时长
*@param  volume:        播放音量
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_play_tone(                                         
                        E_AMOPENAT_TONE_TYPE toneType,      
                        UINT16 duration,                   
                        E_AMOPENAT_SPEAKER_GAIN volume     
                 )
{
    return IVTBL(play_tone)(toneType, duration, volume);
}

/**停止播放TONE音
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_stop_tone(                                         
                        VOID
                 )
{
    return IVTBL(stop_tone)();
}


/**播放DTMF音
*@param  dtmfType:      DTMF类型
*@param  duration:      播放时长
*@param  volume:        播放音量
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_play_dtmf(                                        
                        E_AMOPENAT_DTMF_TYPE dtmfType,     
                        UINT16 duration,                   
                        E_AMOPENAT_SPEAKER_GAIN volume     
                 )
{
    return IVTBL(play_dtmf)(dtmfType, duration, volume);
}

/**停止播放DTMF音
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_stop_dtmf(                                          
                        VOID
                 )
{
    return IVTBL(stop_dtmf)();
}

/**播放音频
*@param  playParam:     播放参数
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_play_music(T_AMOPENAT_PLAY_PARAM*  playParam)
{
    return IVTBL(play_music)(playParam);
}

/**停止音频播放
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_stop_music(                                       
                        VOID
                  )
{
    return IVTBL(stop_music)();
}

/**暂停音频播放
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_pause_music(                                       
                        VOID
                   )
{
    return IVTBL(pause_music)();
}

/**恢复音频播放
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_resume_music(                                     
                        VOID
                    )
{
    return IVTBL(resume_music)();
}

/**设置扬声器静音
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_mute_speaker(                                       
                        VOID
                    )
{
    return IVTBL(mute_speaker)();
}

/**解除扬声器静音
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_unmute_speaker(                                    
                        VOID
                      )
{
    return IVTBL(unmute_speaker)();
}

/**设置扬声器的音量值
*@param     vol:   设置扬声器音量值
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_set_speaker_vol(                                   
                        UINT32 vol 
                        )
{
    return IVTBL(set_music_volume)(vol);
}

/**获取扬声器的音量值
*@return	UINT32: 	 返回扬声器的音量值
**/
UINT32 iot_audio_get_speaker_vol(                
                        VOID
                                           )
{
    return IVTBL(get_music_volume)();
}

/**设通话的音量值
*@param     vol:   设置通话音量值
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_set_sph_vol(                                   
                        UINT32 vol 
                        )
{
    return IVTBL(set_sph_vol)(vol);
}

/**获取通话的音量值
*@return	UINT32: 	 返回通话的音量值
**/
UINT32 iot_audio_get_sph_vol(                
                        VOID
                        )
{
    return IVTBL(get_sph_vol)();
}


/**设置音频通道
*@param     channel:    通道
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_set_channel(                                        
                        E_AMOPENAT_AUDIO_CHANNEL channel   
                   )
{
    return IVTBL(set_channel)(channel);
}

/**获取当前通道
*@return	E_AMOPENAT_AUDIO_CHANNEL: 	  返回通道值
**/
E_AMOPENAT_AUDIO_CHANNEL iot_audio_get_current_channel(            
                        VOID
                                               )

{
    return IVTBL(get_current_channel)();
}

/**开始录音
*@param     param:   录音参数
*@param     cb:     获取录音数据回调
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_rec_start(
                    			E_AMOPENAT_RECORD_PARAM* param,
								AUD_RECORD_CALLBACK_T cb)
{
    return ((IVTBL(audio_record)(param, cb) == 0) ? 1 : 0);
}

/**停止录音
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_audio_rec_stop()
{
    return ((IVTBL(audio_stop_record)() == 0) ? 1 : 0);
}

/**流播放
*@param  playformat:    数据流类型
*@param  cb:    		数据流回调函数
*@param  data:    		数据流
*@param  len:  		  	数据流长度
*@return	>0: 	    播放长度
*           -1:      	播放失败
**/
int iot_audio_streamplay(E_AMOPENAT_AUD_FORMAT playformat,AUD_PLAY_CALLBACK_T cb,char* data,int len)
{
	return IVTBL(streamplay)(playformat,cb,data,len);
}

