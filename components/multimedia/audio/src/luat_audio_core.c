#include "luat_base.h"
#include "luat_audio_core.h"
#include "luat_common_api.h"
#include "luat_fs.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include <string.h>
#include <sys/_types.h>
#define LUAT_LOG_TAG "audio_core"
#include "luat_log.h"
#include "luat_gpio.h"
#define LUAT_AUDIO_DATA_BUFFER_CNT	4
unsigned char luat_audio_debug_flag = 1;	// 调试标志位，默认1，开启调试
enum {
	LUAT_AUDIO_EV_TX_NEED_DATA = 0x01,	// 放音需要更多数据事件
	LUAT_AUDIO_EV_TX_NO_DATA,			// 放音数据完成事件
	LUAT_AUDIO_EV_RX_ENOUGH_DATA,		// 接收数据完成事件
	LUAT_AUDIO_EV_REQUEST,			// 请求启动事件
	LUAT_AUDIO_EV_REQUEST_CANCEL,	// 请求取消事件
	LUAT_AUDIO_EV_PRINT,		// 请求完成事件
	LUAT_AUDIO_EV_TTS_RUN = 0x01,
};

typedef struct
{
	luat_llist_head request_block_list;		// 请求块列表	
	luat_audio_driver_ctrl_t driver_ctrl[LUAT_AUDIO_DRIVER_MAX];
	luat_audio_channel_t channel[LUAT_AUDIO_DRIVER_MAX];
	luat_audio_request_block_t *current_request_block; // 当前正在处理的请求块
	luat_rtos_task_handle common_task_handle;
	luat_rtos_task_handle tts_task_handle;
	void *request_lock;	// 请求块列表操作保护锁
	void *tts_wait_sem;	// tts任务等待信号量
	uint32_t next_request_id;		// 下一个请求id
	uint8_t default_driver_index;	// 默认驱动索引
	uint8_t all_driver_nums;				// 已注册的音频驱动匹配结构数量
	uint8_t decode_is_running:1;			// 解码标志位
}luat_audio_ctrl_t;

static luat_audio_ctrl_t _luat_audio;

#ifdef LUAT_CSDK_CONFIG_FILE
#include LUAT_CSDK_CONFIG_FILE
#endif

#ifndef __LUAT_C_CODE_IN_ISR__
#define __LUAT_C_CODE_IN_ISR__
#endif

extern void soc_printf(char *fmt, ...);

static __LUAT_C_CODE_IN_ISR__ void _audio_play_next_block(struct luat_audio_driver_ctrl *ctrl)
{
	volatile uint32_t next_play_cnt;
	ctrl->current_play_cnt = (ctrl->current_play_cnt + 1) & (LUAT_AUDIO_DATA_BUFFER_CNT - 1);
	// soc_printf("current_play_cnt %d", ctrl->current_play_cnt);
	if (!_luat_audio.current_request_block ) {
		goto CHECK_FILL_BLANK;
	} else {
		if (_luat_audio.current_request_block->play_codec.opts->type == LUAT_AUDIO_DATA_CODEC_TYPE_NO_OP) {
			return;
		}
		if (!_luat_audio.current_request_block->is_wait_play_end && (ctrl->data_channel->user_play_stop || !ctrl->audio_output_enable)) {
			goto CHECK_FILL_BLANK;
		}
	}

	next_play_cnt = (ctrl->current_play_cnt + 1) & (LUAT_AUDIO_DATA_BUFFER_CNT - 1);
	uint8_t *next_play_buff = ctrl->play_buff_byte + ctrl->one_play_block_len * next_play_cnt;
	uint32_t read_len  = luat_fifo_check_used_space(ctrl->data_channel->play_fifo);
	if (read_len < ctrl->one_play_block_len) {	//fifo没有完整的1个block
		if (!_luat_audio.current_request_block->is_wait_play_end) { // 播放状态为非等待播放结束，说明数据不够，填充空白音
			ctrl->opts->fill(ctrl, next_play_buff, ctrl->one_play_block_len, ctrl->opts->is_tx_signed, ctrl->common_param.data_align);
			luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_PRINT, 0, read_len, ctrl->one_play_block_len, 0);
		} else { // 播放状态为等待播放结束，说明数据不够，填充剩余数据为空白音
			read_len = luat_fifo_read(ctrl->data_channel->play_fifo, next_play_buff, ctrl->one_play_block_len);
			if (read_len < ctrl->one_play_block_len) { 	// fifo没有完整的1个block
				ctrl->opts->fill(ctrl, next_play_buff + read_len, ctrl->one_play_block_len - read_len, ctrl->opts->is_tx_signed, ctrl->common_param.data_align);
			}
		}
	} else {
		read_len = luat_fifo_read(ctrl->data_channel->play_fifo, next_play_buff, ctrl->one_play_block_len);
	}
	// soc_printf("read_len %u %d-%d-%x,%u,%x,%d", read_len, ctrl->current_play_cnt, next_play_cnt,next_play_buff,
	// 	ctrl->one_play_block_len, _luat_audio.current_request_block,_luat_audio.current_request_block->is_wait_play_end);
	if (_luat_audio.current_request_block->is_wait_play_end && (read_len >= ctrl->one_play_block_len)) {
		return;
	}
	if (!_luat_audio.decode_is_running && luat_fifo_check_free_space(ctrl->data_channel->play_fifo) >= ctrl->data_channel->play_fifo_low_level) { // fifo剩余数据不足低水位，需要请求更多数据
		luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_TX_NEED_DATA, (uint32_t)ctrl, 0, 0, 0);
	}
	ctrl->data_channel->play_is_stop = 0;
	return ;
CHECK_FILL_BLANK:
	if (!ctrl->data_channel->play_is_stop) {
		if (ctrl->play_buff_byte) {	// 播放缓冲区填充空白音
			ctrl->opts->fill(ctrl, ctrl->play_buff_byte, ctrl->one_play_block_len * LUAT_AUDIO_DATA_BUFFER_CNT, ctrl->opts->is_tx_signed, ctrl->common_param.data_align);
		}
		ctrl->data_channel->play_is_stop = 1;
		luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_PRINT, 2, 0, 0, 0);
	}
}

LUAT_WEAK __LUAT_C_CODE_IN_ISR__ void luat_audio_driver_event_callback(uint32_t event, uint8_t *rx_data, uint32_t param, struct luat_audio_driver_ctrl *ctrl)
{

	uint32_t rest_data_len;
	switch (event) {
	case LUAT_AUDIO_DRIVER_EVENT_TX_ONE_BLOCK_DONE:
		if (ctrl->opts->support_full_loop) {
			return;
		}
		_audio_play_next_block(ctrl);
		break;
	case LUAT_AUDIO_DRIVER_EVENT_RX_ONE_BLOCK_DONE:
		if (ctrl->common_param.driver_work_mode >= LUAT_AUDIO_DRIVER_MODE_RECORD) {
			if (_luat_audio.current_request_block && !_luat_audio.current_request_block->is_record_end) {
				if (_luat_audio.current_request_block->data_channel != ctrl->data_channel) {
					luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_PRINT, 1, (uint32_t)_luat_audio.current_request_block->data_channel, (uint32_t)ctrl->data_channel, 0);
				} else {
					rest_data_len = luat_fifo_check_free_space(ctrl->data_channel->record_fifo);
					if (param < rest_data_len) {
						luat_fifo_write(ctrl->data_channel->record_fifo, rx_data, param);
						if (_luat_audio.current_request_block->is_need_ref_data) {
							luat_fifo_write(ctrl->data_channel->ref_fifo, ctrl->play_buff_byte + ctrl->one_play_block_len * ctrl->current_play_cnt, ctrl->one_play_block_len);
							if (luat_fifo_check_used_space(ctrl->data_channel->ref_fifo) != luat_fifo_check_used_space(ctrl->data_channel->record_fifo)) {
								_luat_audio.current_request_block->error_record_ref_not_match = 1;
							}
						}
					} else {
						_luat_audio.current_request_block->error_record_overflow = 1;
					}

					if (luat_fifo_check_used_space(ctrl->data_channel->record_fifo) >= _luat_audio.current_request_block->record_fifo_enough_data_level) {	// 录音数据足够，发送事件
						luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_RX_ENOUGH_DATA, (uint32_t)ctrl, ctrl->current_play_cnt, 0, 0);
					}
				}
			}
		}
		if (ctrl->opts->support_full_loop) {
			_audio_play_next_block(ctrl);
		}
		break;
	default:
		break;
	}
}

