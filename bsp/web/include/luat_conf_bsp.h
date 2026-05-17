/*
这是Web BSP的配置文件!!!
面向 Emscripten / 浏览器运行环境
*/
#ifndef LUAT_CONF_BSP
#define LUAT_CONF_BSP

#include "stdint.h"

#define LUAT_BSP_WEB 1

#define LUAT_BSP_VERSION "V0001"
#define LUAT_USE_CMDLINE_ARGS 1
#define LUAT_RTOS_API_NOTOK 1
#define LUAT_RT_RET_TYPE void
#define LUAT_RT_CB_PARAM void *param

#define LUA_USE_VFS_FILENAME_OFFSET 1

#define LUAT_USE_FS_VFS 1
#define LUAT_USE_VFS_INLINE_LIB 1
#define LUAT_COMPILER_NOWEAK 1
#define LUAT_USE_LOG_ASYNC_THREAD 0
#define LUAT_USE_MOCKAPI 1

/*
 * Web BSP 先聚焦 Lua VM / VFS / RTOS 基础能力。
 * 浏览器环境下原生 socket / 硬件外设默认关闭，后续再按需补充专用适配层。
 */
#define LUAT_USE_FS 1
#define LUAT_USE_MCU 1
#define LUAT_USE_CJSON 1
#define LUAT_USE_ZBUFF 1
#define LUAT_USE_PACK 1
#define LUAT_USE_BIT64 1
#define LUAT_USE_MINIZ 1

#endif
