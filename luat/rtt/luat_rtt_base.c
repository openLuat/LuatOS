
#include "luat_base.h"
#include "luat_malloc.h"
#include "rtthread.h"
#include "stdio.h"
#include "luat_msgbus.h"
#include "rthw.h"
// #include "vsprintf.h"

#define DBG_TAG           "rtt.base"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>

// int l_sprintf(char *buf, int32_t size, const char *fmt, ...) {
//     rt_int32_t n;
//     va_list args;

//     va_start(args, fmt);
//     n = custom_vsprintf(buf, /*size,*/ fmt, args);
//     va_end(args);

//     return n;
// }

// 打印内存状态
void print_list_mem(const char* name) {
    #if (DBG_LVL <= DBG_DEBUG)
    LOG_I("check memory status, key=%s", name);
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

static const luaL_Reg loadedlibs[] = {
  {"_G", luaopen_base}, // _G
  {LUA_LOADLIBNAME, luaopen_package}, // require
  {LUA_COLIBNAME, luaopen_coroutine}, // coroutine协程库
  {LUA_TABLIBNAME, luaopen_table},    // table库,操作table类型的数据结构
  {LUA_IOLIBNAME, luaopen_io},        // io库,操作文件
  {LUA_OSLIBNAME, luaopen_os},        // os库,已精简
  {LUA_STRLIBNAME, luaopen_string},   // string库,字符串操作
  {LUA_MATHLIBNAME, luaopen_math},    // math 数值计算
//  {LUA_UTF8LIBNAME, luaopen_utf8},
  {LUA_DBLIBNAME, luaopen_debug},     // debug库,已精简
#if defined(LUA_COMPAT_BITLIB)
  {LUA_BITLIBNAME, luaopen_bit32},    // 不太可能启用
#endif
// 往下是RTT环境下加载的库
  {"rtos", luaopen_rtos},             // rtos底层库, 核心功能是队列和定时器
  {"log", luaopen_log},               // 日志库
  {"timer", luaopen_timer},           // 延时库
  {"json", luaopen_cjson},            // json的序列化和反序列化
  {"pack", luaopen_pack},             // pack.pack/pack.unpack
  {"uart", luaopen_uart},             // 串口操作
  {"mqttcore",luaopen_mqttcore},      // MQTT 协议封装
//  {"utest", luaopen_utest},
#ifdef RT_USING_PIN
  {"gpio", luaopen_gpio},              // GPIO脚的操作
  {"sensor", luaopen_sensor},          // 传感器操作
#endif
#ifdef RT_USING_WIFI
  {"wlan", luaopen_wlan},              // wlan/wifi联网操作
#endif
#ifdef SAL_USING_POSIX
  {"socket", luaopen_socket},          // 套接字操作
#endif
#ifdef RT_USING_I2C
  {"i2c", luaopen_i2c},                // I2C操作
#endif
#ifdef RT_USING_SPI
  {"spi", luaopen_spi},                // SPI操作
#endif
#ifdef PKG_USING_U8G2
  {"disp", luaopen_disp},              // 显示屏
#endif
  {NULL, NULL}
};

// 按不同的rtconfig加载不同的库函数
void luat_openlibs(lua_State *L) {
    // 初始化队列服务
    luat_msgbus_init();
    print_list_mem("done>luat_msgbus_init");
    // 加载系统库
    const luaL_Reg *lib;
    /* "require" functions from 'loadedlibs' and set results to global table */
    for (lib = loadedlibs; lib->func; lib++) {
        luaL_requiref(L, lib->name, lib->func, 1);
        lua_pop(L, 1);  /* remove lib */
        //extern void print_list_mem(const char* name);
        //print_list_mem(lib->name);
    }
}

void luat_os_reboot(int code) {
    rt_hw_cpu_reset();
}

void sys_start_standby(int ms);

void luat_os_standy(int timeout) {
    #ifdef BSP_USING_WM_LIBRARIES
        #ifdef BSP_USING_STANDBY
            sys_start_standby(timeout);
        #endif
    #endif
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
static rt_uint32_t wdg_timeout = 15;       /* 溢出时间，单位：秒*/
static rt_device_t wdg_dev;    /* 看门狗设备句柄 */
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
    //rt_thread_idle_sethook(idle_hook);
    return RT_EOK;
}
INIT_DEVICE_EXPORT(wdt_chk);

#define THREAD_PRIORITY         25
#define THREAD_TIMESLICE        5

ALIGN(RT_ALIGN_SIZE)
static char rtt_wdt_stack[256];
static struct rt_thread rtt_wdt;
static int rtt_wdt_feed(void* args) {
    while (1) {
        if (wdg_dev)
            rt_device_control(wdg_dev, RT_DEVICE_CTRL_WDT_KEEPALIVE, NULL);
        rt_thread_mdelay(5000);
    }
    return 0;
}
static int rtt_wdt_thread_start() {
    rt_thread_init(&rtt_wdt,
                   "rtt_wdt",
                   rtt_wdt_feed,
                   RT_NULL,
                   &rtt_wdt_stack[0],
                   sizeof(rtt_wdt_stack),
                   THREAD_PRIORITY - 1, THREAD_TIMESLICE);
    rt_thread_startup(&rtt_wdt);
}
INIT_COMPONENT_EXPORT(rtt_wdt_thread_start);
#endif
