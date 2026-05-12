#include "luat_audio_data_codec.h"
#include "luat_base.h"
#include "luat_audio_api.h"
#include "luat_audio_request.h"
#include "luat_audio_channel.h"
#include "luat_common_api.h"
#include "luat_fs.h"
#include "luat_malloc.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_rtos_legacy.h"
#include <sys/_types.h>
#define LUAT_LOG_TAG "audio_core"
#include "luat_log.h"
#include "luat_gpio.h"

unsigned char luat_audio_debug_flag;
enum {
	LUAT_AUDIO_EV_TX_NEED_DATA = 0x01,
	LUAT_AUDIO_EV_TX_NO_DATA,
	LUAT_AUDIO_EV_RX_ENOUGH_DATA,
	LUAT_AUDIO_EV_REQUEST,

	LUAT_AUDIO_EV_TTS_RUN = 0x01,
};

typedef struct
{
	luat_llist_head request_block_list;
	luat_audio_driver_ctrl_t driver_ctrl[LUAT_AUDIO_DRIVER_MAX];
	luat_audio_channel_t channel[LUAT_AUDIO_DRIVER_MAX];
	luat_audio_request_block_t *request_block;
	luat_rtos_task_handle common_task_handle;
	luat_rtos_task_handle tts_task_handle;
	void *request_lock;	// 请求块列表操作保护锁
	void *tts_wait_sem;	// tts任务等待信号量
	uint32_t next_request_id;		// 下一个请求id
}luat_audio_ctrl_t;

static luat_audio_ctrl_t _luat_audio;

#ifdef LUAT_CSDK_CONFIG_FILE
#include LUAT_CSDK_CONFIG_FILE
#endif

#ifndef __LUAT_C_CODE_IN_ISR__
#define __LUAT_C_CODE_IN_ISR__
#endif

static __LUAT_C_CODE_IN_ISR__ void _audio_play_next_block(struct luat_audio_driver_ctrl *ctrl)
{
	volatile uint32_t next_play_cnt;
	ctrl->last_play_cnt = ctrl->current_play_cnt;
	ctrl->current_play_cnt = (ctrl->current_play_cnt + 1) & 3;
	next_play_cnt = (ctrl->current_play_cnt + 1) & 3;
	uint8_t *next_play_buff = ctrl->play_buff_byte + ctrl->one_play_block_len * next_play_cnt;
	if (!ctrl->data_channel->play_state) {	// 播放状态为停止，播放空白音
		ctrl->opts->fill(ctrl, next_play_buff, ctrl->one_play_block_len, ctrl->opts->is_signed, ctrl->data_channel->data_align);
		return;
	}
	// play数据从这里读取，只有1个消费者，所以不需要加锁
	uint32_t read_len = luat_fifo_read(ctrl->data_channel->play_fifo, next_play_buff, ctrl->one_play_block_len);

	if (read_len < ctrl->one_play_block_len) { 	// fifo没有完整的1个block
		ctrl->opts->fill(ctrl, next_play_buff + read_len, ctrl->one_play_block_len - read_len, ctrl->opts->is_signed, ctrl->data_channel->data_align);
	}
	if (!read_len) { // fifo没有数据，播放空白音
		if (ctrl->data_channel->blank_data_cnt < 10) { // 空数据计数
			ctrl->data_channel->blank_data_cnt++;
		}
	} else {
		ctrl->data_channel->blank_data_cnt = 0;
	}
	if (!_luat_audio.request_block) {  // 没有请求块，直接返回
		return;
	}
	if (luat_fifo_check_free_space(ctrl->data_channel->play_fifo) >= ctrl->data_channel->play_fifo_need_data_level) { // fifo剩余数据不足一半，需要请求更多数据
		luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_TX_NEED_DATA, (uint32_t)ctrl, 0, 0, 0);
	}
}

LUAT_WEAK __LUAT_C_CODE_IN_ISR__ void luat_audio_driver_event_callback(uint32_t event, uint8_t *rx_data, uint32_t param, struct luat_audio_driver_ctrl *ctrl)
{
	switch (event) {
	case LUAT_AUDIO_DRIVER_EVENT_TX_ONE_BLOCK_DONE:
		if (ctrl->opts->support_full_loop) {
			return;
		}
		_audio_play_next_block(ctrl);
		break;
	case LUAT_AUDIO_DRIVER_EVENT_RX_ONE_BLOCK_DONE:
		if (ctrl->opts->support_full_loop) {
			_audio_play_next_block(ctrl);
		}
		uint32_t rest_data_len = luat_fifo_check_free_space(ctrl->data_channel->record_fifo);
		if (param < rest_data_len) {
			luat_fifo_write(ctrl->data_channel->record_fifo, rx_data, param);
		} else {
			ctrl->data_channel->error_record_overflow = 1;
		}
		if (luat_fifo_check_used_space(ctrl->data_channel->record_fifo) >= ctrl->data_channel->record_fifo_enough_data_level) {	// 录音数据足够，发送事件
			luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_RX_ENOUGH_DATA, (uint32_t)ctrl, 0, 0, 0);
		}
		break;
	default:
		break;
	}
}

