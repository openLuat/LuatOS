/*********************************************************
  Copyright (C), AirM2M Tech. Co., Ltd.
  Author: lifei
  Description: AMOPENAT 开放平台
  Others:
  History: 
    Version： Date:       Author:   Modification:
    V0.1      2012.11.24  lifei     创建文件
*********************************************************/
#ifndef OPENAT_KEYPAD_H
#define OPENAT_KEYPAD_H

/*+\BUG WM-637\lifei\2013.03.05\[OpenAT] 增加GPIO键盘接口*/
BOOL OPENAT_InitKeypad(                            /* 键盘初始化接口 */
    T_AMOPENAT_KEYPAD_CONFIG *pConfig   /* 键盘配置参数 */
);
/*-\BUG WM-637\lifei\2013.03.05\[OpenAT] 增加GPIO键盘接口*/

#endif /* OPENAT_KEYPAD_H */