#ifndef LUAT_RTOS_H
#define LUAT_RTOS_H

#include "luat_base.h"

/* ----------------------------------- thread ----------------------------------- */
typedef int (*thread_entry) (void*);
typedef struct luat_thread{
    int id;
    thread_entry entry;
    const char *name;
    uint32_t stack_size;
    uint32_t priority;
    char* stack_buff;
    void* userdata;
}luat_thread_t;

LUAT_RET luat_thread_start(luat_thread_t* thread);
LUAT_RET luat_thread_stop(luat_thread_t* thread);
LUAT_RET luat_thread_delete(luat_thread_t* thread);

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


typedef struct luat_rtos_queue {
    void* userdata;
}luat_rtos_queue_t;

LUAT_RET luat_queue_create(luat_rtos_queue_t* queue, size_t msgcount, size_t msgsize);
LUAT_RET luat_queue_send(luat_rtos_queue_t*   queue, void* msg,  size_t msg_size, size_t timeout);
LUAT_RET luat_queue_recv(luat_rtos_queue_t*   queue, void* msg, size_t msg_size, size_t timeout);
LUAT_RET luat_queue_free(luat_rtos_queue_t*   queue);

#endif
