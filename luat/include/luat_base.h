/******************************************************************************
 *  LuatOS基础操作
 *  @author wendal
 *  @since 0.0.1
 *****************************************************************************/

#ifndef LUAT_BASE
#define LUAT_BASE
/**LuatOS版本号*/
#define LUAT_VERSION "V0006"
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

// 以下luaopen_大多有平台无关的实现, 需要实现的是对应的luat_XXX_XXX 方法.

/** 加载sys库, 预留, 实际不可用状态*/
LUAMOD_API int luaopen_sys( lua_State *L );
/** 加载rtos库, 必选*/
LUAMOD_API int luaopen_rtos( lua_State *L );
/** 加载timer库, 可选*/
LUAMOD_API int luaopen_timer( lua_State *L );
/** 加载msgbus库, 预留, 实际不可用状态*/
LUAMOD_API int luaopen_msgbus( lua_State *L );
/** 加载gpio库, 可选*/
LUAMOD_API int luaopen_gpio( lua_State *L );
/** 加载adc库, 可选*/
LUAMOD_API int luaopen_adc( lua_State *L );
/** 加载pwm库, 可选*/
LUAMOD_API int luaopen_pwm( lua_State *L );
/** 加载uart库, 一般都需要*/
LUAMOD_API int luaopen_uart( lua_State *L );
/** 加载pm库, 预留*/
LUAMOD_API int luaopen_pm( lua_State *L );
/** 加载fs库, 预留*/
LUAMOD_API int luaopen_fs( lua_State *L );
/** 加载wlan库, 操作wifi,可选*/
LUAMOD_API int luaopen_wlan( lua_State *L );
/** 加载socket库, 依赖netclient.h,可选*/
LUAMOD_API int luaopen_socket( lua_State *L );
/** 加载sensor库, 依赖gpio库, 可选*/
LUAMOD_API int luaopen_sensor( lua_State *L );
/** 加载log库, 必选, 依赖底层uart抽象层*/
LUAMOD_API int luaopen_log( lua_State *L );
/** 加载json库, 可选*/
LUAMOD_API int luaopen_cjson( lua_State *L );
/** 加载i2c库, 可选*/
LUAMOD_API int luaopen_i2c( lua_State *L );
/** 加载spi库, 可选*/
LUAMOD_API int luaopen_spi( lua_State *L );
/** 加载disp库, 可选, 会依赖i2c和spi*/
LUAMOD_API int luaopen_disp( lua_State *L );
/** 加载u8g2库, 可选, 会依赖i2c和spi*/
LUAMOD_API int luaopen_u8g2( lua_State *L );
/** 加载utest库, 预留*/
LUAMOD_API int luaopen_utest( lua_State *L );
/** 加载mqtt库, 预留*/
LUAMOD_API int luaopen_mqtt( lua_State *L );
/** 加载mqtt库, 预留*/
LUAMOD_API int luaopen_http( lua_State *L );
/** 加载pack库, 可选,平台无关*/
LUAMOD_API int luaopen_pack( lua_State *L );
/** 加载mqttcore库, 可选,平台无关*/
LUAMOD_API int luaopen_mqttcore( lua_State *L );
/** 加载crypto库, 可选*/
LUAMOD_API int luaopen_crypto( lua_State *L );
LUAMOD_API int luaopen_pm( lua_State *L);
LUAMOD_API int luaopen_m2m( lua_State *L);
LUAMOD_API int luaopen_libcoap( lua_State *L);
LUAMOD_API int luaopen_lpmem( lua_State *L);
LUAMOD_API int luaopen_ctiot( lua_State *L);
LUAMOD_API int luaopen_iconv(lua_State *L);
LUAMOD_API int luaopen_nbiot( lua_State *L );
LUAMOD_API int luaopen_libgnss( lua_State *L ) ;
LUAMOD_API int luaopen_fatfs( lua_State *L );
LUAMOD_API int luaopen_eink( lua_State *L);
LUAMOD_API int luaopen_dbg( lua_State *L );
/** 加载zbuff库, 可选,平台无关*/
LUAMOD_API int luaopen_zbuff( lua_State *L );

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

/** 停止启动,当前仅rt-thread实现有这个设置*/
void stopboot(void);

void luat_timer_us_delay(size_t us);

const char* luat_version_str(void);

#endif
