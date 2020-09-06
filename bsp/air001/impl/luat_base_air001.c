
#include "luat_vdev.h"

#include <unistd.h>

#include "luat_malloc.h"

luat_vdev_t vdev;

int luat_vdev_init() {
    printf("Go\r\n");
    memset(&vdev, 0, sizeof(luat_vdev_t));
    // 分配lua heap内存

    vdev.luatvm_heap_size = 128*1024; // 做成可配置

    // TODO 初始化GPIO
    luat_vdev_gpio_init();

    // TODO 初始化UART
    luat_vdev_uart_init();

    // 初始化Lua VM内存
    luat_heap_init();

    return 0;
}


void luat_os_reboot(int code) {
    return; // NOP
}
/** 设备进入待机模式 */
void luat_os_standy(int timeout) {
    return; // nop
}
/** 厂商/模块名字, 例如Air302, Air640W*/
const char* luat_os_bsp(void) {
    return "Air001"; // 做成配置
}

void luat_timer_us_delay(size_t us) {
    if (us)
        usleep(us);
    return;
}


// -----------------------

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
  {"gpio", luaopen_gpio},              // GPIO脚的操作
  {"sensor", luaopen_sensor},          // 传感器操作
//   {"wlan", luaopen_wlan},              // wlan/wifi联网操作
//   {"socket", luaopen_socket},          // 套接字操作
//   {"http", luaopen_http},              // http库
//   {"libcoap", luaopen_libcoap},        // 处理COAP数据包
//   {"i2c", luaopen_i2c},                // I2C操作
//   {"spi", luaopen_spi},                // SPI操作
//   {"disp", luaopen_disp},              // 显示屏
//   {"crypto", luaopen_crypto},          // 加密和hash库
  {"fs",   luaopen_fs},                // 文件系统库
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