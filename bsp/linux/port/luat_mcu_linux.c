#include "luat_base.h"
#include "luat_mcu.h"
// #include "task.h"

long luat_mcu_ticks(void) {
    return clock()*1000;
}
