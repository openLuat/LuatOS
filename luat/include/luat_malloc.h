

/**
 * 内存池的C API
 * 
*/

#ifndef LUAT_MALLOC

#define LUAT_MALLOC

//----------------
// 这部分是使用系统内存
void  luat_heap_init(void);
void* luat_heap_malloc(size_t len);
void  luat_heap_free(void* ptr);
void* luat_heap_realloc(void* ptr, size_t len);
void* luat_heap_calloc(size_t count, size_t _size);
//size_t luat_heap_getfree(void);
// 这部分是LuaVM专属内存
void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize);

// 两个获取内存信息的方法,单位字节
void luat_meminfo_luavm(size_t* total, size_t* used, size_t* max_used);
void luat_meminfo_sys(size_t* total, size_t* used, size_t* max_used);

#endif

