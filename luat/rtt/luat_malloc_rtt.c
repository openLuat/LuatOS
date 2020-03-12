
#include "luat_base.h"
#include "luat_malloc.h"
#include "rtthread.h"

#define DBG_TAG           "luat.heap"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>

#ifdef RT_USING_MEMTRACE
int memcheck(void);
#endif

void  luat_heap_init(void) {};
void* luat_heap_malloc(size_t len){
    return rt_malloc(len);
}
void  luat_heap_free(void* ptr) {
    #ifdef BSP_USING_WM_LIBRARIES
    if (ptr)
        RT_ASSERT(ptr >= 0x20000000 && ptr <= 0x20028000);
    #endif
    rt_free(ptr);
}

#ifdef BSP_USING_WM_LIBRARIES
#define W600_HEAP_SIZE 64*1024
void *luat_rt_realloc(void *rmem, rt_size_t newsize);
void *luat_rt_free(void *rmem);
void luat_rt_system_heap_init(void *begin_addr, void *end_addr);
void luat_free(void);
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
    if (ptr) {
        RT_ASSERT(ptr >= 0x20028000 && ptr <= (0x20028000 + W600_HEAP_SIZE));
    }
    if (nsize == 0) {
        luat_rt_free(ptr);
        return RT_NULL;
    }
    #ifdef RT_USING_MEMTRACE
    //memcheck();
    #endif
    void* ptr2 = luat_rt_realloc(ptr, nsize);
    if (ptr2 == RT_NULL) {
        //rt_kprintf("luat_heap_alloc FAIL ptr=0x%x osize=0x%x, nsize=0x%x\n", ptr, osize, nsize);
        //luat_free();
    }
    return ptr2;
#else
    return rt_realloc(ptr, nsize);
#endif // end of USE_CUSTOM_MEM
}
