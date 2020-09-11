#ifndef __IOT_GPIO_H__
#define __IOT_GPIO_H__

#include "iot_os.h"

/**
 * @defgroup iot_sdk_device 外设接口
 * @{
 */
	/**@example gpio/demo_gpio.c
	* gpio接口示例
	*/ 

/**
 * @defgroup iot_sdk_gpio GPIO接口
 * @{
 */

/**配置gpio 
*@param		port:		GPIO编号
*@param		cfg:		配置信息
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_gpio_open(                          
                        E_AMOPENAT_GPIO_PORT port,  
                        T_AMOPENAT_GPIO_CFG *cfg  
                   );

/**设置gpio 
*@param		port:		GPIO编号
*@param		value:		0 or 1
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_gpio_set(                               
                        E_AMOPENAT_GPIO_PORT port,  
                        UINT8 value                 
                );

/**读取gpio 
*@param		port:		GPIO编号
*@param		value:		0 or 1
*@return	TRUE: 	    成功
*           FALSE:      失败
**/			
BOOL iot_gpio_read(                            
                        E_AMOPENAT_GPIO_PORT port, 
                        UINT8* value             
                  );

/**关闭gpio 
*@param		port:		GPIO编号
*@return	TRUE: 	    成功
*           FALSE:      失败
**/	
BOOL iot_gpio_close(                            
                        E_AMOPENAT_GPIO_PORT port
                  );

/** @}*/
/** @}*/


#endif


