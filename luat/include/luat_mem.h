#ifndef LUAT_MEM_H
#define LUAT_MEM_H
#include "luat_malloc.h"

typedef enum {
    LUAT_HEAP_SRAM,
    LUAT_HEAP_PSRAM,
} LUAT_HEAP_TYPE_E;

void luat_heap_opt_init(LUAT_HEAP_TYPE_E type);
void* luat_heap_opt_malloc(LUAT_HEAP_TYPE_E type,size_t len);
void luat_heap_opt_free(LUAT_HEAP_TYPE_E type,void* ptr);
void* luat_heap_opt_realloc(LUAT_HEAP_TYPE_E type,void* ptr, size_t len);
void* luat_heap_opt_calloc(LUAT_HEAP_TYPE_E type,size_t count, size_t size);
void* luat_heap_opt_zalloc(LUAT_HEAP_TYPE_E type,size_t size);

void luat_meminfo_opt_sys(LUAT_HEAP_TYPE_E type,size_t* total, size_t* used, size_t* max_used);

#define LUAT_MEM_MALLOC luat_heap_malloc
#define LUAT_MEM_FREE luat_heap_free
#define LUAT_MEM_REALLOC luat_heap_realloc
#define LUAT_MEM_CALLOC luat_heap_calloc


#endif