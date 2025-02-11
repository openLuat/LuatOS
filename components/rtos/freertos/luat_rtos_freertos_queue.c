
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


int luat_rtos_queue_create(luat_rtos_queue_t *queue_handle, uint32_t item_count, uint32_t item_size)
{
	if (!queue_handle) return -1;
	*queue_handle  = xQueueCreate(item_count, item_size);
	return (*queue_handle)?0:-1;
}

int luat_rtos_queue_delete(luat_rtos_queue_t queue_handle)
{
	if (!queue_handle) return -1;
    vQueueDelete ((QueueHandle_t)queue_handle);
	return 0;
}

int luat_rtos_queue_send(luat_rtos_queue_t queue_handle, void *item, uint32_t item_size, uint32_t timeout)
{
	if (!queue_handle || !item) return -1;
	if (luat_rtos_get_ipsr())
	{
		BaseType_t pxHigherPriorityTaskWoken;
		if (xQueueSendFromISR(queue_handle, item, &pxHigherPriorityTaskWoken) != pdPASS)
			return -1;
		portYIELD_FROM_ISR(pxHigherPriorityTaskWoken);
		return 0;
	}
	else
	{
		if (xQueueSend(queue_handle, item, luat_rtos_ms2tick(timeout)) != pdPASS)
			return -1;
	}
	return 0;
}

int luat_rtos_queue_recv(luat_rtos_queue_t queue_handle, void *item, uint32_t item_size, uint32_t timeout)
{
	if (!queue_handle || !item)
		return -1;
	BaseType_t yield = pdFALSE;
	if (luat_rtos_get_ipsr())
	{
		if (xQueueReceiveFromISR(queue_handle, item, &yield) != pdPASS)
			return -1;
		portYIELD_FROM_ISR(yield);
		return 0;
	}
	else
	{
		if (xQueueReceive(queue_handle, item, luat_rtos_ms2tick(timeout)) != pdPASS)
			return -1;
	}
	return 0;
}

int luat_rtos_queue_get_cnt(luat_rtos_queue_t queue_handle, uint32_t *item_cnt)
{
	if (!queue_handle || !item_cnt)
		return -1;
	if (luat_rtos_get_ipsr()) {
		*item_cnt = uxQueueMessagesWaitingFromISR(queue_handle);
	}
	else {
		*item_cnt = uxQueueMessagesWaiting(queue_handle);
	}
	return 0;
}
