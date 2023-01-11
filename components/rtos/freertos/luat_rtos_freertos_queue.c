#include "luat_base.h"
#include "luat_rtos.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"


int luat_rtos_queue_create(luat_rtos_queue_t *queue_handle, uint32_t item_count, uint32_t item_size)
{
	if (!queue_handle) return -1;
	QueueHandle_t pxNewQueue;
	pxNewQueue = xQueueCreate(item_count, item_size);
	if (!pxNewQueue)
		return -1;
	*queue_handle = pxNewQueue;
	return 0;
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
	if (xPortInIsrContext())
	{
		BaseType_t pxHigherPriorityTaskWoken;
		if (xQueueSendToBackFromISR(queue_handle, item, &pxHigherPriorityTaskWoken) != pdPASS)
			return -1;
		portYIELD_FROM_ISR(pxHigherPriorityTaskWoken);
		return 0;
	}
	else
	{
		if (xQueueSendToBack (queue_handle, item, timeout) != pdPASS)
			return -1;
	}
	return 0;
}

int luat_rtos_queue_recv(luat_rtos_queue_t queue_handle, void *item, uint32_t item_size, uint32_t timeout)
{
	if (!queue_handle || !item)
		return -1;
	BaseType_t yield = pdFALSE;
	if (xPortInIsrContext())
	{
		if (xQueueReceiveFromISR(queue_handle, item, &yield) != pdPASS)
			return -1;
		portYIELD_FROM_ISR(yield);
		return 0;
	}
	else
	{
		if (xQueueReceive(queue_handle, item, timeout) != pdPASS)
			return -1;
	}
	return 0;
}

