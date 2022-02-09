#ifndef LUAT_RTOS_H
#define LUAT_RTOS_H

#include "luat_base.h"

/* ----------------------------------- thread ----------------------------------- */
typedef int (*thread_entry) (void*);
typedef struct luat_thread{
    thread_entry thread;
    const char *name;
    uint32_t stack_size;
    uint32_t priority;
    char* stack_buff;
    void* userdata;
}luat_thread_t;

int luat_thread_start(luat_thread_t* thread);

/* ----------------------------------- semaphore ----------------------------------- */
typedef struct luat_sem{
    const char *name;
    uint32_t value;
    uint8_t flag;
    void* userdata;
}luat_sem_t;

int luat_sem_create(luat_sem_t* semaphore);
int luat_sem_delete(luat_sem_t* semaphore);
int luat_sem_take(luat_sem_t* semaphore,uint32_t timeout);
int luat_sem_release(luat_sem_t* semaphore);

#endif
