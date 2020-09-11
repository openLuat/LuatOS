# Copyright (C) 2018 RDA Technologies Limited and/or its affiliates("RDA").
# All rights reserved.
#
# This software is supplied "AS IS" without any warranties.
# RDA assumes no responsibility or liability for the use of the software,
# conveys no license or title under any patent, copyright, or mask work
# right to the product. RDA reserves the right to make changes in the
# software without notification.  RDA also make no representation or
# warranty that such application will be suitable for the specified use
# without further testing or modification.

# Auto generated. Don't edit it manually!

set(CROSS_COMPILE arm-none-eabi-)
set(CMAKE_SYSTEM_PROCESSOR ARM)
set(ARCH arm)

set(CONFIG_SOC 8910)
set(CONFIG_SOC_8910 on)

set(CONFIG_CPU_ARM on)
set(CONFIG_CPU_ARMV7A on)
set(CONFIG_CPU_ARM_CA5 on)

set(CONFIG_NOR_PHY_ADDRESS 0x60000000)
set(CONFIG_RAM_PHY_ADDRESS 0x80000000)

set(CONFIG_APPIMG_LOAD_FLASH on)
set(CONFIG_APPIMG_LOAD_FILE off)
set(CONFIG_APPIMG_LOAD_FILE_NAME )

set(CONFIG_APPIMG_FLASH_ADDRESS 0x60270000)
set(CONFIG_APPIMG_FLASH_OFFSET 0x270000)
set(CONFIG_APPIMG_FLASH_SIZE 0xD0000)
set(CONFIG_APP_FLASHIMG_RAM_OFFSET 0xf00000)
set(CONFIG_APP_FLASHIMG_RAM_SIZE 0x100000)
set(CONFIG_APP_FILEIMG_RAM_OFFSET 0x1000000)
set(CONFIG_APP_FILEIMG_RAM_SIZE  0x0)

set(CONFIG_FDL1_IMAGE_START 0x810000)
set(CONFIG_FDL1_IMAGE_SIZE 0x8000)
set(CONFIG_FDL2_IMAGE_START 0x818000)
set(CONFIG_FDL2_IMAGE_SIZE 0x10000)
