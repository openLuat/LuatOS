#ifndef LUAT_RTOS_H
#define LUAT_RTOS_H

#include "luat_base.h"
#include "luat_rtos_legacy.h"


typedef enum LUAT_RTOS_WAIT
{
	LUAT_NO_WAIT = 0,
	LUAT_WAIT_FOREVER = (uint32_t)0xFFFFFFFF
}LUAT_RTOS_WAIT_E;



/* ------------------------------------------------ task begin------------------------------------------------ */
typedef void (*luat_rtos_task_entry) (void*);
typedef void * luat_rtos_task_handle;
//nStackSize为bytes，必须是4的倍数。nPriority是百分比，0~100,100为最高等级，由具体实现转换到底层SDK用的优先级。event_cout，当底层SDK不支持task带mailbox时，通过queue来模拟，需要设置的item_cout
int luat_rtos_task_create(luat_rtos_task_handle *task_handle, uint32_t stack_size, uint8_t priority, const char *task_name, luat_rtos_task_entry task_fun, void* user_data, uint16_t event_cout);
int luat_rtos_task_delete(luat_rtos_task_handle task_handle);
int luat_rtos_task_suspend(luat_rtos_task_handle task_handle);
int luat_rtos_task_resume(luat_rtos_task_handle task_handle);

void luat_rtos_task_suspend_all(void);
void luat_rtos_task_resume_all(void);
void luat_rtos_task_sleep(uint32_t ms);
/* ------------------------------------------------ task   end------------------------------------------------ */

/* ----------------------------------------------- event begin---------------------------------------------- */
typedef LUAT_RT_RET_TYPE (*luat_rtos_event_wait_callback_t)(LUAT_RT_CB_PARAM);
int luat_rtos_event_send(luat_rtos_task_handle task_handle, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3, uint32_t timeout);
int luat_rtos_event_recv(luat_rtos_task_handle task_handle, uint32_t wait_event_id, luat_event_t *out_event, luat_rtos_event_wait_callback_t *callback_fun, uint32_t timeout);

/* ----------------------------------------------- event end---------------------------------------------- */

/* ----------------------------------------------- message begin---------------------------------------------- */
int luat_rtos_message_send(luat_rtos_task_handle task_handle, uint32_t message_id, void *p_message);
int luat_rtos_message_recv(luat_rtos_task_handle task_handle, uint32_t *message_id, void **p_p_message, uint32_t timeout);
/* ----------------------------------------------- message   end---------------------------------------------- */



/* ---------------------------------------------- semaphore begin--------------------------------------------- */
typedef void * luat_rtos_semaphore_t;

int luat_rtos_semaphore_create(luat_rtos_semaphore_t *semaphore_handle, uint32_t init_count);
int luat_rtos_semaphore_delete(luat_rtos_semaphore_t semaphore_handle);
int luat_rtos_semaphore_take(luat_rtos_semaphore_t semaphore_handle, uint32_t timeout);
int luat_rtos_semaphore_release(luat_rtos_semaphore_t semaphore_handle);
/* ---------------------------------------------- semaphore   end--------------------------------------------- */



/* ------------------------------------------------ mutex begin----------------------------------------------- */
typedef void * luat_rtos_mutex_t;
int luat_rtos_mutex_create(luat_rtos_mutex_t *mutex_handle);
int luat_rtos_mutex_lock(luat_rtos_mutex_t mutex_handle, uint32_t timeout);
int luat_rtos_mutex_unlock(luat_rtos_mutex_t mutex_handle);
int luat_rtos_mutex_delete(luat_rtos_mutex_t mutex_handle);

/* ------------------------------------------------ mutex   end----------------------------------------------- */



/* ------------------------------------------------ queue begin----------------------------------------------- */
typedef void * luat_rtos_queue_t;

int luat_rtos_queue_create(luat_rtos_queue_t *queue_handle, uint32_t msgcount, uint32_t msgsize);
int luat_rtos_queue_delete(luat_rtos_queue_t queue_handle);
int luat_rtos_queue_send(luat_rtos_queue_t queue_handle, void *msg, uint32_t msg_size, uint32_t timeout);
int luat_rtos_queue_recv(luat_rtos_queue_t queue_handle, void *msg, uint32_t msg_size, uint32_t timeout);
/* ------------------------------------------------ queue   end----------------------------------------------- */



/* ------------------------------------------------ timer begin----------------------------------------------- */
typedef void * luat_rtos_timer_t;
typedef LUAT_RT_RET_TYPE (*luat_rtos_timer_callback_t)(LUAT_RT_CB_PARAM);
int luat_rtos_timer_create(luat_rtos_timer_t *timer_handle);
int luat_rtos_timer_delete(luat_rtos_timer_t timer_handle);
int luat_rtos_timer_start(luat_rtos_timer_t timer_handle, uint32_t timeout, uint8_t repeat, luat_rtos_timer_callback_t callback_fun, void *user_param);
int luat_rtos_timer_stop(luat_rtos_timer_t timer_handle);
/*------------------------------------------------ timer   end----------------------------------------------- */
#endif
