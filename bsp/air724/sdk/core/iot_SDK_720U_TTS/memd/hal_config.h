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

#ifndef _HAL_CONFIG_H_
#define _HAL_CONFIG_H_

// Auto generated. Don't edit it manually!

/**
 * whether it is 8910 series
 */
#define CONFIG_SOC_8910

/**
 * whether it is 6760 series
 */
/* #undef CONFIG_SOC_6760 */

/**
 * whether it is 8955 series
 */
/* #undef CONFIG_SOC_8955 */

/**
 * whether it is 8908 and 8909 series
 */
/* #undef CONFIG_SOC_8909 */

/**
 * whether it is FPGA, not real chip
 *
 * This will be defined when developing in FPGA. For SOC independent codes,
 * and it is needed to distinguish FPGA and real chip, this macro can be
 * used.
 */
/* #undef CONFIG_RUN_ON_FPGA */

/**
 * whether it is ARM CPUs
 */
#define CONFIG_CPU_ARM

/**
 * whether it is ARMv7-A CPUs
 */
#define CONFIG_CPU_ARMV7A

/**
 * whether it is ARM Cortex A5
 */
#define CONFIG_CPU_ARM_CA5

/**
 * whether it is ARMv7-M CPUs
 */
/* #undef CONFIG_CPU_ARMV7M */

/**
 * whether it is ARM Cortex M4F
 */
/* #undef CONFIG_CPU_ARM_CM4F */

/**
 * whether it is MIPS CPUs
 */
/* #undef CONFIG_CPU_MIPS */

/**
 * whether it is XCPU, used in 8955
 */
/* #undef CONFIG_CPU_MIPS_XCPU */

/**
 * whether it is XCPU2, used in 8909
 */
/* #undef CONFIG_CPU_MIPS_XCPU2 */

/**
 * I-cache and D-cache line size
 *
 * It is assumed that I-cache line size is the same with D-cache line size.
 */
#define CONFIG_CACHE_LINE_SIZE 32

/**
 * whether there is MMU
 */
#define CONFIG_HAVE_MMU

/**
 * whether there is PSRAM
 */
#define CONFIG_USE_PSRAM

/**
 * whether there is DDR
 */
/* #undef CONFIG_USE_DDR */

/**
 * whether there is PSRAM or DDR
 */
#define CONFIG_HAVE_EXT_RAM

/**
 * PSRAM or DDR size, shall match CONFIG_RAM_xx
 */
#define CONFIG_RAM_SIZE 0x1000000

/**
 * whether NOR flash is used
 */
#define CONFIG_NOR_FLASH

/**
 * NOR flash size, shall match CONFIG_FLASH_xx
 */
#define CONFIG_FLASH_SIZE 0x800000

/**
 * whether external NOR flash is used
 */
/* #undef CONFIG_SUPPORT_EXT_FLASH */

/**
 * external NOR flash size
 */
/* #undef CONFIG_EXT_FLASH_SIZE */

/**
 * SRAM size
 *
 * - 8955/8909: system SRAM size
 * - 8811: total SRAM size
 * - 8910: it is not used
 */
/* #undef CONFIG_SRAM_SIZE */

/**
 * uimage header size (used in 8910)
 */
#define CONFIG_UIMAGE_HEADER_SIZE 0x40

/**
 * system SRAM physical address
 */
#define CONFIG_SRAM_PHY_ADDRESS 0x800000

/**
 * NOR flash physical address
 */
#define CONFIG_NOR_PHY_ADDRESS 0x60000000

/**
 * external NOR flash physical address
 */
#define CONFIG_NOR_EXT_PHY_ADDRESS 0x70000000

/**
 * PSRAM or DDR physical address
 */
#define CONFIG_RAM_PHY_ADDRESS 0x80000000

/**
 * GIC base address
 */
#define CONFIG_GIC_BASE_ADDRESS 0x08201000

/**
 * GIC CPU interface offset
 */
#define CONFIG_GIC_CPU_INTERFACE_OFFSET 0x00001000

/**
 * system ROM load SRAM offset
 */
#define CONFIG_ROM_LOAD_SRAM_OFFSET 0xc0

/**
 * system ROM load maximum size
 */
#define CONFIG_ROM_LOAD_SIZE 0xbf40

/**
 * NOR flash offset of bootloader
 */
#define CONFIG_BOOT_FLASH_OFFSET 0x0

