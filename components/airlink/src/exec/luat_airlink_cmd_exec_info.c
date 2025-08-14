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
#include "lwip/ip_addr.h"
#include "luat_netdrv_whale.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

extern luat_airlink_dev_info_t g_airlink_ext_dev_info;

__AIRLINK_CODE_IN_RAM__ int luat_airlink_cmd_exec_dev_info(luat_airlink_cmd_t* cmd, void* userdata) {
    luat_airlink_dev_info_t* dev = cmd->data;
    luat_netdrv_t* drv = NULL;
    char buff[32] = {0};
    uint32_t version = 0;
    // LLOGD("收到设备信息通知 类型 %d", dev->tp);
    if (dev->tp == 0) {
        return 0;
    }
    size_t len = sizeof(luat_airlink_dev_info_t);
    if (len > cmd->len) {
        len = cmd->len; // 为了兼容老版本的wifi固件, 需要把数据截断, 如果超过的话
    }
    else {
        // wifi固件比4G固件更新的, 那就抛弃掉后面的数据
    }
    memcpy(&g_airlink_ext_dev_info, dev, len);
    #ifdef LUAT_USE_DRV_WLAN
    if (dev->tp == 1) {
        // WIFI设备
        // 首先, 把MAC地址打印出来
        // LLOGD("wifi sta MAC %02X:%02X:%02X:%02X:%02X:%02X", dev->wifi.sta_mac[0], dev->wifi.sta_mac[1], dev->wifi.sta_mac[2], dev->wifi.sta_mac[3], dev->wifi.sta_mac[4], dev->wifi.sta_mac[5]);
        if (dev->wifi.sta_mac[0]) {
            memcpy(&version, dev->wifi.version, 4);
            // 是合法的MAC地址, 那就搞一下
            drv = luat_netdrv_get(NW_ADAPTER_INDEX_LWIP_WIFI_STA);
            while (1) {
                if (drv == NULL) {
                    // LLOGD("没有找到lwip wifi sta驱动, 无法设置MAC地址");
                    break;
                }
                if (drv->netif == NULL) {
                    // LLOGD("没有找到lwip wifi sta接口, 无法设置MAC地址");
                    break;
                }
                memcpy(drv->netif->hwaddr, dev->wifi.sta_mac, 6);
                drv->netif->hwaddr_len = 6;

                // STA网络状态对吗?
                if (dev->wifi.sta_state == 0) {
                    if (netif_is_up(drv->netif)) {
                        // 网卡掉线了哦
                        LLOGD("wifi sta掉线了");
                        luat_netdrv_whale_ipevent(drv, 0);
                    }
                }
                else {
                    if (netif_is_up(drv->netif) == 0) {
                        // 网卡上线了哦
                        LLOGD("wifi sta上线了");
                        luat_netdrv_whale_ipevent(drv, 1);
                    }
                }
                break;
            }
            drv = luat_netdrv_get(NW_ADAPTER_INDEX_LWIP_WIFI_AP);
            while (1) {
                if (drv == NULL) {
                    // LLOGD("没有找到lwip wifi ap驱动, 无法设置MAC地址");
                    break;
                }
                if (drv->netif == NULL) {
                    // LLOGD("没有找到lwip wifi ap接口, 无法设置MAC地址");
                    break;
                }
                drv->netif->hwaddr_len = 6;
                memcpy(drv->netif->hwaddr, dev->wifi.ap_mac, 6);

                // 如果wifi固件版本是0, 那需要兼容一下AP状态
                if (version == 0) {
                    dev->wifi.ap_state = 1;
                }
                // AP网络状态对吗?
                if (dev->wifi.ap_state == 0) {
                    if (netif_is_up(drv->netif)) {
                        // 网卡掉线了哦
                        LLOGD("wifi ap已关闭");
                        luat_netdrv_whale_ipevent(drv, 0);
                    }
                }
                else {
                    if (netif_is_up(drv->netif) == 0) {
                        // 网卡上线了哦
                        ipaddr_ntoa_r(&drv->netif->ip_addr, buff, 32);
                        LLOGD("wifi ap已开启 %s", buff);
                        luat_netdrv_whale_ipevent(drv, 1);
                    }
                }
                break;
            }
        }
    }
    #endif
    #ifdef LUAT_USE_DRV_MOBILE
    if (dev->tp == 2) { // 4G设备
        // 根据网络状态, 发出IP_READY/IP_LOSE事件
        drv = luat_netdrv_get(NW_ADAPTER_INDEX_LWIP_GP_GW);
        if (drv == NULL || drv->netif == NULL) {
            // GP代理网卡没有找到, 可能是没有初始化
            return 0;
        }
        // 1是已注册, 5是漫游且已注册
        if (dev->cat1.cat_state != 1 && dev->cat1.cat_state != 5) {
            // 掉线了
            if (netif_is_up(drv->netif)) {
                // 网卡掉线了哦
                LLOGD("4G网卡掉线了");
                luat_netdrv_whale_ipevent(drv, 0);
                g_airlink_self_dev_info.cat1.netif_enable = 0; // 关闭状态
            }
        }
        else {
            // 上线了
            if (netif_is_up(drv->netif) == 0) {
                // 网卡上线了哦
                LLOGD("4G网卡上线了");
                luat_netdrv_whale_ipevent(drv, 1);
                g_airlink_self_dev_info.cat1.netif_enable = 1;  // 开启状态
            }
        }
    }
    #endif
    return 0;
}