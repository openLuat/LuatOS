#ifndef __IOT_LCD_H__
#define __IOT_LCD_H__

#include "iot_os.h"

/**
 * @ingroup iot_sdk_device 外设接口
 * @{
 */
/**
 * @defgroup iot_sdk_lcd lcd接口
 * @{
 */
 
/**@example zbar/demo_zbar_lcd.c
* LCD&键盘接口示例
*/ 

/**写入 lcd命令
*@param		cmd: 命令
**/
VOID iot_lcd_write_cmd(                          
                        UINT8 cmd 
                   );

/**lcd 写入lcd数据 
*@param	 	data: 数据
**/
VOID iot_lcd_write_data(                               
                        UINT8 data                
                );


/**lcd初始化
*@param		param: lcd初始化参数
*@return	TRUE: 	    成功
*           FALSE:      失败
**/	
BOOL iot_lcd_color_init(T_AMOPENAT_COLOR_LCD_PARAM *param );

/**  刷新lcd
*@param		rect: 需要刷新的区域
*@param		pDisplayBuffer: 刷新的缓冲区
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
VOID iot_lcd_update_color_screen(
				T_AMOPENAT_LCD_RECT_T* rect,        /* 需要刷新的区域 */
				UINT16 *pDisplayBuffer    );

/** 解码jpg格式图片
*@param		filename: 文件路径包括文件名
*@param		imageinfo: 文件格式
*@return	INT32: 解码状态码
**/
INT32 iot_decode_jpeg(
                    CONST char * filename,
                    T_AMOPENAT_IMAGE_INFO *imageinfo
                    );

/** 释放jpg格式解码数据
*@param		buffer: 缓存显示buffer
*@return	INT32: 释放状态码
**/
INT32 iot_free_jpeg_decodedata(
                    INT16* buffer
                    );
/** @}*/
/** @}*/
#endif









