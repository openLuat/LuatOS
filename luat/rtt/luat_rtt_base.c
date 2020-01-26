
#include "luat_base.h"
#include "luat_malloc.h"
#include "rtthread.h"
#include "stdio.h"

// 打印内存状态
void print_list_mem(const char* name) {
  luat_printf("==>>%s\n", name);
  list_mem();
}

// fix for mled加密库
// rtt的方法名称变了. rt_hwcrypto_dev_dufault --> rt_hwcrypto_dev_default
#ifdef RT_USING_HWCRYPTO
#include <hwcrypto.h>
RT_WEAK struct rt_hwcrypto_device *rt_hwcrypto_dev_dufault(void) {
    return rt_hwcrypto_dev_default();
}
#endif

// 文件系统初始化函数, 做个虚拟的
RT_WEAK void luat_fs_init() {}


// 按不同的rtconfig加载不同的库函数
void luat_openlibs(lua_State *L) {
    // 初始化队列服务
    luat_msgbus_init();
    print_list_mem("done>luat_msgbus_init");

    luaL_requiref(L, "rtos", luaopen_rtos, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(rtos)");

    //luaL_requiref(L, "sys", luaopen_sys, 1);
    //lua_pop(L, 1);
    //print_list_mem("done> require(sys)");
    
    luaL_requiref(L, "timer", luaopen_timer, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(timer)");

    #ifdef RT_USING_PIN
    luaL_requiref(L, "gpio", luaopen_gpio, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(gpio)");

    luaL_requiref(L, "sensor", luaopen_sensor, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(sensor)");
    #endif

    #ifdef RT_USING_WIFI
    luaL_requiref(L, "wlan", luaopen_wlan, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(wlan)");
    #endif

    luaL_requiref(L, "socket", luaopen_socket, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(socket)");
}