static void _audio_find_next_request_block(void)
{
	if (luat_llist_empty(&_luat_audio.request_block_list)) {
		LLOGC(luat_audio_debug_flag, "no request block");
		return;
	}
	_luat_audio.current_request_block = (luat_audio_request_block_t *)_luat_audio.request_block_list.next;
	luat_llist_del(&_luat_audio.current_request_block->node);
}


static int _audio_add_request(void *node, void *param)
{
	luat_audio_request_block_t *old_req = (luat_audio_request_block_t *)node;
	luat_audio_request_block_t *new_req = (luat_audio_request_block_t *)param;
	if (new_req->priority > old_req->priority)
	{
		LLOGC(luat_audio_debug_flag, "add request id %d priority %d before request id %d priority %d", new_req->request_id, new_req->priority, old_req->request_id, old_req->priority);
		luat_llist_add_tail(&new_req->node, &old_req->node);
		return LUAT_LIST_FIND;
	}
	return LUAT_LIST_PASS;
}

static int _audio_find_request(void *node, void *param)
{
	luat_audio_request_block_t *req = (luat_audio_request_block_t *)node;
	luat_audio_driver_ctrl_t *ctrl = (luat_audio_driver_ctrl_t *)param;
	if (req->data_channel->driver_ctrl == ctrl)
	{
		return LUAT_LIST_FIND;
	}
	return LUAT_LIST_PASS;
}

static int _audio_tts_output_callback(void *data, uint32_t param, void *user_data)
{
	luat_audio_request_block_t *request_block = (luat_audio_request_block_t *)user_data;
	int ret;
	if (data) {
		while(!request_block->is_user_stop && (luat_fifo_check_used_space(request_block->data_channel->play_fifo) >= request_block->data_channel->play_fifo_high_level))
		{
			LLOGC(luat_audio_debug_flag, "tts wait fifo space %d", luat_fifo_check_used_space(request_block->data_channel->play_fifo));
			if (luat_rtos_semaphore_take(_luat_audio.tts_wait_sem, 1000)) {
				LLOGE("tts wait timeout");
				return -1;
			}
		}
		if (request_block->is_user_stop) {
			LLOGC(luat_audio_debug_flag, "tts user stop, stop");
			return -1;
		}
		uint32_t written_bytes;
		luat_buffer_write(&request_block->out_buffer, data, param);
		ret = luat_audio_channel_write_data(request_block->data_channel, &request_block->out_buffer, &request_block->data_align_buffer, 
			&request_block->channel_nums_buffer, &written_bytes, &request_block->play_codec.common_param);
		if (ret) {
			request_block->is_error_stop = 1;
			LLOGE("tts write data failed");
			return -1;
		}
		if (written_bytes) {
			request_block->out_buffer.pos  = 0;
		}
	} else {
		LLOGC(luat_audio_debug_flag, "tts start, play info %u,%u,%u", request_block->play_codec.common_param.sample_rate, request_block->play_codec.common_param.data_align, request_block->play_codec.common_param.channel_nums);
		ret = luat_audio_driver_start(request_block->data_channel->driver_ctrl, &request_block->play_codec.common_param, NULL, 0, LUAT_AUDIO_DATA_BUFFER_CNT);
		if (ret) {
			LLOGE("tts start driver failed");
			return -1;
		}
		luat_buffer_reinit(&request_block->out_buffer, 8192);
		if (!request_block->out_buffer.data) {
			LLOGE("tts init output bufferfailed");
			return -1;
		}
		luat_audio_request_init_play_temp_buffer(request_block);
	}
	return LUAT_ERROR_NONE;
}

/**
 * @brief 请求块完成
 */
static void _audio_request_finish(void)
{
	luat_audio_request_block_t *request_block = _luat_audio.current_request_block;
	luat_audio_driver_ctrl_t *ctrl = request_block->data_channel->driver_ctrl;
	luat_audio_request_cb_t cb = request_block->cb;
	void *done_sem = request_block->done_sem;
	void *cancel_sem = request_block->cancel_sem;

	uint32_t cr = luat_rtos_entry_critical();
	luat_fifo_clear(request_block->data_channel->play_fifo);
	luat_fifo_clear(request_block->data_channel->record_fifo);
	luat_fifo_clear(request_block->data_channel->ref_fifo);
	_luat_audio.current_request_block = NULL;
	luat_rtos_exit_critical(cr);
	luat_audio_request_deinit(request_block);
	cb(LUAT_AUDIO_REQUEST_EVENT_END, NULL, 0, request_block);

	if (done_sem) {
		luat_mutex_unlock(done_sem);
	}
	if (cancel_sem) {
		luat_mutex_unlock(cancel_sem);
	}
	luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
}

static void _audio_current_request_stop(void)
{
	_luat_audio.current_request_block->is_input_end = 1;
	_luat_audio.current_request_block->is_wait_play_end = 1;
	_luat_audio.current_request_block->play_blank_data_cnt = 0;
	_luat_audio.current_request_block->is_record_end = 1;
	luat_audio_driver_pa_power_off(_luat_audio.current_request_block->data_channel->driver_ctrl);
    luat_audio_driver_codec_power_off(_luat_audio.current_request_block->data_channel->driver_ctrl);
	uint32_t cr = luat_rtos_entry_critical();
	luat_fifo_clear(_luat_audio.current_request_block->data_channel->play_fifo);
	luat_rtos_exit_critical(cr);
	LLOGC(luat_audio_debug_flag, "current request stop, wait play end");
	if (_luat_audio.current_request_block->driver_work_mode == LUAT_AUDIO_DRIVER_MODE_RECORD) {
		_audio_request_finish();
	}
}


static void luat_audio_tts_task(void *param)
{
	luat_event_t out_event;
	luat_audio_request_block_t *tts_request_block;
	for(;;)
	{
		luat_rtos_event_recv(_luat_audio.tts_task_handle, 0, &out_event, NULL, 0);
		switch (out_event.id) {
		case LUAT_AUDIO_EV_TTS_RUN:
			tts_request_block = (luat_audio_request_block_t *)out_event.param1;
			if (tts_request_block->request_id == _luat_audio.current_request_block->request_id) {
				if (tts_request_block->play_codec.opts->tts_decode_sync(&tts_request_block->play_codec, tts_request_block->tts_data, tts_request_block->tts_data_size, tts_request_block)) {
					tts_request_block->is_error_stop = 1;
					LLOGE("tts decode sync failed");
				} else {
					tts_request_block->is_input_end = 1;
					LLOGC(luat_audio_debug_flag, "tts decode sync end");
				}
				luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_TX_NEED_DATA, (uint32_t)tts_request_block, 0, 0, 0);
			}
			break;
		default:
			break;
		}
	}
}


/**
 * @brief 解码当前请求块的播放信息
 * @param request_block 请求块
 */
