#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_fs.h"
#include "luat_timer.h"
#include <stdlib.h>

// int luaopen_lfs(lua_State * L);

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
// 往下是LuatOS定制的库, 如需精简请仔细测试
//----------------------------------------------------------------------
// 核心支撑库, 不可禁用!!
  {"rtos",    luaopen_rtos},              // rtos底层库, 核心功能是队列和定时器
  {"log",     luaopen_log},               // 日志库
  {"timer",   luaopen_timer},             // 延时库
//-----------------------------------------------------------------------
// 设备驱动类, 可按实际情况删减. 即使最精简的固件, 也强烈建议保留uart库
  {"uart",    luaopen_uart},              // 串口操作
  {"gpio",    luaopen_gpio},              // GPIO脚的操作
  // {"i2c",     luaopen_i2c},               // I2C操作
  // {"spi",     luaopen_spi},               // SPI操作
  // {"adc",     luaopen_adc},               // ADC模块
  // {"pwm",     luaopen_pwm},               // PWM模块
//-----------------------------------------------------------------------
// 工具库, 按需选用
  // {"json",    luaopen_cjson},             // json的序列化和反序列化
  // {"pack",    luaopen_pack},              // pack.pack/pack.unpack
  // {"mqttcore",luaopen_mqttcore},          // MQTT 协议封装
  // {"libcoap", luaopen_libcoap},           // 处理COAP消息
  // {"libgnss", luaopen_libgnss},           // 处理GNSS定位数据
  // {"fs",      luaopen_fs},                // 文件系统库,在io库之外再提供一些方法
  // {"sensor",  luaopen_sensor},            // 传感器库,支持DS18B20
  // {"disp",  luaopen_disp},              // OLED显示模块,支持SSD1306
  // {"u8g2", luaopen_u8g2},              // u8g2
  // {"crypto",luaopen_crypto},            // 加密和hash模块
  // {"eink",  luaopen_eink},              // 电子墨水屏,试验阶段
  //{"iconv", luaopen_iconv},             // 编码转换,暂不可用
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
    }
}
void luat_meminfo_sys(size_t* total, size_t* used, size_t* max_used)
{


}

const char* luat_os_bsp(void) {
    return "pico";
}

void luat_os_reboot(int code)
{

}

void luat_os_standy(int timeout)
{


}

void luat_timer_us_delay(size_t us)
{
}



