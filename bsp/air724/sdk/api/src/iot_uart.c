#include "iot_uart.h"

/**打开uart
*@param		port:		UART 编号
*@param		cfg:		配置信息
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_uart_open(
                        E_AMOPENAT_UART_PORT port,          
                        T_AMOPENAT_UART_PARAM *cfg         
                   )
{
    return OPENAT_config_uart(port, cfg);
}

/**关闭uart
*@param		port:		UART 编号
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_uart_close(
                        E_AMOPENAT_UART_PORT port          
                   )
{
    return OPENAT_close_uart(port);
}
 
/**读uart
*@param		port:		UART 编号
*@param		buf:		存储数据地址
*@param		bufLen:		存储空间长度
*@param		timeoutMs:	读取超时 ms
*@return	UINT32:     实际读取长度
**/
UINT32 iot_uart_read(                                      
                        E_AMOPENAT_UART_PORT port,          
                        UINT8* buf,                       
                        UINT32 bufLen,                    
                        UINT32 timeoutMs                   
                   )
{
    return OPENAT_read_uart(port, buf, bufLen, timeoutMs);
}

/**写uart
*@param		port:		UART 编号
*@param		buf:		写入数据地址
*@param		bufLen:		写入数据长度
*@return	UINT32:     实际读取长度
**/
UINT32 iot_uart_write(                                        
                        E_AMOPENAT_UART_PORT port,           
                        UINT8* buf,                         
                        UINT32 bufLen                     
                    )
{
    return OPENAT_write_uart(port, buf, bufLen);
}

/**uart接收中断使能
*@param		port:		UART 编号
*@param		enable:		是否使能
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_uart_enable_rx_int(
                        E_AMOPENAT_UART_PORT port,          
                        BOOL enable                       
                            )
{
    //return IVTBL(uart_enable_rx_int)(port, enable);
    return FALSE;
}