#include "luat_base.h"
#include "luat_rtos.h"

#include "common.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/timers.h"

typedef struct
{
	uint32_t ID;
	uint32_t Param1;
	uint32_t Param2;
	uint32_t Param3;
}OS_EVENT;


typedef void (*IrqHandler)(int32_t IrqLine, void *pData);
typedef void (* TaskFun_t)( void * );
typedef void (* CommonFun_t)(void);
typedef void(* CBDataFun_t)(uint8_t *Data, uint32_t Len);
typedef int32_t(*CBFuncEx_t)(void *pData, void *pParam);
typedef uint64_t LongInt;

/**
 * @brief 创建一个带event收发机制的task，event就是一个16byte的queue，在创建task的时候，同时创建好了一个queue，event结构见OS_EVENT
 * 
 * @param task_fun task的入口函数
 * @param param task的入口参数
 * @param stack_bytes task的堆栈长度，单位byte，会强制4字节对齐
 * @param priority task的任务优先级，注意是百分比，0~100，100为底层OS允许的最高级，0为底层OS允许的最低级
 * @param task_name task的name
 * @param event_max_cnt，如果OS不带mailbox，就需要本参数来创建queue
 * @return void* task的句柄，后续收发event都需要这个参数，NULL为创建失败
 */
void *create_event_task(TaskFun_t task_fun, void *param, uint32_t stack_bytes, uint8_t priority, uint16_t event_max_cnt, const char *task_name);

/**
 * @brief 删除掉一个带event收发机制的task，比正常删除task多了一步删除event queue。
 * 
 * @param task_handle task的句柄
 */
void delete_event_task(void *task_handle);

/**
 * @brief 发送一个event给task
 * 
 * @param task_handle task的句柄
 * @param event 一个已经构建好的event，如果传入指针不为NULL，将忽略后续4个参数，反之，会由后续4个参数构建一个event，每个函数参数对应event内同名参数
 * @param event_id 需要构建的event id
 * @param param1 需要构建的param1
 * @param param2 需要构建的param2
 * @param param3 需要构建的param3
 * @param timeout_ms 发送的超时时间，0不等待，0xffffffff永远等待，建议就直接写0
 * @return int 成功返回0，其他都是失败
 */
int send_event_to_task(void *task_handle, OS_EVENT *event, uint32_t event_id, uint32_t param1, uint32_t param2, uint32_t param3, uint32_t timeout_ms);

/**
 * @brief 获取一个event，并根据需要返回
 * 如果target_event_id != 0 && != 0xffffffff，那么收到对应event id时返回，如果不是，则由callback交给用户临时处理，如果callback为空，则抛弃掉
 * 如果target_event_id == 0，收到消息就返回
 * 如果target_event_id == 0xffffffff，收到消息则由callback交给用户临时处理，如果callback为空，则抛弃掉
 * 
 * @param task_handle task的句柄
 * @param target_event_id 指定收到的event id
 * @param event 缓存event的空间，当收到需要的event时，缓存在这里
 * @param callback 在收到不需要的event时，回调给用户处理，回调函数中的第一个参数就是event指针，第二个参数是task句柄。这里可以为NULL，直接抛弃event
 * @param timeout_ms 0和0xffffffff永远等待，建议就直接写0
 * @return int 收到需要的event返回0
 */
int get_event_from_task(void *task_handle, uint32_t target_event_id, OS_EVENT *event,  CBFuncEx_t callback, uint32_t timeout_ms);


typedef struct
{
	void *timer;
	luat_rtos_timer_callback_t call_back;
	void *user_param;
	uint8_t is_repeat;
}luat_rtos_user_timer_t;



int luat_rtos_task_create(luat_rtos_task_handle *task_handle, uint32_t stack_size, uint8_t priority, const char *task_name, luat_rtos_task_entry task_fun, void* user_data, uint16_t event_cout)
{
	if (!task_handle) return -1;
	*task_handle = create_event_task(task_fun, user_data, stack_size, priority, event_cout, task_name);
	return (*task_handle)?0:-1;
}

int luat_rtos_task_delete(luat_rtos_task_handle task_handle)
{
	if (!task_handle) return -1;
	delete_event_task(task_handle);
	return 0;
}

int luat_rtos_task_suspend(luat_rtos_task_handle task_handle)
{
	if (!task_handle) return -1;
	vTaskSuspend(task_handle);
	return 0;
}

int luat_rtos_task_resume(luat_rtos_task_handle task_handle)
{
	if (!task_handle) return -1;
	vTaskResume(task_handle);
	return 0;
}

