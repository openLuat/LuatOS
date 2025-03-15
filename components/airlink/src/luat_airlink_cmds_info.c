#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_fota.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "luat_netdrv_whale.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

luat_airlink_dev_info_t airlink_ext_dev_info;

int luat_airlink_cmd_exec_dev_info(luat_airlink_cmd_t* cmd, void* userdata) {
    luat_airlink_dev_info_t* dev = cmd->data;
    luat_netdrv_t* drv = NULL;
    // LLOGD("收到设备信息通知 类型 %d", dev->tp);
    if (dev->tp == 0) {
        return 0;
    }
    memcpy(&airlink_ext_dev_info, dev, sizeof(luat_airlink_dev_info_t));
    if (dev->tp == 1) {
        // WIFI设备
        // 首先, 把MAC地址打印出来
        // LLOGD("wifi sta MAC %02X:%02X:%02X:%02X:%02X:%02X", dev->wifi.sta_mac[0], dev->wifi.sta_mac[1], dev->wifi.sta_mac[2], dev->wifi.sta_mac[3], dev->wifi.sta_mac[4], dev->wifi.sta_mac[5]);
        if (dev->wifi.sta_mac[0]) {
            // 是合法的MAC地址, 那就搞一下
            drv = luat_netdrv_get(NW_ADAPTER_INDEX_LWIP_WIFI_STA);
            while (1) {
                if (drv == NULL) {
                    LLOGD("没有找到lwip wifi sta驱动, 无法设置MAC地址");
                    break;
                }
                if (drv->netif == NULL) {
                    LLOGD("没有找到lwip wifi sta接口, 无法设置MAC地址");
                    break;
                }
                memcpy(drv->netif->hwaddr, dev->wifi.sta_mac, 6);
                drv->netif->hwaddr_len = 6;

                // 网络状态对吗?
                if (dev->wifi.sta_state == 0) {
                    if (netif_is_up(drv->netif)) {
                        // 网卡掉线了哦
                        LLOGD("wifi sta掉线了, 重新连接");
                        netif_set_down(drv->netif);
                        luat_netdrv_whale_ipevent(drv->id);
                    }
                }
                else {
                    if (netif_is_up(drv->netif) == 0) {
                        // 网卡上线了哦
                        LLOGD("wifi sta上线了");
                        netif_set_up(drv->netif);
                        luat_netdrv_whale_ipevent(drv->id);
                    }
                }
                break;
            }
        }
    }
    return 0;
}