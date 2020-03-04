
#include "luat_base.h"
#include "luat_malloc.h"
#include "rtthread.h"

#define DBG_TAG           "luat.heap"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>

// 导入rt-thread的内存管理函数

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
}

#ifdef BSP_USING_WM_LIBRARIES
#define W600_HEAP_SIZE 64*1024
void *luat_rt_realloc(void *rmem, rt_size_t newsize);
void *luat_rt_free(void *rmem);
void luat_rt_system_heap_init(void *begin_addr, void *end_addr);
void list_luat_mem(void);
static rt_err_t w60x_memcheck() {
    // 首先, 把128k的内存全部设置为0
    void *ptr = 0x20028000;
    rt_memset(ptr, 0, 128*1024);
    luat_rt_system_heap_init(ptr, ptr + W600_HEAP_SIZE);

    return 0;
}
INIT_COMPONENT_EXPORT(w60x_memcheck);
#endif

void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
  (void)ud; (void)osize;  /* not used */
#ifdef BSP_USING_WM_LIBRARIES
    if (nsize == 0) {
        luat_rt_free(ptr);
        return RT_NULL;
    }
    void* ptr2 = luat_rt_realloc(ptr, nsize);
    if (ptr2 == RT_NULL) {
        rt_kprintf("luat_heap_alloc FAIL ptr=0x%x osize=0x%x, nsize=0x%x\n", ptr, osize, nsize);
        list_luat_mem();
    }
    return ptr2;
#else
    return rt_realloc(ptr, nsize);
#endif // end of USE_CUSTOM_MEM
}
