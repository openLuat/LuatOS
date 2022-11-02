#ifndef LUAT_RTOS_H
#define LUAT_RTOS_H

#include "luat_base.h"
//定时器回调函数需要定义成 LUAT_RT_RET_TYPE fun_name(LUAT_RT_CB_PARAM)
//定时器回调函数退出时需要， return LUAT_RT_RET;
#ifndef LUAT_RT_RET_TYPE
#define LUAT_RT_RET_TYPE	void
#endif

#ifndef LUAT_RT_RET
#define LUAT_RT_RET
#endif

#ifndef LUAT_RT_CB_PARAM
#define LUAT_RT_CB_PARAM	void
//#define LUAT_RT_CB_PARAM	void *param
//#define LUAT_RT_CB_PARAM void *pdata, void *param
#endif
/* ----------------------------------- thread ----------------------------------- */
typedef int (*thread_entry) (void*);
typedef void (*task_entry) (void*);
typedef struct luat_thread{
	union
	{
		int id;
		void *handle;
	};
    union
	{
		thread_entry entry;
		task_entry task_fun;
	};
    const char *name;
    uint32_t stack_size;
    uint32_t* task_stk;
    uint32_t priority;
    char* stack_buff;
    void* userdata;
}luat_thread_t;

LUAT_RET luat_thread_start(luat_thread_t* thread);
LUAT_RET luat_thread_stop(luat_thread_t* thread);
LUAT_RET luat_thread_delete(luat_thread_t* thread);
LUAT_RET luat_send_event_to_task(void *task_handle, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3);
LUAT_RET luat_wait_event_from_task(void *task_handle, uint32_t wait_event_id, void *out_event, void *call_back, uint32_t ms);
void *luat_get_current_task(void);
/* ----------------------------------- semaphore ----------------------------------- */
void *luat_semaphore_create(void);
LUAT_RET luat_semaphore_delete(void* semaphore);
LUAT_RET luat_semaphore_take(void* semaphore,uint32_t timeout);
LUAT_RET luat_semaphore_release(void* semaphore);


void *luat_mutex_create(void);
LUAT_RET luat_mutex_lock(void *mutex);
LUAT_RET luat_mutex_unlock(void *mutex);
void luat_mutex_release(void *mutex);

/* ----------------------------------- queue ----------------------------------- */

void *luat_queue_create(size_t msgcount, size_t msgsize);
LUAT_RET luat_queue_send(void*   queue, void* msg,  size_t msg_size, size_t timeout);
LUAT_RET luat_queue_recv(void*   queue, void* msg, size_t msg_size, size_t timeout);
LUAT_RET luat_queue_reset(void*   queue);
LUAT_RET luat_queue_delete(void*   queue);
LUAT_RET luat_queue_free(void*   queue);


/* ----------------------------------- timer ----------------------------------- */
void *luat_create_rtos_timer(void *cb, void *param, void *task_handle);
int luat_start_rtos_timer(void *timer, uint32_t ms, uint8_t is_repeat);
void luat_stop_rtos_timer(void *timer);
void luat_release_rtos_timer(void *timer);

void luat_task_suspend_all(void);
void luat_task_resume_all(void);
#endif
