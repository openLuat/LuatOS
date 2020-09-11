/* Copyright (C) 2018 RDA Technologies Limited and/or its affiliates("RDA").
 * All rights reserved.
 *
 * This software is supplied "AS IS" without any warranties.
 * RDA assumes no responsibility or liability for the use of the software,
 * conveys no license or title under any patent, copyright, or mask work
 * right to the product. RDA reserves the right to make changes in the
 * software without notification.  RDA also make no representation or
 * warranty that such application will be suitable for the specified use
 * without further testing or modification.
 */

#ifndef _FUPDATE_CONFIG_H_
#define _FUPDATE_CONFIG_H_

#include "hal_config.h"

// Auto generated. Don't edit it manually!

#define CONFIG_FUPDATE_PACK_FILE_NAME "fota.pack"
#define CONFIG_FUPDATE_STAGE_FILE_NAME "fota.stage"
#define CONFIG_FUPDATE_TEMP_FILE_NAME "fota.tmp"

#define CONFIG_FUPDATE_SUPPORT_FLASH_PATCH
#define CONFIG_FUPDATE_SUPPORT_FS_PATCH

//+zhuwangbin\2020.06.20\add newapp newcore api
#define CONFIG_NEWAPP_FILE_NAME "newapp.tmp"
#define FUPDATE_NEWAPP_FILE_NAME CONFIG_FS_FOTA_DATA_DIR "/" CONFIG_NEWAPP_FILE_NAME
//-zhuwangbin\2020.06.20\add newapp newcore api

#define FUPDATE_PACK_FILE_NAME CONFIG_FS_FOTA_DATA_DIR "/" CONFIG_FUPDATE_PACK_FILE_NAME
#define FUPDATE_STAGE_FILE_NAME CONFIG_FS_FOTA_DATA_DIR "/" CONFIG_FUPDATE_STAGE_FILE_NAME
#define FUPDATE_TEMP_FILE_NAME CONFIG_FS_FOTA_DATA_DIR "/" CONFIG_FUPDATE_TEMP_FILE_NAME
#define LOG_TAG_FUPDATE OSI_MAKE_LOG_TAG('F', 'U', 'P', 'D')
#endif