/**
 * bootloader reserved size on NOR flash
 *
 * When dual bootloader is supported, this is the total reserved NOR flash
 * size for bootloader.
 */
#define CONFIG_BOOT_FLASH_SIZE 0x10000

/**
 * NOR flash offset of application
 */
#define CONFIG_APP_FLASH_OFFSET 0x10000

/**
 * reserved NOR flash size for application
 */
#define CONFIG_APP_FLASH_SIZE 0x260000

/**
 * NOR flash physical address of application
 */
#define CONFIG_APP_FLASH_ADDRESS 0x60010000

/**
 * NOR flash offset of loadable app image
 */
#define CONFIG_APPIMG_FLASH_OFFSET 0x270000

/**
 * reserved NOR flash size for loadable app image
 */
#define CONFIG_APPIMG_FLASH_SIZE 0xD0000

/**
 * NOR flash offset of modem image file system
 *
 * The mount point of modem image file system is \p CONFIG_FS_MODEM_MOUNT_POINT.
 */
#define CONFIG_FS_MODEM_FLASH_OFFSET 0x4a0000

/**
 * reserved NOR flash size for modem image file system
 */
#define CONFIG_FS_MODEM_FLASH_SIZE 0x340000

/**
 * NOR flash physical address of modem image file system
 */
#define CONFIG_FS_MODEM_FLASH_ADDRESS 0x604a0000

/**
 * NOR flash offset of system file system
 *
 * The mount point of system file system is \p CONFIG_FS_SYS_MOUNT_POINT.
 */
#define CONFIG_FS_SYS_FLASH_OFFSET 0x340000

/**
 * reserved NOR flash size for system file system
 */
#define CONFIG_FS_SYS_FLASH_SIZE 0x160000

/**
 * NOR flash offset of factory file system
 *
 * The mount point of factory file system is \p CONFIG_FS_FACTORY_MOUNT_POINT.
 */
#define CONFIG_FS_FACTORY_FLASH_OFFSET 0x7e0000

/**
 * reserved NOR flash size for factory file system
 */
#define CONFIG_FS_FACTORY_FLASH_SIZE 0x20000

/**
 * NOR flash offset of calibration data
 *
 * It is only used for legacy platforms, calibration data are located on flash
 * as raw data, rather than stored in file system.
 */
/* #undef CONFIG_CALIB_FLASH_OFFSET */

/**
 * NOR flash offset of GSM calibration data
 *
 * It is only used for legacy platforms, calibration data are located on flash
 * as raw data, rather than stored in file system.
 */
/* #undef CONFIG_CALIB_GSM_FLASH_OFFSET */

/**
 * NOR flash offset of NB calibration data
 *
 * It is only used for legacy platforms, calibration data are located on flash
 * as raw data, rather than stored in file system.
 */
/* #undef CONFIG_CALIB_NB_FLASH_OFFSET */

/**
 * NOR flash offset of factory data
 *
 * It is only used for legacy platforms, factory data are located on flash
 * as raw data, rather than stored in file system.
 */
/* #undef CONFIG_FACTORY_FLASH_OFFSET */

/**
 * NOR flash address of bootloader
 *
 * When dual bootloader is supported, it is the same as
 * \p CONFIG_BOOT1_FLASH_ADDRESS.
 */
#define CONFIG_BOOT_FLASH_ADDRESS 0x60000000

/**
 * bootloader maximum size
 *
 * When dual bootloader is enabled, it is \p CONFIG_BOOT_FLASH_SIZE/2.
 * When dual bootloader isn't enabled, it is \p CONFIG_BOOT_FLASH_SIZE.
 *
 * The image header size is included.
 */
#define CONFIG_BOOTLOADER_SIZE 0x10000

/**
 * mount point of modem image file system
 */
#define CONFIG_FS_MODEM_MOUNT_POINT "/modem"

/**
 * mount point of system file system
 */
#define CONFIG_FS_SYS_MOUNT_POINT "/"

/**
 * mount point of factory file system
 */
#define CONFIG_FS_FACTORY_MOUNT_POINT "/factory"

/**
 * directory for modem running NV
 */
#define CONFIG_FS_MODEM_NVM_DIR "/modemnvm"

/**
 * directory for application NV
 */
#define CONFIG_FS_AP_NVM_DIR "/nvm"

/**
 * directory for firmware update
 *
 * Firmware update related files will be located under this directory,
 * including the differential pack file, and intermediate files.
 */
#define CONFIG_FS_FOTA_DATA_DIR "/fota"

