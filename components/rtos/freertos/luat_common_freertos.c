

#ifdef LUAT_FREERTOS_FULL_INCLUDE
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/timers.h"
#else
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semphr.h"
#include "timers.h"
#endif

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_mcu.h"
#include "luat_mem.h"
#include "c_common.h"

#define LUAT_LOG_TAG "rtos"
#include "luat_log.h"

typedef struct
{
	TaskHandle_t handle;
	QueueHandle_t queue;
	uint8_t is_run;
}task_handle_t;

typedef void (*IrqHandler)(int32_t IrqLine, void *pData);
typedef void (* TaskFun_t)( void * );
typedef void (* CommonFun_t)(void);
typedef void(* CBDataFun_t)(uint8_t *Data, uint32_t Len);
typedef int32_t(*CBFuncEx_t)(void *pData, void *pParam);
typedef uint64_t LongInt;

#ifdef __LUATOS_TICK_64BIT__
uint64_t GetSysTickMS(void)
{
	return xTaskGetTickCount();
}
#endif

#if defined(CHIP_EC618) || defined(CHIP_EC716) || defined(CHIP_EC718)
#else
int luat_rtos_ms2tick(int ms) {
	if (configTICK_RATE_HZ == 1000) {
		return ms;
	}
	if (ms == LUAT_WAIT_FOREVER) {
		return LUAT_WAIT_FOREVER;
	}
    if (ms <= 0) {
        return 0;
	}
    if ((configTICK_RATE_HZ) == 500) {
        return (ms + 1) / 2;
	}
    return ms;
}
#endif


void *create_event_task(TaskFun_t task_fun, void *param, uint32_t stack_bytes, uint8_t priority, uint16_t event_max_cnt, const char *task_name)
{
	priority = configMAX_PRIORITIES * priority / 100;
	if (!priority) priority = 2;
	if (priority >= configMAX_PRIORITIES) priority -= 1;

	// 不同的BSP的StackType_t大小不一样,这导致stack_bytes需要适配
	if (sizeof(StackType_t) == 1) {
		// nop
	}
	else if (sizeof(StackType_t) == 2) {
		stack_bytes = (stack_bytes + 1) >> 1;
	}
	else if (sizeof(StackType_t) == 4) {
		stack_bytes = (stack_bytes + 3) >> 2;
	}
	else if (sizeof(StackType_t) == 8) {
		stack_bytes = (stack_bytes + 7) >> 3;
	}
	else {
		LLOGW("unkown sizeof(StackType_t) , fallback to 4");
		stack_bytes = (stack_bytes + 3) >> 2;
	}

	task_handle_t *handle = luat_heap_zalloc(sizeof(task_handle_t));

	if (event_max_cnt)
	{
		handle->queue = xQueueCreate(event_max_cnt, sizeof(OS_EVENT));
		if (!handle->queue)
		{
			luat_heap_free(handle);
			return NULL;
		}
	}
	else
	{
		handle->queue = NULL;
	}
	if (pdPASS != xTaskCreate(task_fun, task_name, stack_bytes, param, priority, &handle->handle))
	{
		if (handle->queue)
			vQueueDelete(handle->queue);
		luat_heap_free(handle);
		return NULL;
	}

	handle->is_run = 1;
	return handle;
}

void delete_event_task(void *task_handle)
{
	task_handle_t *handle = (void *)task_handle;
	uint32_t cr;
	cr = luat_rtos_entry_critical();
	if (handle->queue)
	{
		vQueueDelete(handle->queue);
	}
	handle->queue = NULL;
	handle->is_run = 0;
	luat_rtos_exit_critical(cr);
	vTaskDelete(handle->handle);
}

int send_event_to_task(void *task_handle, OS_EVENT *event, uint32_t event_id, uint32_t param1, uint32_t param2, uint32_t param3, uint32_t timeout_ms)
{
	if (!task_handle) return -1;
	BaseType_t result = pdFALSE;
	task_handle_t *handle = (void *)task_handle;
	OS_EVENT Event;
	if (event)
	{
		Event = *event;

	}
	else
	{
		Event.ID = event_id;
		Event.Param1 = param1;
		Event.Param2 = param2;
		Event.Param3 = param3;
	}

	BaseType_t xHigherPriorityTaskWoken = pdFALSE;
	if (luat_rtos_get_ipsr())
	{
		result = xQueueSendToBackFromISR(handle->queue, &Event, &xHigherPriorityTaskWoken);
		if (xHigherPriorityTaskWoken)
		{
			portYIELD_WITHIN_API();
		}
	}
	else
	{
		return ((pdPASS == xQueueSendToBack(handle->queue, &Event, timeout_ms))?0:-1);
	}
	return (pdPASS == result)?0:-1;
}


int get_event_from_task(void *task_handle, uint32_t target_event_id, OS_EVENT *event,  CBFuncEx_t callback, uint32_t timeout_ms)
{
	uint64_t start_ms = GetSysTickMS();
	int32_t result = ERROR_NONE;
	uint32_t wait_ms = timeout_ms;
	task_handle_t *handle = (void *)task_handle;
	int ret = 0;
	if (xTaskGetCurrentTaskHandle() != handle->handle)
	{
		return -1;
	}
	if (luat_rtos_get_ipsr())
	{
		return -ERROR_PERMISSION_DENIED;
	}
	if (!task_handle) return -ERROR_PARAM_INVALID;

	if (!wait_ms)
	{
		wait_ms = portMAX_DELAY;
	}
GET_NEW_EVENT:
	if ((ret = xQueueReceive(handle->queue, event, wait_ms)) != pdTRUE)
	{
		return -ERROR_OPERATION_FAILED;
	}

	if ((target_event_id == CORE_EVENT_ID_ANY) || (event->ID == target_event_id))
	{
		goto GET_EVENT_DONE;
	}
	if (callback)
	{
		callback(event, task_handle);
	}

	if ((timeout_ms != portMAX_DELAY) && timeout_ms)
	{
		if (timeout_ms > (uint32_t)(GetSysTickMS() - start_ms + 3))
		{
			wait_ms = timeout_ms - (uint32_t)(GetSysTickMS() - start_ms);
		}
		else
		{
			return -ERROR_OPERATION_FAILED;
		}
	}
	else
	{
		wait_ms = portMAX_DELAY;
	}
	goto GET_NEW_EVENT;
GET_EVENT_DONE:
	return result;
}

