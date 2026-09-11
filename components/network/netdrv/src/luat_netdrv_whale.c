/*
提供共用的函数, 方便适配各种netdrv设备
*/

#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_msgbus.h"
#include "lwip/netif.h"
#include "lwip/ip.h"
#include "lwip/pbuf.h"
#include "lwip/tcpip.h"
#include "net_lwip2.h"
#include "luat_airlink.h"
#include "luat_mem.h"
#include "luat_netdrv_whale.h"
#include "luat_netdrv_event.h"
#include "luat_netdrv_pkg.h"

#define LUAT_LOG_TAG "netdrv.whale"
#include "luat_log.h"

extern err_t luat_netdrv_netif_input_main(struct pbuf *p, struct netif *inp);
extern err_t luat_netdrv_etharp_output(struct netif *netif, struct pbuf *q, const ip4_addr_t *ipaddr);

static err_t luat_netif_init(struct netif *netif);
static err_t netif_output(struct netif *netif, struct pbuf *p);

void luat_netdrv_whale_dataout(luat_netdrv_t* drv, void* userdata, uint8_t* buff, uint16_t len) {
    // TODO 发送到spi slave task
    // LLOGD("上行给主机的IP数据 %d %p %d", drv->id, buff, len);
    if (len < 0) {
        return;
    }
    // TODO 这里应该根据userdata, 也就是whale上下文, 转发可配置的出口
    luat_airlink_queue_send_ippkg(drv->id, buff, len);
}

static err_t netif_output(struct netif *netif, struct pbuf *p) {
    // TODO 发送到spi slave task
    // LLOGD("上行给主机的IP数据2 %p %d", p, p->tot_len);
    // LLOGD("上行给主机的IP数据 前24个字节 " MACFMT "" MACFMT "" MACFMT "" MACFMT,
    //         MAC_ARG(p->payload),
    //         MAC_ARG(p->payload + 6),
    //         MAC_ARG(p->payload + 12),
    //         MAC_ARG(p->payload + 18));
    luat_netdrv_t* netdrv = (luat_netdrv_t*)(netif->state);
    void* buff = luat_heap_opt_zalloc(LUAT_HEAP_PSRAM, p->tot_len);
    if (buff == NULL) {
        LLOGE("netif_output: PSRAM alloc fail for %d bytes! netif=%d", p->tot_len, netdrv ? netdrv->id : -1);
        return ERR_MEM;
    }
    // LLOGD("netif_output: %d bytes to adapter %d", p->tot_len, netdrv ? netdrv->id : -1);
    pbuf_copy_partial(p, buff, p->tot_len, 0);
    // LWIP 层拦截: 用户已声明拦截 (layer="lwip") 则原 dataout 流程被吞掉.
    // 返回值: 0 = 未拦截, 1 = 已拦截 (跳过 airlink_queue_send_ippkg).
    if (netdrv != NULL) {
        int intercepted = luat_netdrv_pkg_input(netdrv->id, LUAT_NETDRV_CH_LWIP, buff, p->tot_len);
        if (intercepted != 0) {
            // Lua 已拿走控制权, 原始 TX 包不送硬件 (Lua 用 send_raw 自己决定后续)
            luat_heap_opt_free(LUAT_HEAP_PSRAM, buff);
            return 0;
        }
    }
    if (g_netdrv_debug_enable) {
        luat_airlink_hexdump("上行给硬件", buff, p->tot_len);
    }
    // TODO 这里应该根据userdata, 也就是whale上下文, 转发可配置的出口
    luat_airlink_queue_send_ippkg(netdrv->id, buff, p->tot_len);
    luat_heap_opt_free(LUAT_HEAP_PSRAM, buff);
    return 0;
}

static err_t netif_ip4_output(struct netif *netif, struct pbuf *p, const ip_addr_t *ipaddr) {
    LWIP_UNUSED_ARG(ipaddr);
    return netif_output(netif, p);
}

#if LWIP_IPV6
static err_t netif_output_ip6(struct netif *netif, struct pbuf *p, const ip6_addr_t *ipaddr) {
    LWIP_UNUSED_ARG(ipaddr);
    return netif_output(netif, p);
}
#endif

void luat_netdrv_whale_boot(luat_netdrv_t* drv, void* userdata) {
    luat_netdrv_t* netdrv = drv;
    // 首先, 初始化netif
    if (netdrv->netif == NULL) {
        netdrv->netif = luat_heap_malloc(sizeof(struct netif));
        memset(netdrv->netif, 0, sizeof(struct netif));
    }

    netif_add(netdrv->netif, IP4_ADDR_ANY, IP4_ADDR_ANY, IP4_ADDR_ANY, netdrv, luat_netif_init, luat_netdrv_netif_input_main);

    // 网卡设置成半可用状态
    if (netdrv->id == NW_ADAPTER_INDEX_LWIP_WIFI_STA || netdrv->id == NW_ADAPTER_INDEX_LWIP_WIFI_AP) {
        // 默认是down的就行
    }
    else if (netdrv->id == NW_ADAPTER_INDEX_LWIP_GP_GW) {
        // GP_GW 的 link 状态由 drv_mobile 来控制（IP_READY/IP_LOSE）
    }
    else {
        // 其他的设备, 直接设置成up和link up
        netif_set_link_up(netdrv->netif);
    }
    if (netdrv->id == NW_ADAPTER_INDEX_LWIP_WIFI_STA) {
        drv->dhcp_enable = 1;
    }
    netif_set_up(netdrv->netif);
    net_lwip2_set_netif(netdrv->id, netdrv->netif);
    net_lwip2_register_adapter(netdrv->id);
    // IPv6: 依据 luat_netif_init 里设置好的 hwaddr 生成链路本地地址(EUI-64).
    // 必须在地址注册之后调用, 否则 ND6/RS 无链路本地地址可用, SLAAC 无法启动.
    // 该函数幂等, 重复 boot 也安全.
    net_lwip2_ipv6_create_linklocal(netdrv->id);
    // LLOGD("luat_netdrv_whale_boot 执行完成");
    drv->boot = NULL; // 不允许二次boot
}

