#ifndef __IOT_ZBAR_H__
#define __IOT_ZBAR_H__
#include "iot_os.h"

/**
 * @defgroup iot_sdk_zbar 二维码解析接口
 * @{
 */
 
/**@example zbar/demo_zbar.c
* 二维码接口示例
*/ 

/**解析二维码，返回句柄handle
*@param		width:		解析图片的宽度
*@param		height:		解析图片的高度
*@param		data:		解析图片的数据
*@param		size:		解析图片数据大小
*@return	获取句柄handle， 不等于0表示解析成功
*           
**/
int iot_zbar_scannerOpen(int width, int height, int size, unsigned char *data);

/**获取解析二维码的数据
*@param		handle:		句柄,由iot_zbar_scannerOpen生成
*@param		len:		获取数据的长度
*@return	获取的数据地址
**/
char * iot_zbar_getData(int handle, int *len);

/**查看是否还有下一个数据
*@param		handle:		句柄,由iot_zbar_scannerOpen生成
*@return	TRUE:   还有下一个数据
*			FALSE:  没有下一个数据
**/
BOOL iot_zbar_findNextData(int handle);

/**获取当前数据编码的格式
*@param		handle:		句柄,由iot_zbar_scannerOpen生成
*@return	返回的格式类型
**/
char * iot_zbar_getType(int handle);

/**释放句柄
*@param		handle:		句柄,由iot_zbar_scannerOpen生成
*@return    void	
**/
void iot_zbar_scannerClose(int handle);

/** @}*/
#endif
