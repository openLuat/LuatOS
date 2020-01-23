/*
 * Copyright (c) 2006-2018, RT-Thread Development Team
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Change Logs:
 * Date           Author          Notes
 * 2019-07-15     WillianChan     the first version.
 *
 */

#ifndef __DS18B20_H__
#define __DS18B20_H__

#include <rthw.h>
#include <rtthread.h>
#include <rtdevice.h>

#define CONNECT_SUCCESS  0
#define CONNECT_FAILED   1

uint8_t ds18b20_init(rt_base_t pin);
int32_t ds18b20_get_temperature(rt_base_t pin);

#ifdef PKG_USING_SENSORS_DRIVERS
#include "sensor.h"

struct ds18b20_device
{
    rt_base_t pin;
    rt_mutex_t lock;
};
typedef struct ds18b20_device *ds18b20_device_t;

int rt_hw_ds18b20_init(const char *name, struct rt_sensor_config *cfg);

#endif

#endif /* __DS18B20_H_ */

