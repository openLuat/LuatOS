/*********************************************************
  Copyright (C), AirM2M Tech. Co., Ltd.
  Author: lifei
  Description: AMOPENAT 开放平台
  Others:
  History: 
    Version： Date:       Author:   Modification:
    V0.1      2012.12.14  lifei     创建文件
*********************************************************/
#ifndef AM_OPENAT_IMAGE_H
#define AM_OPENAT_IMAGE_H

#include "am_openat_common.h"

typedef struct
{
     UINT16 width;
     UINT16 height;
     UINT8  format;
     UINT16*             buffer;     
}T_AMOPENAT_IMAGE_INFO;

typedef enum
{
  AMOPENAT_DECODE_FORMAT_RGB,
  AMOPENAT_DECODE_FORMAT_YUV,
  AMOPENAT_DECODE_FORMAT_MAX
}T_AMOPENAT_DECODE_FORMAT;

typedef struct
{
  UINT16                        inWidth;
  UINT16                        inHeight;
  UINT16                        outWidth;
  UINT16                        outHeight;
  BOOL                           inQuality;
  T_AMOPENAT_DECODE_FORMAT       inFormat;
  UINT8*                         inBuffer;  
}T_AMOPENAT_DECODE_INPUT_PARAM;

INT32 OPENAT_ImgsDecodeJpeg(UINT8 * buffer, UINT32 len, T_AMOPENAT_IMAGE_INFO *imageinfo);
INT32 OPENAT_ImgsDecodeJpegBuffer(CONST char * buffer, T_AMOPENAT_IMAGE_INFO *imageinfo);
INT32 OPENAT_ImgsFreeJpegDecodedata(UINT16* buffer);
INT32 OPENAT_ImgsEncodeJpegBuffer(
          T_AMOPENAT_DECODE_INPUT_PARAM *inputParam,
          UINT8    *outBuffer,
          UINT32   *outBufferLen
                                          );
#endif /* AM_OPENAT_IMAGE_H */

