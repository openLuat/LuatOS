

/**
 * 内存池的C API
 * 
*/

#ifndef LUAT_MALLOC

#define LUAT_MALLOC
#define LUAT_MALLOC_HEAP_SIZE ((size_t) 85 * 1024)

void  luat_heap_init(void);
void* luat_heap_malloc(size_t len);
void  luat_heap_free(void* ptr);
void* luat_heap_realloc(void* ptr, size_t len);
void* luat_heap_calloc(size_t count, size_t _size);
size_t luat_heap_getfree(void);

void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize);
#endif

