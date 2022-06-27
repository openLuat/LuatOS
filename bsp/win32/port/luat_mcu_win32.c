#include "luat_base.h"
#include "luat_mcu.h"
#include "windows.h"

long luat_mcu_ticks(void) {
    return GetTickCount();
}
