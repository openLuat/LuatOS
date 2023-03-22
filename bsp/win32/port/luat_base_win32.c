#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_timer.h"
#include <stdlib.h>

#ifdef LUAT_USE_LVGL
#include "lvgl.h"
void luat_lv_fs_init(void);
void lv_bmp_init(void);
void lv_png_init(void);
void lv_split_jpeg_init(void);
#endif

LUAMOD_API int luaopen_win32( lua_State *L );
int luaopen_lfs(lua_State * L);
int luaopen_rs232_core(lua_State * L);

static const luaL_Reg loadedlibs[] = {
  {"_G", luaopen_base}, // _G
  {LUA_LOADLIBNAME, luaopen_package}, // require
  {LUA_COLIBNAME, luaopen_coroutine}, // coroutine协程库
  {LUA_TABLIBNAME, luaopen_table},    // table库,操作table类型的数据结构
  {LUA_IOLIBNAME, luaopen_io},        // io库,操作文件
  {LUA_OSLIBNAME, luaopen_os},        // os库,已精简
  {LUA_STRLIBNAME, luaopen_string},   // string库,字符串操作
  {LUA_MATHLIBNAME, luaopen_math},    // math 数值计算
  {LUA_UTF8LIBNAME, luaopen_utf8},
  {LUA_DBLIBNAME, luaopen_debug},     // debug库,已精简
#if defined(LUA_COMPAT_BITLIB)
  {LUA_BITLIBNAME, luaopen_bit32},    // 不太可能启用
#endif
  {"rtos", luaopen_rtos},             // rtos底层库, 核心功能是队列和定时器
  {"log", luaopen_log},               // 日志库
  {"timer", luaopen_timer},           // 延时库
  {"pack", luaopen_pack},             // pack.pack/pack.unpack
  {"json", luaopen_cjson},             // json
  {"win32", luaopen_win32},            // windows 32 tools
  {"zbuff", luaopen_zbuff},            // 
  {"libcoap", luaopen_libcoap},        // 
  {"crypto", luaopen_crypto},
// #ifdef LUAT_USE_FATFS
//   {"fatfs", luaopen_fatfs},
// #endif
  {"sfd",   luaopen_sfd},
  {"lfs2",   luaopen_lfs2},
  {"gpio",   luaopen_gpio},
  {"i2c",   luaopen_i2c},
  {"spi",   luaopen_spi},
  {"uart",    luaopen_uart},
  // {"vmx",    luaopen_vmx},
#ifdef LUAT_USE_LCD
  {"lcd",    luaopen_lcd},
#endif
#ifdef LUAT_USE_LCD
  {"u8g2", luaopen_u8g2},
#endif
#ifdef LUAT_USE_LVGL
  {"lvgl",   luaopen_lvgl},
#endif
  {"iotauth", luaopen_iotauth},
  {"miniz", luaopen_miniz},
  {"protobuf", luaopen_protobuf},
  {"libgnss", luaopen_libgnss},
  {"rsa", luaopen_rsa},
  {NULL, NULL}
};

// 按不同的rtconfig加载不同的库函数
void luat_openlibs(lua_State *L) {
    // 初始化队列服务
    luat_msgbus_init();
    //print_list_mem("done>luat_msgbus_init");
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
    exit(code);
}

const char* luat_os_bsp(void) {
    #ifdef LUA_USE_WINDOWS
    return "win32";
    #else
    return "posix";
    #endif
}


void vConfigureTimerForRunTimeStats( void ) {}

/** 设备进入待机模式 */
void luat_os_standy(int timeout) {
    return; // nop
}

void luat_ota_reboot(int timeout_ms) {
  if (timeout_ms > 0)
    luat_timer_mdelay(timeout_ms);
  exit(0);
}

#include "windows.h"
#include <io.h>

#include <time.h>
#include <math.h>

// 获取当前时间
uint32_t get_timestamp(void) {
    // struct timespec _t;
    // clock_gettime(CLOCK_REALTIME, &_t);
    // uint32_t timenow = _t.tv_sec*1000 + lround(_t.tv_nsec/1e6);
    // //printf("time now > %u\n", timenow);
    LARGE_INTEGER ticks;
    QueryPerformanceCounter(&ticks);
    return ticks.QuadPart;
}


