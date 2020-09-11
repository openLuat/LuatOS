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

#ifndef _BOOT_CONFIG_H_
#define _BOOT_CONFIG_H_

#include "hal_config.h"

// Auto generated. Don't edit it manually!

/**
 * Whether to enable debug event in bootloader and fdl
 */
/* #undef CONFIG_BOOT_EVENT_ENABLED */

/**
 * Whether to enable trace in bootloader and fdl
 */
/* #undef CONFIG_BOOT_TRACE_ENABLED */

/**
 * bootloader image start address (8910, 8811)
 *
 * This is the bootloader loaded address in SRAM, rather than the address
 * on flash. Also, it is start address of image header. It should match
 * system ROM.
 */
#define CONFIG_BOOT_IMAGE_START 0x8000c0

/**
 * bootloader maximum image size
 */
#define CONFIG_BOOT_IMAGE_SIZE 0xbf40

/**
 * FDL1 image address in SRAM (8910)
 *
 * It should match system ROM.
 */
#define CONFIG_FDL1_IMAGE_START 0x810000

/**
 * FDL1 maximum image size (8910)
 */
#define CONFIG_FDL1_IMAGE_SIZE 0x8000

/**
 * FDL2 image address in SRAM (8910)
 */
#define CONFIG_FDL2_IMAGE_START 0x818000

/**
 * FDL2 maximum image size (8910)
 */
#define CONFIG_FDL2_IMAGE_SIZE 0x10000

/**
 * TTB start address (8910)
 */
#define CONFIG_BOOT_TTB_START 0x828000

/**
 * TTB size (8910)
 */
#define CONFIG_BOOT_TTB_SIZE 0x4400

/**
 * bootloader exception stack start address (8910)
 */
#define CONFIG_BOOT_EXCEPTION_STACK_START 0x82c400

/**
 * bootloader exception stack size (8910)
 */
#define CONFIG_BOOT_EXCEPTION_STACK_SIZE 0xc00

/**
 * heap start address for bootloader, fdl1 and fdl2 (8910)
 */
#define CONFIG_BOOT_SRAM_HEAP_START 0x82d000

/**
 * heap size for bootloader, fdl1 and fdl2 (8910)
 */
#define CONFIG_BOOT_SRAM_HEAP_SIZE 0x13000

/**
 * bootloader SVC stack size (8910)
 */
#define CONFIG_BOOT_SVC_STACK_SIZE 0xa00

/**
 * bootloader IRQ stack size (8910)
 */
#define CONFIG_BOOT_IRQ_STACK_SIZE 0x200

/**
 * bootloader SVC stack top address (8910)
 */
#define CONFIG_BOOT_SVC_STACK_TOP 0x82ce00

/**
 * bootloader IRQ stack top address (8910)
 */
#define CONFIG_BOOT_IRQ_STACK_TOP 0x82d000

/**
 * whether to enable timer interrupt in bootloader (8910)
 */
/* #undef CONFIG_BOOT_TIMER_IRQ_ENABLE */

/**
 * bootloader timer interval in milliseconds (8910)
 */
/* #undef CONFIG_BOOT_TIMER_PERIOD */

/**
 * fixed nv bin maximum size in bytes (8910, 8811)
 */
#define CONFIG_NVBIN_FIXED_SIZE 0x20000

/**
 * FDL1, FDL2 default uart device (8910)
 */
#define CONFIG_FDL_DEFAULT_UART DRV_NAME_UART2

/**
 * FDL1, FDL2 default uart baud rate (8910)
 */
#define CONFIG_FDL_UART_BAUD 921600

#endif
