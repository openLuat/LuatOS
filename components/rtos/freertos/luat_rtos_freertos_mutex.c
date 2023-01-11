#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/timers.h"

int luat_rtos_mutex_create(luat_rtos_mutex_t *mutex_handle)
{
	if (!mutex_handle) return -1;
	QueueHandle_t pxNewQueue = NULL;
	pxNewQueue = xSemaphoreCreateRecursiveMutex();
	if (!pxNewQueue)
		return -1;
	*mutex_handle = pxNewQueue;
	return 0;
}

int luat_rtos_mutex_lock(luat_rtos_mutex_t mutex_handle, uint32_t timeout)
{
	if (!mutex_handle) return -1;
	if (pdFALSE == xSemaphoreTakeRecursive(mutex_handle, timeout))
		return -1;
	return 0;
}

int luat_rtos_mutex_unlock(luat_rtos_mutex_t mutex_handle)
{
	if (!mutex_handle) return -1;
	if (pdFALSE == xSemaphoreGiveRecursive(mutex_handle))
		return -1;
	return 0;
}

int luat_rtos_mutex_delete(luat_rtos_mutex_t mutex_handle)
{
	if (!mutex_handle) return -1;
	vSemaphoreDelete(mutex_handle);
	return 0;
}

