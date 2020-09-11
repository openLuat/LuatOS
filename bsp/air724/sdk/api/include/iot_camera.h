#ifndef __IOT_CAMERA_H__
#define __IOT_CAMERA_H__

#include "iot_os.h"

/**
 * @defgroup iot_sdk_device 外设接口
 * @{
 */
	/**@example zbar/demo_zbar_camera.c
	* camera接口示例
	*/ 

/**
 * @defgroup iot_sdk_camera 摄像头接口
 * @{
 */

/**摄像头初始化
*@param		cameraParam:		初始化参数
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_camera_init(T_AMOPENAT_CAMERA_PARAM *cameraParam);

/**打开摄像头
*@param		videoMode:		是否视频模式
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_camera_poweron(BOOL videoMode);  
/**关闭摄像头
*@return  TRUE:       成功
*           FALSE:      失败
**/
BOOL iot_camera_poweroff(void); 
/**开始预览
*@param  previewParam:       预览参数
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_camera_preview_open(T_AMOPENAT_CAM_PREVIEW_PARAM *previewParam);
/**退出预览
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_camera_preview_close(void);
/**拍照
*@param  fileName:      保存图片的文件名
*@param  captureParam:       预览参数
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_camera_capture(char *fileName, T_AMOPENAT_CAM_CAPTURE_PARAM *captureParam);

/**设置camera寄存器
*@param  initRegTable_p: cam寄存器表
*@param  len:   cam寄存器长度
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_camera_WriteReg(PAMOPENAT_CAMERA_REG initRegTable_p, int len);

/** @}*/
/** @}*/


#endif


