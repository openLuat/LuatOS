
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


int luat_rtos_semaphore_create(luat_rtos_semaphore_t *semaphore_handle, uint32_t init_count)
{
	if (!semaphore_handle) return -1;
	SemaphoreHandle_t sem = NULL;
	if (init_count <= 1)
	{
		sem = xSemaphoreCreateBinary();
		if (!sem)
			return -1;
		if (!init_count)
			xSemaphoreGive(sem);
	}
	else
	{
		sem = xSemaphoreCreateCounting(init_count, init_count);
		if (!sem)
			return -1;
	}
	*semaphore_handle = (luat_rtos_semaphore_t)sem;
	return 0;
}

int luat_rtos_semaphore_delete(luat_rtos_semaphore_t semaphore_handle)
{
	if (!semaphore_handle) return -1;
	vSemaphoreDelete(semaphore_handle);
	return 0;
}

int luat_rtos_semaphore_take(luat_rtos_semaphore_t semaphore_handle, uint32_t timeout)
{
	if (!semaphore_handle) return -1;
	if (pdTRUE == xSemaphoreTake(semaphore_handle, luat_rtos_ms2tick(timeout)))
		return 0;
	return -1;
}

int luat_rtos_semaphore_release(luat_rtos_semaphore_t semaphore_handle)
{
	if (!semaphore_handle) return -1;
	if (luat_rtos_get_ipsr())
	{
		BaseType_t yield = pdFALSE;
		if (pdTRUE == xSemaphoreGiveFromISR(semaphore_handle, &yield))
		{
			portYIELD_FROM_ISR(yield);
			return 0;
		}
		return -1;
	}
	else
	{
		if (pdTRUE == xSemaphoreGive(semaphore_handle))
			return 0;
		return -1;
	}
}