static void _audio_decode_current_request_play_info(luat_audio_request_block_t *request_block)
{
	uint8_t error = 0;
	int ret;
	request_block->play_codec.common_param.sample_rate = 0;
	while (!request_block->play_codec.common_param.sample_rate && !request_block->is_error_stop && !request_block->is_user_stop && request_block->file_done_cnt < request_block->file_info_cnt) {
		if (request_block->play_codec.opts) {
			//已经指定了解码器则自动处理
			if (luat_audio_get_play_info_from_file(&request_block->play_codec, &request_block->file_info[request_block->file_done_cnt])) {
				LLOGE("no play info found for file %d", request_block->file_done_cnt);
				error = 1;
			} else {
				LLOGC(luat_audio_debug_flag, "find play info %u,%u,%u", request_block->play_codec.common_param.sample_rate, request_block->play_codec.common_param.data_align, request_block->play_codec.common_param.channel_nums);
			}
		} else {
			luat_audio_data_codec_t codec = {0};
			codec.common_param.driver_work_mode = LUAT_AUDIO_DRIVER_MODE_PLAY;
			uint8_t codec_type = 255;
			//没有指定解码器则需要搜索所有的解码器，解码尝试分析播放参数，找到合适的解码器
			for (int i = 0; i < LUAT_AUDIO_DATA_CODEC_TYPE_MAX; i++) {
				codec.opts = (luat_audio_data_codec_opts_t *)luat_audio_data_codec_find(i);
				if (!codec.opts || !codec.opts->support_detect) {
					continue;
				}
				if (LUAT_ERROR_NONE == luat_audio_get_play_info_from_file(&codec, &request_block->file_info[request_block->file_done_cnt])) {
					LLOGC(luat_audio_debug_flag, "auto search find codec %d", i);
					codec_type = i;
					break;
				}
			}
			if (255 == codec_type) {
				LLOGE("no play info found for file %d", request_block->file_done_cnt);
				error = 1;
			}
			if (!error) {
				// 绑定解码器
				ret = luat_audio_data_codec_bind(&request_block->play_codec, luat_audio_data_codec_find(codec_type), request_block);
				if (ret) {
					LLOGE("bind codec %d failed, ret %d", codec_type, ret);
					error = 1;
				} else {
					if (request_block->play_codec.opts->init(&request_block->play_codec, 0)) {
						LLOGE("init codec %d failed", codec_type);
						luat_audio_data_codec_deinit(&request_block->play_codec);
						luat_audio_data_codec_unbind(&request_block->play_codec);
						error = 1;
					} else {
						request_block->play_codec.common_param = codec.common_param;
						LLOGC(luat_audio_debug_flag, "find codec %d, play info %u,%u,%u", codec_type, request_block->play_codec.common_param.sample_rate, request_block->play_codec.common_param.data_align, request_block->play_codec.common_param.channel_nums);
					}
				}
			}
		}
		if (error) {
			if (request_block->file_info[request_block->file_done_cnt].fail_continue) {
				LLOGC(luat_audio_debug_flag, "continue decode file %d", request_block->file_done_cnt);
				request_block->file_done_cnt++;
				continue;
			} else {
				request_block->is_error_stop = 1;
			}
		} else {
			return;
		}
	}
	LLOGE("no play info found for request id %d", request_block->request_id);
	request_block->is_error_stop = 1;
}

/**
 * @brief 解码文件开始
 * @param request_block 请求块
 */
static void _audio_decode_file_start(luat_audio_request_block_t *request_block)
{
	if (!request_block->is_stream) {
		_audio_decode_current_request_play_info(request_block);
	}
	if (request_block->is_error_stop || request_block->is_user_stop) {
		return;
	}
	luat_buffer_reinit(&request_block->out_buffer, request_block->play_codec.opts->decode_max_output_len * 2);
	if (!request_block->out_buffer.data) {
		LLOGE("create out buffer failed, no memory");
		request_block->is_error_stop = 1;
	}
	request_block->is_stream_end = 0;
}
/**
 * @brief 解码一次后，写入数据到播放fifo
 * @param request_block 请求块
 * @param stop 是否停止解码循环
 * @param is_file_end 是否为文件结束
 */
static void _audio_after_decode_once(luat_audio_request_block_t *request_block, uint8_t *stop, uint8_t is_file_end)
{
	if (request_block->out_buffer.pos) {
		uint32_t written_bytes;
		int ret = luat_audio_channel_write_data(request_block->data_channel, &request_block->out_buffer, &request_block->data_align_buffer, 
			&request_block->channel_nums_buffer, &written_bytes, &request_block->play_codec.common_param);	
		if (ret) {
			request_block->is_error_stop = 1;
			LLOGE("write data failed ret %d", ret);
			*stop = 1;
		}
		request_block->out_buffer.pos -= written_bytes;
		if (!written_bytes) {
			*stop = 1;
			return;
		}
	}

	uint32_t rest_bytes = luat_fifo_check_used_space(request_block->org_input_data_fifo);
	if (request_block->is_input_end || is_file_end) {
		if (!rest_bytes) { // 文件结束，且fifo数据为空，结束解码循环
			*stop = 1;
		}
	} else {
		if (rest_bytes < request_block->play_codec.opts->decode_min_input_len) {
			*stop = 1;
		}
	}
}

static void _audio_decode_stream_to_fifo(luat_audio_request_block_t *request_block)
{
	uint8_t stop = 0;
	int ret;

	while (!stop && !request_block->is_error_stop && !request_block->is_user_stop && (luat_fifo_check_used_space(request_block->data_channel->play_fifo) < request_block->data_channel->play_fifo_high_level)) {	//fifo剩余数据不足高水位，需要请求更多数据
		ret =luat_audio_data_codec_decode_once(&request_block->play_codec, 
			request_block->org_input_data_fifo, 
			&request_block->out_buffer, 
			request_block->is_input_end);
		if (ret) {
			LLOGE("decode failed, ret = %d", ret);
			request_block->is_error_stop = 1;
			return;
		}
		_audio_after_decode_once(request_block, &stop, 0);
	}
}

static void _audio_decode_file_to_fifo(luat_audio_request_block_t *request_block)
{
	int ret = 0;
	uint8_t is_file_end = 0;
	uint8_t stop = 0;
	uint8_t error  = 0;
	while (!stop && !request_block->is_error_stop && !request_block->is_user_stop && (luat_fifo_check_used_space(request_block->data_channel->play_fifo) < request_block->data_channel->play_fifo_high_level)) {	//fifo剩余数据不足高水位，需要请求更多数据
		error = 0;
		ret = 0;
		if (!request_block->is_input_end) {
			ret = luat_audio_data_read_to_fifo(&request_block->file_info[request_block->file_done_cnt], request_block->org_input_data_fifo, &is_file_end);
		}
		// 有没有读取错误
		if (ret < 0) {
			LLOGC(luat_audio_debug_flag, "read file %d failed", request_block->file_done_cnt, ret);
			if (request_block->file_info[request_block->file_done_cnt].fail_continue) {
				is_file_end = 1;
			} else {
				request_block->is_error_stop = 1;
				is_file_end = 0;
			}
		}
		if (is_file_end) { //读到文件结尾了，看看是否还有文件文件读	
			if (!request_block->is_input_end) {
				request_block->file_done_cnt++;
				LLOGC(luat_audio_debug_flag, "decode file to fifo done,request id %u, file_done_cnt %d, total %d", request_block->request_id, request_block->file_done_cnt, request_block->file_info_cnt);
			}
			if (request_block->file_done_cnt >= request_block->file_info_cnt) {	//全部文件读取完成
				request_block->is_input_end = 1;
				request_block->file_done_cnt = request_block->file_info_cnt;
			} else { // 还有文件未读取，开始读取下一个文件
				_audio_decode_current_request_play_info(request_block);
			}
		}
		if (request_block->is_error_stop || request_block->is_user_stop || error) {
			stop = 1;
		}
		if (!stop) {
			ret =luat_audio_data_codec_decode_once(&request_block->play_codec, 
				request_block->org_input_data_fifo, 
				&request_block->out_buffer, 
				request_block->is_input_end || is_file_end);
			if (ret) {
				LLOGE("decode failed, ret = %d", ret);
				request_block->is_error_stop = 1;
				return;
			}
			_audio_after_decode_once(request_block, &stop, is_file_end);
		}
	}
}

