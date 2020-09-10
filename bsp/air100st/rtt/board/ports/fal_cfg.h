/*
 * Copyright (c) 2006-2018, RT-Thread Development Team
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2018-12-5      SummerGift   first version
 */

#ifndef _FAL_CFG_H_
#define _FAL_CFG_H_

#include <rtthread.h>
#include <board.h>

//extern const struct fal_flash_dev stm32f4_onchip_flash;

/* ===================== Flash device Configuration ========================= */
extern struct fal_flash_dev nor_flash0;
extern struct fal_flash_dev stm32f4_onchip_flash;

/* flash device table */
#define FAL_FLASH_DEV_TABLE                                          \
{                                                                    \
    &stm32f4_onchip_flash,                                           \
    &nor_flash0,                                                     \
}

/* ====================== Partition Configuration ========================== */
#ifdef FAL_PART_HAS_TABLE_CFG

/* partition table */
#define FAL_PART_TABLE                                                      \
{                                                                           \
    {FAL_PART_MAGIC_WROD, "app", "stm32_onchip",  0 , 1024*1024 , 0},         \
    {FAL_PART_MAGIC_WORD, "flash", "W25Q16JV",  0, 1024*1024, 0},           \
    {FAL_PART_MAGIC_WORD, "download", "W25Q16JV", 1024*1024, 1024*1024, 0}, \
}

#endif /* FAL_PART_HAS_TABLE_CFG */
#endif /* _FAL_CFG_H_ */
