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

#ifndef _DIAG_CONFIG_H_
#define _DIAG_CONFIG_H_

// Auto generated. Don't edit it manually!

/**
 * whether diag is enabled
 */
#define CONFIG_DIAG_ENABLED

/**
 * diag default uart device
 */
#define CONFIG_DIAG_DEFAULT_UART DRV_NAME_UART2

/**
 * diag uart default baud rate
 */
#define CONFIG_DIAG_DEFAULT_UART_BAUD 921600

/**
 * whether diag through usb serial is supported
 */
#define CONFIG_DIAG_DEVICE_USRL_SUPPORT

/**
 * diag default usb serial device
 */
#define CONFIG_DIAG_DEFAULT_USERIAL DRV_NAME_USRL_COM5

#endif