static void _audio_start_request(luat_audio_request_block_t *request_block)
{
	int ret = -LUAT_ERROR_ID_INVALID;
	uint8_t check_tx_fifo,check_rx_fifo,check_ref_fifo;
	switch (request_block->driver_work_mode) {
		case LUAT_AUDIO_DRIVER_MODE_PLAY:
			check_tx_fifo = 1;
			check_rx_fifo = 0;
			check_ref_fifo = 0;
			break;
		case LUAT_AUDIO_DRIVER_MODE_RECORD:
			check_tx_fifo = 0;
			check_rx_fifo = 1;
			check_ref_fifo = 0;
			break;
		default:
			check_tx_fifo = 1;
			check_rx_fifo = 1;
			check_ref_fifo = 1;
			break;
	}	
	if (check_tx_fifo) {
		if (!request_block->data_channel->play_fifo) {
			LLOGD("driver 0x%x create play fifo", request_block->data_channel->driver_ctrl->probe.probe_id);
			request_block->data_channel->play_fifo = luat_fifo_create(LUAT_AUDIO_CHANNEL_PLAY_FIFO_DEFAULT_SIZE_POWER);
			request_block->data_channel->play_fifo_low_level = 32 * 1024;
			request_block->data_channel->play_fifo_high_level = request_block->data_channel->play_fifo->size - 16 * 1024;
		}
		if (!request_block->data_channel->play_fifo) {
			LLOGE("driver 0x%x create play fifo failed", request_block->data_channel->driver_ctrl->probe.probe_id);
			request_block->is_error_stop = 1;
			return;
		}
	}
	if (check_rx_fifo) {
		if (!request_block->data_channel->record_fifo) {
			LLOGD("driver 0x%x create record fifo", request_block->data_channel->driver_ctrl->probe.probe_id);
			request_block->data_channel->record_fifo = luat_fifo_create(LUAT_AUDIO_CHANNEL_RECORD_FIFO_DEFAULT_SIZE_POWER);
		}
		if (!request_block->data_channel->record_fifo) {
			LLOGE("driver 0x%x create record fifo failed", request_block->data_channel->driver_ctrl->probe.probe_id);
			request_block->is_error_stop = 1;
			return;
		}
		request_block->record_codec.common_param.one_frame_bytes_from_driver = request_block->record_codec.common_param.one_frame_sample_cnt * request_block->data_channel->driver_ctrl->common_param.data_align * request_block->data_channel->driver_ctrl->common_param.channel_nums;
		if (!request_block->record_callback_frame_cnt) {
			request_block->record_callback_frame_cnt = request_block->data_channel->driver_ctrl->one_record_block_len / request_block->record_codec.common_param.one_frame_bytes_from_driver;
			if (!request_block->record_callback_frame_cnt) {
				request_block->record_callback_frame_cnt = 1;
			}
		}
		request_block->record_fifo_enough_data_level = request_block->record_callback_frame_cnt * request_block->record_codec.common_param.one_frame_bytes_from_driver;
		LLOGC(luat_audio_debug_flag, "record driver frame len %u callback frame cnt %u driver max rx len %u", 
			request_block->record_codec.common_param.one_frame_bytes_from_driver, 
			request_block->record_callback_frame_cnt, 
			request_block->data_channel->driver_ctrl->opts->rx_one_block_max_len);
	}
	if (check_ref_fifo) {
		if (!request_block->data_channel->ref_fifo) {
			LLOGD("driver 0x%x create ref fifo", request_block->data_channel->driver_ctrl->probe.probe_id);
			request_block->data_channel->ref_fifo = luat_fifo_create(LUAT_AUDIO_CHANNEL_RECORD_FIFO_DEFAULT_SIZE_POWER);
		}
		if (!request_block->data_channel->ref_fifo) {
			LLOGE("driver 0x%x create ref fifo failed", request_block->data_channel->driver_ctrl->probe.probe_id);
			request_block->is_error_stop = 1;
			return;
		}
	}

	request_block->cb(LUAT_AUDIO_REQUEST_EVENT_START, NULL, 0, request_block);
	switch (request_block->driver_work_mode) {
		case LUAT_AUDIO_DRIVER_MODE_PLAY:
			if (request_block->is_tts) {	//TTS模式发送给tts_task处理
				if (request_block->play_codec.opts->is_tts_asynchronous) {
					LLOGE("request id %d tts asynchronous mode not support", request_block->request_id);
					request_block->is_error_stop = 1;
					return;
				} else {
					luat_rtos_event_send(_luat_audio.tts_task_handle, LUAT_AUDIO_EV_TTS_RUN, (uint32_t)request_block, 0, 0, 0);
				}
				return;
			} else  {	//本地文件模式
				_audio_decode_file_start(request_block);
				if (request_block->is_error_stop || request_block->is_user_stop) {
					return;
				}
				request_block->data_channel->driver_ctrl->opts->modify_audio_common_param(request_block->data_channel->driver_ctrl, request_block->play_codec.common_param.sample_rate, request_block->play_codec.common_param.data_align,request_block->play_codec.common_param.channel_nums);
				luat_audio_request_init_play_temp_buffer(request_block);
				if (!request_block->is_stream) {
					_audio_decode_file_to_fifo(request_block);
				} else {
					request_block->cb(LUAT_AUDIO_REQUEST_EVENT_NEED_NEW_DATA, NULL, 0, request_block);
					_audio_decode_stream_to_fifo(request_block);
				}
			}
			ret = luat_audio_driver_start(request_block->data_channel->driver_ctrl, &request_block->play_codec.common_param, NULL, request_block->is_stream ? request_block->stream_one_block_len : 0, LUAT_AUDIO_DATA_BUFFER_CNT);
			
			break;
		case LUAT_AUDIO_DRIVER_MODE_RECORD:
			request_block->record_codec.common_param.driver_work_mode = LUAT_AUDIO_DRIVER_MODE_RECORD;
			ret = luat_audio_driver_start(request_block->data_channel->driver_ctrl, &request_block->record_codec.common_param, NULL, request_block->record_fifo_enough_data_level, LUAT_AUDIO_DATA_BUFFER_CNT);
			luat_audio_request_init_record_temp_buffer(request_block);
			request_block->is_need_ref_data = 0;
			break;
		case LUAT_AUDIO_DRIVER_MODE_SPEECH:
			request_block->record_codec.common_param.driver_work_mode = LUAT_AUDIO_DRIVER_MODE_SPEECH;
			ret = luat_audio_driver_start(request_block->data_channel->driver_ctrl, &request_block->record_codec.common_param, NULL, request_block->record_fifo_enough_data_level, LUAT_AUDIO_DATA_BUFFER_CNT);
			luat_audio_request_init_play_temp_buffer(request_block);
			luat_audio_request_init_record_temp_buffer(request_block);
			request_block->is_need_ref_data = 1;
			break;
		case LUAT_AUDIO_DRIVER_MODE_SPEECH_WITH_BUFFER:
			request_block->record_codec.common_param.driver_work_mode = LUAT_AUDIO_DRIVER_MODE_SPEECH_WITH_BUFFER;
			ret = luat_audio_driver_start(request_block->data_channel->driver_ctrl, &request_block->record_codec.common_param, request_block->static_play_buff, request_block->static_play_buff_one_block_len, request_block->static_play_buff_block_nums);
			luat_audio_request_init_play_temp_buffer(request_block);
			luat_audio_request_init_record_temp_buffer(request_block);
			request_block->is_need_ref_data = 1;
			break;
		default:
			break;
	}

	if (ret) {
		LLOGE("request id %d start driver failed, ret %d", request_block->request_id, ret);
		request_block->is_error_stop = 1;
	} else {
		request_block->cb(LUAT_AUDIO_REQUEST_EVENT_DRIVER_START, NULL, 0, request_block);
	}
}

