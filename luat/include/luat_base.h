/******************************************************************************
 *  LuatOS基础操作
 *  @author wendal
 *  @since 0.0.1
 *****************************************************************************/

#ifndef LUAT_BASE_H
#define LUAT_BASE_H
/**LuatOS版本号*/
#define LUAT_VERSION "V0007"
#define LUAT_VERSION_BETA 1
// 调试开关, 预留
#define LUAT_DEBUG 0

#define LUAT_WEAK                     __attribute__((weak))

//-------------------------------
// 通用头文件
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "stdint.h"
#include "string.h"

//以下是u8g2的字库，默认不开启，根据需要自行开启对应宏定义
//#define USE_U8G2_WQY12_T_GB2312      //enable u8g2 chinese font
//#define USE_U8G2_UNIFONT_SYMBOLS
//#define USE_U8G2_ICONIC_WEATHER_6X

//lua_State * luat_get_state();
/**
 * LuatOS主入口函数, 从这里开始就交由LuatOS控制了.
 * 集成时,该函数应在独立的thread/task中启动
 */
int luat_main (void);

/**
 * 加载库函数. 平台实现应该根据时间情况, 加载可用的标准库和扩展库.
 * 其中, 标准库定义为_G/table/io/os等lua原生库.
 * 扩展库为下述luaopen_XXXX及厂商自行扩展的库.
 */
void luat_openlibs(lua_State *L);

// luaopen_xxx 代表各种库, 2021.09.26起独立一个头文件
#include "luat_libs.h"

/** sprintf需要支持longlong值的打印, 提供平台无关的实现*/
int l_sprintf(char *buf, size_t size, const char *fmt, ...);

/** 重启设备 */
void luat_os_reboot(int code);
/** 设备进入待机模式 */
void luat_os_standy(int timeout);
/** 厂商/模块名字, 例如Air302, Air640W*/
const char* luat_os_bsp(void);

void luat_os_entry_cri(void);

void luat_os_exit_cri(void);

void luat_os_irq_disable(uint8_t IRQ_Type);

void luat_os_irq_enable(uint8_t IRQ_Type);

/** 停止启动,当前仅rt-thread实现有这个设置*/
void stopboot(void);

void luat_timer_us_delay(size_t us);

const char* luat_version_str(void);

void luat_os_print_heapinfo(const char* tag);

// 自定义扩展库的初始化入口, 可以自行注册lua库, 或其他初始化操作.
void luat_custom_init(lua_State *L);

#endif