static void _audio_find_next_request_block(void)
{
	if (luat_llist_empty(&_luat_audio.request_block_list)) {
		luat_mutex_unlock(_luat_audio.request_lock);
		return;
	}
	_luat_audio.request_block = (luat_audio_request_block_t *)_luat_audio.request_block_list.next;
	luat_llist_del(&_luat_audio.request_block->node);
}


static int _audio_add_request(void *node, void *param)
{
	luat_audio_request_block_t *old_req = (luat_audio_request_block_t *)node;
	luat_audio_request_block_t *new_req = (luat_audio_request_block_t *)param;
	if (new_req->priority > old_req->priority)
	{
		luat_llist_add_tail(&new_req->node, &old_req->node);
		return LUAT_LIST_FIND;
	}
	return LUAT_LIST_PASS;
}

static int _audio_tts_output_callback(void *data, uint32_t param, void *user_data)
{
	luat_audio_request_block_t *request_block = (luat_audio_request_block_t *)user_data;
	if (data) {
		while(!request_block->user_stop && luat_fifo_check_free_space(request_block->data_channel->play_fifo) >= request_block->codec.opts->decode_max_output_len * ((request_block->data_channel->driver_ctrl->data_align == 3)?4:request_block->data_channel->driver_ctrl->data_align))
		{
			LLOGC(luat_audio_debug_flag, "tts wait fifo space %d", luat_fifo_check_free_space(request_block->data_channel->play_fifo));
			if (luat_rtos_semaphore_take(_luat_audio.tts_wait_sem, 1000)) {
				LLOGE("tts wait timeout");
				return -1;
			}
		}
		if (request_block->user_stop) {
			return -1;
		}
		uint32_t written_bytes = 0;
		luat_audio_channel_write_data(request_block->data_channel, data, param, &written_bytes, request_block->codec.play_info.is_signed, request_block->codec.play_info.data_align, request_block->codec.play_info.channels);	
	} else {
		request_block->codec.play_info.sample_rate = param;
	}
	return LUAT_ERROR_NONE;
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
			if (tts_request_block->request_id == _luat_audio.request_block->request_id) {
				tts_request_block->codec.param.tts_output_callback_t = _audio_tts_output_callback;
				tts_request_block->codec.opts->tts_decode(&tts_request_block->codec, tts_request_block->tts_data, tts_request_block->tts_data_size_or_file_info_cnt, tts_request_block);
			}
			break;
		default:
			break;
		}
	}
}

static void luat_audio_common_task(void *param)
{
	luat_event_t out_event;
	luat_audio_request_block_t *request_block;
	for(;;) {
		luat_rtos_event_recv(_luat_audio.common_task_handle, 0, &out_event, NULL, 0);
		switch (out_event.id) {
		case LUAT_AUDIO_EV_TX_NEED_DATA:
			luat_mutex_lock(_luat_audio.request_lock);
			request_block = _luat_audio.request_block;
			if (!request_block) {
				_audio_find_next_request_block();
			}
			if (request_block->is_stream) {
				luat_audio_data_codec_decode_once(&request_block->codec, 
					request_block->input_data_fifo, 
					&request_block->out_buffer, 
					request_block->is_stream_end);
				if (request_block->out_buffer.pos) {
					uint32_t written_bytes = 0;
					luat_audio_channel_write_data(request_block->data_channel, request_block->out_buffer.data, request_block->out_buffer.pos, &written_bytes, request_block->codec.play_info.is_signed, request_block->codec.play_info.data_align, request_block->codec.play_info.channels);
					request_block->out_buffer.pos -= written_bytes;
				} else {
					request_block->out_buffer.pos = 0;
				}
				
			} else {
				if (request_block->tts_data) {
					luat_mutex_unlock(_luat_audio.tts_wait_sem);
					//luat_rtos_event_send(_luat_audio.tts_task_handle, LUAT_AUDIO_EV_TTS_RUN, request_block, 0, 0, 0);
				}
			}
			luat_mutex_unlock(_luat_audio.request_lock);
			break;
		case LUAT_AUDIO_EV_RX_ENOUGH_DATA:
			break;
		case LUAT_AUDIO_EV_REQUEST:
			luat_mutex_lock(_luat_audio.request_lock);
			if (!_luat_audio.request_block) {	// 没有请求块，找下一个请求块
				_audio_find_next_request_block();
				if (!_luat_audio.request_block) {	// 找不到请求块，直接返回
					break;
				}
			} else {
				if (!luat_llist_empty(&_luat_audio.request_block_list)) { // 请求队列不空的情况下，检查一下是否有更高优先级的请求块
					request_block = (luat_audio_request_block_t *)_luat_audio.request_block_list.next;
					if (request_block->priority > _luat_audio.request_block->priority) {
						LLOGD("request_id: %d priority higher than now request_id: %d", request_block->request_id, _luat_audio.request_block->request_id);
						luat_llist_del(&request_block->node);
						if (!luat_llist_traversal(&_luat_audio.request_block_list, _audio_add_request, _luat_audio.request_block)) {
							luat_llist_add_tail(&_luat_audio.request_block->node, &_luat_audio.request_block_list);
						}
						_luat_audio.request_block = request_block;
					}
				}
			}
			luat_mutex_unlock(_luat_audio.request_lock);
			break;
		}
	}
}

