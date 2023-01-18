#include "luat_base.h"
#include "luat_rtos.h"

#if (defined(CONFIG_IDF_CMAKE))
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#else
#include "FreeRTOS.h"
#include "semphr.h"
#endif

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

void *luat_mutex_create(void){
	return xSemaphoreCreateRecursiveMutex();
}

int luat_mutex_lock(void *mutex){
	if (!mutex) return -1;
	if (pdFALSE == xSemaphoreTakeRecursive(mutex, portMAX_DELAY))
		return -1;
	return 0;
}

int luat_mutex_unlock(void *mutex){
	if (!mutex) return -1;
	if (pdFALSE == xSemaphoreGiveRecursive(mutex))
		return -1;
	return 0;
}

void luat_mutex_release(void *mutex){
	if (!mutex) return;
	vSemaphoreDelete(mutex);
}

