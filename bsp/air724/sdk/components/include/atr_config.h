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

#ifndef _ATR_CONFIG_H_
#define _ATR_CONFIG_H_

#include "srv_config.h"

// Auto generated. Don't edit it manually!

/**
 * maximum AT command parameter count
 */
#define CONFIG_ATR_CMD_PARAM_MAX 24

/**
 * maximum AT command line size
 *
 * The trailing \r is included, and \0 is not included.
 */
#define CONFIG_ATR_CMDLINE_MAX 1024

/**
 * AT command engine worker thread stack size in bytes
 */
#define CONFIG_ATR_CMD_WORKER_STACK_SIZE 2048

/**
 * whether AT command URC buffer is enabled
 *
 * When enabled, URC will be buffered when there are AT commands in
 * execution. And URC buffer will be flushed after current AT command
 * finished. When there are too many URC, either size overflow or count
 * overflow, URC will be discarded.
 */
#define CONFIG_ATR_URC_BUFF_ENABLE

/**
 * AT command URC buffer size
 *
 * Each AT channel will have separated URC buffer, this is the buffer size
 * for each AT channel.
 */
#define CONFIG_ATR_URC_BUFF_SIZE 2048

/**
 * AT command URC buffering count
 *
 * Each AT channel will have separated URC buffer, this is the count
 * for each AT channel.
 */
#define CONFIG_ATR_URC_BUFF_COUNT 32

/**
 * whether to echo command only
 *
 * When defined, extra or invalid chracters not belongs to valid AT command
 * line won't be echoed. For example, "AT\r\n" will be echoed as "AT\r" if
 * defined.
 */
/* #undef CONFIG_ATR_ECHO_COMMAND_ONLY */

/**
 * timeout in milliseconds to wait '\n' after '\r'
 *
 * It only take effects when \p CONFIG_ATR_ECHO_COMMAND_ONLY is not defined,
 * and only affects echo.
 *
 * Though '\r' is the ending character of AT comamnd line, if '\n' comes
 * immediately after '\r', '\n' is echoed before responses.
 */
#define CONFIG_ATR_LF_WAIT_MS 20

/**
 * whether enable AT command output cache
 *
 * When enabled, a small cache will be added to AT command output. It will
 * make it easier to parse AT command response.
 */
#define CONFIG_ATR_CMD_OUTPUT_CACHE_ENABLE

/**
 * AT command output cache
 *
 * There is only one global AT command output. This is the cache size.
 */
#define CONFIG_ATR_CMD_OUTPUT_CACHE_SIZE 1024

/**
 * data mode buffer size
 *
 * In PPP mode, it should be enough to hold a complete packet, with HDLC
 * escape.
 */
#define CONFIG_ATR_DATA_BUFF_SIZE 4096

/**
 * PPP packet check timeout after PPP end
 *
 * After PPP terminated, it is possible that peer will still send more PPP
 * packets. If they are interpreted as AT commands, it is possible some "bad"
 * commands will be interpreted.
 */
#define CONFIG_ATR_PPP_END_CHECK_TIMEOUT 1000

/**
 * whether CMUX is supported
 */
#define CONFIG_ATR_CMUX_SUPPORT

/**
 * CMUX input buffer size
 *
 * It should be enough to hold the input packet. At buffer overflow, the
 * content of the buffer will be dropped silently.
 */
#define CONFIG_ATR_CMUX_IN_BUFF_SIZE 4096

/**
 * CMUX output buffer size
 *
 * It should be enough to hold the output packet. At buffer overflow, the
 * content of the buffer will be dropped silently.
 */
#define CONFIG_ATR_CMUX_OUT_BUFF_SIZE 4096

/**
 * CMUX sub-channel minimum input buffer size
 */
#define CONFIG_ATR_CMUX_SUBCHANNEL_MIN_IN_BUFF_SIZE 64

/**
 * CMUX maximum DLC number
 */
#define CONFIG_ATR_CMUX_DLC_NUM 63

/**
 * AT profile count
 */
#define CONFIG_ATR_PROFILE_COUNT 2

/**
 * maximum count of delay free memory
 */
#define CONFIG_ATR_MEM_FREE_LATER_COUNT 16

/**
 * whether to enable CINIT URC output
 */
/* #undef CONFIG_ATR_CINIT_URC_ENABLED */

/**
 * maximum registered event count
 */
#define CONFIG_ATR_EVENT_MAX_COUNT 200

/**
 * maximum pending CFW UTI count
 */
#define CONFIG_ATR_CFW_PENDING_UTI_COUNT 64

/**
 * whether to create uart AT device
 */
/* #undef CONFIG_ATR_CREATE_UART */

/**
 * default uart AT device name
 */
#define CONFIG_ATR_DEFAULT_UART DRV_NAME_UART1

/**
 * default uart baud rate
 */
#define CONFIG_ATR_DEFAULT_UART_BAUD 115200

/**
 * uart auto sleep timeout
 */
#define CONFIG_ATR_UART_AUTO_SLEEP_TIMEOUT 500

/**
 * whether to power on CFW automatically
 *
 * When not defined, AT engine will wait \p EV_DM_POWER_ON_IND.
 */
#define CONFIG_ATR_CFW_AUTO_POWER_ON

/**
 * whether to create usb serial AT device
 */
#define CONFIG_ATR_CREATE_USB_SERIAL

/**
 * whether to create diag AT device
 */
#define CONFIG_ATR_CREATE_DIAG

/**
 * whether to combine all AT configuration into one file
 */
/* #undef CONFIG_ATR_CFG_IN_ONE_FILE */

/**
 * whether to support file system AT commands
 */
/* #undef CONFIG_ATS_FS_SUPPORT */

/**
 * maximum download (write) file size
 */
/* #undef CONFIG_ATS_FS_DWN_SIZE_MAX */

/**
 * maximum read file size
 */
/* #undef CONFIG_ATS_FS_RD_SIZE_MAX */

/**
 * whether to support +UPDATE AT commands
 */
#define CONFIG_ATS_UPDATE_SUPPORT

/**
 * whether to support alarm AT commands
 */
#define CONFIG_ATS_ALARM_SUPPORT

/**
 * maximum alarm count in AT
 */
#define CONFIG_ATS_ALARM_COUNT 16

/**
 * maximum alarm text length, not including \0
 */
#define CONFIG_ATS_ALARM_TEXT_LEN 32

/**
 * whether to support SGCC AT commands
 */
/* #undef CONFIG_ATS_SGCC_CATM_SUPPORT */

/**
 * whether to support camera AT commands
 */
/* #undef CONFIG_AT_CAMERA_SUPPORT */


/* #undef CONFIG_AM_AT_PLATFORM */


/*+new\rww\2020.4.30\lua tts float空间不足*/
/* #undef CONFIG_BUILD_LUA_TTS */


/* #undef CONFIG_BUILD_LUA_FLOAT */
/*-new\rww\2020.4.30\lua tts float空间不足*/

/*zhuwangbin 2020-5-20 add at+gpio*/
/* #undef CONFIG_AT_GPIO_SUPPORT */

/*+\NEW\czm\2020.07.21\添加中国电信自注册项目*/
/* #undef CONFIG_BUILD_AT_CTREG */
/*-\NEW\czm\2020.07.21\添加中国电信自注册项目*/

#undef CONFIG_AT_WITHOUT_SAT
#undef CONFIG_AT_WITHOUT_SMS
#undef CONFIG_AT_WITHOUT_PBK
#undef CONFIG_AT_WITHOUT_GPRS

#endif
