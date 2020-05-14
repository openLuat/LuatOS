
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "stdio.h"
#include "string.h"

LUAMOD_API int luaopen_lpmem( lua_State *L );
LUAMOD_API int luaopen_nbiot( lua_State *L );

int l_sprintf(char *buf, int32_t size, const char *fmt, ...) {
    size_t n;
    va_list args;

    va_start(args, fmt);
    n = sprintf(buf, fmt, args);
    va_end(args);

    return n;
}

// 打印内存状态
void print_list_mem(const char* name) {
    // nop
}


// 文件系统初始化函数, 做个虚拟的
void luat_fs_init() {}


// 按不同的rtconfig加载不同的库函数
void luat_openlibs(lua_State *L) {
    // 初始化队列服务
    luat_msgbus_init();
    print_list_mem("done>luat_msgbus_init");

    luaL_requiref(L, "rtos", luaopen_rtos, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(rtos)");

    luaL_requiref(L, "log", luaopen_log, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(log)");

    //luaL_requiref(L, "sys", luaopen_sys, 1);
    //lua_pop(L, 1);
    //print_list_mem("done> require(sys)");

    luaL_requiref(L, "timer", luaopen_timer, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(timer)");

    luaL_requiref(L, "gpio", luaopen_gpio, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(gpio)");

    //luaL_requiref(L, "uart", luaopen_uart, 1);
    //lua_pop(L, 1);
    //print_list_mem("done> require(uart)");

    luaL_requiref(L, "socket", luaopen_socket, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(socket)");

    luaL_requiref(L, "json", luaopen_cjson, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(json)");

    #ifdef USING_I2C
    luaL_requiref(L, "i2c", luaopen_i2c, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(i2c)");
    #endif

    luaL_requiref(L, "lpmem", luaopen_lpmem, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(lpmem)");

    
    luaL_requiref(L, "nbiot", luaopen_nbiot, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(nbiot)");
}

void luat_os_reboot(int code) {
    //;
}

void sys_start_standby(int ms);

void luat_os_standy(int timeout) {
    //
}

const char* luat_os_bsp(void) {
    return "air302";
}
// watchdog

// mock for time and exit
int time() {
    return 0;
}

void exit(int code) {
    //
}