void luat_rtos_task_sleep(uint32_t ms)
{
	vTaskDelay(ms);
}

void luat_task_suspend_all(void)
{
	vTaskSuspendAll();
}
void luat_task_resume_all(void)
{
	xTaskResumeAll();
}

void *luat_get_current_task(void)
{
	return xTaskGetCurrentTaskHandle();
}

int luat_rtos_event_send(luat_rtos_task_handle task_handle, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3, uint32_t timeout)
{
	if (!task_handle) return -1;
	return send_event_to_task(task_handle, NULL, id, param1, param2, param3, timeout);
}

LUAT_RET luat_send_event_to_task(void *task_handle, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3)
{
	if (!task_handle) return -1;
	return send_event_to_task(task_handle, NULL, id, param1, param2, param3, LUAT_WAIT_FOREVER);
}
LUAT_RET luat_wait_event_from_task(void *task_handle, uint32_t wait_event_id, luat_event_t *out_event, void *call_back, uint32_t ms)
{
	if (!task_handle) return -1;
	return get_event_from_task(task_handle, wait_event_id, (void *)out_event, call_back, ms);
}

/**
 * 等同于luat_rtos_semaphore_create时init_count = 0
 */
void *luat_mutex_create(void)
{
	SemaphoreHandle_t sem = xSemaphoreCreateBinary();
	if (sem)
	{
		xSemaphoreGive(sem);
	}
	return sem;
}
LUAT_RET luat_mutex_lock(void *mutex)
{
	return luat_rtos_semaphore_take(mutex, LUAT_WAIT_FOREVER);
}
LUAT_RET luat_mutex_unlock(void *mutex)
{
	return luat_rtos_semaphore_release(mutex);
}
void luat_mutex_release(void *mutex)
{
	luat_rtos_semaphore_delete(mutex);
}

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
	if (pdTRUE == xSemaphoreTake(semaphore_handle, timeout))
		return 0;
	return -1;
}

int luat_rtos_semaphore_release(luat_rtos_semaphore_t semaphore_handle)
{
	if (!semaphore_handle) return -1;
	if (xPortInIsrContext())
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
		if (timeout || (xQueueSendToBackFromISR(queue_handle, item, &pxHigherPriorityTaskWoken) != pdPASS))
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
		if (timeout || (xQueueReceiveFromISR(queue_handle, item, &yield) != pdPASS))
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


/* ----------------------------------- timer ----------------------------------- */
void *luat_create_rtos_timer(void *cb, void *param, void *task_handle)
{
	luat_rtos_user_timer_t *timer = malloc(sizeof(luat_rtos_user_timer_t));
	if (timer)
	{
		timer->timer = xTimerCreate(NULL, 1, 1, timer, s_timer_callback);
		if (!timer->timer)
		{
			free(timer);
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
        if (xPortInIsrContext())
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
    if (xPortInIsrContext())
    {
		BaseType_t pxHigherPriorityTaskWoken;
		if ((xTimerChangePeriodFromISR(htimer->timer, ms, &pxHigherPriorityTaskWoken) != pdPASS))
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
        if (xPortInIsrContext())
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
	free(htimer);
}


int luat_rtos_timer_start(luat_rtos_timer_t timer_handle, uint32_t timeout, uint8_t repeat, luat_rtos_timer_callback_t callback_fun, void *user_param)
{
	if (!timer_handle) return -1;
	luat_rtos_user_timer_t *htimer = (luat_rtos_user_timer_t *)timer_handle;

    if (xTimerIsTimerActive (htimer->timer))
	{
        if (xPortInIsrContext())
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
    if (xPortInIsrContext())
    {
		BaseType_t pxHigherPriorityTaskWoken;
		if ((xTimerChangePeriodFromISR(htimer->timer, timeout, &pxHigherPriorityTaskWoken) != pdPASS))
			return -1;
		portYIELD_FROM_ISR(pxHigherPriorityTaskWoken);
		return 0;
    }
    else
    {
		if (xTimerChangePeriod(htimer->timer, timeout, 0) != pdPASS)
			return -1;
    }
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

/* ------------------------------------------------ critical begin----------------------------------------------- */
/**
 * @brief 进入临界保护
 *
 * @return uint32_t 退出临界保护所需参数
 */
uint32_t luat_rtos_entry_critical(void)
{
	luat_os_entry_cri();
    return 0;
}

/**
 * @brief 退出临界保护
 *
 * @param critical 进入临界保护时返回的参数
 */
void luat_rtos_exit_critical(uint32_t critical)
{
	luat_os_exit_cri();
}
