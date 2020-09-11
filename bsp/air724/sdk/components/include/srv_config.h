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

#ifndef _SRV_CONFIG_H_
#define _SRV_CONFIG_H_

// Auto generated. Don't edit it manually!

/**
 * whether to enable trace through usb serial
 */
#define CONFIG_USB_TRACE_ENABLE

/**
 * whether to enable 2line wakeup feature
 */
/* #undef CONFIG_TWOLINE_WAKEUP_ENABLE */

/**
 * input gpio number for 2line wakeup feature
 */
/* #undef CONFIG_TWOLINE_WAKEUP_IN_GPIO */

/**
 * output gpio number for 2line wakeup feature
 */
/* #undef CONFIG_TWOLINE_WAKEUP_OUT_GPIO */

/**
 * whether to enable gpio simulation for DTR
 */
/* #undef CONFIG_SRV_DTR_ENABLE */

/**
 * gpio number for DTR simulation
 */
/* #undef CONFIG_SRV_DTR_GPIO */

/**
 * whether to enable software debounce of DTR gpio simulation
 */
/* #undef CONFIG_SRV_DTR_DEBOUNCE_ENABLE */

/**
 * software debounce time for DTR gpio simulation
 */
/* #undef CONFIG_SRV_DTR_DEBOUNCE_TIME */

/**
 * log tag of service module
 */
#define LOG_TAG_SRV OSI_MAKE_LOG_TAG('S', 'E', 'R', 'V')

#endif
