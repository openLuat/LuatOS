#include "csdk.h"
#include "airtalk_def.h"
#include "airtalk_api.h"
#include "luat_airtalk.h"
#include "luat_multimedia.h"

#define PCM_BLOCK_LEN (prv_speech.one_frame_len)
#define DOWNLOAD_CACHE_MASK	(14)		//下行数据缓存1<<14Byte (16K)
#define PCM_PLAY_FRAME_LOOP_CNT	(4)	//4个播放缓冲区循环使用
#define SPEECH_ONE_CACHE_MAX	(6400)	//16K单声道200ms的数据量
static const uint8_t  amr_nb_byte_len[16] = {12, 13, 15, 17, 19, 20, 26, 31, 5, 0, 0, 0, 0, 0, 0, 0};
static const uint8_t  amr_wb_byte_len[16] = {17, 23, 32, 36, 40, 46, 50, 58, 60, 5,0, 0, 0, 0, 0, 0};
typedef struct
{

	BSP_FifoStruct download_data_fifo;
	luat_rtos_task_handle speech_task_handle;
	int multimedia_id;
	void *audio_handle;
	const uint8_t *amr_byte_len;
	uint32_t one_frame_len;
	uint32_t play_data_cache[SPEECH_ONE_CACHE_MAX];
	uint32_t record_data_cache[SPEECH_ONE_CACHE_MAX >> 1];
	uint8_t *play_data_buffer;				//播放缓冲区
	uint8_t *record_data_buffer;
	uint16_t decode_frame_cnt;
	uint16_t encode_frame_cnt;
	uint16_t total_play_frame;							//播放缓冲区总共的帧数
	uint16_t ref_frame_start_pos;							//回声抑制参考起始帧位置
	volatile uint16_t record_frame_pos;					//已经缓存的录音帧数
	volatile uint16_t play_frame_pos;					//已经播放的帧数
	uint8_t record_enable;						//允许录音
	uint8_t play_enable;						//允许播放
	uint8_t audio_sleep_mode;
	uint8_t decode_sync_ok;
	volatile uint8_t record_buffer_pos;
	uint8_t debug_on_off;
	uint8_t amr_data_cahce[RECORD_DATA_MAX];
	uint8_t download_data_buffer[1 << DOWNLOAD_CACHE_MASK];					//测试用的播放缓冲区，正常播放不要使用

}speech_ctrl_t;

static speech_ctrl_t prv_speech;

static __USER_FUNC_IN_RAM__ int airtalk_record_cb(uint8_t id ,luat_i2s_event_t event, uint8_t *rx_data, uint32_t rx_len, void *param)
{

	if (!prv_speech.audio_handle) return 0;
	switch(event)
	{
	case LUAT_I2S_EVENT_RX_DONE:
		memcpy(&prv_speech.record_data_buffer[SPEECH_ONE_CACHE_MAX * prv_speech.record_buffer_pos + prv_speech.record_frame_pos * prv_speech.one_frame_len], rx_data, rx_len);
		prv_speech.record_frame_pos++;
		prv_speech.play_frame_pos++;
		if (prv_speech.record_frame_pos >= prv_speech.encode_frame_cnt)
		{
			if (prv_speech.record_enable)
			{
				luat_rtos_event_send(prv_speech.speech_task_handle, AIRTALK_EVENT_AMR_ENCODE_ONCE, prv_speech.record_buffer_pos, prv_speech.ref_frame_start_pos, 0, 0);
			}
			prv_speech.record_frame_pos = 0;
			prv_speech.record_buffer_pos = !prv_speech.record_buffer_pos;
			prv_speech.ref_frame_start_pos += prv_speech.encode_frame_cnt;
			if (prv_speech.ref_frame_start_pos >= prv_speech.total_play_frame)
			{
				prv_speech.ref_frame_start_pos = 0;
			}
		}
		if (prv_speech.play_frame_pos >= prv_speech.decode_frame_cnt)
		{
			luat_rtos_event_send(prv_speech.speech_task_handle, AIRTALK_EVENT_AMR_DECODE_ONCE, 0, 0, 0, 0);
			prv_speech.play_frame_pos = 0;
		}
		break;
	case LUAT_I2S_EVENT_TRANSFER_DONE:
		break;
	default:
		break;
	}
	return 0;
}

