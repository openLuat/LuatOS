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
#include "lstate.h"
#include "stdint.h"
#include "string.h"
#include "luat_types.h"

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

uint32_t luat_os_interrupt_disable(void);

void luat_os_interrupt_enable(uint32_t level);

void luat_os_irq_disable(uint8_t IRQ_Type);

void luat_os_irq_enable(uint8_t IRQ_Type);

/** 停止启动,当前仅rt-thread实现有这个设置*/
void stopboot(void);

void luat_timer_us_delay(size_t us);

const char* luat_version_str(void);

void luat_os_print_heapinfo(const char* tag);

// 自定义扩展库的初始化入口, 可以自行注册lua库, 或其他初始化操作.
void luat_custom_init(lua_State *L);

//c等待接口
uint64_t luat_pushcwait(lua_State *L);
//c等待接口，直接向用户返回错误的对象
void luat_pushcwait_error(lua_State *L, int arg_num);
//c等待接口，对指定id进行回调响应，并携带返回参数
int luat_cbcwait(lua_State *L, uint64_t id, int arg_num);
//c等待接口，无参数的回调，可不传入lua栈
void luat_cbcwait_noarg(uint64_t id);

#endif
