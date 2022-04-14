#ifndef LUAT_RTOS_H
#define LUAT_RTOS_H

#include "luat_base.h"

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
/* ----------------------------------- semaphore ----------------------------------- */
typedef struct luat_sem{
    const char *name;
    uint32_t value;
    uint8_t flag;
    void* userdata;
}luat_sem_t;


LUAT_RET luat_sem_create(luat_sem_t* semaphore);
LUAT_RET luat_sem_delete(luat_sem_t* semaphore);
LUAT_RET luat_sem_take(luat_sem_t* semaphore,uint32_t timeout);
LUAT_RET luat_sem_release(luat_sem_t* semaphore);


/* ----------------------------------- queue ----------------------------------- */

typedef struct luat_rtos_queue {
    void* userdata;
}luat_rtos_queue_t;

LUAT_RET luat_queue_create(luat_rtos_queue_t* queue, size_t msgcount, size_t msgsize);
LUAT_RET luat_queue_send(luat_rtos_queue_t*   queue, void* msg,  size_t msg_size, size_t timeout);
LUAT_RET luat_queue_recv(luat_rtos_queue_t*   queue, void* msg, size_t msg_size, size_t timeout);
LUAT_RET luat_queue_reset(luat_rtos_queue_t*   queue);
LUAT_RET luat_queue_delete(luat_rtos_queue_t*   queue);
LUAT_RET luat_queue_free(luat_rtos_queue_t*   queue);


/* ----------------------------------- timer ----------------------------------- */
void *luat_create_rtos_timer(void *cb, void *param, void *task_handle);
int luat_start_rtos_timer(void *timer, uint32_t ms, uint8_t is_repeat);
void luat_stop_rtos_timer(void *timer);
void luat_release_rtos_timer(void *timer);
#endif
