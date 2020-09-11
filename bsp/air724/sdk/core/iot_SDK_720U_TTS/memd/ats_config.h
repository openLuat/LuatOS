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

#ifndef _ATS_CONFIG_H_
#define _ATS_CONFIG_H_

#include "srv_config.h"
#include "tts_config.h"

// Auto generated. Don't edit it manually!

#define GMI_ID "CSDK"
#define GMM_ID "CSDK_720U"
#define GMR_ID "CSDK_V1166_RDA8910_TTS"

/**
 * Whether to support coap AT commands
 */
/* #undef CONFIG_AT_COAP_SUPPORT */

/**
 * Whether to support http AT commands
 */
/* #undef CONFIG_AT_HTTP_SUPPORT */

/**
 * Whether to support ftp client AT commands
 */
/* #undef CONFIG_AT_FTP_SUPPORT */

/**
 * Whether to support MYNET AT commands
 */
/* #undef CONFIG_AT_MYNET_TCPIP_SUPPORT */

/**
 * Whether to support MYINFO AT commands
 */
/* #undef CONFIG_AT_MYINFO_SUPPORT */

/**
 * Whether to support +IPR=<n>&W
 *
 * It doesn't conform to specification, but it is needed in many cases.
 */
#define CONFIG_AT_IPR_SUPPORT_ANDW

/**
 * Whether to support CISSDK AT commands
 */
/* #undef CONFIG_AT_CISSDK_MIPL_SUPPORT */

/**
 * Whether to support softsim AT commands
 */
/* #undef CONFIG_AT_SSIM_SUPPORT */

/**
 * whether to support onenet DM AT command
 */
/* #undef CONFIG_AT_DM_LWM2M_SUPPORT */

/**
 * whether to support AT commands for memory size
 */
#define CONFIG_AT_EMMCDDRSIZE_SUPPORT

/**
 * whether to support audio AT commands
 */
#define CONFIG_AT_AUDIO_SUPPORT

/**
 * whether to use global APN
 *
 * When enabled, global/large APN information will be embedded. Otherwise,
 * local/small APN information will be embedded.
 */
#define CONFIG_AT_GLOBAL_APN_SUPPORT

/*+\new\task_183\rww\2020.4.1\添加libat版本号*/
/* #undef CONFIG_BUILD_AT */

#ifdef CONFIG_BUILD_AT
#define LIBAT_ID ""
#endif
/*-\new\task_183\rww\2020.4.1\添加libat版本号*/

/**+\new\zhuwangbin\2020.5.26\添加mqtt 3GPP宏控制mqtt 3GPP的at指令，方便裁剪 **/
#define CONFIG_ATR_MQTT_SUPPORT
#define CONFIG_ATR_3GPP_SUPPORT
/**-\new\zhuwangbin\2020.5.26\添加mqtt 3GPP宏控制mqtt 3GPP的at指令，方便裁剪 **/

#endif
