#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include <stdlib.h>
#include "luat_mock.h"
#include "luat_libs.h"

#define LUAT_LOG_TAG "main"
#include "luat_log.h"

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
// 外设类
#ifdef LUAT_USE_UART
  {"uart",    luaopen_uart},              // 串口操作
#endif
#ifdef LUAT_USE_GPIO
  {"gpio",    luaopen_gpio},              // GPIO脚的操作
#endif
#ifdef LUAT_USE_I2C
  {"i2c",     luaopen_i2c},               // I2C操作
#endif
#ifdef LUAT_USE_SPI
  {"spi",     luaopen_spi},               // SPI操作
#endif
#ifdef LUAT_USE_I2S
  {"i2s",     luaopen_i2s},               // I2S操作
#endif
#ifdef LUAT_USE_ADC
  {"adc",     luaopen_adc},               // ADC模块
#endif
#ifdef LUAT_USE_PWM
  {"pwm",     luaopen_pwm},               // PWM模块
#endif
#ifdef LUAT_USE_WDT
  {"wdt",     luaopen_wdt},               // watchdog模块
#endif
#ifdef LUAT_USE_PM
  {"pm",      luaopen_pm},                // 电源管理模块
#endif
#ifdef LUAT_USE_MCU
  {"mcu",     luaopen_mcu},               // MCU特有的一些操作
#endif
#ifdef LUAT_USE_RTC
  {"rtc", luaopen_rtc},                   // 实时时钟
#endif
#ifdef LUAT_USE_OTP
  {"otp", luaopen_otp},                   // OTP
#endif
//-----------------------------------------------------------------
  {"rtos", luaopen_rtos},             // rtos底层库, 核心功能是队列和定时器
  {"log", luaopen_log},               // 日志库
  {"timer", luaopen_timer},           // 延时库
  {"pack", luaopen_pack},             // pack.pack/pack.unpack
  {"json", luaopen_cjson},             // json
  {"zbuff", luaopen_zbuff},            // 
  {"crypto", luaopen_crypto},
  {"hmeta", luaopen_hmeta},           // 硬件信息库
#ifdef LUAT_USE_RSA
  {"rsa", luaopen_rsa},
#endif
#ifdef LUAT_USE_MINIZ
  {"miniz", luaopen_miniz},
#endif
#ifdef LUAT_USE_PROTOBUF
  {"protobuf", luaopen_protobuf},
#endif
#ifdef LUAT_USE_IOTAUTH
  {"iotauth", luaopen_iotauth},
#endif
#ifdef LUAT_USE_ICONV
  {"iconv", luaopen_iconv},
#endif
#ifdef LUAT_USE_BIT64
  {"bit64", luaopen_bit64},
#endif
#ifdef LUAT_USE_GMSSL
  {"gmssl", luaopen_gmssl},
#endif
#ifdef LUAT_USE_MCU
  {"mcu",   luaopen_mcu},
#endif
#ifdef LUAT_USE_LIBGNSS
  {"libgnss", luaopen_libgnss},           // 处理GNSS定位数据
#endif
#ifdef LUAT_USE_FFT
  {"fft", luaopen_fft},                   // FFT 库
#endif
#ifdef LUAT_USE_FS
  {"fs",      luaopen_fs},                // 文件系统库,在io库之外再提供一些方法
#endif
#ifdef LUAT_USE_FSKV
  {"fskv",      luaopen_fskv},
#endif
#ifdef LUAT_USE_MQTTCORE
  {"mqttcore",luaopen_mqttcore},          // MQTT 协议封装
#endif
#ifdef LUAT_USE_LIBCOAP
  {"libcoap", luaopen_libcoap},           // 处理COAP消息
#endif
#ifdef LUAT_USE_YMODEM
  {"ymodem", luaopen_ymodem},
#endif
#ifdef LUAT_USE_FASTLZ
  {"fastlz", luaopen_fastlz},
#endif
#ifdef LUAT_USE_COREMARK
  {"coremark", luaopen_coremark},
#endif
#ifdef LUAT_USE_NDK
  {"ndk", luaopen_ndk},
