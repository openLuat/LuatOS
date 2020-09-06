


#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "luat_base.h"
#include "luat_malloc.h"


#include "luat_vdev.h"
#include "bget.h"

extern luat_vdev_t vdev;

void luat_heap_init(void) {
    if (vdev.luatvm_heap_ptr)
        return;
    vdev.luatvm_heap_ptr = malloc(vdev.luatvm_heap_size);
    bpool(vdev.luatvm_heap_ptr, vdev.luatvm_heap_size);
    return; // nop
}

void luat_meminfo_sys(size_t* total, size_t* used, size_t* max_used) {
    *total = 0;
    *used = 0;
    *max_used = 0;
}