/**
 * whether loading app image from NOR flash is enabled
 */
#define CONFIG_APPIMG_LOAD_FLASH

#/*+\new\zhuwangbin\2020.5.23\add poc app*/
/* #undef CONFIG_POC_SUPPORT */
#/*-\new\zhuwangbin\2020.5.23\add poc app*/
/**
 * whether loading app image from file is enabled
 *
 * When loading app image from file, the image will be loaded to RAM, and
 * execute on RAM.
 */
/* #undef CONFIG_APPIMG_LOAD_FILE */

/**
 * loadable app image file name
 */
/* #undef CONFIG_APPIMG_LOAD_FILE_NAME */

/**
 * PSRAM or DDR offset for application
 */
#define CONFIG_APP_RAM_OFFSET 0xC00000

/**
 * PSRAM or DDR total size for application
 *
 * When loadable app image is support, the reserved RAM are included inside.
 */
#define CONFIG_APP_TOTAL_RAM_SIZE 0x400000

/**
 * PSRAM or DDR size for application
 *
 * This is the total size, minus various reserved size, for example loadable
 * app image reserved size.
 */
#define CONFIG_APP_RAM_SIZE 0x300000

/**
 * PSRAM or DDR offset for app image from NOR flash
 *
 * When loading app image from NOR flash, the reserved size is only for
 * data andd bss sections of loadable app image.
 */
#define CONFIG_APP_FLASHIMG_RAM_OFFSET 0xf00000

/**
 * PSRAM or DDR size for app image from NOR flash
 */
#define CONFIG_APP_FLASHIMG_RAM_SIZE 0x100000

/**
 * PSRAM or DDR offset for app image from RAM
 *
 * When loading app image from RAM, the reserved size will be used for text,
 * data and bss sections.
 */
#define CONFIG_APP_FILEIMG_RAM_OFFSET 0x1000000

/**
 * PSRAM or DDR size for app image from RAM
 */
#define CONFIG_APP_FILEIMG_RAM_SIZE  0x0

/**
 * SRAM offset for application
 */
#define CONFIG_APP_SRAM_OFFSET 0x100

/**
 * SRAM size for application
 */
#define CONFIG_APP_SRAM_SIZE 0x1f00

/**
 * SRAM shared memory offset (8910)
 *
 * A part of SRAM is used for AP/CP shared memory. This is not included in
 * application SRAM.
 */
#define CONFIG_APP_SRAM_SHMEM_OFFSET 0x2000

/**
 * SRAM shared memory size (8910)
 */
#define CONFIG_APP_SRAM_SHMEM_SIZE 0x1000

/**
 * BBSRAM physical address (8955, 8909)
 */
/* #undef CONFIG_BBSRAM_PHY_ADDRESS */

/**
 * BBSRAM size (8955, 8909)
 */
/* #undef CONFIG_BBSRAM_SIZE */

/**
 * dual port SRAM physical address (8955, 8909)
 */
/* #undef CONFIG_DPRAM_PHY_ADDRESS */

/**
 * dual port SRAM size (8955, 8909)
 */
/* #undef CONFIG_DPRAM_SIZE */

/**
 * NBSRAM physical address (8909)
 */
/* #undef CONFIG_NBSRAM_PHY_ADDRESS */

/**
 * NBSRAM size (8909)
 */
/* #undef CONFIG_NBSRAM_SIZE */

/**
 * BBSRAM reserved size for patch (8955, 8909)
 */
/* #undef CONFIG_BBSRAM_RESERVED_PATCH_SIZE */

/**
 * dual port SRAM reserved size for mailbox (8955, 8909)
 */
/* #undef CONFIG_DPRAM_RESERVED_MBX_SIZE */

/**
 * NBSRAM reserved size for patch (8909)
 */
/* #undef CONFIG_NBSRAM_RESERVED_PATCH_SIZE */

/**
 * NBSRAM patch size (8909)
 */
/* #undef CONFIG_NBSRAM_PATCH_SIZE */

/**
 * NBSRAM stack size (8909)
 */
/* #undef CONFIG_NBSRAM_STACK_SIZE */

/**
 * NOR flash offset for BCPU (8955, 8909)
 */
/* #undef CONFIG_BCPU_FLASH_OFFSET */

/**
 * RAM offset for BCPU (8955, 8909)
 */
/* #undef CONFIG_BCPU_RAM_OFFSET */