extern void log_on(void);
static void speech_task(void *param)
{
	if (!prv_speech.audio_sleep_mode)
	{
		prv_speech.audio_sleep_mode = LUAT_AUDIO_PM_SHUTDOWN;
	}
	if (!prv_speech.decode_frame_cnt)
	{
		prv_speech.decode_frame_cnt = 5;
	}
	if (!prv_speech.encode_frame_cnt)
	{
		prv_speech.encode_frame_cnt = 5;
	}
	prv_speech.play_data_buffer = (uint8_t *)prv_speech.play_data_cache;
	prv_speech.record_data_buffer = (uint8_t *)prv_speech.record_data_cache;
	luat_audio_conf_t* audio_conf = luat_audio_get_config(prv_speech.multimedia_id);
	luat_i2s_conf_t *i2s = luat_i2s_get_config(audio_conf->codec_conf.i2s_id);

	OS_InitFifo(&prv_speech.download_data_fifo, prv_speech.download_data_buffer, DOWNLOAD_CACHE_MASK);
	uint8_t *ref_input;
	luat_event_t event;
	uint32_t decode_pos = 0;
	uint32_t current_play_cnt = 0;					//当前播放缓冲区，用于解码数据存入下一个缓存
	uint32_t i,save_pos;
	uint32_t data_pos;
	PV_Union u_point;
	uint8_t out_len, lost_data, temp_len, need_stop_record, need_stop_play, wait_stop_play,is_amr_wb;
	uint8_t amr_buff[64];

	need_stop_record = 0;
	need_stop_play = 0;
	wait_stop_play = 0;
	temp_len = 0;
	prv_speech.debug_on_off = 1;
	while (1)
	{
		luat_rtos_event_recv(prv_speech.speech_task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
		switch(event.id)
		{
		case AIRTALK_EVENT_AMR_ENCODE_ONCE:
			if (!prv_speech.audio_handle)
			{
				break;
			}
			if (prv_speech.record_enable)
			{
				if (prv_speech.debug_on_off)
				{
					LUAT_DEBUG_PRINT("ref point %d, record cnt %d", event.param2, event.param1);
				}
				u_point.pu8 = &prv_speech.record_data_buffer[SPEECH_ONE_CACHE_MAX * event.param1];
				save_pos = 0;
				for(i = 0; i < prv_speech.encode_frame_cnt; i++)
				{
					ref_input = &prv_speech.play_data_buffer[PCM_BLOCK_LEN * event.param2 + i * PCM_BLOCK_LEN];
					//录音时刻对应的放音数据作为回声消除的参考数据输入，可以完美消除回声
					luat_audio_inter_amr_encode_with_ref(&u_point.pu16[(i * PCM_BLOCK_LEN) >> 1], amr_buff, &out_len, ref_input);
					memcpy(prv_speech.amr_data_cahce + save_pos, amr_buff, out_len);
					save_pos += out_len;
				}
				luat_airtalk_net_uplink_once(luat_mcu_tick64_ms(), prv_speech.amr_data_cahce, save_pos);
				//如果有停止录音的请求，让MQTT上行一次终止包
				if (need_stop_record)
				{
					LUAT_DEBUG_PRINT("upload stop!");
					need_stop_record = 0;
					prv_speech.record_enable = 0;
					luat_airtalk_callback(LUAT_AIRTALK_CB_RECORD_END, NULL, 0);
					luat_airtalk_net_uplink_end();
				}
			}
			break;
		case AIRTALK_EVENT_AMR_DECODE_ONCE:
			if (!prv_speech.audio_handle)
			{
				break;
			}
			current_play_cnt = (current_play_cnt + 1) & 0x3;
			decode_pos = (current_play_cnt + 1) & 0x03;
			if (prv_speech.debug_on_off)
			{
				LUAT_DEBUG_PRINT("play pos %u, decode pos %u", current_play_cnt, decode_pos);
			}
			if (prv_speech.decode_sync_ok)
			{
				lost_data = 0;
				for(i = 0; i < prv_speech.decode_frame_cnt; i++)
				{
					if (OS_CheckFifoUsedSpace(&prv_speech.download_data_fifo))
					{
						data_pos = (uint32_t)(prv_speech.download_data_fifo.RPoint & prv_speech.download_data_fifo.Mask);
						temp_len = prv_speech.amr_byte_len[(prv_speech.download_data_buffer[data_pos] >> 3) & 0x0f];
						OS_ReadFifo(&prv_speech.download_data_fifo, amr_buff, temp_len + 1);
						u_point.pu8 = &prv_speech.play_data_buffer[PCM_BLOCK_LEN * prv_speech.decode_frame_cnt * decode_pos + i * PCM_BLOCK_LEN];
						luat_audio_inter_amr_coder_decode(prv_speech.audio_handle, u_point.pu16, amr_buff, &out_len);
					}
					else
					{
						memset(&prv_speech.play_data_buffer[PCM_BLOCK_LEN * prv_speech.decode_frame_cnt * decode_pos + i * PCM_BLOCK_LEN], 0, PCM_BLOCK_LEN);
						lost_data = 1;

					}
				}
				if (lost_data)
				{
					LUAT_DEBUG_PRINT("lost");
					prv_speech.decode_sync_ok = 0;
					luat_airtalk_net_force_sync_downlink();
				}
			}
			else
			{
				if (prv_speech.debug_on_off)
				{
					LUAT_DEBUG_PRINT("no decode");
				}
				memset(&prv_speech.play_data_buffer[PCM_BLOCK_LEN * prv_speech.decode_frame_cnt * decode_pos], 0, prv_speech.decode_frame_cnt * PCM_BLOCK_LEN);
			}

			if (wait_stop_play)
			{
				wait_stop_play = 0;
				prv_speech.play_enable = 0;
				LUAT_DEBUG_PRINT("play stop!");
				luat_airtalk_callback(LUAT_AIRTALK_CB_PLAY_END, NULL, 0);
			}
			else if (need_stop_play)
			{
				LUAT_DEBUG_PRINT("play wait stop!");
				wait_stop_play = 1;
				need_stop_play = 0;
			}
			//既没有播放也没有录音，就直接停止audio
			if (!prv_speech.record_enable && !prv_speech.play_enable)
			{
				LUAT_DEBUG_PRINT("audio stop!");
				luat_audio_record_stop(prv_speech.multimedia_id);
				luat_audio_pm_request(prv_speech.multimedia_id, prv_speech.audio_sleep_mode);
				luat_audio_inter_amr_coder_deinit(prv_speech.audio_handle);
				luat_i2s_load_old_config(audio_conf->codec_conf.i2s_id);
				prv_speech.audio_handle = NULL;
				prv_speech.decode_sync_ok = 0;
				luat_airtalk_callback(LUAT_AIRTALK_CB_AUDIO_END, NULL, 0);
			}
			break;
		case AIRTALK_EVENT_AMR_START:
			if (!prv_speech.audio_handle)
			{
				is_amr_wb = event.param1?1:0;
				LUAT_DEBUG_PRINT("play start %s!", is_amr_wb?"amr-wb":"amr-nb");
				prv_speech.one_frame_len = 320 * (is_amr_wb + 1);
				luat_audio_pm_request(prv_speech.multimedia_id, LUAT_AUDIO_PM_RESUME);
				prv_speech.amr_byte_len = is_amr_wb?amr_wb_byte_len:amr_nb_byte_len;
				memset(prv_speech.play_data_cache, 0, sizeof(prv_speech.play_data_cache));
				memset(prv_speech.record_data_cache, 0, sizeof(prv_speech.record_data_cache));
				prv_speech.record_buffer_pos = 0;
				prv_speech.record_frame_pos = 0;
				prv_speech.play_frame_pos = 0;
				prv_speech.ref_frame_start_pos = 0;
				prv_speech.total_play_frame = prv_speech.decode_frame_cnt * PCM_PLAY_FRAME_LOOP_CNT;
				prv_speech.audio_handle = luat_audio_inter_amr_coder_init(is_amr_wb, 7 + is_amr_wb);
				prv_speech.download_data_fifo.RPoint  = 0;
				prv_speech.download_data_fifo.WPoint  = 0;
				current_play_cnt = 0;

				luat_i2s_save_old_config(audio_conf->codec_conf.i2s_id);
				i2s->cb_rx_len = PCM_BLOCK_LEN;
				i2s->luat_i2s_event_callback = airtalk_record_cb;
				luat_audio_record_and_play(prv_speech.multimedia_id, 8000 * (is_amr_wb + 1), prv_speech.play_data_buffer, prv_speech.decode_frame_cnt * PCM_BLOCK_LEN, PCM_PLAY_FRAME_LOOP_CNT);
				luat_airtalk_callback(LUAT_AIRTALK_CB_PLAY_START, NULL, 0);
				if (prv_speech.record_enable)//已经请求录音了，那么就开始录音了
				{
//					LUAT_DEBUG_PRINT("record start!");
					luat_airtalk_callback(LUAT_AIRTALK_CB_RECORD_START, NULL, 0);
				}
				luat_airtalk_callback(LUAT_AIRTALK_CB_AUDIO_START, NULL, 0);
			}

			break;
		case AIRTALK_EVENT_AMR_RECORD_STOP:
			if (prv_speech.record_enable)
			{
				need_stop_record = 1;
				LUAT_DEBUG_PRINT("record require stop!");
			}
			break;
		case AIRTALK_EVENT_AMR_PLAY_STOP:
			if (prv_speech.play_enable && !need_stop_play)
			{
				need_stop_play = 1;
				LUAT_DEBUG_PRINT("play require stop!");
			}
			break;
		}
	}
}

void luat_airtalk_speech_init(void)
{
#if defined (FEATURE_AMR_CP_ENABLE) || defined (FEATURE_VEM_CP_ENABLE)
	if (!prv_speech.speech_task_handle)
	{
		luat_rtos_task_create(&prv_speech.speech_task_handle, 4096, 100, "airtalk_speech", speech_task, NULL, 64);
	}
#else
	LUAT_DEBUG_PRINT("sdk no audio function, stop!!!");
#endif
}

void luat_airtalk_speech_audio_param_config(int multimedia_id, uint8_t audio_sleep_mode)
{
	prv_speech.multimedia_id = multimedia_id;
	prv_speech.audio_sleep_mode = audio_sleep_mode;
}

void luat_airtalk_speech_start_play(uint8_t is_16k)
{
	if (!prv_speech.audio_handle)
	{
		prv_speech.play_enable = 1;
		luat_rtos_event_send(prv_speech.speech_task_handle, AIRTALK_EVENT_AMR_START, is_16k, 0, 0, 0);
	}
}

void luat_airtalk_speech_stop_play()
{
	LUAT_DEBUG_PRINT("broadcast play end!");
	luat_rtos_event_send(prv_speech.speech_task_handle, AIRTALK_EVENT_AMR_PLAY_STOP, 0, 0, 0, 0);
}

void luat_airtalk_speech_sync_ok(void)
{
	prv_speech.decode_sync_ok = 1;
}

int luat_airtalk_speech_set_one_block_frame_cnt(uint8_t decode_frame_cnt, uint8_t encode_frame_cnt)
{
	if (prv_speech.audio_handle) return -ERROR_DEVICE_BUSY;
	if (decode_frame_cnt > 10) return -ERROR_PARAM_INVALID;
	if (decode_frame_cnt < 2) return -ERROR_PARAM_INVALID;
	if (encode_frame_cnt < 2) return -ERROR_PARAM_INVALID;
	if (encode_frame_cnt > 5) return -ERROR_PARAM_INVALID;
	prv_speech.decode_frame_cnt = decode_frame_cnt;
	prv_speech.encode_frame_cnt = encode_frame_cnt;
	return 0;
}

void luat_airtalk_speech_save_downlink_data(uint8_t *data, uint32_t len)
{
	OS_WriteFifo(&prv_speech.download_data_fifo, data, len);
}

void luat_airtalk_speech_record_switch(uint8_t on_off)
{
	if (on_off)
	{
		if (!prv_speech.audio_handle)
		{
			prv_speech.record_enable = 1;
			luat_rtos_event_send(prv_speech.speech_task_handle, AIRTALK_EVENT_AMR_START, luat_airtalk_is_16k(), 0, 0, 0);
		}
		else
		{
			if (!prv_speech.record_enable)
			{
				prv_speech.record_enable = 1;
				LUAT_DEBUG_PRINT("record start!");
				luat_airtalk_callback(LUAT_AIRTALK_CB_RECORD_START, NULL, 0);
			}
		}
	}
	else
	{
		luat_rtos_event_send(prv_speech.speech_task_handle, AIRTALK_EVENT_AMR_RECORD_STOP, 0, 0, 0, 0);
	}
}

void luat_airtalk_speech_debug_switch(uint8_t on_off)
{
	prv_speech.debug_on_off = on_off;
	if (on_off) 	log_on();
}
