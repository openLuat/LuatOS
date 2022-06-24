#include "luat_base.h"
#include "luat_mcu.h"
#include "stdio.h"
#include "time.h"

long luat_mcu_ticks(void) {
    return clock()*1000/CLOCKS_PER_SEC;
}
