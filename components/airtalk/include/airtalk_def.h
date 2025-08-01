#ifndef __AIRTALK_H__
#define __AIRTALK_H__
#include "luat_network_adapter.h"
#include "luat_rtos.h"

#define UPLOAD_CACHE_MAX (32)
#define DOWNLOAD_CACHE_MAX (32)
#define RECORD_DATA_MAX	(640)

enum
{
	AIRTALK_EVENT_AMR_ENCODE_ONCE = 1,
	AIRTALK_EVENT_AMR_DECODE_ONCE,
	AIRTALK_EVENT_AMR_START,			//audio处理流程开始
	AIRTALK_EVENT_AMR_RECORD_STOP,		//录音停止
	AIRTALK_EVENT_AMR_PLAY_STOP,		//播放停止


	AIRTALK_EVENT_NETWORK_DOWNLINK_DATA,	//下行数据，需要解码播放
	AIRTALK_EVENT_NETWORK_UPLINK_DATA,		//上行数据，已经编码过了
	AIRTALK_EVENT_NETWORK_UPLINK_END,
	AIRTALK_EVENT_NETWORK_READY_START,
	AIRTALK_EVENT_NETWORK_FORCE_SYNC,		//重新同步数据
	AIRTALK_EVENT_NETWORK_FORCE_STOP,		//停止对讲流程
	AIRTALK_EVENT_NETWORK_MSG,				//其他消息
};

typedef struct
{
	llist_head node;
	uint64_t local_tamp;
	uint32_t total_len;
	uint8_t save_data[RECORD_DATA_MAX];
}record_data_struct;

typedef struct
{
	luat_rtos_task_handle task_handle;
	llist_head upload_cache_head;
	llist_head download_cache_head;
	llist_head free_cache_head;
	uint32_t download_cache_time;
	luat_rtos_timer_t download_check_timer;
	CBDataFun_t send_function;
	CBDataFun_t recv_function;
	HANDLE record_cache_locker;
	uint32_t remote_ssrc;
	uint32_t local_ssrc;
	uint8_t remote_ssrc_exsit;
	uint8_t data_sync_ok;
	uint8_t is_ready;
	uint8_t audio_data_protocl;
	uint8_t is_16k;
	uint8_t work_mode;
	uint8_t debug_on_off;
}airtalk_network_ctrl_t;
#endif
