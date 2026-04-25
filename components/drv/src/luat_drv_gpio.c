#include "luat_base.h"
#if defined(LUAT_USE_DRV_GPIO)
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat/drv_gpio.h"
#include "luat_airlink.h"
#include "luat_airlink_drv_gpio.h"
#include "luat_airlink_drv_rpc_gpio.h"

#define LUAT_LOG_TAG "drv.gpio"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

int luat_drv_gpio_open(luat_gpio_cfg_t* gpio) {
    if (gpio == NULL) {
        return -1;
    }
    if (gpio->pin < 0 || gpio->pin >= 255) {
        return -2;
    }
    if (gpio->pin < 128) {
        return luat_gpio_open(gpio);
    }
    else {
        #if defined(LUAT_USE_AIRLINK_RPC)
        if (luat_airlink_peer_rpc_supported() && luat_airlink_current_mode_get() >= 0)
            return luat_airlink_drv_rpc_gpio_open(gpio);
        #endif
        return luat_airlink_drv_gpio_open(gpio);
    }
}

int luat_drv_gpio_set(int pin, int level) {
    if (pin < 0 || pin >= 255) {
        return -1;
    }
    if (pin < 128) {
        return luat_gpio_set(pin, level);
    }
    else {
        #if defined(LUAT_USE_AIRLINK_RPC)
        if (luat_airlink_peer_rpc_supported() && luat_airlink_current_mode_get() >= 0)
            return luat_airlink_drv_rpc_gpio_set(pin, level);
        #endif
        return luat_airlink_drv_gpio_set(pin, level);
    }
}

int luat_drv_gpio_setup(luat_gpio_t* gpio) {
    LLOGD("执行luat_drv_gpio_setup pin %d mode %d", gpio->pin, gpio->mode);
    if (gpio == NULL) {
        LLOGE("gpio is NULL");
        return -1;
    }
    if (gpio->pin < 0 || gpio->pin >= 255) {
        return -2;
    }
    if (gpio->pin < 128) {
        return luat_gpio_setup(gpio);
    }
    else {
        #if defined(LUAT_USE_AIRLINK_RPC)
        if (luat_airlink_peer_rpc_supported() && luat_airlink_current_mode_get() >= 0)
            return luat_airlink_drv_rpc_gpio_setup(gpio);
        #endif
        return luat_airlink_drv_gpio_setup(gpio);
    }
}


int luat_drv_gpio_get(int pin, int* val) {
    if (pin < 0 || pin >= 255) {
        return -2;
    }
    if (pin < 128) {
        *val = luat_gpio_get(pin);
        return 0;
    }
    else {
        #if defined(LUAT_USE_AIRLINK_RPC)
        if (luat_airlink_peer_rpc_supported() && luat_airlink_current_mode_get() >= 0)
            return luat_airlink_drv_rpc_gpio_get(pin, val);
        #endif
        return luat_airlink_drv_gpio_get(pin, val);
    }
}

int luat_drv_gpio_driver_yhm27xx(uint32_t Pin, uint8_t ChipID, uint8_t RegAddress, uint8_t IsRead, uint8_t *Data) 
{
    if (Pin >= 128) {
        return luat_airlink_drv_gpio_driver_yhm27xx(Pin, ChipID, RegAddress, IsRead, Data);
    }
    else {
        return luat_gpio_driver_yhm27xx(Pin, ChipID, RegAddress, IsRead, Data);
    }
}

int luat_drv_gpio_driver_yhm27xx_reqinfo(uint8_t Pin, uint8_t ChipID) {
    return luat_airlink_drv_gpio_driver_yhm27xx_reqinfo(Pin, ChipID);
}

#endif /* LUAT_USE_DRV_GPIO */
