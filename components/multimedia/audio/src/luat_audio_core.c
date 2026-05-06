#include "luat_base.h"
#include "luat_audio_api.h"
#include "luat_audio_request.h"
#include "luat_audio_channel.h"
#include "luat_common_api.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_rtos_legacy.h"

enum {
	LUAT_AUDIO_EV_NEED_DATA = 0x01,
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
}luat_audio_ctrl_t;

static luat_audio_ctrl_t _luat_audio;

#ifndef __LUAT_C_CODE_IN_ISR__
#define __LUAT_C_CODE_IN_ISR__
#endif

LUAT_WEAK __LUAT_C_CODE_IN_ISR__ int luat_audio_driver_event_callback(uint32_t event, uint8_t *rx_data, uint32_t param, struct luat_audio_driver_ctrl *ctrl)
{
	return 0;
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
	for(;;) {
		luat_rtos_event_recv(_luat_audio.common_task_handle, 0, &out_event, NULL, 0);
		switch (out_event.id) {
		case LUAT_AUDIO_EV_NEED_DATA:
			break;
		case LUAT_AUDIO_EV_REQUEST:
			if (luat_llist_empty(&_luat_audio.request_block_list)) {
				break;
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

int luat_audio_request(luat_audio_request_block_t *req)
{
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

void luat_audio_base_init(void)
{
	luat_rtos_task_create(&_luat_audio.common_task_handle, LUAT_AUDIO_TASK_STACK, 80, "luat_audio", luat_audio_common_task, NULL, 128);
	luat_rtos_task_create(&_luat_audio.tts_task_handle, LUAT_AUDIO_TASK_STACK, 20, "luat_tts", luat_audio_tts_task, NULL, 0);
	_luat_audio.luat_audio_request_lock = luat_mutex_create();
	LUAT_INIT_LLIST_HEAD(&_luat_audio.request_block_list);
}
