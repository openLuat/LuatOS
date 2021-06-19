#include "luat_base.h"
#include "luat_malloc.h"

void luat_meminfo_sys(size_t* total, size_t* used, size_t* max_used) {
    *total = 0;
    *used = 0;
    *max_used = 0;
}
