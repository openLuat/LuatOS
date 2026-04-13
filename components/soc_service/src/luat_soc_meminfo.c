#include "luat_base.h"
#include "luat_soc_service.h"
#include "luat_mem.h"
#include "luat_mcu.h"

void luat_meminfo_query(LUAT_HEAP_TYPE_E tp,size_t* total, size_t* used, size_t* max_used, int log_out) {
    // 输出内存信息, Lua内存和系统内存
    uint64_t tnow = luat_mcu_tick64_ms();
    if (tp == LUAT_HEAP_SRAM) {
        luat_meminfo_opt_sys(LUAT_HEAP_SRAM, total, used, max_used);
        if (log_out) {
            soc_info("+MEM: SYS %llu %u %u %u", tnow, *total, *used, *max_used);
        }
    }
    // 然后是PSRAM
    else if (tp == LUAT_HEAP_PSRAM) {
        #ifdef LUAT_USE_PSRAM
        luat_meminfo_opt_sys(LUAT_HEAP_PSRAM, total, used, max_used);
        if (log_out) {
            soc_info("+MEM: PSRAM %llu %u %u %u", tnow, *total, *used, *max_used);
        }
        #endif
    }
    // 然后是LUA内存
    else if (tp == 0) {
        luat_meminfo_luavm(total, used, max_used);
        if (log_out) {
            soc_info("+MEM: LUA %llu %u %u %u", tnow, *total, *used, *max_used);
        }
    }
}