static void luat_audio_common_task(void *param)
{
	luat_event_t out_event;
	luat_audio_request_block_t *request_block;
	uint8_t request_change;
	for(;;) {
		luat_rtos_event_recv(_luat_audio.common_task_handle, 0, &out_event, NULL, 0);
		//LLOGC(luat_audio_debug_flag, "common task recv event %d", out_event.id);
		switch (out_event.id) {
		case LUAT_AUDIO_EV_TX_NEED_DATA:
			_luat_audio.decode_is_running = 1;
			luat_mutex_lock(_luat_audio.request_lock);
			if (!_luat_audio.current_request_block) {
				luat_mutex_unlock(_luat_audio.request_lock);
				luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
				_luat_audio.decode_is_running = 0;
				break;
			}
			request_block = _luat_audio.current_request_block;
			luat_mutex_unlock(_luat_audio.request_lock);
			if (request_block->is_wait_play_end) {
				request_block->play_blank_data_cnt++;
				LLOGC(luat_audio_debug_flag, "wait play end %d", request_block->play_blank_data_cnt);
				if (request_block->play_blank_data_cnt >= 4) {	// 播放空白数据超过4次，认为播放结束
					request_block->is_stream_end = 1;
					request_block->is_wait_play_end = 0;
				}
			} else {
				if (request_block->is_input_end && (request_block->is_tts?1:(!luat_fifo_check_used_space(request_block->org_input_data_fifo)))) {
					LLOGC(luat_audio_debug_flag, "play request end, fifo empty, stop decode");
					request_block->is_wait_play_end = 1;
					request_block->play_blank_data_cnt = 0;
				} else {
					if (request_block->is_stream) {	//流媒体模式
						_audio_decode_stream_to_fifo(request_block);
						if (!request_block->is_input_end && !request_block->is_data_callback_stop) {
							request_block->cb(LUAT_AUDIO_REQUEST_EVENT_NEED_NEW_DATA, NULL, 0, request_block);
						}
					} else if (request_block->is_tts) {
						if (!request_block->is_input_end) {
							luat_mutex_unlock(_luat_audio.tts_wait_sem);
						}
					} else {
						_audio_decode_file_to_fifo(request_block);
					}
				}

			}
			if (_luat_audio.current_request_block->is_stream_end) {
				_audio_request_finish();
			} else if (!request_block->is_wait_play_end && (request_block->is_error_stop || request_block->is_user_stop)) {
				_audio_current_request_stop();
			}
			_luat_audio.decode_is_running = 0;
			break;
		case LUAT_AUDIO_EV_RX_ENOUGH_DATA:
			request_block = _luat_audio.current_request_block;
			if (request_block) {
				uint32_t last_play_cnt = out_event.param2;
				uint32_t read_bytes;
				uint32_t deal_bytes;
				luat_buffer_t temp_record_buffer = {0};
				luat_buffer_t temp_ref_buffer = {0};
				temp_record_buffer.data = request_block->record_codec.input_buffer;
				temp_record_buffer.max_len = request_block->record_codec.common_param.one_frame_bytes;
				temp_ref_buffer.data = request_block->record_codec.ref_buffer;
				temp_ref_buffer.max_len = request_block->record_codec.common_param.one_frame_bytes;
				int ret;
				uint8_t stop = 0;
				if (request_block->is_record_dummy_data) {
					continue;
				}
				deal_bytes = 0;
				while (!stop) {
					read_bytes = 0;
					temp_record_buffer.pos = 0;
					ret =luat_audio_channel_read_data(request_block->data_channel, &temp_record_buffer, &request_block->record_temp_buffer, 
					&request_block->data_align_buffer, &request_block->channel_nums_buffer, &read_bytes, &request_block->record_codec.common_param, 0);
					if (ret) {
						LLOGE("request id %d read data failed, ret %d", request_block->request_id, ret);
					}
					if (!read_bytes) {
						stop = 1;
						continue;
					}
					deal_bytes += read_bytes;
					if (request_block->is_need_ref_data) {
						read_bytes = 0;
						temp_ref_buffer.pos = 0;
						ret =luat_audio_channel_read_data(request_block->data_channel, &temp_ref_buffer, &request_block->record_temp_buffer, 
						&request_block->data_align_buffer, &request_block->channel_nums_buffer, &read_bytes, &request_block->record_codec.common_param, 1);
						if (ret) {
							LLOGE("request id %d read data failed, ret %d", request_block->request_id, ret);
						}
						if (!read_bytes) {
							stop = 1;
							continue;
						}
					}
					luat_audio_data_codec_encode_once(&request_block->record_codec, &temp_record_buffer, request_block->is_need_ref_data?&temp_ref_buffer:NULL, request_block->encode_save_fifo);					
				}
				request_block->cb(LUAT_AUDIO_REQUEST_EVENT_GET_NEW_DATA, NULL, deal_bytes, request_block);
			}

			// if (_luat_audio.current_request_block->is_error_stop || _luat_audio.current_request_block->is_user_stop || _luat_audio.current_request_block->is_stream_end) {
			// 	_audio_request_finish();
			// }
			break;
		case LUAT_AUDIO_EV_REQUEST:
			request_change = 0;
			luat_mutex_lock(_luat_audio.request_lock);
			if (!_luat_audio.current_request_block) {	// 没有请求块，找下一个请求块
				_audio_find_next_request_block();
				luat_mutex_unlock(_luat_audio.request_lock);
				if (!_luat_audio.current_request_block) {	// 找不到请求块，直接返回
					break;
				}
				request_change = 1;
			} else {	// 有请求块，检查一下队列里是否有更高优先级的请求块
				if (!luat_llist_empty(&_luat_audio.request_block_list)) { // 请求队列不空的情况下，检查一下是否有更高优先级的请求块
					request_block = (luat_audio_request_block_t *)_luat_audio.request_block_list.next;
					LLOGC(luat_audio_debug_flag, "next request_id: %d priority: %d, now request_id: %d priority: %d", request_block->request_id, request_block->priority, _luat_audio.current_request_block->request_id, _luat_audio.current_request_block->priority);
					if (request_block->priority > _luat_audio.current_request_block->priority) {
						if (_luat_audio.current_request_block->is_tts) {
							LLOGC(luat_audio_debug_flag, "request_id: %d is tts, wait stop", request_block->request_id);
							luat_mutex_unlock(_luat_audio.tts_wait_sem);
						} else {
							LLOGC(luat_audio_debug_flag, "request_id: %d is not tts, stop now", request_block->request_id);
							_audio_current_request_stop();
						}
					}
				}
			}
			luat_mutex_unlock(_luat_audio.request_lock);
			if (request_change) {
				// 请求块有变化，需要重新播放
				luat_rtos_task_sleep(1);	// 让低优先级的task能返回结果
				_audio_start_request(_luat_audio.current_request_block);
				if (_luat_audio.current_request_block->is_error_stop || _luat_audio.current_request_block->is_user_stop || _luat_audio.current_request_block->is_stream_end) {	// 启动请求块失败，将当前工作请求块设置为NULL，并且重新触发一下请求事件
					_audio_request_finish();
				}
			}
			break;
		case LUAT_AUDIO_EV_REQUEST_CANCEL:
			request_block = (luat_audio_request_block_t *)out_event.param1;
			luat_mutex_lock(_luat_audio.request_lock);
			luat_llist_del(&request_block->node);
			luat_mutex_unlock(_luat_audio.request_lock);
			if (_luat_audio.current_request_block && (_luat_audio.current_request_block->request_id == request_block->request_id)) {
				_audio_current_request_stop();
			} else {
				luat_audio_request_deinit(request_block);
				request_block->cb(LUAT_AUDIO_REQUEST_EVENT_END, NULL, 0, request_block);
				luat_mutex_unlock(request_block->cancel_sem);
			}
			break;
		case LUAT_AUDIO_EV_PRINT:
			LLOGW("print from irq %d %u %u", out_event.param1, out_event.param2, out_event.param3);
			break;
		}
	}
}

int luat_audio_driver_register(const luat_audio_driver_opts_t *opts, struct luat_audio_driver_probe probe, void *driver_data)
{
	volatile uint8_t i = _luat_audio.all_driver_nums;
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].opts == NULL) {
			_luat_audio.driver_ctrl[i].opts = opts;
			_luat_audio.driver_ctrl[i].driver_data = driver_data;
			_luat_audio.driver_ctrl[i].probe = probe;
			_luat_audio.driver_ctrl[i].data_channel = &_luat_audio.channel[i];
			if (opts->init(&_luat_audio.driver_ctrl[i])) {
				LLOGE("probe_id: %x driver init failed, can not register", probe.probe_id);
				memset(&_luat_audio.driver_ctrl[i], 0, sizeof(luat_audio_driver_ctrl_t));
				return -LUAT_ERROR_OPERATION_FAILED; // 驱动注册失败，初始化失败
			}
			_luat_audio.driver_ctrl[i].state = LUAT_AUDIO_DRIVER_STATE_INITED;
			_luat_audio.channel[i].driver_ctrl = &_luat_audio.driver_ctrl[i];
			// _luat_audio.channel[i].play_lock_mutex = luat_mutex_create();
			_luat_audio.channel[i].soft_volume = 100;
			_luat_audio.all_driver_nums++;
			LLOGC(luat_audio_debug_flag, "probe_id: %x driver register success index: %d", probe.probe_id, i);
			return LUAT_ERROR_NONE;
		}
	}
	LLOGE("driver %x register failed, max driver count is %d", probe.probe_id, LUAT_AUDIO_DRIVER_MAX);
	return -LUAT_ERROR_ID_INVALID; // 驱动注册失败，超过最大支持数量
}

