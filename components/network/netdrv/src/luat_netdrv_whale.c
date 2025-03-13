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
#include "net_lwip2.h"
#include "luat_airlink.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "netdrv.whale"
#include "luat_log.h"

static err_t luat_netif_init(struct netif *netif);
static err_t netif_output(struct netif *netif, struct pbuf *p);
static int netif_ip_event_cb(lua_State *L, void* ptr);

void luat_netdrv_whale_dataout(luat_netdrv_t* drv, void* userdata, uint8_t* buff, uint16_t len) {
    // TODO 发送到spi slave task
    LLOGD("上行给主机的IP数据 %p %d", buff, len);
    if (len < 0) {
        return;
    }
    luat_netdrv_t* netdrv = (luat_netdrv_t*)userdata;
    luat_airlink_queue_send_ippkg(netdrv->id, buff, len);
}

static err_t netif_output(struct netif *netif, struct pbuf *p) {
    // TODO 发送到spi slave task
    LLOGD("上行给主机的IP数据 %p %d", p, p->tot_len);
    luat_netdrv_t* netdrv = (luat_netdrv_t*)(netif->state);
    void* buff = luat_heap_opt_zalloc(LUAT_HEAP_PSRAM, p->tot_len);
    if (buff == NULL) {
        return ERR_MEM;
    }
    pbuf_copy_partial(p, buff, p->tot_len, 0);
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
    if (userdata == NULL) {
        return;
    }
    luat_netdrv_t* netdrv = drv;
    // 首先, 初始化netif
    if (netdrv->netif == NULL) {
        netdrv->netif = luat_heap_malloc(sizeof(struct netif));
        memset(netdrv->netif, 0, sizeof(struct netif));
    }

    netif_add(netdrv->netif, IP4_ADDR_ANY, IP4_ADDR_ANY, IP4_ADDR_ANY, netdrv, luat_netif_init, netif_input);

    // 网卡设置成可用状态
    netif_set_up(netdrv->netif);
    netif_set_link_up(netdrv->netif);
    net_lwip2_set_netif(netdrv->id, netdrv->netif);
    net_lwip2_register_adapter(netdrv->id);
    LLOGD("luat_netif_init 执行完成");
}

static err_t luat_netif_init(struct netif *netif) {
    netif->linkoutput = netif_output;
    netif->output     = netif_ip4_output;
    #if ENABLE_PSIF
    netif->primary_ipv4_cid = LWIP_PS_INVALID_CID;
    #endif
    #if LWIP_IPV6
    netif->output_ip6 = netif_output_ip6;
    #if ENABLE_PSIF
    netif->primary_ipv6_cid = LWIP_PS_INVALID_CID;
    #endif
    #endif
    if (netif->mtu == 0) {
        netif->mtu        = 1420;
    }
    if (netif->flags == 0) {
        netif->flags      = NETIF_FLAG_BROADCAST;
    }
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
        // TODO 要区分是READY还是LOSE呀
        ipaddr_ntoa_r(&netdrv->netif->ip_addr, buff,  32);
        LLOGD("IP_READY %d %s", netdrv->id, buff);
        lua_pushstring(L, "IP_READY");
        lua_pushstring(L, buff);
        lua_pushinteger(L, netdrv->id);
        lua_call(L, 3, 0);
    }
    return 0;
}

void luat_netdrv_whale_ipevent(int id) {
    net_lwip2_set_link_state(id, 1);
    rtos_msg_t msg = {0};
    msg.arg1 = id;
    msg.arg2 = 0;
    msg.ptr = NULL;
    msg.handler = netif_ip_event_cb;
    luat_msgbus_put(&msg, 0);
}