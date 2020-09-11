/*********************************************************
  Copyright (C), AirM2M Tech. Co., Ltd.
  Author: lifei
  Description: AMOPENAT 开放平台
  Others:
  History: 
    Version： Date:       Author:   Modification:
    V0.1      2012.12.14  lifei     创建文件
*********************************************************/
#ifndef AM_OPENAT_VAT_H
#define AM_OPENAT_VAT_H

#include "am_openat_common.h"


typedef VOID (*PAT_MESSAGE)(UINT8 *pData, UINT16 length);

/*+\NEW\zhuwangbin\2020.4.22\添加LUA_POC项目， 通过虚拟通道兼容POC的控制*/
typedef BOOL (*PAT_POC_MESSAGE)(char *pData, int length);
/*-\NEW\zhuwangbin\2020.4.22\添加LUA_POC项目， 通过虚拟通道兼容POC的控制*/

/*+\NEW\lijiaodi\2020.7.25\修改lua task还没跑起来的时候就已经注册上网，会有很多主动上报丢掉的问题*/
void OPENAT_vat_set_cb(PAT_MESSAGE resp_cb);
BOOL OPENAT_vat_init(void);
/*-\NEW\lijiaodi\2020.7.25\修改lua task还没跑起来的时候就已经注册上网，会有很多主动上报丢掉的问题*/
BOOL OPENAT_vat_send_at( const char* pAtCommand, unsigned nLength );

int vat_test_enter(void *param);



#endif /* AM_OPENAT_VAT_H */