luat_audio_driver_ctrl_t *luat_audio_driver_probe(luat_audio_driver_probe_t *probe)
{
	int i;
	if (!probe) {
		if (_luat_audio.driver_ctrl[_luat_audio.default_driver_index].opts) {
			LLOGC(luat_audio_debug_flag, "use default driver index: %d probe_id: %x", _luat_audio.default_driver_index,
				_luat_audio.driver_ctrl[_luat_audio.default_driver_index].probe.probe_id);
			return &_luat_audio.driver_ctrl[_luat_audio.default_driver_index];
		}
		return NULL;
	}
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].opts != NULL && _luat_audio.driver_ctrl[i].probe.probe_id == probe->probe_id) {
			return &_luat_audio.driver_ctrl[i];
		}
	}
	return NULL;
}

int luat_audio_driver_set_default(luat_audio_driver_probe_t *probe)
{
	uint8_t i;
	if (!probe) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].opts != NULL && _luat_audio.driver_ctrl[i].probe.probe_id == probe->probe_id) {
			_luat_audio.default_driver_index = i;
			return LUAT_ERROR_NONE;
		}
	}
	return -LUAT_ERROR_PARAM_INVALID;
}

luat_audio_driver_ctrl_t *luat_audio_driver_get_ctrl_info(uint8_t *all_nums, uint8_t *default_index)
{
	*all_nums = _luat_audio.all_driver_nums;
	*default_index = _luat_audio.default_driver_index;
	return _luat_audio.driver_ctrl;
}

int luat_audio_request_init(luat_audio_request_block_t *request_block)
{
	if (!request_block) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	memset(request_block, 0, sizeof(luat_audio_request_block_t));
	luat_mutex_lock(_luat_audio.request_lock);
	request_block->request_id = ++_luat_audio.next_request_id;
	luat_mutex_unlock(_luat_audio.request_lock);
	LLOGC(luat_audio_debug_flag, "request_id: %d init", request_block->request_id);
	return LUAT_ERROR_NONE;
}

void luat_audio_request_deinit(luat_audio_request_block_t *request_block)
{
	if (!request_block) {
		return;
	}
	if (LUAT_AUDIO_DRIVER_MODE_PLAY == request_block->driver_work_mode) {
		if (!request_block->is_stream && !request_block->is_tts) {
			LLOGC(luat_audio_debug_flag, "request_id: %d close all file", request_block->request_id);
			for (int i = 0; i < request_block->file_info_cnt; i++) {
				if (!request_block->file_info[i].rom_data_len && request_block->file_info[i].fd) {
					luat_fs_fclose(request_block->file_info[i].fd);
					request_block->file_info[i].fd = NULL;
				}
			}
		}
	}
	luat_fifo_destroy(request_block->org_input_data_fifo);
	request_block->org_input_data_fifo = NULL;
	request_block->encode_save_fifo = NULL;
	luat_buffer_deinit(&request_block->out_buffer);
	luat_buffer_deinit(&request_block->data_align_buffer);
	luat_buffer_deinit(&request_block->channel_nums_buffer);
	luat_buffer_deinit(&request_block->record_temp_buffer);
	if (request_block->play_codec.opts) {
		luat_audio_data_codec_deinit(&request_block->play_codec);
		luat_audio_data_codec_unbind(&request_block->play_codec);
	}
	if (request_block->record_codec.opts) {
		luat_audio_data_codec_deinit(&request_block->record_codec);
		luat_audio_data_codec_unbind(&request_block->record_codec);
	}
	if (request_block->temp_buff) {
		luat_heap_free(request_block->temp_buff);
		request_block->temp_buff = NULL;
	}
	request_block->cb = NULL;
	LLOGC(luat_audio_debug_flag, "request_id: %d deinit", request_block->request_id);
}

int luat_audio_request_start(luat_audio_request_block_t *request_block, uint8_t is_sync)
{
	if (!request_block) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	LLOGC(luat_audio_debug_flag, "request_id: %d add in request_block_list", request_block->request_id);
	luat_mutex_lock(_luat_audio.request_lock);
	if (luat_llist_empty(&_luat_audio.request_block_list)) {
		luat_llist_add(&request_block->node, &_luat_audio.request_block_list);
	} else {
		if (!luat_llist_traversal(&_luat_audio.request_block_list, _audio_add_request, request_block)) {
			luat_llist_add_tail(&request_block->node, &_luat_audio.request_block_list);
		}
	}
	luat_mutex_unlock(_luat_audio.request_lock);
	void *done_sem = NULL;
	if (is_sync) {
		done_sem = luat_mutex_create();
		request_block->done_sem = done_sem;
		luat_mutex_lock(done_sem);
	} 
	luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
	if (is_sync) {
		luat_mutex_lock(done_sem);
		luat_mutex_release(done_sem);
		return request_block->is_error_stop ? -LUAT_ERROR_OPERATION_FAILED : LUAT_ERROR_NONE;
	} else {
		return LUAT_ERROR_NONE;
	}
}

void luat_audio_request_cancel(luat_audio_request_block_t *request_block)
{
	void *done_sem = luat_mutex_create();
	luat_mutex_lock(done_sem);
	request_block->cancel_sem = done_sem;
	luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST_CANCEL, (uint32_t)request_block, 0, 0, 0);
	luat_mutex_lock(done_sem);
	luat_mutex_release(done_sem);
	LLOGC(luat_audio_debug_flag, "request_id: %d cancel", request_block->request_id);
	return;
}

int luat_audio_request_prepare(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, uint8_t driver_work_mode, 
    luat_audio_request_cb_t cb, void *user_data)
{
	if (!request_block || !driver_work_mode || (driver_work_mode >= LUAT_AUDIO_DRIVER_MODE_MAX)) {
		LLOGE("driver_work_mode %d is invalid", driver_work_mode);
		return -LUAT_ERROR_PARAM_INVALID;
	}
	luat_audio_request_init(request_block);
	luat_audio_driver_ctrl_t *driver_ctrl = luat_audio_driver_probe(probe);
	if (!driver_ctrl) {
		LLOGE("driver 0x%x not found", probe->probe_id);
		return -LUAT_ERROR_NO_SUCH_ID;
	}
	request_block->data_channel = driver_ctrl->data_channel;
	request_block->driver_work_mode = driver_work_mode;
	request_block->cb = cb;
	request_block->user_data = user_data;
	return LUAT_ERROR_NONE;
}

int luat_audio_request_play_files(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, const luat_audio_data_codec_opts_t *codec_opts, luat_audio_play_file_info_t *files, uint32_t files_num, uint8_t priority, uint8_t is_sync,
    luat_audio_request_cb_t cb, void *user_data, const luat_audio_dsp_opts_t *dsp_opts)
{
	if (!request_block) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	int ret = luat_audio_request_prepare(request_block, probe, LUAT_AUDIO_DRIVER_MODE_PLAY, cb, user_data);
	if (ret != LUAT_ERROR_NONE) {
		return ret;
	}
	request_block->org_input_data_fifo = luat_fifo_create(LUAT_AUDIO_DATA_CODEC_INPUT_FIFO_DEFAULT_SIZE_POWER);
	if (!request_block->org_input_data_fifo) {
		return -LUAT_ERROR_NO_MEMORY;
	}
	if (codec_opts) {
		
		if (luat_audio_data_codec_bind(&request_block->play_codec, codec_opts, request_block)) {
			luat_audio_request_deinit(request_block);
			return -LUAT_ERROR_OPERATION_FAILED;
		}
		if (request_block->play_codec.opts->init(&request_block->play_codec, 0) != LUAT_ERROR_NONE) {
			luat_audio_request_deinit(request_block);
			return -LUAT_ERROR_OPERATION_FAILED;
		}
		request_block->play_codec.common_param.driver_work_mode = LUAT_AUDIO_DRIVER_MODE_PLAY;
	}
	request_block->temp_buff = luat_heap_calloc(files_num, sizeof(luat_audio_play_file_info_t));
	if (!request_block->temp_buff) {
		return -LUAT_ERROR_NO_MEMORY;
	}
	memcpy(request_block->temp_buff, files, files_num * sizeof(luat_audio_play_file_info_t));
	request_block->file_info = (luat_audio_play_file_info_t *)request_block->temp_buff;
	for (int i = 0; i < files_num; i++) {
		if (!request_block->file_info[i].rom_data_len) {	//真正的文件形式
			request_block->file_info[i].fd = luat_fs_fopen(files[i].path, "r");
			if (!request_block->file_info[i].fd) {
				LLOGE("request_id: %d open file %s failed", request_block->request_id, files[i].path);
				luat_audio_request_deinit(request_block);
				return -LUAT_ERROR_NO_SUCH_ID;
			}
		}
	}
	request_block->priority = priority;
	request_block->file_info_cnt = files_num;
	return luat_audio_request_start(request_block, is_sync);
}

