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
#define LUAT_LOG_TAG "audio_core"
#include "luat_log.h"
enum {
	LUAT_AUDIO_EV_TX_NEED_DATA = 0x01,
	LUAT_AUDIO_EV_TX_NO_DATA,
	LUAT_AUDIO_EV_RX_ENOUGH_DATA,
	LUAT_AUDIO_EV_REQUEST,
};

typedef struct
{
	luat_llist_head request_block_list;
	luat_audio_driver_ctrl_t driver_ctrl[LUAT_AUDIO_DRIVER_MAX];
	luat_audio_channel_t channel[LUAT_AUDIO_DRIVER_MAX];
	luat_audio_request_block_t *request_block;
	luat_rtos_task_handle common_task_handle;
	luat_rtos_task_handle tts_task_handle;
	void *luat_audio_request_lock;
	uint32_t next_request_id;
}luat_audio_ctrl_t;

static luat_audio_ctrl_t _luat_audio;

#ifndef __LUAT_C_CODE_IN_ISR__
#define __LUAT_C_CODE_IN_ISR__
#endif

static __LUAT_C_CODE_IN_ISR__ void _audio_play_next_block(struct luat_audio_driver_ctrl *ctrl)
{
	volatile uint32_t next_play_cnt;
	ctrl->last_play_cnt = ctrl->current_play_cnt;
	ctrl->current_play_cnt = (ctrl->current_play_cnt + 1) & 3;
	next_play_cnt = (ctrl->current_play_cnt + 1) & 3;
	uint8_t *next_play_buff = ctrl->play_buff + ctrl->one_play_block_len * next_play_cnt;
	if (!ctrl->data_channel->play_state) {	// 播放状态为停止，播放空白音
		ctrl->driver_opts->fill(ctrl, next_play_buff, ctrl->one_play_block_len, ctrl->driver_opts->is_signed, ctrl->data_channel->data_align);
		return;
	}
	uint32_t read_len = luat_fifo_read(ctrl->data_channel->play_fifo, next_play_buff, ctrl->one_play_block_len);

	if (read_len < ctrl->one_play_block_len) { 	// fifo没有完整的1个block
		ctrl->driver_opts->fill(ctrl, next_play_buff + read_len, ctrl->one_play_block_len - read_len, ctrl->driver_opts->is_signed, ctrl->data_channel->data_align);
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
		if (ctrl->driver_opts->support_full_loop) {
			return;
		}
		_audio_play_next_block(ctrl);
		break;
	case LUAT_AUDIO_DRIVER_EVENT_RX_ONE_BLOCK_DONE:
		if (ctrl->driver_opts->support_full_loop) {
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
	luat_mutex_lock(_luat_audio.luat_audio_request_lock);
	if (luat_llist_empty(&_luat_audio.request_block_list)) {
		luat_mutex_unlock(_luat_audio.luat_audio_request_lock);
		return;
	}
	_luat_audio.request_block = (luat_audio_request_block_t *)_luat_audio.request_block_list.next;
	luat_llist_del(&_luat_audio.request_block->node);
	luat_mutex_unlock(_luat_audio.luat_audio_request_lock);
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

static void luat_audio_tts_task(void *param)
{
	luat_event_t out_event;
	for(;;)
	{
		luat_rtos_event_recv(_luat_audio.tts_task_handle, 0, &out_event, NULL, 0);
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
			request_block = _luat_audio.request_block;
			if (!request_block) {
				_audio_find_next_request_block();
			}
			if (request_block->is_stream) {
				luat_mutex_lock(request_block->data_channel->lock_mutex);
				luat_audio_data_codec_decode_once(&request_block->codec, 
					request_block->input_data_fifo, 
					&request_block->out_buffer, 
					request_block->is_stream_end);
				if (request_block->out_buffer.pos) {
					luat_fifo_write(request_block->data_channel->play_fifo, request_block->out_buffer.data, request_block->out_buffer.pos);
					request_block->out_buffer.pos = 0;
				}
				luat_mutex_unlock(request_block->data_channel->lock_mutex);
			} else {
			}
			break;
		case LUAT_AUDIO_EV_RX_ENOUGH_DATA:
			break;
		case LUAT_AUDIO_EV_REQUEST:
			if (!_luat_audio.request_block) {	// 没有请求块，找下一个请求块
				_audio_find_next_request_block();
				if (!_luat_audio.request_block) {	// 找不到请求块，直接返回
					break;
				}
			} else {
				luat_mutex_lock(_luat_audio.luat_audio_request_lock);
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
				luat_mutex_unlock(_luat_audio.luat_audio_request_lock);
			}

			break;
		}
	}
}

int luat_audio_driver_register(const luat_audio_driver_opts_t *ops, struct luat_audio_driver_probe probe, void *driver_data)
{
	int i;
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].driver_opts == NULL) {
			_luat_audio.driver_ctrl[i].driver_opts = ops;
			_luat_audio.driver_ctrl[i].driver_data = driver_data;
			_luat_audio.driver_ctrl[i].probe = probe;
			_luat_audio.driver_ctrl[i].data_channel = &_luat_audio.channel[i];
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
		if (_luat_audio.driver_ctrl[0].driver_opts) {
			return &_luat_audio.driver_ctrl[0];
		}
		return NULL;
	}
	for (i = 0; i < LUAT_AUDIO_DRIVER_MAX; i++) {
		if (_luat_audio.driver_ctrl[i].driver_opts != NULL && _luat_audio.driver_ctrl[i].probe.bus_type == probe->bus_type && _luat_audio.driver_ctrl[i].probe.bus_id == probe->bus_id) {
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
	luat_mutex_lock(_luat_audio.luat_audio_request_lock);
	req->request_id = ++_luat_audio.next_request_id;
	luat_mutex_unlock(_luat_audio.luat_audio_request_lock);
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
	LLOGD("request_id: %d add in request_block_list", req->request_id);
	luat_mutex_lock(_luat_audio.luat_audio_request_lock);
	if (luat_llist_empty(&_luat_audio.request_block_list)) {
		luat_llist_add(&req->node, &_luat_audio.request_block_list);
	} else {
		if (!luat_llist_traversal(&_luat_audio.request_block_list, _audio_add_request, req)) {
			luat_llist_add_tail(&req->node, &_luat_audio.request_block_list);
		}
	}
	luat_mutex_unlock(_luat_audio.luat_audio_request_lock);
	return luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
}

int luat_audio_request_cancel(luat_audio_request_block_t *req)
{
	if (!req) {
		return -LUAT_ERROR_PARAM_INVALID;
	}
	LLOGD("request_id: %d cancel", req->request_id);
	luat_mutex_lock(_luat_audio.luat_audio_request_lock);
	luat_llist_del(&req->node);
	if (_luat_audio.request_block) {
		if (req->request_id == _luat_audio.request_block->request_id) {
			LLOGD("now work request_id: %d cancel", req->request_id);
			_luat_audio.request_block = NULL;
		}
	}
	luat_mutex_unlock(_luat_audio.luat_audio_request_lock);
	return luat_rtos_event_send(_luat_audio.common_task_handle, LUAT_AUDIO_EV_REQUEST, 0, 0, 0, 0);
}

void luat_audio_base_init(void)
{
	luat_rtos_task_create(&_luat_audio.common_task_handle, LUAT_AUDIO_TASK_STACK, 80, "luat_audio", luat_audio_common_task, NULL, 128);
	luat_rtos_task_create(&_luat_audio.tts_task_handle, LUAT_AUDIO_TASK_STACK, 20, "luat_tts", luat_audio_tts_task, NULL, 0);
	_luat_audio.luat_audio_request_lock = luat_mutex_create();
	LUAT_INIT_LLIST_HEAD(&_luat_audio.request_block_list);
}
