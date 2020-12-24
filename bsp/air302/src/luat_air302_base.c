
#include "luat_base.h"
#include "luat_malloc.h"



static const luaL_Reg loadedlibs[] = {
  {"_G", luaopen_base}, // _G
  // {LUA_LOADLIBNAME, luaopen_package_air302}, // require
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
// 往下是LuatOS定制的库
  {"rtos", luaopen_rtos},             // rtos底层库, 核心功能是队列和定时器
  {"log", luaopen_log},               // 日志库
  {"timer", luaopen_timer},           // 延时库
  {"json", luaopen_cjson},            // json的序列化和反序列化
  {"pack", luaopen_pack},             // pack.pack/pack.unpack
  {"uart", luaopen_uart},             // 串口操作
  {"mqttcore",luaopen_mqttcore},      // MQTT 协议封装
  {"gpio", luaopen_gpio},              // GPIO脚的操作
  {"socket", luaopen_socket},          // 套接字操作
  {"i2c", luaopen_i2c},                // I2C操作
  {"spi", luaopen_spi},                // SPI操作
  {"lpmem", luaopen_lpmem},            // 低功耗时仍工作的内存块
  {"nbiot", luaopen_nbiot},            // NBIOT专属模块
  {"adc",   luaopen_adc},              // ADC模块
  {"pwm",   luaopen_pwm},              // PWM模块
  {"crypto",luaopen_crypto},           // 加密和hash模块
  {"disp",  luaopen_disp},             // OLED显示模块
  {"fatfs", luaopen_fatfs},            // TF卡
  {"pm",    luaopen_pm},               // 低功耗模式
  {"libcoap",luaopen_libcoap},         // 处理COAP消息
  {"libgnss",luaopen_libgnss},         // 处理GNSS定位数据
  {"sensor", luaopen_sensor},          // 传感器库,当前支持DS18B20
  {"http",  luaopen_http},              // http库
  {"fs",    luaopen_fs},                // 文件系统库
  {"ctiot",	luaopen_ctiot},				      // ctiot库，NB专用
  //{"eink",  luaopen_eink},              // 电子墨水屏
  //{"iconv", luaopen_iconv},             // UTF8-GB2312互转
  {NULL, NULL}
};

// 按不同的rtconfig加载不同的库函数
void luat_openlibs(lua_State *L) {
    //print_list_mem("done>luat_msgbus_init");
    // 加载系统库
    const luaL_Reg *lib;
    /* "require" functions from 'loadedlibs' and set results to global table */
    for (lib = loadedlibs; lib->func; lib++) {
        luaL_requiref(L, lib->name, lib->func, 1);
        lua_pop(L, 1);  /* remove lib */
    }
}

const char* luat_os_bsp(void) {
    return "ec616";
}