int luat_audio_request_play_tts(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, const char *text, uint32_t text_len, uint8_t priority, uint8_t is_sync,
    luat_audio_request_cb_t cb, void *user_data, const luat_audio_dsp_opts_t *dsp_opts)
{
	if (!request_block) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	int ret = luat_audio_request_prepare(request_block, probe, LUAT_AUDIO_DRIVER_MODE_PLAY, cb, user_data);
	if (ret != LUAT_ERROR_NONE) {
		return ret;
	}
	request_block->org_input_data_fifo = luat_fifo_create(LUAT_AUDIO_DATA_CODEC_INPUT_FIFO_DEFAULT_SIZE_POWER);
	if (!request_block->org_input_data_fifo) {
		return -LUAT_ERROR_NO_MEMORY;
	}
	if (!luat_audio_data_codec_find(LUAT_AUDIO_DATA_CODEC_TYPE_TTS)) {
		LLOGE("request_id: %d tts codec not found", request_block->request_id);
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_NO_SUCH_ID;
	}

	if (luat_audio_data_codec_bind(&request_block->play_codec, luat_audio_data_codec_find(LUAT_AUDIO_DATA_CODEC_TYPE_TTS), request_block) != LUAT_ERROR_NONE) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	if (request_block->play_codec.opts->init(&request_block->play_codec, 0) != LUAT_ERROR_NONE) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	request_block->temp_buff = luat_heap_malloc(text_len);
	if (!request_block->temp_buff) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_NO_MEMORY;
	}
	memcpy(request_block->temp_buff, text, text_len);
	request_block->priority = priority;
	request_block->is_tts = 1;
	request_block->tts_data = (const char *)request_block->temp_buff;
	request_block->tts_data_size = text_len;
	request_block->play_codec.param.tts_output_callback = _audio_tts_output_callback;
	return luat_audio_request_start(request_block, is_sync);
}

int luat_audio_request_play_stream(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, const luat_audio_data_codec_opts_t *codec_opts,
    luat_audio_common_param_t *common_param, uint32_t one_block_len, uint8_t priority, uint8_t is_sync,
    luat_audio_request_cb_t cb, void *user_data, const luat_audio_dsp_opts_t *dsp_opts)
{
	if (!request_block || !common_param || !codec_opts) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	int ret = luat_audio_request_prepare(request_block, probe, LUAT_AUDIO_DRIVER_MODE_PLAY, cb, user_data);
	if (ret != LUAT_ERROR_NONE) {
		return ret;
	}
	request_block->org_input_data_fifo = luat_fifo_create(LUAT_AUDIO_DATA_CODEC_INPUT_FIFO_DEFAULT_SIZE_POWER);
	if (!request_block->org_input_data_fifo) {
		return -LUAT_ERROR_NO_MEMORY;
	}
	if (luat_audio_data_codec_bind(&request_block->play_codec, codec_opts, request_block)) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	if (request_block->play_codec.opts->init(&request_block->play_codec, 0) != LUAT_ERROR_NONE) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	request_block->play_codec.common_param = *common_param;
	request_block->stream_one_block_len = one_block_len;
	request_block->priority = priority;
	request_block->is_stream = 1;
	request_block->play_codec.common_param.driver_work_mode = LUAT_AUDIO_DRIVER_MODE_PLAY;
	return luat_audio_request_start(request_block, is_sync);
}

int luat_audio_request_record(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, const luat_audio_data_codec_opts_t *codec_opts, 
	luat_audio_common_param_t *common_audio_param, luat_fifo_t *record_fifo, uint8_t record_callback_frame_cnt, uint8_t priority, 
    luat_audio_request_cb_t cb, void *user_data, const luat_audio_dsp_opts_t *dsp_opts)
{
	if (!request_block || !common_audio_param || !codec_opts || !record_fifo || (!codec_opts->encode && !codec_opts->encode_with_sync_output_ref)) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	
	int ret = luat_audio_request_prepare(request_block, probe, LUAT_AUDIO_DRIVER_MODE_RECORD, cb, user_data);
	if (ret != LUAT_ERROR_NONE) {
		return ret;
	}
	if (luat_audio_data_codec_bind(&request_block->record_codec, codec_opts, request_block)) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	if (luat_audio_data_codec_bind(&request_block->play_codec, &luat_audio_data_codec_no_op_opts, request_block)) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	
	if (request_block->record_codec.opts->init(&request_block->record_codec, 1) != LUAT_ERROR_NONE) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	request_block->record_codec.opts->set_record_info(&request_block->record_codec, common_audio_param);
	request_block->encode_save_fifo = record_fifo;
	request_block->priority = priority;
	request_block->record_callback_frame_cnt = record_callback_frame_cnt;
	//LLOGC(luat_audio_debug_flag, "record_one_frame_len: %d , callback_frame_cnt: %d", request_block->record_codec.common_param.one_frame_bytes, record_callback_frame_cnt);
	//request_block->record_fifo_enough_data_level = record_callback_frame_cnt * request_block->record_codec.common_param.one_frame_bytes;
	return luat_audio_request_start(request_block, 0);
}

int luat_audio_request_speech(luat_audio_request_block_t *request_block, luat_audio_driver_probe_t *probe, 
    const luat_audio_data_codec_opts_t *play_codec_opts, const luat_audio_data_codec_opts_t *record_codec_opts,
    luat_audio_common_param_t *common_audio_param, luat_fifo_t *record_fifo, uint8_t record_callback_frame_cnt,
    uint32_t *tx_buff, uint32_t one_block_len, uint8_t block_num,
    luat_audio_request_cb_t cb, void *user_data, const luat_audio_dsp_opts_t *dsp_opts)
{
	if (!request_block || !common_audio_param || !play_codec_opts || !record_codec_opts || !record_fifo || (!record_codec_opts->encode && !record_codec_opts->encode_with_sync_output_ref)) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	
	int ret = luat_audio_request_prepare(request_block, probe, tx_buff?LUAT_AUDIO_DRIVER_MODE_SPEECH_WITH_BUFFER:LUAT_AUDIO_DRIVER_MODE_SPEECH, cb, user_data);
	if (ret != LUAT_ERROR_NONE) {
		return ret;
	}
	request_block->org_input_data_fifo = luat_fifo_create(LUAT_AUDIO_DATA_CODEC_INPUT_FIFO_DEFAULT_SIZE_POWER);
	if (!request_block->org_input_data_fifo) {
		return -LUAT_ERROR_NO_MEMORY;
	}

	if (luat_audio_data_codec_bind(&request_block->record_codec, record_codec_opts, request_block)) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	if (luat_audio_data_codec_bind(&request_block->play_codec, play_codec_opts, request_block)) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	if (request_block->record_codec.opts->init(&request_block->record_codec, 1) != LUAT_ERROR_NONE) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	if (request_block->play_codec.opts->init(&request_block->play_codec, 0) != LUAT_ERROR_NONE) {
		luat_audio_request_deinit(request_block);
		return -LUAT_ERROR_OPERATION_FAILED;
	}
	request_block->record_codec.opts->set_record_info(&request_block->record_codec, common_audio_param);
	request_block->play_codec.common_param = *common_audio_param;
	request_block->encode_save_fifo = record_fifo;
	request_block->priority = 255;
	request_block->static_play_buff = tx_buff;
	request_block->static_play_buff_one_block_len = one_block_len;
	request_block->static_play_buff_block_nums = block_num;
	request_block->record_callback_frame_cnt = record_callback_frame_cnt;
	request_block->is_stream = 1;
	request_block->is_need_ref_data = 1;
	return luat_audio_request_start(request_block, 0);
}

