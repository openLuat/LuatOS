#ifndef LUAT_AIRLINK_DRV_RPC_GPIO_H
#define LUAT_AIRLINK_DRV_RPC_GPIO_H

#include "luat_base.h"

#if defined(LUAT_USE_AIRLINK_RPC) && defined(LUAT_USE_DRV_GPIO)
#include "luat_airlink.h"
#include "luat_gpio.h"

int luat_airlink_drv_rpc_gpio_setup(luat_gpio_t* gpio);
int luat_airlink_drv_rpc_gpio_open(luat_gpio_cfg_t* gpio);
int luat_airlink_drv_rpc_gpio_set(int pin, int level);
int luat_airlink_drv_rpc_gpio_get(int pin, int* val);

#endif /* LUAT_USE_AIRLINK_RPC && LUAT_USE_DRV_GPIO */

#endif /* LUAT_AIRLINK_DRV_RPC_GPIO_H */