int luat_audio_driver_register(const luat_audio_driver_opts_t *opts, struct luat_audio_driver_probe probe, void *driver_data)
{
	int i;
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].opts == NULL) {
			_luat_audio.driver_ctrl[i].opts = opts;
			_luat_audio.driver_ctrl[i].driver_data = driver_data;
			_luat_audio.driver_ctrl[i].probe = probe;
			_luat_audio.driver_ctrl[i].data_channel = &_luat_audio.channel[i];
			if (opts->init(&_luat_audio.driver_ctrl[i])) {
				LLOGE("%d-%d driver init failed, can not register", probe.bus_type, probe.bus_id);
				memset(&_luat_audio.driver_ctrl[i], 0, sizeof(luat_audio_driver_ctrl_t));
				return -LUAT_ERROR_OPERATION_FAILED; // 驱动注册失败，初始化失败
			}
			_luat_audio.driver_ctrl[i].state = LUAT_AUDIO_DRIVER_STATE_INITED;
			_luat_audio.channel[i].driver_ctrl = &_luat_audio.driver_ctrl[i];
			return LUAT_ERROR_NONE;
		}
	}
	LLOGE("driver register failed, max driver count is %d", LUAT_AUDIO_DRIVER_MAX);
	return -LUAT_ERROR_ID_INVALID; // 驱动注册失败，超过最大支持数量
}

luat_audio_driver_ctrl_t *luat_audio_driver_probe(struct luat_audio_driver_probe *probe)
{
	int i;
	if (!probe) {
		if (_luat_audio.driver_ctrl[0].opts) {
			return &_luat_audio.driver_ctrl[0];
		}
		return NULL;
	}
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].opts != NULL && _luat_audio.driver_ctrl[i].probe.bus_type == probe->bus_type && _luat_audio.driver_ctrl[i].probe.bus_id == probe->bus_id) {
			return &_luat_audio.driver_ctrl[i];
		}
	}
	return NULL;
}

int luat_audio_request_init(luat_audio_request_block_t *req)
{
	if (!req) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	memset(req, 0, sizeof(luat_audio_request_block_t));
	luat_mutex_lock(_luat_audio.request_lock);
	req->request_id = ++_luat_audio.next_request_id;
	luat_mutex_unlock(_luat_audio.request_lock);
	return LUAT_ERROR_NONE;
}

int luat_audio_request_deinit(luat_audio_request_block_t *req)
{
	if (!req) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	if (req->fd) {
		luat_fs_fclose(req->fd);
	}
	luat_heap_free(req->input_data_fifo);
	luat_heap_free(req->tts_data);
	luat_heap_free(req->file_info);
	luat_buffer_deinit(&req->out_buffer);
	luat_audio_data_codec_deinit(&req->codec);
	return LUAT_ERROR_NONE;
}

int luat_audio_request(luat_audio_request_block_t *req)
{
	if (!req) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	LLOGC(luat_audio_debug_flag, "request_id: %d add in request_block_list", req->request_id);
	luat_mutex_lock(_luat_audio.request_lock);
	if (luat_llist_empty(&_luat_audio.request_block_list)) {
		luat_llist_add(&req->node, &_luat_audio.request_block_list);
	} else {
		if (!luat_llist_traversal(&_luat_audio.request_block_list, _audio_add_request, req)) {
			luat_llist_add_tail(&req->node, &_luat_audio.request_block_list);
		}
	}
	luat_mutex_unlock(_luat_audio.request_lock);
	return luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
}

int luat_audio_request_cancel(luat_audio_request_block_t *req)
{
	if (!req) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	LLOGC(luat_audio_debug_flag, "request_id: %d cancel", req->request_id);
	luat_mutex_lock(_luat_audio.request_lock);
	luat_llist_del(&req->node);
	if (_luat_audio.request_block) {
		if (req->request_id == _luat_audio.request_block->request_id) {
			LLOGC(luat_audio_debug_flag, "now work request_id: %d cancel", req->request_id);
			_luat_audio.request_block = NULL;
		}
	}
	luat_mutex_unlock(_luat_audio.request_lock);
	return luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
}

void luat_audio_base_init(void)
{
	luat_rtos_task_create(&_luat_audio.common_task_handle, LUAT_AUDIO_TASK_STACK, 90, "luat_audio", luat_audio_common_task, NULL, 64);
	luat_rtos_task_create(&_luat_audio.tts_task_handle, LUAT_AUDIO_TASK_STACK, 20, "luat_tts", luat_audio_tts_task, NULL, 0);
	_luat_audio.request_lock = luat_mutex_create();
	_luat_audio.tts_wait_sem = luat_mutex_create();
	luat_mutex_lock(_luat_audio.tts_wait_sem);
	LUAT_INIT_LLIST_HEAD(&_luat_audio.request_block_list);
}

void luat_audio_debug_switch(uint8_t on_off)
{
	luat_audio_debug_flag = on_off;
}

