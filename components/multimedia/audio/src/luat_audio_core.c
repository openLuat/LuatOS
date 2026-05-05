#include "luat_base.h"
#include "luat_audio_api.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#ifndef LUAT_AUDIO_TASK_STACK
#define LUAT_AUDIO_TASK_STACK 13 * 1024
#endif
typedef struct
{
	luat_rtos_task_handle common_task_handle;
	luat_rtos_task_handle tts_task_handle;
}luat_audio_ctrl_t;

static luat_audio_ctrl_t _luat_audio;

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
	for(;;)
	{
		luat_rtos_event_recv(_luat_audio.common_task_handle, 0, &out_event, NULL, 0);
	}
}

void luat_audio_base_init(void)
{
	luat_rtos_task_create(&_luat_audio.common_task_handle, LUAT_AUDIO_TASK_STACK, 80, "luat_audio", luat_audio_common_task, NULL, 128);
	luat_rtos_task_create(&_luat_audio.tts_task_handle, LUAT_AUDIO_TASK_STACK, 20, "luat_tts", luat_audio_tts_task, NULL, 0);
}
