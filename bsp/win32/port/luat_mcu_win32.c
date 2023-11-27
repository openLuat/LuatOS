#include "luat_base.h"
#include "luat_mcu.h"
#include "windows.h"

long luat_mcu_ticks(void) {
    return GetTickCount();
}

int luat_mcu_us_period(void) {
    return 1;
}

static uint64_t tick64;
uint64_t luat_mcu_tick64(void) {
    tick64 ++;
    return tick64;
}
