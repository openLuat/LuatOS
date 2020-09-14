
#include "iot_os.h"
#include "iot_debug.h"

#include "luat_base.h"
#include "bget.h"

#define HEAP_SIZE (512*1024)
static char luatos_heap[HEAP_SIZE];

int appimg_enter(void *param)
{    
	iot_debug_print("[os] appimg_enter");
    bpool(luatos_heap, HEAP_SIZE);
    luat_main();
    return 0;
}

void appimg_exit(void)
{
    iot_debug_print("[os] appimg_exit");
}
