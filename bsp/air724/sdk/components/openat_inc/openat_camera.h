/*********************************************************
  Copyright (C), AirM2M Tech. Co., Ltd.
  Author: Jack.li
  Description: AMOPENAT 开放平台
  Others:
  History: 
    Version： Date:       Author:   Modification:
    V0.1      2013.1.28   Jack.li     创建文件
*********************************************************/
#ifndef OPENAT_CAMERA_H
#define OPENAT_CAMERA_H

BOOL OPENAT_InitCamera(T_AMOPENAT_CAMERA_PARAM *cameraParam);

BOOL OPENAT_CameraPoweron(BOOL videoMode);
BOOL OPENAT_CameraPowerOff(void);
BOOL OPENAT_CameraPreviewOpen(T_AMOPENAT_CAM_PREVIEW_PARAM *previewParam);
BOOL OPENAT_CameraPreviewClose(void);
BOOL OPENAT_CameraCapture(T_AMOPENAT_CAM_CAPTURE_PARAM *captureParam);
BOOL OPENAT_CameraSavePhoto(INT32 iFd);
/*+\bug2406\zhuwangbin\2020.6.28\摄像头扫描预览时，要支持配置是否刷屏显示功能 */
BOOL OPENAT_CameraLcdUpdateEnable(BOOL lcdUpdateEnable);
/*-\bug2406\zhuwangbin\2020.6.28\摄像头扫描预览时，要支持配置是否刷屏显示功能 */

/*+\NEW\Jack.li\2013.2.9\增加摄像头视频录制接口 */
BOOL OPENAT_CameraVideoRecordStart(INT32 iFd);
BOOL OPENAT_CameraVideoRecordPause(void);
BOOL OPENAT_CameraVideoRecordResume(void);
BOOL OPENAT_CameraVideoRecordStop(void);
/*-\NEW\Jack.li\2013.2.9\增加摄像头视频录制接口 */

/*+\NEW\zhuwangbin\2020.7.14\添加camera sensor写寄存器接口*/
BOOL OPENAT_CameraWriteReg(PAMOPENAT_CAMERA_REG initRegTable_p, int len);
/*+\NEW\zhuwangbin\2020.7.14\添加camera sensor写寄存器接口*/

#endif /* OPENAT_CAMERA_H */

