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

static void _main(void* param) {
    rt_thread_mdelay(100); // 故意延后100ms
    luat_log_set_uart_port(1);
    luat_main(NULL, NULL, NULL);
    while (1)
        rt_thread_delay(10000000);
}

int main(void)
{
    rt_thread_t t = rt_thread_create("luat", _main, RT_NULL, 8*1024, 15, 20);
    rt_thread_startup(t);
    //luat_main(NULL, NULL, NULL);
    //while (1) {
    //    rt_thread_mdelay(2000000);
    //}
    return 0;
}
