
#include "luat_base.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "mem"
#include "luat_log.h"


LUAT_WEAK void* luat_heap_calloc(size_t count, size_t _size) {
    void *ptr = luat_heap_malloc(count * _size);
    if (ptr) {
        memset(ptr, 0, count * _size);
    }
    return ptr;
}

LUAT_WEAK void* luat_heap_zalloc(size_t _size) {
    void *ptr = luat_heap_malloc(_size);
    if (ptr) {
        memset(ptr, 0, _size);
    }
    return ptr;
}

