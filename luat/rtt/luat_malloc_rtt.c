
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
    rt_free(ptr);
}


void *luat_rt_realloc(void *rmem, rt_size_t newsize);
void *luat_rt_free(void *rmem);
void luat_rt_system_heap_init(void *begin_addr, void *end_addr);
void luat_free(void);

#ifdef BSP_USING_WM_LIBRARIES
#define LUAT_HEAP_SIZE 64*1024
#define W600_HEAP_ADDR 0x20028000
#else
#define LUAT_HEAP_SIZE 128*1024
static char luavm_buff[128*1024] = {0};
#endif

static int rtt_mem_init() {
    #ifdef BSP_USING_WM_LIBRARIES
    void *ptr = W600_HEAP_ADDR;
    luat_rt_system_heap_init(ptr, ptr + LUAT_HEAP_SIZE);
    #else
    void *ptr = (void*)luavm_buff;
    luat_rt_system_heap_init(ptr, ptr + LUAT_HEAP_SIZE);
    #endif
    return 0;
}
INIT_COMPONENT_EXPORT(rtt_mem_init);

void* luat_heap_alloc(void *ud, void *ptr, size_t osize, size_t nsize) {
  (void)ud; (void)osize;  /* not used */
#ifdef BSP_USING_WM_LIBRARIES
    if (ptr) {
        RT_ASSERT(ptr >= 0x20028000 && ptr <= (0x20028000 + LUAT_HEAP_SIZE));
    }
#endif
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
}

// void luat_rt_memory_info(size_t *total,
//                     size_t *used,
//                     size_t *max_used);

// void luat_meminfo_luavm(size_t* total, size_t* used, size_t* max_used) {
//     luat_rt_memory_info(total, used, max_used);
// }
