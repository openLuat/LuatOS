#ifndef __OPENAT_OTA_H__
#define __OPENAT_OTA_H__

#include "am_openat.h"

E_OPENAT_OTA_RESULT openat_otaInit(void);

E_OPENAT_OTA_RESULT openat_otaProcess(char* data, unsigned int len, unsigned int total);

E_OPENAT_OTA_RESULT openat_otaDone(void);

/*+\NEW\zhuwangbin\2020.06.20\添加newapp, newcore 接口*/
BOOL  OPENAT_FlashSetNewCoreRegion(char* filename);

BOOL OPENAT_FlashSetNewAppRegion(CONST char* filename);
/*-\NEW\zhuwangbin\2020.06.20\添加newapp, newcore 接口*/

#endif
