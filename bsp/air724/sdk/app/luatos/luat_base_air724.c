
#include "luat_base.h"
#include "luat_timer.h"

void luat_openlibs(lua_State *L) {

}

void luat_os_reboot(int code) {

}

const char* luat_os_bsp(void) {
    return "rda8910";
}

void luat_meminfo_sys(size_t* total, size_t* used, size_t* max_used) {
    // NOP
}

void _exit(int code){}