#endif
#ifdef LUAT_USE_NETWORK
  {"socket", luaopen_socket_adapter},
  {"http", luaopen_http},
  {"mqtt", luaopen_mqtt},
  {"websocket", luaopen_websocket},
  // {"ftp", luaopen_ftp},
  {"errDump", luaopen_errdump},
#endif
#ifdef LUAT_USE_ERCOAP
  {"ercoap", luaopen_ercoap},
#endif
// UI类
#ifdef LUAT_USE_FONTS
  {"fonts", luaopen_fonts},
#endif
#ifdef LUAT_USE_DISP
  {"disp",  luaopen_disp},              // OLED显示模块
#endif
#ifdef LUAT_USE_U8G2
  {"u8g2", luaopen_u8g2},              // u8g2
#endif

#ifdef LUAT_USE_EINK
  {"eink",  luaopen_eink},              // 电子墨水屏
#endif
#ifdef LUAT_USE_FATFS
  {"fatfs",  luaopen_fatfs},              // SD卡/tf卡
#endif
#ifdef LUAT_USE_LVGL
  {"lvgl",   luaopen_lvgl},
#endif
#ifdef LUAT_USE_LCD
  {"lcd",    luaopen_lcd},
#endif
#ifdef LUAT_USE_PINYIN
  {"pinyin", luaopen_pinyin},
#endif
#ifdef LUAT_USE_GTFONT
  {"gtfont", luaopen_gtfont},
#endif
#ifdef LUAT_USE_HZFONT
  {"hzfont", luaopen_hzfont},
#endif
#ifdef LUAT_USE_TP
  {"tp",     luaopen_tp},
#endif
#ifdef LUAT_USE_AUDIO
  {"audio", luaopen_multimedia_audio},
#endif
#ifdef LUAT_USE_SQLITE3
  {"sqlite3",    luaopen_sqlite3},
#endif
#ifdef LUAT_USE_WS2812
  {"ws2812", luaopen_ws2812},
#endif
#ifdef LUAT_USE_ONEWIRE
  {"onewire", luaopen_onewire},
#endif
#ifdef LUAT_USE_XXTEA
  {"xxtea", luaopen_xxtea},
#endif
#ifdef LUAT_USE_ULWIP
  {"ulwip", luaopen_ulwip},
#endif
#ifdef LUAT_USE_PROFILER
  {"profiler", luaopen_profiler},
#endif
#ifdef LUAT_USE_VTOOL
  {"vtool", luaopen_vtool},
#endif
#ifdef LUAT_USE_AIRUI
  {"airui", luaopen_airui},
#endif
#ifdef LUAT_USE_CAN
  {"can", luaopen_can},
#endif
#ifdef LUAT_USE_OTP
  {"otp", luaopen_otp},
#endif
#ifdef LUAT_USE_MOBILE
  {"mobile", luaopen_mobile},
#endif
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

char bsp_name[64];

const char* luat_os_bsp(void) {
    int ret = 0;
    #ifdef LUAT_USE_MOCKAPI
    luat_mock_ctx_t ctx = {0};
    memcpy(ctx.key, "rtos.bsp.get", strlen("rtos.bsp.get"));
    ret = luat_mock_call(&ctx);
    if (ret == 0 && ctx.resp_len > 0 && ctx.resp_len < 64) {
      memcpy(bsp_name, ctx.resp_data, ctx.resp_len);
      bsp_name[ctx.resp_len] = 0x00;
      return bsp_name;
    }
    #endif
    return "PC";
}


/** 设备进入待机模式 */
void luat_os_standy(int timeout) {
  (void)timeout;
  return; // nop
}

void luat_ota_reboot(int timeout_ms) {
  if (timeout_ms > 0)
    luat_timer_mdelay(timeout_ms);
  exit(0);
}

///------------------------------------

#include "uv.h"

static void on_free(uv_handle_t* ptr) {
  luat_heap_free(ptr);
}


void free_uv_handle(void* ptr) {
  if (ptr == NULL)
    return;
  uv_close((uv_handle_t*)ptr, on_free);
}

void luat_rtos_task_suspend_all(void) {}

void luat_rtos_task_resume_all(void) {}
