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

#ifndef _CFW_CONFIG_H_
#define _CFW_CONFIG_H_

#include "hal_config.h"
#include "modem_config.h"

// Auto generated. Don't edit it manually!

#define CONFIG_GSM_SUPPORT
#define CONFIG_LTE_NBIOT_SUPPORT
#define CONFIG_LTE_SUPPORT

#define LTE_SUPPORT
#define LTE_NBIOT_SUPPORT

#define CFW_GPRS_SUPPORT
#define CFW_VOLTE_SUPPORT
#define PHONE_SMS_ENTRY_COUNT 200
#define DEFAULT_SIM_SLOT 0

#define CONFIG_NUMBER_OF_SIM 2
#define CONFIG_EVENT_NAME_ENABLED

#define CONFIG_CFW_PENDING_UTI_COUNT 64

/* #undef CONFIG_CFW_SKIP_NV_SAVE_RESTORE */

#define CONFIG_CFW_CALL_WITH_RPC
/* #undef CONFIG_CFW_CALL_STACK_WITH_IPC */
/* #undef CONFIG_CFW_DEBUG_IPFILTER */

#endif
