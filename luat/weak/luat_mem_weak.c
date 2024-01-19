
#include "luat_base.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "mem"
#include "luat_log.h"

LUAT_WEAK void luat_heap_opt_init(LUAT_HEAP_TYPE_E type){
    luat_heap_init();
}

LUAT_WEAK void* luat_heap_opt_malloc(LUAT_HEAP_TYPE_E type,size_t len){
    return luat_heap_malloc(len);
}

LUAT_WEAK void luat_heap_opt_free(LUAT_HEAP_TYPE_E type,void* ptr){
    luat_heap_free(ptr);
}

LUAT_WEAK void* luat_heap_opt_realloc(LUAT_HEAP_TYPE_E type,void* ptr, size_t len){
    return luat_heap_realloc(ptr, len);
}

LUAT_WEAK void* luat_heap_opt_calloc(LUAT_HEAP_TYPE_E type,size_t count, size_t size){
    return luat_heap_opt_zalloc(type,count*size);
}

LUAT_WEAK void* luat_heap_opt_zalloc(LUAT_HEAP_TYPE_E type,size_t size){
    void *ptr = luat_heap_opt_malloc(type,size);
    if (ptr) {
        memset(ptr, 0, size);
    }
    return ptr;
}

LUAT_WEAK void luat_meminfo_opt_sys(LUAT_HEAP_TYPE_E type,size_t* total, size_t* used, size_t* max_used){
    if (type == LUAT_HEAP_PSRAM){
        *total = 0;
        *used = 0;
        *max_used = 0;
    }else
        luat_meminfo_sys(total, used, max_used);
}



