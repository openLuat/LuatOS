
#ifndef LUAT_CONF_BSP
#define LUAT_CONF_BSP

#include "stdint.h"

#define LUAT_BSP_VERSION "V1005"
#define LUAT_USE_CMDLINE_ARGS 1
// 启用64位虚拟机
#define LUAT_CONF_VM_64bit
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
