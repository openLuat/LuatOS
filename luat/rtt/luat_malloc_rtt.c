
#include "luat_base.h"
#include "luat_malloc.h"

// 导入rt-thread的内存管理函数
extern void* rt_malloc(size_t len);
extern void  rt_free(void* ptr);
extern void* rt_realloc(void* ptr, size_t len);
extern void* rt_calloc(size_t count, size_t _size);

void  luat_heap_init(void) {};
void* luat_heap_malloc(size_t len){
    return rt_malloc(len);
}
void  luat_heap_free(void* ptr) {
    rt_free(ptr);
}
void* luat_heap_realloc(void* ptr, size_t len) {
    return rt_realloc(ptr, len);
}
void* luat_heap_calloc(size_t count, size_t _size) {
    return rt_calloc(count, _size);
}
size_t luat_heap_getfree(void) {
    return 1024*1024*16;
};

void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
  (void)ud; (void)osize;  /* not used */
  if (nsize == 0) {
    rt_free(ptr);
    return NULL;
  }
  else
    return rt_realloc(ptr, nsize);
}
