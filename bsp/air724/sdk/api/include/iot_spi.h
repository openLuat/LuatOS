#ifndef __IOT_SPI_H__
#define __IOT_SPI_H__

#include "iot_os.h"

/**
 * @ingroup iot_sdk_device 外设接口
 * @{
 */
/**
 * @defgroup iot_sdk_spi spi接口
 * @{
 */

/**配置spi
*@param		port:		SPI 编号
*@param		cfg:		初始化参数
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_spi_open(
                        E_AMOPENAT_SPI_PORT  port,         
                        T_AMOPENAT_SPI_PARAM *cfg        
                  );

/**读取spi数据
*@param		port:		SPI 编号
*@param		buf:		存储数据地址
*@param		bufLen:		存储空间长度
*@return	UINT32: 	实际读取长度
**/
UINT32 iot_spi_read(                                       
                        E_AMOPENAT_SPI_PORT port,         
                        UINT8* buf,                      
                        UINT32 bufLen                      
                  );

/**写入spi数据
*@param		port:		SPI 编号
*@param		buf:		写入数据地址
*@param		bufLen:		写入数据长度
*@return	UINT32: 	实际写入长度
**/
UINT32 iot_spi_write(                                       
                        E_AMOPENAT_SPI_PORT port,        
                        CONST UINT8* buf,                  
                        UINT32 bufLen                      
                   );

/**spi全双工读写
*@note      全双工方式读写，读写长度相同
*@param		port:		SPI 编号
*@param		txBuf:		写缓冲
*@param		rxBuf:		读缓冲
*@param		len:		读写长度
*@return	UINT32: 	实际写入长度
**/
UINT32 iot_spi_rw(                                       
                        E_AMOPENAT_SPI_PORT port,         
                        CONST UINT8* txBuf,               
                        UINT8* rxBuf,                       
                        UINT32 len                          
                );

/**关闭spi
*@param		port:		SPI 编号
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_spi_close(
                        E_AMOPENAT_SPI_PORT  port
                );    

/** @}*/
/** @}*/

#endif



