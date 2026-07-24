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
#include "luat_netdrv_napt.h"
#include "luat_netdrv_pkg.h"
#include "luat_netdrv_lwip_etharp.h"
#include "luat_network_adapter.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

extern airlink_statistic_t g_airlink_statistic;

__AIRLINK_CODE_IN_RAM__ int luat_airlink_cmd_exec_ip_pkg(luat_airlink_cmd_t* cmd, void* userdata) {
    uint8_t adapter_id = cmd->data[0];
    // 防御: cmd->len == 0 时 cmd->len - 1 在 uint16_t 下会绕回 0xFFFF
    // 进而把 64KB 当作包长度丢进 napt_pkg_input, 触发缓冲区越界.
    // cmd->len < 2 时 payload 长度不足 1 字节, 也不可处理.
    if (cmd->len < 2) {
        g_airlink_statistic.rx_ip.drop += 1;
        return 0;
    }
    g_airlink_statistic.rx_ip.total += 1;
    g_airlink_statistic.rx_bytes.total += cmd->len - 1;
    // 打印 EtherType 用于调试入向帧类型
    if (cmd->len >= 1 + 14) {
        uint16_t eth_type = (uint16_t)cmd->data[1+12] << 8 | cmd->data[1+13];
        LLOGI("IP pkg RX adapter=%d len=%d ethertype=0x%04X", adapter_id, cmd->len - 1, eth_type);
    } else {
        LLOGI("IP pkg RX adapter=%d len=%d (short frame)", adapter_id, cmd->len - 1);
    }
    // luat_airlink_print_mac_pkg(cmd->data + 1, cmd->len - 1);
    // 集中入口: pkg_input 内含 EVT_PKG 截获检查, 再走 NAPT
    // 返回值语义与 napt_pkg_input 兼容 (0=未消费需继续, 非0=已消费)
    int ret = 0;
    luat_netdrv_t* drv = NULL;

#ifdef LUAT_USE_AIRLINK_HSPI_MASTER
    // HSPI 桥接：ARP 网关提取 + MAC 注入，1601 lwIP DHCP 已设网关，此块为冗余保护
    do {
        uint8_t *eth = cmd->data + 1;
        if (cmd->len < 1 + 42) break;
        if (eth[12] != 0x08 || eth[13] != 0x06) break;
        if (eth[21] != 0x02) break;
        drv = luat_netdrv_get(adapter_id);
        if (!drv || !drv->netif) break;
        uint32_t gw = (uint32_t)eth[28] | (eth[29]<<8) | (eth[30]<<16) | ((uint32_t)eth[31]<<24);
        if (gw == 0) break;
        drv->netif->gw.u_addr.ip4.addr = gw;
        {   /* 注入网关 MAC，避免 TCP SYN 排队问题 */
            ip4_addr_t gw_ip;
            gw_ip.addr = gw;
            struct eth_addr gw_mac;
            memcpy(gw_mac.addr, eth + 22, 6);
            err_t arp_ret = luat_netdrv_etharp_add_static_entry_on_netif(drv->netif, &gw_ip, &gw_mac);
            if (arp_ret != ERR_OK) {
                LLOGW("ARP entry add failed: ret=%d", arp_ret);
            }
        }
        luat_netdrv_send_ip_event(drv, 1);
    } while (0);
#endif


    ret = luat_netdrv_pkg_input(adapter_id, LUAT_NETDRV_CH_HW,
                                cmd->data + 1, (uint16_t)(cmd->len - 1));
    if (ret != 0) {
        // 仅当 NAPT 真正消费时 (+= 1) 才计入 rx_napt_ip, 避免 -1 错误
        // 与 0 长度空包被错误地算成 NAPT 成功
        if (ret > 0) {
            g_airlink_statistic.rx_napt_ip.total += 1;
            g_airlink_statistic.rx_napt_bytes.total += cmd->len - 1;
        }
        // LLOGD("NAPT/Lua 已处理, 不需要转发给具体的netdrv了");
        return 0;
    }
    drv = luat_netdrv_get(adapter_id);
    if (drv == NULL || drv->netif == NULL) {
        g_airlink_statistic.rx_ip.drop += 1;
        g_airlink_statistic.rx_bytes.drop += cmd->len - 1;
        LLOGD("没有找到适配器 %d, 无法处理其IP包", adapter_id);
        return 0;
    }
    g_airlink_statistic.rx_ip.ok += 1;
    g_airlink_statistic.rx_bytes.ok += cmd->len - 1;

    // 这里开始就复杂了
    // 首先, 如果是平台的包, 那就直接交给平台处理
    //      例如wifi的包, 在wifi平台, 那就应该输出到硬件去
    // 否则, 那就应该转给lwip处理
    #ifdef __BK72XX__
    if (drv->id == NW_ADAPTER_INDEX_LWIP_WIFI_STA || drv->id == NW_ADAPTER_INDEX_LWIP_WIFI_AP) {
        // 这里是wifi的包, 直接输出到硬件去
        // LLOGD("收到wifi的IP包, 直接输出到硬件去 %p %d", cmd->data + 1, cmd->len - 1);
        drv->dataout(drv, drv->userdata, cmd->data + 1, cmd->len - 1);
        return 0;
    }
    #endif

    // luat_airlink_hexdump("收到IP包且要注入LWIP", cmd->data + 1, cmd->len - 1);
    luat_netdrv_netif_input_proxy(drv->netif, cmd->data + 1, cmd->len - 1);

    return 0;
}
