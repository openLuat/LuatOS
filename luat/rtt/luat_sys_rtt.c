
#include "luat_base.h"
#include "luat_sys.h"
#include "rtthread.h"

int luat_sys_mdelay(size_t ms) {
    if (ms > 0)
        rt_thread_mdelay(ms);
    return 0;
}