/**
 * SRAM offset for BCPU (8955, 8909)
 */
/* #undef CONFIG_BCPU_SRAM_OFFSET */

/**
 * IRQ stack top from the end of application SRAM (8910)
 */
#define CONFIG_IRQ_STACK_TOP 0x0

/**
 * SVC stack top from the end of application SRAM (8910)
 */
#define CONFIG_SVC_STACK_TOP 0x200

/**
 * FIQ stack top from the end of application SRAM (8910)
 */
#define CONFIG_FIQ_STACK_TOP 0x800

/**
 * ABT stack top from the end of application SRAM (8910)
 */
#define CONFIG_ABT_STACK_TOP 0x800

/**
 * UND stack top from the end of application SRAM (8910)
 */
#define CONFIG_UND_STACK_TOP 0x800

/**
 * SYS stack top from the end of application SRAM (8910)
 */
#define CONFIG_SYS_STACK_TOP 0x800

/**
 * exception stack bottom from the end of application SRAM
 */
#define CONFIG_STACK_BOTTOM 0xc00

/**
 * stack size for blue screen mode (8955, 8909)
 */
/* #undef CONFIG_BLUE_SCREEN_STACK_SIZE */

/**
 * IRQ stack size (8955, 8909, 8811)
 */
/* #undef CONFIG_IRQ_STACK_SIZE */

/**
 * IRQ stack size for one level (8955, 8909)
 */
/* #undef CONFIG_IRQ_STACK_LEVEL_SIZE */

/**
 * IRQ maximum nested level count (8955, 8909)
 */
/* #undef CONFIG_IRQ_NEST_MAX_COUNT */

/**
 * mempll frequency (8910)
 */
#define CONFIG_DEFAULT_MEMPLL_FREQ 800000000

/**
 * cpupll frequency (8910)
 */
#define CONFIG_DEFAULT_CPUPLL_FREQ 1000000000

/**
 * cpu frequency (8910)
 */
#define CONFIG_DEFAULT_CPU_FREQ 500000000

/**
 * AXI bus frequency (8910)
 */
#define CONFIG_DEFAULT_SYSAXI_FREQ 400000000

/**
 * AHB bus frequency (8910)
 */
#define CONFIG_DEFAULT_SYSAHB_FREQ 200000000

/**
 * PSRAM or DDR frequency (8910)
 */
#define CONFIG_DEFAULT_MEMBUS_FREQ 200000000

/**
 * flash device clock frequency (8910)
 */
#define CONFIG_DEFAULT_SPIFLASH_DEV_FREQ 200000000

/**
 * flash controller clock frequency (8910)
 */
#define CONFIG_DEFAULT_SPIFLASH_CTRL_FREQ 200000000

/**
 * NOR flash interface frequency
 */
#define CONFIG_DEFAULT_SPIFLASH_INTF_FREQ 100000000

/**
 * syspll frequency (8955, fixed)
 */
/* #undef CONFIG_SYSPLL_FREQ */

/**
 * mcupll frequency (8909)
 */
/* #undef CONFIG_DEFAULT_MCUPLL_FREQ */

/**
 * default sys_clk frequency (8955, 8909)
 */
/* #undef CONFIG_DEFAULT_SYS_CLK_FREQ */

/**
 * default bb_clk frequency (8955, 8909)
 */
/* #undef CONFIG_DEFAULT_BB_CLK_FREQ */

/**
 * default rf_dig frequency (8909)
 */
/* #undef CONFIG_DEFAULT_RFDIG_CLK_FREQ */

/**
 * default mem_clk (2x PSRAM) frequency (8909)
 */
/* #undef CONFIG_DEFAULT_MEM_CLK_FREQ */

/**
 * mem_clk (2x PSRAM) high frequency (8955)
 *
 * There are only 2 settings of mem_clk will be used. High frequency is used
 * with PLL on, and low frequency is used with PLL off.
 */
/* #undef CONFIG_MEM_CLK_HIGH_FREQ */

/**
 * mem_clk (2x PSRAM) low frequency (8955)
 */
/* #undef CONFIG_MEM_CLK_LOW_FREQ */

/**
 * whetehr use dcdc vcore by default (8955, 8909)
 */
/* #undef CONFIG_DEFAULT_VCORE_DCDC_MODE */

/**
 * dcdc vcore setting at level high (8955, 8909)
 */
/* #undef CONFIG_VCORE_DCDC_HIGH */

