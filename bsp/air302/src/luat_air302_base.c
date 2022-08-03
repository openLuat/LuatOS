
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
  {"i2c",     luaopen_i2c},               // I2C操作
  {"spi",     luaopen_spi},               // SPI操作
  {"adc",     luaopen_adc},               // ADC模块
  {"pwm",     luaopen_pwm},               // PWM模块
//-----------------------------------------------------------------------
// 工具库, 按需选用
  {"json",    luaopen_cjson},             // json的序列化和反序列化
  {"pack",    luaopen_pack},              // pack.pack/pack.unpack
  {"mqttcore",luaopen_mqttcore},          // MQTT 协议封装
  {"libcoap", luaopen_libcoap},           // 处理COAP消息
  {"libgnss", luaopen_libgnss},           // 处理GNSS定位数据
  {"fs",      luaopen_fs},                // 文件系统库,在io库之外再提供一些方法
  {"sensor",  luaopen_sensor},            // 传感器库,支持DS18B20
  {"crypto",luaopen_crypto},            // 加密和hash模块

  /* UI */
  // {"disp",  luaopen_disp},              // OLED显示模块,支持SSD1306
  // {"u8g2", luaopen_u8g2},              // u8g2
  // {"eink",  luaopen_eink},              // 电子墨水屏,试验阶段
  // {"lcd",luaopen_lcd}, 

  //{"iconv", luaopen_iconv},             // 编码转换,暂不可用
  // {"fatfs",   luaopen_fatfs},             // 挂载sdcard
  //{"sfd",   luaopen_sfd},             // 挂载与sfd配合, 挂载spi flash
  //{"lfs2",   luaopen_lfs2},             // 挂载与sfd配合, 挂载spi flash
  //{"zbuff",luaopen_zbuff},            // zbuff库

//------------------------------------------------------------------------
// 联网及NBIOT特有的库
  {"socket",  luaopen_socket},            // 套接字操作
  {"lpmem",   luaopen_lpmem},             // 低功耗时仍工作的内存块
  {"nbiot",   luaopen_nbiot},             // NBIOT专属模块
  {"pm",      luaopen_pm},                // 低功耗模式
  {"http",    luaopen_http},              // http库
  // {"ctiot",	luaopen_ctiot},				      // ctiot库，中国电信ctwing平台
#ifdef LUAT_USE_FDB
  {"fdb",     luaopen_fdb},              // kv数据库
#endif
  {NULL, NULL}
};

// 按不同的rtconfig加载不同的库函数
void luat_openlibs(lua_State *L) {
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

// 如需调整Lua VM的内存大小, 可用实现luat_air302_vmheap_size函数
// 默认值是72kb, 总内存有100kb左右(取决于启用的库),务必留足内存给系统本身
size_t luat_air302_vmheap_size(void);
