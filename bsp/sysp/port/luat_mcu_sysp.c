#include "luat_base.h"
#include "luat_mcu.h"
#include "stdio.h"

long luat_mcu_ticks(void) {
    return clock()*1000/CLOCKS_PRE_SEC;
}
