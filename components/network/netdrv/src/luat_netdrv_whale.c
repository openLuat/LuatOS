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
#include "luat_ulwip.h"

#define LUAT_LOG_TAG "netdrv.whale"
#include "luat_log.h"

static err_t luat_netif_init(struct netif *netif);
static err_t netif_output(struct netif *netif, struct pbuf *p);
static int netif_ip_event_cb(lua_State *L, void* ptr);
static int whale_dhcp(luat_netdrv_t* drv, void* userdata, int enable);

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
        return ERR_MEM;
    }
    pbuf_copy_partial(p, buff, p->tot_len, 0);
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
    luat_netdrv_whale_t* cfg = (luat_netdrv_whale_t*)userdata;
    cfg->ulwip.netif = netdrv->netif;
    cfg->ulwip.adapter_index = cfg->id;

    netif_add(netdrv->netif, IP4_ADDR_ANY, IP4_ADDR_ANY, IP4_ADDR_ANY, netdrv, luat_netif_init, netif_input);

    // 网卡设置成半可用状态
    if (netdrv->id == NW_ADAPTER_INDEX_LWIP_WIFI_STA || netdrv->id == NW_ADAPTER_INDEX_LWIP_WIFI_AP) {
    }
    else {
        netif_set_up(netdrv->netif);
    }
    if (netdrv->id == NW_ADAPTER_INDEX_LWIP_WIFI_STA) {
        cfg->dhcp = 1;
        cfg->ulwip.dhcp_enable = 1;
    }
    netif_set_link_up(netdrv->netif);
    net_lwip2_set_netif(netdrv->id, netdrv->netif);
    net_lwip2_register_adapter(netdrv->id);
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
    }

    netif->linkoutput = netif_output;
    if (netif->flags & NETIF_FLAG_ETHARP) {
        netif->output = ulwip_etharp_output;
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

static int netif_ip_event_cb(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    char buff[32] = {0};
    luat_netdrv_t* netdrv = luat_netdrv_get(msg->arg1);
    if (netdrv == NULL) {
        return 0;
    }
    lua_getglobal(L, "sys_pub");
    if (lua_isfunction(L, -1)) {
        if (msg->arg2 == 0) {
            lua_pushstring(L, "IP_LOSE");
            lua_pushinteger(L, netdrv->id);
            lua_call(L, 2, 0);
        }
        else {
            ipaddr_ntoa_r(&netdrv->netif->ip_addr, buff,  32);
            LLOGD("IP_READY %d %s", netdrv->id, buff);
            lua_pushstring(L, "IP_READY");
            lua_pushstring(L, buff);
            lua_pushinteger(L, netdrv->id);
            lua_call(L, 3, 0);
        }
    }
    return 0;
}

typedef struct tmpptr {
    luat_netdrv_t* drv;
    uint8_t updown;
}tmpptr_t;

static void _luat_netdrv_whale_ipevent(tmpptr_t* ptr) {
    luat_netdrv_t* drv = ptr->drv;
    uint8_t updown = ptr->updown;
    rtos_msg_t msg = {0};
    void* userdata = NULL;
    luat_netdrv_whale_t* cfg = (luat_netdrv_whale_t*)drv->userdata;
    if (updown) {
        netif_set_up(drv->netif);
        if (cfg->ulwip.netif == NULL) {
            cfg->ulwip.netif = drv->netif;
        }
        if (cfg->dhcp) {
            // LLOGD("dhcp启动 %p", cfg->ulwip.netif);
            ip_addr_set_ip4_u32(&cfg->ulwip.netif->ip_addr, 0);
            ip_addr_set_ip4_u32(&cfg->ulwip.netif->gw, 0);
            ulwip_dhcp_client_start(&cfg->ulwip);
        }
    }
    else {
        netif_set_down(drv->netif);
        if (cfg->dhcp) {
            // LLOGD("dhcp停止");
            ip_addr_set_ip4_u32(&cfg->ulwip.netif->ip_addr, 0);
            ip_addr_set_ip4_u32(&cfg->ulwip.netif->gw, 0);
            ulwip_dhcp_client_stop(&cfg->ulwip);
        }
    }
	network_adapter_info* info = network_adapter_fetch(drv->id, &userdata);
    if (info == NULL || info->check_ready == NULL) {
        // LLOGI("网络适配器(%d)不存在, 或者没有check_ready函数", adapter_index);
        return;
    }
    int ready = info->check_ready(userdata);
    net_lwip2_set_link_state(drv->id, ready);
    msg.arg1 = drv->id;
    msg.arg2 = ready;
    msg.ptr = NULL;
    msg.handler = netif_ip_event_cb;
    luat_msgbus_put(&msg, 0);
}

void luat_netdrv_whale_ipevent(luat_netdrv_t* drv, uint8_t updown) {
    if (drv == NULL || drv->netif == NULL) {
        return;
    }
    tmpptr_t ptr = {
        .drv = drv,
        .updown = updown,
    };
    tcpip_callback_with_block(_luat_netdrv_whale_ipevent, &ptr, 1);
}


luat_netdrv_t* luat_netdrv_whale_create(luat_netdrv_whale_t* tmp) {
    // LLOGD("创建Whale设备");
    luat_netdrv_t* netdrv = luat_heap_malloc(sizeof(luat_netdrv_t));
    if (netdrv == NULL) {
        return NULL;
    }
    // 把配置信息拷贝一份
    luat_netdrv_whale_t* cfg = luat_heap_malloc(sizeof(luat_netdrv_whale_t));
    memcpy(cfg, tmp, sizeof(luat_netdrv_whale_t));

    // 初始化netdrv
    memset(netdrv, 0, sizeof(luat_netdrv_t));
    netdrv->id = cfg->id;
    netdrv->netif = NULL;
    netdrv->dataout = luat_netdrv_whale_dataout;
    netdrv->boot = luat_netdrv_whale_boot;
    netdrv->userdata = cfg;
    netdrv->dhcp = whale_dhcp;
    return netdrv;
}

luat_netdrv_t*  luat_netdrv_whale_setup(luat_netdrv_conf_t* conf) {
    luat_netdrv_whale_t cfg = {0};
    cfg.id = conf->id;
    cfg.flags = conf->flags;
    cfg.mtu = conf->mtu;
    if (cfg.flags == 0) {
        if (cfg.id == NW_ADAPTER_INDEX_LWIP_WIFI_STA || cfg.id == NW_ADAPTER_INDEX_LWIP_WIFI_AP) {
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
    }

    luat_netdrv_t* drv = luat_netdrv_whale_create(&cfg);
    if (drv == NULL) {
        return NULL;
    }
    drv->boot(drv, drv->userdata);
    return drv;
}

static int whale_dhcp(luat_netdrv_t* drv, void* userdata, int enable) {
    luat_netdrv_whale_t* cfg = (luat_netdrv_whale_t*)userdata;
    if (cfg->dhcp == enable) {
        return 0;
    }
    cfg->dhcp = (uint8_t)enable;
    cfg->ulwip.dhcp_enable = enable;
    if (cfg->ulwip.netif == NULL) {
        return 0;
    }
    if (enable) {
        ulwip_dhcp_client_start(&cfg->ulwip);
    }
    else {
        ulwip_dhcp_client_stop(&cfg->ulwip);
    }
    return 0;
}
