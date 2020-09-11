#ifndef __IOT_DEBUG_H__
#define __IOT_DEBUG_H__

#include "iot_os.h"
#include "stdarg.h"

/**
 * @defgroup iot_sdk_debug 调试接口
 * @{
 */

/**调试信息打印
**/
VOID iot_debug_print(     CHAR *fmt, ...);

/**assert断言
*@param		condition:	断言条件
*@param		func:	    断言函数
*@param		line:	    断言位置
*@return	TURE: 	    成功
*           FALSE:      失败
**/
VOID iot_debug_assert(                                            
                        BOOL condition,                  
                        CHAR *func,                      
                        UINT32 line                     
              );

/**设置软件异常时，设备模式
*@param		mode:	OPENAT_FAULT_RESET 重启模式
                    OPENAT_FAULT_HANG  调试模式
**/

VOID iot_debug_set_fault_mode(E_OPENAT_FAULT_MODE mode);

/** @}*/

#endif
