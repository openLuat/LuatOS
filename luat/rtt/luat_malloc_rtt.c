
#include "luat_base.h"
#include "luat_malloc.h"
#include "rtthread.h"

#include "bget.h"

#define ALI8 __attribute__ ((aligned (8)))

#ifdef BSP_USING_WM_LIBRARIES
    #define LUAT_HEAP_SIZE 64*1024
    #define W600_HEAP_ADDR 0x20028000
    #ifdef RT_USING_WIFI

    #else
    #define W600_MUC_HEAP_SIZE (64*1024)
    ALI8 static char w600_mcu_heap[W600_MUC_HEAP_SIZE]; // MCU模式下, rtt起码剩余140kb内存, 用64kb不过分吧

    #endif
#else
    #ifndef LUAT_HEAP_SIZE
        #ifdef SOC_FAMILY_STM32
            #define LUAT_HEAP_SIZE (64*1024)
        #else
            #define LUAT_HEAP_SIZE 128*1024
        #endif
    #endif
    ALI8 static char luavm_buff[LUAT_HEAP_SIZE] = {0};
#endif

static int rtt_mem_init() {
    #ifdef BSP_USING_WM_LIBRARIES
    #ifdef RT_USING_WIFI
        // nothing
    #else
        // MUC heap 
        bpool(w600_mcu_heap, W600_MUC_HEAP_SIZE);
    #endif
    void *ptr = W600_HEAP_ADDR;
    #else
    char *ptr = (char*)luavm_buff;
    #endif
	bpool(ptr, LUAT_HEAP_SIZE);
    return 0;
}
INIT_COMPONENT_EXPORT(rtt_mem_init);

void luat_meminfo_sys(size_t* total, size_t* used, size_t* max_used) {
    rt_memory_info(total, used, max_used);
}
