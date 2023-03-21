#ifndef LUAT_PROFILER_H
#define LUAT_PROFILER_H

#include "stdint.h"

typedef struct luat_profiler_ctx
{
    int tag;
    int ticks_start;
    int ticks_stop;
    uint32_t counter_malloc;
    uint32_t counter_free;
    uint32_t counter_realloc;
    uint32_t lua_heap_begin_used;
    uint32_t lua_heap_end_used;
    uint32_t sys_heap_begin_used;
    uint32_t sys_heap_end_used;
}luat_profiler_ctx_t;

void* luat_profiler_alloc(void *ud, void *ptr, size_t osize, size_t nsize);

int luat_profiler_start(void);
int luat_profiler_stop(void);

void luat_profiler_print(void);

typedef struct luat_profiler_mem
{
    uint32_t addr;
    size_t len;
}luat_profiler_mem_t;

#define LUAT_PROFILER_MEMDEBUG_ADDR_COUNT (1024)

#endif
