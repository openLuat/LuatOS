#include "iot_camera.h"
#include "iot_fs.h"

/**摄像头初始化
*@param		cameraParam:		初始化参数
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_camera_init(T_AMOPENAT_CAMERA_PARAM *cameraParam)
{
  return IVTBL(InitCamera)(cameraParam);
}

/**打开摄像头
*@param		videoMode:		是否视频模式
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_camera_poweron(BOOL videoMode)
{
  return IVTBL(CameraPoweron)(videoMode);
}
/**关闭摄像头
*@return  TRUE:       成功
*           FALSE:      失败
**/
BOOL iot_camera_poweroff(void)
{
  IVTBL(CameraPowerOff)();
  return TRUE;
}
/**开始预览
*@param  previewParam:       预览参数
*@return	TRUE: 	    成功
*           FALSE:      失败

**/
BOOL iot_camera_preview_open(T_AMOPENAT_CAM_PREVIEW_PARAM *previewParam)
{
  return IVTBL(CameraPreviewOpen)(previewParam);
}
/**退出预览
*@return	TRUE: 	    成功
*           FALSE:      失败

**/
BOOL iot_camera_preview_close(void)
{
  return IVTBL(CameraPreviewClose)();
}
/**拍照
*@param  fileName:      保存图片的文件名
*@param  captureParam:       预览参数
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_camera_capture(char *fileName, T_AMOPENAT_CAM_CAPTURE_PARAM *captureParam)
{ 
	INT32 fd;
		
	if (!fileName)
	{
		return FALSE;
	}
	
	iot_fs_delete_file(fileName);
	fd = iot_fs_create_file(fileName);

	if (fd < 0)
	{
		return FALSE; 
	}
	
	if(!IVTBL(CameraCapture)(captureParam))
	{
		iot_fs_close_file(fd);
		return FALSE;
	}

	if (!IVTBL(CameraSavePhoto)(fd))
	{
		iot_fs_close_file(fd);
		return FALSE; 
	}

	iot_fs_close_file(fd);

	return TRUE;
}

/**设置camera寄存器
*@param  initRegTable_p: cam寄存器表
*@param  len:   cam寄存器长度
*@return	TRUE: 	    成功
*           FALSE:      失败
**/
BOOL iot_camera_WriteReg(PAMOPENAT_CAMERA_REG initRegTable_p, int len)
{
	return IVTBL(CameraWriteReg)(initRegTable_p, len);
}