/**
 * dcdc vcore setting at level medium (8955, 8909)
 */
/* #undef CONFIG_VCORE_DCDC_MEDIUM */

/**
 * dcdc vcore setting at level low (8955, 8909)
 */
/* #undef CONFIG_VCORE_DCDC_LOW */

/**
 * dcdc vcore setting at level low power mode (8955, 8909)
 */
/* #undef CONFIG_VCORE_DCDC_LP */

/**
 * ldo vcore setting at level high (8955, 8909)
 */
/* #undef CONFIG_VCORE_LDO_HIGH */

/**
 * ldo vcore setting at level medium (8955, 8909)
 */
/* #undef CONFIG_VCORE_LDO_MEDIUM */

/**
 * ldo vcore setting at level low (8955, 8909)
 */
/* #undef CONFIG_VCORE_LDO_LOW */

/**
 * ldo vcore setting at low power mode (8955, 8909)
 */
/* #undef CONFIG_VCORE_LDO_LP */

/**
 * force pull up for tst_h in iomux (8910)
 */
#define CONFIG_TST_H_GROUND

/**
 * keyled power is used for RF switch (8910)
 */
#define CONFIG_BOARD_KPLED_USED_FOR_RF_SWITCH

/**
 * force pull up for gpio4 in iomux (8910)
 */
/* #undef CONFIG_GPIO4_FORCE_PULL_UP */

/**
 * gpio number for pmic interrupt (8910)
 */
#define CONFIG_PMIC_INTR_GPIO 6

/**
 * gpio number used in 32K sleep mode (8910)
 */
#define CONFIG_SLEEP32K_GPIO 7

/**
 * enable camera power at initialization (8910)
 */
/* #undef CONFIG_CAMA_POWER_ON_INIT */

/**
 * whether camera clock is needed for audio (8910)
 */
/* #undef CONFIG_CAMA_CLK_FOR_AUDIO */

/**
 * enable gsm/nbiot dual mode in 8909
 */
/* #undef CONFIG_8909_DUALMODE */

/**
 * use 26MHz DCXO, rather than VCXO (8909)
 */
/* #undef CONFIG_CRYSTAL_WITHOUT_OSCILLATOR */

/**
 * RF use LDO (8909)
 */
/* #undef CONFIG_RF_LDO_MODE */

/**
 * hardware supported SIM count
 *
 * This is not the supported SIM count of protocol stack and application.
 */
/* #undef CONFIG_HAL_SIM_COUNT */

/**
 * whether GSM is supported
 */
#define CONFIG_GSM_SUPPORT

/**
 * whether NBIOT is supported
 */
#define CONFIG_LTE_NBIOT_SUPPORT

/**
 * whether to enter RF calibration mode by gpio
 */
/* #undef CONFIG_BOARD_ENTER_CALIB_BY_GPIO */

/**
 * the gpio for detect entering RF calibration mode
 */
/* #undef CONFIG_BOARD_ENTER_CALIB_GPIO */

/**
 * whether to support SIM1 hot plug
 */
/* #undef CONFIG_BOARD_SUPPORT_SIM1_DETECT */

/**
 * gpio for SIM1 hot plug detect
 */
/* #undef CONFIG_BOARD_SIM1_DETECT_GPIO */

/**
 * whether to support SIM2 hot plug
 */
/* #undef CONFIG_BOARD_SUPPORT_SIM2_DETECT */

/**
 * gpio for SIM2 hot plug detect
 */
/* #undef CONFIG_BOARD_SIM2_DETECT_GPIO */

/**
 * whether power key can wakeup psm mode
 */
/* #undef CONFIG_PWRKEY_WAKEUP_PSM */




/**
 * whether power key can power up after shutdown
 */
#define CONFIG_PWRKEY_POWERUP

/**
 * whether wakeup pin (psm_ext_int) can power up after shutdown
 */
#define CONFIG_WAKEUP_PIN_POWERUP

/**
 * whether charger can power up after shutdown
 */
/* #undef CONFIG_CHARGER_POWERUP */
/**
 * support normal shutdown power off mode in pmic 2720 platform
 */
/* #undef CONFIG_SHUTDOWN_NORMAL_POWER_OFF */

#/*+\new\zhuwangbin\2020.5.23\add poc app*/
#define CONFIG_POC_VAT_SUPPORT
#define CONFIG_POC_TONE_SUPPORT
#/*-\new\zhuwangbin\2020.5.23\add poc app*/
#endif
