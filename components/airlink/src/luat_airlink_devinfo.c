#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_airlink_devinfo.h"
#include "luat_mcu.h"
#include "luat_netdrv.h"
#include "luat_netdrv_event.h"
#include "luat_network_adapter.h"
#include "lwip/netif.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

// 对端设备的信息, TODO 支持多个对端设备
luat_airlink_dev_info_t g_airlink_ext_dev_info;
// 自身设备的信息 — 不得直接访问, 须通过下方 API 操作
static luat_airlink_dev_info_t g_airlink_self_dev_info;
// 最后一次修改时间 (ms)
static uint64_t g_airlink_self_dev_info_mtime = 0;

// 从机链路超时阈值 (ms)
#define AIRLINK_LINK_TIMEOUT_MS 5000

extern uint64_t g_airlink_last_cmd_timestamp;

luat_airlink_dev_info_t* luat_airlink_self_dev_info_ptr(void) {
    return &g_airlink_self_dev_info;
}

void luat_airlink_self_dev_info_notify(void) {
    g_airlink_self_dev_info_mtime = luat_mcu_tick64_ms();
    AIRLINK_DEV_INFO_UPDATE_CB cb = luat_airlink_mode_dev_info_update_cb_get();
    if (cb) {
        cb();
    }
}

uint64_t luat_airlink_self_dev_info_get_mtime(void) {
    return g_airlink_self_dev_info_mtime;
}

// 由传输层周期性调用，检测从机是否超时断开
void luat_airlink_check_link_timeout(void) {
    if (g_airlink_last_cmd_timestamp == 0)
        return;
    if (luat_mcu_tick64_ms() - g_airlink_last_cmd_timestamp < AIRLINK_LINK_TIMEOUT_MS)
        return;

    uint8_t tp = g_airlink_ext_dev_info.tp;
    luat_netdrv_t* drv = NULL;

    if (tp == 0x01) {
        drv = luat_netdrv_get(NW_ADAPTER_INDEX_LWIP_WIFI_STA);
        luat_netdrv_t* ap = luat_netdrv_get(NW_ADAPTER_INDEX_LWIP_WIFI_AP);
        if (ap && ap->netif && netif_is_link_up(ap->netif)) {
            luat_netdrv_set_link_updown(ap, 0);
        }
    } else if (tp == 0x02) {
        drv = luat_netdrv_get(NW_ADAPTER_INDEX_LWIP_GP_GW);
    } else {
        return;
    }

    if (drv && drv->netif && netif_is_link_up(drv->netif)) {
        LLOGI("airlink link timeout %llums, tp=%d, set link down",
              luat_mcu_tick64_ms() - g_airlink_last_cmd_timestamp, tp);
        luat_netdrv_set_link_updown(drv, 0);
    }
}

