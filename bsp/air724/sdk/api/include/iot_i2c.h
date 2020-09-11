#ifndef __IOT_I2C_H__
#define __IOT_I2C_H__

#include "iot_os.h"

/**
 * @ingroup iot_sdk_device 外设接口
 * @{
 */
/**
 * @defgroup iot_sdk_i2c i2c接口
 * @{
 */

/**开打i2c
*@param		port:		I2C 编号
*@param		param:		初始化参数
*@return	TRUE:       成功
*	        FALSE:      失败
**/
BOOL iot_i2c_open(
                        E_AMOPENAT_I2C_PORT  port,         
                        T_AMOPENAT_I2C_PARAM *param        
                  );

/**关闭i2c
*@param		port:		I2C 编号
*@return	TRUE:       成功
*	        FALSE:      失败
**/
BOOL iot_i2c_close(
                        E_AMOPENAT_I2C_PORT  port          
                  );

/**写入i2c数据
*@param		port:		    I2C 编号
*@param		salveAddr:		从设备地址
*@param		pRegAddr:		寄存器地址
*@param		buf:		    写入数据地址
*@param		bufLen:		    写入数据长度
*@return	UINT32:         实际写入长度
**/
UINT32 iot_i2c_write(                                    
                        E_AMOPENAT_I2C_PORT port,        
                        UINT8 salveAddr,
                        CONST UINT8 *pRegAddr,          
                        CONST UINT8* buf,               
                        UINT32 bufLen                    
                   );

/**读取i2c数据
*@param		port:		    I2C 编号
*@param		slaveAddr:		从设备地址
*@param		pRegAddr:		寄存器地址
*@param		buf:		    存储数据地址
*@param		bufLen:		    存储空间长度
*@return	UINT32:         实际读取长度
**/
UINT32 iot_i2c_read(                                        
                        E_AMOPENAT_I2C_PORT port,        
                        UINT8 slaveAddr, 
                        CONST UINT8 *pRegAddr,             
                        UINT8* buf,                      
                        UINT32 bufLen                      
                  );

/** @}*/
/** @}*/

#endif

