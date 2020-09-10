
#include "luat_base.h"
#include "luat_malloc.h"
#include "rtthread.h"

#include "bget.h"

#ifdef BSP_USING_WM_LIBRARIES
    #define LUAT_HEAP_SIZE 64*1024
    #define W600_HEAP_ADDR 0x20028000
#else
    #ifndef LUAT_HEAP_SIZE
        #ifdef SOC_FAMILY_STM32
            #define LUAT_HEAP_SIZE (64*1024)
        #else
            #define LUAT_HEAP_SIZE 128*1024
        #endif
    #endif
static char luavm_buff[LUAT_HEAP_SIZE] = {0};
#endif

static int rtt_mem_init() {
    #ifdef BSP_USING_WM_LIBRARIES
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