static err_t luat_netif_init(struct netif *netif) {
    luat_netdrv_t* drv = (luat_netdrv_t*)netif->state;
    // LLOGD("luat_netif_init 执行drv %p", drv);
    luat_netdrv_whale_t* cfg = (luat_netdrv_whale_t*)drv->userdata;
    // LLOGD("luat_netif_init 执行cfg %p", cfg);
    // 先配置MTU和flags
    if (0 == cfg->mtu) {
        netif->mtu        = 1460;
    }
    else{
        netif->mtu = cfg->mtu;
    }
    if (0 == cfg->flags) {
        netif->flags      = NETIF_FLAG_BROADCAST;
    }
    else {
        netif->flags = cfg->flags;
    }
    if (netif->flags & NETIF_FLAG_ETHARP) {
        netif->hwaddr_len = 6;
        memcpy(netif->hwaddr, cfg->mac, 6);
        if (memcmp(cfg->mac, "\x00\x00\x00\x00\x00\x00", 6) == 0) {
            LLOGW("whale网卡 %d 未配置MAC, IPv6链路本地地址不可用(netdrv.setup 可用 mac 参数指定)", drv->id);
        }
    }

    netif->linkoutput = netif_output;
    if (netif->flags & NETIF_FLAG_ETHARP) {
        netif->output = luat_netdrv_etharp_output;
    }
    else {
        netif->output = netif_ip4_output;
    }
    #if ENABLE_PSIF
    netif->primary_ipv4_cid = LWIP_PS_INVALID_CID;
    netif->primary_ipv6_cid = LWIP_PS_INVALID_CID;
    #endif
    #if LWIP_IPV6
    netif->output_ip6 = netif_output_ip6;
    #endif
    return 0;
}

luat_netdrv_t* luat_netdrv_whale_create(luat_netdrv_whale_t* tmp) {
    // LLOGD("创建Whale设备");
    luat_netdrv_t* netdrv = luat_heap_malloc(sizeof(luat_netdrv_t));
    luat_netdrv_whale_t* cfg = luat_heap_malloc(sizeof(luat_netdrv_whale_t));
    if (netdrv == NULL || cfg == NULL) {
        if (netdrv)
            luat_heap_free(netdrv);
        if (cfg)
            luat_heap_free(cfg);
        return NULL;
    }
    memset(netdrv, 0, sizeof(luat_netdrv_t));
    // 把配置信息拷贝一份
    memcpy(cfg, tmp, sizeof(luat_netdrv_whale_t));

    // 初始化netdrv
    netdrv->id = cfg->id;
    netdrv->netif = NULL;
    netdrv->dataout = luat_netdrv_whale_dataout;
    netdrv->boot = luat_netdrv_whale_boot;
    netdrv->userdata = cfg;
    netdrv->dhcp = luat_netdrv_dhcp_opt;
    return netdrv;
}

luat_netdrv_t*  luat_netdrv_whale_setup(luat_netdrv_conf_t* conf) {
    luat_netdrv_whale_t cfg = {0};
    cfg.id = conf->id;
    cfg.flags = conf->flags;
    cfg.mtu = conf->mtu;
    // MAC 用于以太网头部与 IPv6 链路本地地址(EUI-64), 由 netdrv.setup 的 mac 参数传入
    memcpy(cfg.mac, conf->mac, 6);
    // 是否显式请求以太网模式: 传了 flags 或传了(非全0的) mac 都算.
    // 未显式请求时保持历史行为(裸 IP 帧), 避免影响既有 airlink 部署.
    int explicit_eth = (conf->flags != 0) || (memcmp(conf->mac, "\x00\x00\x00\x00\x00\x00", 6) != 0);
    if (cfg.flags == 0) {
        if (cfg.id == NW_ADAPTER_INDEX_LWIP_WIFI_STA || cfg.id == NW_ADAPTER_INDEX_LWIP_WIFI_AP) {
            // WIFI_STA/AP 一直是按以太网设备处理的(airlink WiFi 依赖这个), 保持不变
            cfg.flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP;
            #if LWIP_IGMP
            cfg.flags |= NETIF_FLAG_IGMP;
            #endif
            #if LWIP_IPV6
            cfg.flags |= NETIF_FLAG_MLD6;
            #endif
            if (cfg.mtu == 0) {
                cfg.mtu = 1460;
            }
        }
        else if (explicit_eth) {
            // 显式指定 mac(或 flags)的虚拟网卡: 按以太网设备配置.
            //   - NETIF_FLAG_ETHARP: 决定走 ethernet_input, 以及 airlink 的 IPv4/IPv6 放行判断
            //   - NETIF_FLAG_MLD6:   IPv6 组播(ND/MLD)必需, 否则链路本地地址无法完成 DAD
            cfg.flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP;
            #if LWIP_IPV6
            cfg.flags |= NETIF_FLAG_MLD6;
            #endif
            if (cfg.mtu == 0) {
                cfg.mtu = 1460;
            }
        }
    }
    else {
        // 用户显式给了 flags: 原样使用(需要以太网/IPv6 时请自行带上 ETHARP/MLD6)
        if (cfg.mtu == 0) {
            cfg.mtu = 1460;
        }
    }

    luat_netdrv_t* drv = luat_netdrv_whale_create(&cfg);
    if (drv == NULL) {
        return NULL;
    }
    drv->boot(drv, drv->userdata);
    return drv;
}


