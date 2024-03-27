
#ifndef LUAT_CONF_BSP
#define LUAT_CONF_BSP

/*
注意!! 这个文件仅供bsp/mini使用!!!
注意!! 这个文件仅供bsp/mini使用!!!
注意!! 这个文件仅供bsp/mini使用!!!
注意!! 这个文件仅供bsp/mini使用!!!
注意!! 这个文件仅供bsp/mini使用!!!

如果你在尝试修改 air780e, air101, air601, air780ep 等等模块的 LuatOS固件 的配置, 请到对应的bsp库修改.

不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件!!

例如: 

air780e到 luatos-soc-2022 库修改里面的 luat_conf_bsp.h 文件
air780ep到 luatos-soc-2023 库修改里面的 luat_conf_bsp.h 文件
air101到 luatos-soc-air101 库修改里面的 luat_conf_bsp.h 文件

不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件!!
不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件!!
不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件, 不是这个文件!!

*/

#include "stdint.h"

#define LUAT_BSP_VERSION "V1111"
#define LUAT_USE_CMDLINE_ARGS 1
// 启用64位虚拟机
// #define LUAT_CONF_VM_64bit
#define LUAT_RTOS_API_NOTOK 1
#define LUAT_RET int
#define LUAT_RT_RET_TYPE	void
#define LUAT_RT_CB_PARAM void *param

#define LUA_USE_VFS_FILENAME_OFFSET 1

#define LUAT_USE_FS_VFS 1

#define LUAT_USE_VFS_INLINE_LIB 1

#define LUAT_COMPILER_NOWEAK 1

#define LUAT_USE_LOG_ASYNC_THREAD 0


#endif
