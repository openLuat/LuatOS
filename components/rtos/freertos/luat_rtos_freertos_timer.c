
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
#include "luat_mem.h"

typedef struct
{
	void *timer;
	luat_rtos_timer_callback_t call_back;
	void *user_param;
	uint8_t is_repeat;
}luat_rtos_user_timer_t;

static void s_timer_callback(TimerHandle_t hTimer)
{
	luat_rtos_user_timer_t *timer = (luat_rtos_user_timer_t *)pvTimerGetTimerID(hTimer);
	if (!timer)
		return;
	if (!timer->is_repeat)
	{
		xTimerStop(hTimer, 0);
	}
	if (timer->call_back)
	{
		timer->call_back(timer->user_param);
	}
}

void *luat_create_rtos_timer(void *cb, void *param, void *task_handle)
{
	luat_rtos_user_timer_t *timer = luat_heap_malloc(sizeof(luat_rtos_user_timer_t));
	if (timer)
	{
		timer->timer = xTimerCreate(NULL, 1, 1, timer, s_timer_callback);
		if (!timer->timer)
		{
			luat_heap_free(timer);
			return NULL;
		}
		timer->call_back = cb;
		timer->user_param = param;
		timer->is_repeat = 0;
	}
	return timer;
}

int luat_start_rtos_timer(void *timer, uint32_t ms, uint8_t is_repeat)
{
	luat_rtos_user_timer_t *htimer = (luat_rtos_user_timer_t *)timer;

    if (xTimerIsTimerActive (htimer->timer))
	{
        if (luat_rtos_get_ipsr())
        {
    		BaseType_t pxHigherPriorityTaskWoken;
    		if ((xTimerStopFromISR(htimer->timer, &pxHigherPriorityTaskWoken) != pdPASS))
    			return -1;
    		portYIELD_FROM_ISR(pxHigherPriorityTaskWoken);
    		return 0;
        }
        else
        {
    		if (xTimerStop(htimer->timer, LUAT_WAIT_FOREVER) != pdPASS)
    			return -1;
        }
    }
    htimer->is_repeat = is_repeat;
    if (luat_rtos_get_ipsr())
    {
		BaseType_t pxHigherPriorityTaskWoken;
		if ((xTimerChangePeriodFromISR(htimer->timer, luat_rtos_ms2tick(ms), &pxHigherPriorityTaskWoken) != pdPASS))
			return -1;
		portYIELD_FROM_ISR(pxHigherPriorityTaskWoken);
		return 0;
    }
    else
    {
		if (xTimerChangePeriod(htimer->timer, ms, LUAT_WAIT_FOREVER) != pdPASS)
			return -1;
    }
	return 0;
}

void luat_stop_rtos_timer(void *timer)
{
	luat_rtos_user_timer_t *htimer = (luat_rtos_user_timer_t *)timer;
    if (xTimerIsTimerActive (htimer->timer))
	{
        if (luat_rtos_get_ipsr())
        {
    		BaseType_t pxHigherPriorityTaskWoken;
    		if ((xTimerStopFromISR(htimer->timer, &pxHigherPriorityTaskWoken) != pdPASS))
    			return ;
    		portYIELD_FROM_ISR(pxHigherPriorityTaskWoken);

        }
        else
        {
    		xTimerStop(htimer->timer, LUAT_WAIT_FOREVER);
        }
    }
}

void luat_release_rtos_timer(void *timer)
{
	luat_rtos_user_timer_t *htimer = (luat_rtos_user_timer_t *)timer;
	xTimerDelete(htimer->timer, LUAT_WAIT_FOREVER);
	luat_heap_free(htimer);
}

int luat_rtos_timer_create(luat_rtos_timer_t *timer_handle)
{
	if (!timer_handle) return -1;
	*timer_handle = luat_create_rtos_timer(NULL, NULL, NULL);
	return (*timer_handle)?0:-1;
}

int luat_rtos_timer_delete(luat_rtos_timer_t timer_handle)
{
	if (!timer_handle) return -1;
	luat_release_rtos_timer(timer_handle);
	return 0;
}

int luat_rtos_timer_start(luat_rtos_timer_t timer_handle, uint32_t timeout, uint8_t repeat, luat_rtos_timer_callback_t callback_fun, void *user_param)
{
	if (!timer_handle) return -1;
	luat_rtos_user_timer_t *htimer = (luat_rtos_user_timer_t *)timer_handle;

    if (xTimerIsTimerActive (htimer->timer))
	{
        if (luat_rtos_get_ipsr())
        {
    		BaseType_t pxHigherPriorityTaskWoken;
    		if ((xTimerStopFromISR(htimer->timer, &pxHigherPriorityTaskWoken) != pdPASS))
    			return -1;
    		portYIELD_FROM_ISR(pxHigherPriorityTaskWoken);
    		return 0;
        }
        else
        {
    		if (xTimerStop(htimer->timer, LUAT_WAIT_FOREVER) != pdPASS)
    			return -1;
        }
    }
    htimer->is_repeat = repeat;
    htimer->call_back = callback_fun;
    htimer->user_param = user_param;
    if (luat_rtos_get_ipsr())
    {
		BaseType_t pxHigherPriorityTaskWoken;
		if ((xTimerChangePeriodFromISR(htimer->timer, luat_rtos_ms2tick(timeout), &pxHigherPriorityTaskWoken) != pdPASS))
			return -1;
		portYIELD_FROM_ISR(pxHigherPriorityTaskWoken);
		return 0;
    }
    else
    {
		if (xTimerChangePeriod(htimer->timer, luat_rtos_ms2tick(timeout), 0) != pdPASS)
			return -1;
    }
	return 0;

}

int luat_rtos_timer_stop(luat_rtos_timer_t timer_handle)
{
	if (!timer_handle) return -1;
	luat_stop_rtos_timer(timer_handle);
	return 0;
}

int luat_rtos_timer_is_active(luat_rtos_timer_t timer_handle)
{
	if (!timer_handle) return -1;
	luat_rtos_user_timer_t *htimer = (luat_rtos_user_timer_t *)timer_handle;
	if (pdTRUE == xTimerIsTimerActive (htimer->timer))
		return 1;
	else
		return 0;
}


/*------------------------------------------------ timer   end----------------------------------------------- */
/** @}*/