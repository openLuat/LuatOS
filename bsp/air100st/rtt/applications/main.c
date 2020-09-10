/*
 * Copyright (c) 2006-2018, RT-Thread Development Team
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author       Notes
 * 2018-11-06     SummerGift   first version
 * 2018-11-19     flybreak     add stm32f407-atk-explorer bsp
 */

#include <rtthread.h>
#include <rtdevice.h>
#include "luat_base.h"
#include "luat_log.h"
#include "spi_flash_sfud.h"
#include "drv_spi.h"

/* 添加 DEBUG 头文件 */
#define DBG_SECTION_NAME               "main"
#define DBG_LEVEL                      DBG_INFO
#include <rtdbg.h>
#define FS_PARTITION_NAME              "fs"

#include "fal.h"
#include <dfs_fs.h>

static void _main(void* param) {
    rt_thread_mdelay(100); // 故意延后100ms
    luat_log_set_uart_port(1);
    luat_main(NULL, NULL, NULL);
    while (1)
        rt_thread_delay(10000000);
}

int main(void)
{
    fal_init();

    struct rt_device *mtd_dev = RT_NULL;
    mtd_dev = fal_mtd_nor_device_create("app");
    if (!mtd_dev)
    {
        LOG_E("Can't create a mtd device on '%s' partition.", "app");
    }
    else
    {
        /* 挂载 littlefs */
        if (dfs_mount("app", "/", "lfs", 0, 0) == 0)
        {
            LOG_I("Filesystem initialized!");
        }
        else
        {
            LOG_I("fs reinitialize");
            /* 格式化文件系统 */
            dfs_mkfs("lfs", "app");
            /* 挂载 littlefs */
            if (dfs_mount("app", "/", "lfs", 0, 0) == 0)
            {
                LOG_I("Filesystem initialized!");
            }
            else
            {
                LOG_E("Failed to initialize filesystem!");
            }
        }
    }



    // /* 生成 mtd 设备 */
    // struct rt_device *mtd_dev = RT_NULL;
    // mtd_dev = fal_mtd_nor_device_create("flash");
    // if (!mtd_dev)
    // {
    //     LOG_E("Can't create a mtd device on '%s' partition.", "flash");
    // }
    // else
    // {
    //     /* 挂载 littlefs */
    //     if (dfs_mount("flash", "/flash", "lfs", 0, 0) == 0)
    //     {
    //         LOG_I("Filesystem initialized!");
    //     }
    //     else
    //     {
    //         LOG_I("fs reinitialize");
    //         /* 格式化文件系统 */
    //         dfs_mkfs("lfs", "flash");
    //         /* 挂载 littlefs */
    //         if (dfs_mount("flash", "/flash", "lfs", 0, 0) == 0)
    //         {
    //             LOG_I("Filesystem initialized!");
    //         }
    //         else
    //         {
    //             LOG_E("Failed to initialize filesystem!");
    //         }
    //     }
    // }

    // struct rt_device *mtd_dev_download = RT_NULL;
    // mtd_dev_download = fal_mtd_nor_device_create("download");
    // if (!mtd_dev_download)
    // {
    //     LOG_E("Can't create a mtd device on '%s' partition.", "download");
    // }
    // else
    // {
    //     /* 挂载 littlefs */
    //     if (dfs_mount("download", "/download", "lfs", 0, 0) == 0)
    //     {
    //         LOG_I("Filesystem initialized!");
    //     }
    //     else
    //     {
    //         LOG_I("download reinitialize");
    //         /* 格式化文件系统 */
    //         dfs_mkfs("lfs", "download");
    //         /* 挂载 littlefs */
    //         if (dfs_mount("download", "/download", "lfs", 0, 0) == 0)
    //         {
    //             LOG_I("Filesystem initialized!");
    //         }
    //         else
    //         {
    //             LOG_E("Failed to initialize filesystem!");
    //         }
    //     }
    // }

    rt_thread_t t = rt_thread_create("luat", _main, RT_NULL, 8*1024, 15, 20);
    rt_thread_startup(t);
    //luat_main(NULL, NULL, NULL);
    //while (1) {
    //    rt_thread_mdelay(2000000);
    //}
    return 0;
}
