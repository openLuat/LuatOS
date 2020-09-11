#include "iot_debug.h"
#include "am_openat.h"
#include "string.h"
#include <stdio.h>


extern BOOL g_s_traceflag;
/*******************************************
**                 DEBUG                  **
*******************************************/

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
              )
{
    IVTBL(assert)(condition, func, line);
}


/**调试信息打印
**/
VOID iot_debug_print(CHAR *fmt, ...)
{
	char buff[256] = {0};
	va_list args;
	va_start(args, fmt);
	vsnprintf(buff, 256, fmt, args);
	if(g_s_traceflag)
		IVTBL(lua_print)("%s", buff);
	else
		IVTBL(print)("%s", buff);
	va_end (args);
}

/**设置软件异常时，设备模式
*@param	  mode:   OPENAT_FAULT_RESET 重启模式
				  OPENAT_FAULT_HANG  调试模式
**/

VOID iot_debug_set_fault_mode(E_OPENAT_FAULT_MODE mode)
{
	IVTBL(SetFaultMode)(mode);
}

