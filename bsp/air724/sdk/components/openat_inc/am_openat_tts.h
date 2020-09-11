#ifndef _AM_OPENAT_TTS_H_
#define _AM_OPENAT_TTS_H_
/*+\new\wj\2019.12.27\添加TTS功能*/

typedef enum 
{
	tts_result_ok,
	tts_result_error,

}TTSResultCode;

typedef enum 
{
	OPENAT_TTS_PARAM_SPEED, /*播放速度 -32768 to +32767 */
	OPENAT_TTS_PARAM_VOLUME, /*播放音量参数 -32768 to +32767 */
	OPENAT_TTS_PARAM_PITCH, /*播放声调参数 -32768 to +32767 */
	OPENAT_TTS_PARAM_CODEPAGE,/* 文本类型 */
}OPENAT_TTS_PARAM_FLAG;

typedef enum 
{
	OPENAT_CODEPAGE_ASCII,
	OPENAT_CODEPAGE_GBK,
	OPENAT_CODEPAGE_BIG5,
	OPENAT_CODEPAGE_UTF16LE, //UTF-16，小头
	OPENAT_CODEPAGE_UTF16BE,  //UTF-16，大头
	OPENAT_CODEPAGE_UTF8, //UTF-8
	OPENAT_CODEPAGE_UTF16, 
	OPENAT_CODEPAGE_UNICODE,
	OPENAT_CODEPAGE_PHONETIC_PLAIN, //Phontic plain 音标编码
}TTS_CODEPAGE_PARAM;

typedef enum 
{
	FIRST_START,
	PLAYING,
	STOP
}TTSStatus;//tts 运行状态

typedef enum 
{	
	OPENAT_TTS_PLAY_OPREATION,	/*播放操作*/
	OPENAT_TTS_FINISH_OPRETION,	/*播放结束操作*/
	OPENAT_TTS_STOP_OPREATION,	/*停止播放操作*/

}OPENAT_TTS_OPERATION;


typedef struct
{
	int speed;
	int volume;
	int pitch;
	u32 codepage;
}TTS_PARAM_STRUCT;

typedef struct
{
	char *text;
	int size;
}TTS_PLAY_PARAM;

typedef enum 
{
	OPENAT_TTS_CB_MSG_ERROR,
	OPENAT_TTS_CB_MSG_STATUS	

}OPENAT_TTS_CB_MSG;

typedef void (*TTS_PLAY_CB)(OPENAT_TTS_CB_MSG msg_id,u8 event);	/*播放结束回调函数*/


BOOL OPENAT_tts_init(TTS_PLAY_CB fCb);
BOOL OPENAT_tts_set_param(OPENAT_TTS_PARAM_FLAG flag,u32 value);
BOOL OPENAT_tts_play(char *text,u32 len);
BOOL OPENAT_tts_stop();





/*-\new\wj\2019.12.27\添加TTS功能*/
#endif