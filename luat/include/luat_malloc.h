

/**
 * 内存池的C API
 * 
*/

#ifndef LUAT_MALLOC_H
#define LUAT_MALLOC_H

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

//----------------
// 这部分是使用系统内存
void  luat_heap_init(void);
void* luat_heap_malloc(size_t len);
void  luat_heap_free(void* ptr);
void* luat_heap_realloc(void* ptr, size_t len);
void* luat_heap_calloc(size_t count, size_t _size);
void* luat_heap_zalloc(size_t _size);

//size_t luat_heap_getfree(void);
// 这部分是LuaVM专属内存
void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize);

// 两个获取内存信息的方法,单位字节
void luat_meminfo_luavm(size_t* total, size_t* used, size_t* max_used);
void luat_meminfo_sys(size_t* total, size_t* used, size_t* max_used);

#endif
