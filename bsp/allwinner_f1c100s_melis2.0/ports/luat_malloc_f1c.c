#include "luat_base.h"
#include "luat_malloc.h"

#include "port.h"
#include "stdint.h"

void luat_meminfo_sys(size_t* total, size_t* used, size_t* max_used) {
    *total = 0;
    *used = 0;
    *max_used = 0;
}

void* luat_heap_malloc(size_t len) {
    return esMEMS_Malloc(NULL, len);
}

void  luat_heap_free(void* ptr) {
    esMEMS_Mfree(NULL, ptr);
}

void* luat_heap_realloc(void* ptr, size_t len) {
    return esMEMS_Realloc(NULL, ptr, len);
}

void* luat_heap_calloc(size_t count, size_t _size) {
    return luat_heap_malloc(count * _size);
}