void luat_audio_base_init(void)
{
	luat_rtos_task_create(&_luat_audio.common_task_handle, LUAT_AUDIO_TASK_STACK, LUAT_AUDIO_TASK_PRIORITY, "luat_audio", luat_audio_common_task, NULL, 64);
	luat_rtos_task_create(&_luat_audio.tts_task_handle, LUAT_AUDIO_TASK_STACK, LUAT_AUDIO_TTS_TASK_PRIORITY, "luat_tts", luat_audio_tts_task, NULL, 0);
	_luat_audio.request_lock = luat_mutex_create();
	_luat_audio.tts_wait_sem = luat_mutex_create();
	luat_mutex_lock(_luat_audio.tts_wait_sem);
	LUAT_INIT_LLIST_HEAD(&_luat_audio.request_block_list);
#ifdef __LUATOS__
	l_audio_init();
#endif
	luat_audio_data_codec_register(&luat_audio_data_codec_no_op_opts);
}

void luat_audio_debug_switch(uint8_t on_off)
{
	luat_audio_debug_flag = on_off;
}



uint8_t luat_audio_is_request_all_done(luat_audio_driver_ctrl_t *ctrl)
{
	uint8_t result = 1;
	
	if (ctrl) {
		uint32_t cr = luat_rtos_entry_critical();
		if (_luat_audio.current_request_block->data_channel->driver_ctrl == ctrl) {
			result = 0;
		}
		luat_rtos_exit_critical(cr);
		if (result) {
			luat_mutex_lock(_luat_audio.request_lock);
			if (luat_llist_traversal(&_luat_audio.request_block_list, _audio_find_request, ctrl)) {
				result = 0;
			}
			luat_mutex_unlock(_luat_audio.request_lock);
		}
	} else {
		luat_mutex_lock(_luat_audio.request_lock);
	if (!luat_llist_empty(&_luat_audio.request_block_list) || _luat_audio.current_request_block) {
			result = 0;
		}
		luat_mutex_unlock(_luat_audio.request_lock);
	}
	
	return result;
}

void luat_audio_request_init_play_temp_buffer(luat_audio_request_block_t *request_block)
{
	if (request_block->play_codec.common_param.data_align == request_block->data_channel->driver_ctrl->common_param.data_align && 
		request_block->play_codec.common_param.channel_nums == request_block->data_channel->driver_ctrl->common_param.channel_nums) {
		LLOGC(luat_audio_debug_flag, "play temp buffer codec param same as driver param");
	} else {
		uint32_t data_align_len, channel_nums_len;
		if (request_block->play_codec.common_param.data_align >= request_block->data_channel->driver_ctrl->common_param.data_align) {
			data_align_len = request_block->out_buffer.max_len;
		} else {
			data_align_len = request_block->out_buffer.max_len * request_block->data_channel->driver_ctrl->common_param.data_align / request_block->play_codec.common_param.data_align;
		}
		if (request_block->play_codec.common_param.channel_nums >= request_block->data_channel->driver_ctrl->common_param.channel_nums) {
			channel_nums_len = data_align_len;
		} else {
			channel_nums_len = data_align_len * request_block->data_channel->driver_ctrl->common_param.channel_nums / request_block->play_codec.common_param.channel_nums;
		}
		LLOGC(luat_audio_debug_flag, "check play temp buffer codec param %u %u-%u, driver param %u %u-%u", 
			request_block->out_buffer.max_len, 
			request_block->play_codec.common_param.data_align, 
			request_block->play_codec.common_param.channel_nums, 	
			channel_nums_len,		
			request_block->data_channel->driver_ctrl->common_param.data_align, 
			request_block->data_channel->driver_ctrl->common_param.channel_nums
			);
		if (request_block->data_align_buffer.max_len < channel_nums_len) {
			luat_buffer_reinit(&request_block->data_align_buffer, channel_nums_len);
			if (!request_block->data_align_buffer.data) {
				LLOGE("create data align buffer failed, no memory");
				request_block->is_error_stop = 1;
				return;
			}
		}
		if (request_block->channel_nums_buffer.max_len < channel_nums_len) {
			luat_buffer_reinit(&request_block->channel_nums_buffer, channel_nums_len);
			if (!request_block->channel_nums_buffer.data) {
				LLOGE("create channel nums buffer failed, no memory");
				request_block->is_error_stop = 1;
				return;
			}
		}
	}
}

void luat_audio_request_init_record_temp_buffer(luat_audio_request_block_t *request_block)
{
	if (request_block->record_codec.input_buffer) {
		luat_heap_free(request_block->record_codec.input_buffer);
		request_block->record_codec.input_buffer = luat_heap_malloc(request_block->record_codec.common_param.one_frame_bytes);
		if (!request_block->record_codec.input_buffer) {
			LLOGE("request id %d record codec input buffer failed", request_block->request_id);
			request_block->is_error_stop = 1;
			return;
		}
		if (request_block->record_codec.ref_buffer) {
			luat_heap_free(request_block->record_codec.ref_buffer);
			request_block->record_codec.ref_buffer = NULL;
		}
		request_block->record_codec.ref_buffer = luat_heap_malloc(request_block->record_codec.common_param.one_frame_bytes);
		if (!request_block->record_codec.ref_buffer) {
			LLOGE("request id %d record codec ref buffer failed", request_block->request_id);
			request_block->is_error_stop = 1;
			return;
		}
	}

	if (request_block->record_codec.common_param.data_align == request_block->data_channel->driver_ctrl->common_param.data_align && 
		request_block->record_codec.common_param.channel_nums == request_block->data_channel->driver_ctrl->common_param.channel_nums) {
		LLOGC(luat_audio_debug_flag, "record temp buffer codec param same as driver param");
		luat_buffer_reinit(&request_block->record_temp_buffer, request_block->record_codec.common_param.one_frame_bytes_from_driver);
		if (!request_block->record_temp_buffer.data) {
			LLOGE("create record temp buffer failed, no memory");
			request_block->is_error_stop = 1;
			return;
		}
	} else {
		uint32_t max_data_align, max_channel_nums, final_data_bytes;

		if (request_block->record_codec.common_param.data_align >= request_block->data_channel->driver_ctrl->common_param.data_align) {
			max_data_align = request_block->record_codec.common_param.data_align;
		} else {
			max_data_align = request_block->data_channel->driver_ctrl->common_param.data_align;
		}
		if (request_block->record_codec.common_param.channel_nums >= request_block->data_channel->driver_ctrl->common_param.channel_nums) {
			max_channel_nums = request_block->record_codec.common_param.channel_nums;
		} else {
			max_channel_nums = request_block->data_channel->driver_ctrl->common_param.channel_nums;
		}
		final_data_bytes = max_data_align * max_channel_nums * request_block->record_codec.common_param.one_frame_sample_cnt;
		LLOGC(luat_audio_debug_flag, "check record temp buffer codec param %u %u-%u, driver param %u %u-%u", 
			request_block->out_buffer.max_len, 
			request_block->play_codec.common_param.data_align, 
			request_block->play_codec.common_param.channel_nums, 	
			final_data_bytes,		
			request_block->data_channel->driver_ctrl->common_param.data_align, 
			request_block->data_channel->driver_ctrl->common_param.channel_nums
			);
		if (request_block->data_align_buffer.max_len < final_data_bytes) {
			luat_buffer_reinit(&request_block->data_align_buffer, final_data_bytes);
			if (!request_block->data_align_buffer.data) {
				LLOGE("create data align buffer failed, no memory");
				request_block->is_error_stop = 1;
				return;
			}
		}
		if (request_block->channel_nums_buffer.max_len < final_data_bytes) {
			luat_buffer_reinit(&request_block->channel_nums_buffer, final_data_bytes);
			if (!request_block->channel_nums_buffer.data) {
				LLOGE("create channel nums buffer failed, no memory");
				request_block->is_error_stop = 1;
				return;
			}
		}
		luat_buffer_reinit(&request_block->record_temp_buffer, final_data_bytes);
		if (!request_block->record_temp_buffer.data) {
			LLOGE("create record temp buffer failed, no memory");
			request_block->is_error_stop = 1;
			return;
		}
	}
}