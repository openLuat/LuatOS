/**
 * PC模拟器 USB ETH stub
 * 提供 luat_netdrv_usb_eth.c 所需的 USB HAL 空实现,
 * 使 netdrv 模块在 PC 端可编译链接。
 */
#include "luat_usb.h"
#include <stddef.h>

void *luat_usb_bind_eth(int id, luat_usb_event_callback_fun_t callback, void *user_param) {
    (void)id;
    (void)callback;
    (void)user_param;
    return NULL;
}

int luat_usb_eth_start_tx(int id, const uint32_t *data, uint32_t len) {
    (void)id;
    (void)data;
    (void)len;
    return -1;
}

int luat_usb_eth_continue_tx(int id, const uint32_t *data, uint32_t len) {
    (void)id;
    (void)data;
    (void)len;
    return -1;
}
