
#include "luat_base.h"
#include "luat_malloc.h"
#include "rtthread.h"
#include "stdio.h"
#include "luat_msgbus.h"
#include "rthw.h"
#include "vsprintf.h"

#define DBG_TAG           "rtt.base"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>

int l_sprintf(char *buf, int32_t size, const char *fmt, ...) {
    rt_int32_t n;
    va_list args;

    va_start(args, fmt);
    n = custom_vsprintf(buf, /*size,*/ fmt, args);
    va_end(args);

    return n;
}

// 打印内存状态
void print_list_mem(const char* name) {
    #if (DBG_LVL <= DBG_DEBUG)
    LOG_D("check memory status, key=%s", name);
    list_mem();
    #endif
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

    luaL_requiref(L, "log", luaopen_log, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(log)");

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

    luaL_requiref(L, "uart", luaopen_uart, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(uart)");
    #endif

    #ifdef RT_USING_WIFI
    luaL_requiref(L, "wlan", luaopen_wlan, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(wlan)");
    #endif

    #ifdef SAL_USING_POSIX
    luaL_requiref(L, "socket", luaopen_socket, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(socket)");
    #endif

    luaL_requiref(L, "json", luaopen_cjson, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(json)");

    #ifdef RT_USING_I2C
    luaL_requiref(L, "i2c", luaopen_i2c, 1);
    lua_pop(L, 1);
    print_list_mem("done> require(i2c)");
    #endif
}

void luat_os_reboot(int code) {
    rt_hw_cpu_reset();
}

const char* luat_os_bsp(void) {
    #ifdef BSP_USING_WM_LIBRARIES
        return "w60x";
    #else
        #ifdef STM32L1
            return "stm32";
        #else
            return "_";
        #endif
    #endif
}


RT_WEAK void rt_hw_us_delay(rt_uint32_t us)
{
    ; // nop
}

RT_WEAK void rt_hw_cpu_reset() {
    ; // nop
}

// watchdog

#ifdef BSP_USING_WDT
#include <rtdevice.h>
static rt_uint32_t wdg_timeout = 120;       /* 溢出时间，单位：秒*/
static rt_device_t wdg_dev;    /* 看门狗设备句柄 */
static void idle_hook(void)
{
    /* 在空闲线程的回调函数里喂狗 */
    rt_device_control(wdg_dev, RT_DEVICE_CTRL_WDT_KEEPALIVE, NULL);
}
static int wdt_chk(void) {
    wdg_dev = rt_device_find("wdt");
    if (wdg_dev == RT_NULL) {
        wdg_dev = rt_device_find("wdg");
        if (wdg_dev == RT_NULL) {
            LOG_I("watchdog is miss");
            return RT_EOK;
        }
    }
    LOG_I("watchdog found, enable it");
    rt_device_init(wdg_dev);
    rt_device_control(wdg_dev, RT_DEVICE_CTRL_WDT_SET_TIMEOUT, (void *)wdg_timeout);
    rt_device_control(wdg_dev, RT_DEVICE_CTRL_WDT_START, (void *)wdg_timeout);
    rt_thread_idle_sethook(idle_hook);
    return RT_EOK;
}
INIT_DEVICE_EXPORT(wdt_chk);
#endif
