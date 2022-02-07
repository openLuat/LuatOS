#ifndef LUAT_RTOS_H
#define LUAT_RTOS_H

#include "luat_base.h"

typedef int (*thread_entry) (void*);

typedef struct luat_thread
{
    thread_entry thread;
    const char *name;
    uint32_t stack_size;
    uint32_t priority;
    char* stack_buff;
    void* userdata;
}luat_thread_t;

int luat_thread_start(luat_thread_t thread);

#endif
