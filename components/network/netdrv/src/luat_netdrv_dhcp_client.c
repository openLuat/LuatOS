#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_netdrv_dhcp_client.h"
#include "luat_netdrv_event.h"
#include "luat_network_adapter.h"
#include "luat_crypto.h"
#include "luat_mem.h"
#include "luat_rtos.h"

#include "net_lwip2.h"
#include "dhcp_def.h"

#define LUAT_LOG_TAG "netdrv.dhcp"
#include "luat_log.h"

#include "lwip/opt.h"
#include "lwip/udp.h"
#include "lwip/ip.h"
#include "lwip/ip_addr.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "lwip/etharp.h"
#include "lwip/tcpip.h"

// -------------------------------------
//           DHCP 客户端逻辑
// -------------------------------------
static struct udp_pcb* s_netdrv_dhcp_udp;

static void dhcp_client_timer_cb(void *arg);

static int luat_netdrv_dhcp_client_run(luat_netdrv_t* drv, char* rxbuff, size_t len) {
    PV_Union uIP, uIPMask, uIPGW;
    // 检查dhcp的状态
    dhcp_client_info_t* dhcp = &drv->dhcp_client;
    u8_t adapter_index = drv->id;
    struct netif* netif = drv->netif;

    Buffer_Struct rx_msg_buf = {0,0,0};
    Buffer_Struct tx_msg_buf = {0,0,0};
	uint32_t remote_ip = 0;
    int result = 0;

    if (netif == NULL || !netif_is_up(netif) || !netif_is_link_up(netif)) {
        LLOGD("网卡未就绪,不发送dhcp请求 %d", adapter_index);
        if (rxbuff) {
            luat_heap_free(rxbuff);
            rxbuff = NULL;
        }
        return 0;
    }

    if (rxbuff) {
        rx_msg_buf.Data = (uint8_t*)rxbuff;
        rx_msg_buf.Pos = len;
        rx_msg_buf.MaxLen = len;
    }

    // 看看是不是获取成功了
    if (DHCP_STATE_CHECK == dhcp->state) {
on_check:
        uIP.u32 = dhcp->ip;
		uIPMask.u32 = dhcp->submask;
		uIPGW.u32 = dhcp->gateway;
		LLOGI("adapter %d ip %d.%d.%d.%d mask %d.%d.%d.%d gw %d.%d.%d.%d lease_time %us", adapter_index, 
            uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3], 
            uIPMask.u8[0], uIPMask.u8[1], uIPMask.u8[2], uIPMask.u8[3], 
            uIPGW.u8[0], uIPGW.u8[1], uIPGW.u8[2], uIPGW.u8[3],
            dhcp->lease_time);

        if (dhcp->dns_server[0] != 0) {
            uIP.u32 = dhcp->dns_server[0];
            LLOGD("adapter %d DNS1:%d.%d.%d.%d", adapter_index, uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
        }
        if (dhcp->dns_server[1] != 0) {
            uIP.u32 = dhcp->dns_server[1];
            LLOGD("adapter %d DNS2:%d.%d.%d.%d", adapter_index, uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
        }

        // 设置到netif
        ip4_addr_t ipaddr = {.addr=dhcp->ip};
        ip4_addr_t netmask = {.addr=dhcp->submask};
        ip4_addr_t gw = {.addr=dhcp->gateway};
        netif_set_addr(netif, &ipaddr, &netmask, &gw);
        // gratuitous ARP，通知局域网刷新本机 IP/MAC 映射
        err_t arp_err = etharp_gratuitous(netif);
        if (arp_err != ERR_OK) {
            LLOGW("adapter %d gratuitous ARP failed %d", adapter_index, arp_err);
        }
        // 预热网关 MAC，避免上层首包出网卡顿
        if (ip4_addr_isany_val(gw) == 0) {
            arp_err = etharp_request(netif, &gw);
            if (arp_err != ERR_OK) {
                LLOGW("adapter %d gateway ARP request failed %d", adapter_index, arp_err);
            }
        }
        dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
        if (rxbuff) {
            luat_heap_free(rxbuff);
            rxbuff = NULL;
        }
        net_lwip2_set_link_state(adapter_index, 1);
        luat_netdrv_send_ip_event(drv, 1);
        luat_rtos_timer_stop(drv->dhcp_timer);
        luat_rtos_timer_start(drv->dhcp_timer, 60000, 1, dhcp_client_timer_cb, drv);
        return 0;
    }
    result = ip4_dhcp_run(dhcp, rxbuff == NULL ? NULL : &rx_msg_buf, &tx_msg_buf, &remote_ip);
    if (rxbuff) {
        luat_heap_free(rxbuff);
        rxbuff = NULL;
    }
    if (result) {
        LLOGE("adapter %d ip4_dhcp_run error %d", adapter_index, result);
        return 0;
    }
    if (!tx_msg_buf.Pos) {
        if (DHCP_STATE_CHECK == dhcp->state) {
            goto on_check;
        }
        return 0; // 没有数据需要发送
    }
    // 通过UDP发出来
    struct pbuf *p;
    struct pbuf *q;
    p = pbuf_alloc(PBUF_TRANSPORT, tx_msg_buf.Pos, PBUF_RAM);
    if (p == NULL) {
        LLOGE("pbuf_alloc error %d", tx_msg_buf.Pos);
        return -1;
    }
    char* data = (char*)tx_msg_buf.Data;
    for (q = p; q != NULL; q = q->next) {
        memcpy(q->payload, data, q->len);
        data += q->len;
    }
    data = p->payload;
    LLOGD("adapter %d dhcp payload len %d", adapter_index, p->tot_len);
    // 本地地址设为netif的ip地址
    memcpy(&s_netdrv_dhcp_udp->local_ip, &netif->ip_addr, sizeof(ip_addr_t));
    result = udp_sendto_if(s_netdrv_dhcp_udp, p, IP_ADDR_BROADCAST, 67, netif);
    pbuf_free(p);
    if (result != ERR_OK) {
        LLOGE("adapter %d dhcp udp_sendto_if error %d", adapter_index, result);
    }
    return 0;
}

static int luat_netdrv_dhcp_recv(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port) {
    LWIP_UNUSED_ARG(arg);
    LWIP_UNUSED_ARG(pcb);
    LWIP_UNUSED_ARG(port);
    LLOGD("收到DHCP数据包(len=%d)", p->tot_len);
    u16_t total_len = p->tot_len;
    char* ptr = luat_heap_malloc(total_len);
    if (!ptr) {
        LLOGE("malloc fail when parse dhcp packet %d", p->tot_len);
        pbuf_free(p);
        return ERR_OK;
    }
    pbuf_copy_partial(p, ptr, total_len, 0);
    pbuf_free(p);
    p = NULL; // 防止重复释放

    // 解析DHCP数据包中的mac地址
    uint8_t received_mac[6];
    memcpy(received_mac, ptr + 28, 6);
    
    u16_t ip_header_length = IP_IS_V6(addr) ? 40 : 20;
    u16_t udp_header_length = 8;
    u16_t max_dhcp_packet_len;

    // 收到DHCP数据包, 需要逐个netdrv查一遍, 对照mac
    for (size_t i = 0; i < NW_ADAPTER_INDEX_LWIP_NETIF_QTY; i++)
    {
        luat_netdrv_t* drv = luat_netdrv_get(i);
        if (drv == NULL || drv->netif == NULL) {
            continue;
        }

        // 获取网络接口的mac地址
        struct netif *netif = drv->netif;
        uint8_t *local_mac = netif->hwaddr;

        // 比较mac地址
        if (0 == memcmp(local_mac, received_mac, 6)) {
            // 如果找到匹配的网络接口
            // 先检查数据包长度是否足够
            max_dhcp_packet_len = netif->mtu - ip_header_length - udp_header_length;
            if (total_len > max_dhcp_packet_len) {
                LLOGE("dhcp pkg too large %d mtu %d len %d", drv->id, netif->mtu, max_dhcp_packet_len);
                break;
            }
            // 注意, luat_netdrv_dhcp_client_run是会释放ptr的, 所以不能在这里释放
            luat_netdrv_dhcp_client_run(drv, ptr, total_len);
            ptr = NULL; // 防止重复释放
            break;
        }
    }
    if (ptr) {
        // 如果没有找到匹配的网络接口, 释放ptr
        LLOGD("dhcp data not for us len=%d mac %02X%02X%02X%02X%02X%02X", total_len, 
            received_mac[0], received_mac[1], received_mac[2], received_mac[3], received_mac[4], received_mac[5]);
        luat_heap_free(ptr);
        ptr = NULL;
    }
    return ERR_OK;
}

static void luat_netdrv_dhcp_client_run_proxy(void* args) {
    luat_netdrv_dhcp_client_run((luat_netdrv_t *)args, NULL, 0);
}

// timer回调, 或者是直接被调用, arg是nets的索引号
static void dhcp_client_timer_cb(void *arg) {
    luat_netdrv_t *drv = (luat_netdrv_t *)arg;
    // 简单防御一下
    if (drv->dhcp_enable == 0) {
        return;
    }
    #if NO_SYS
    luat_netdrv_dhcp_client_run_proxy(drv);
    #else
    tcpip_callback(luat_netdrv_dhcp_client_run_proxy, drv);
    #endif
}

static void reset_dhcp_client(luat_netdrv_t *drv) {
    char tmp[32] = {0};
    memcpy(tmp, drv->dhcp_client.name, 32);
    memset(&drv->dhcp_client, 0, sizeof(dhcp_client_info_t));
    memcpy(&drv->dhcp_client.mac, drv->netif->hwaddr, 6);
    luat_crypto_trng((char*)&drv->dhcp_client.xid, sizeof(drv->dhcp_client.xid));
    // 优先级: Lua侧显式设置的名称 > netif hostname > 默认名称
    if (tmp[0] != 0) {
        memcpy(drv->dhcp_client.name, tmp, 32);
    }
    #if LWIP_NETIF_HOSTNAME
    else if (drv->netif && drv->netif->hostname && drv->netif->hostname[0]) {
        strncpy(drv->dhcp_client.name, drv->netif->hostname, sizeof(drv->dhcp_client.name) - 1);
        drv->dhcp_client.name[sizeof(drv->dhcp_client.name) - 1] = 0;
    }
    #endif
    else {
        sprintf_(drv->dhcp_client.name, "LuatOS_%02X%02X%02X%02X%02X%02X",
                drv->dhcp_client.mac[0],drv->dhcp_client.mac[1], drv->dhcp_client.mac[2],
                drv->dhcp_client.mac[3],drv->dhcp_client.mac[4], drv->dhcp_client.mac[5]);
    }
}

void luat_netdrv_dhcp_client_start(luat_netdrv_t *drv) {
    LLOGD("adapter %d dhcp start netif %p", drv->id, drv->netif);
    if (drv->netif == NULL) {
        LLOGE("drv->netif is NULL!!!!");
        return;
    }
    // 注意, 这里只能建一个udp上下文, 要监听全部网卡
    if (s_netdrv_dhcp_udp == NULL) {
        s_netdrv_dhcp_udp = udp_new();
        ip_set_option(s_netdrv_dhcp_udp, SOF_BROADCAST);
        udp_bind(s_netdrv_dhcp_udp, IP4_ADDR_ANY, 68);
        udp_connect(s_netdrv_dhcp_udp, IP4_ADDR_ANY, 67);
        udp_recv(s_netdrv_dhcp_udp, luat_netdrv_dhcp_recv, NULL);
    }
    reset_dhcp_client(drv);
    net_lwip2_set_dhcp_client(drv->id, &drv->dhcp_client);
    if (drv->dhcp_timer == NULL) {
        luat_rtos_timer_create(&drv->dhcp_timer);
    }
    ip4_addr_t ipaddr = {0};
    ip4_addr_t netmask = {0};
    ip4_addr_t gw = {0};
    if (drv->netif) {
        netif_set_addr(drv->netif, &ipaddr, &netmask, &gw);
    }
    drv->dhcp_client.state = DHCP_STATE_DISCOVER;
    drv->dhcp_client.discover_cnt = 0;
    if (!luat_rtos_timer_is_active(drv->dhcp_timer))
    {
        luat_rtos_timer_start(drv->dhcp_timer, 1000, 1, dhcp_client_timer_cb, drv);
    }
    dhcp_client_timer_cb(drv);
}

void luat_netdrv_dhcp_client_stop(luat_netdrv_t *drv) {
    if (drv->dhcp_timer != NULL && luat_rtos_timer_is_active(drv->dhcp_timer)) {
        luat_rtos_timer_stop(drv->dhcp_timer);
    }
    if (drv->dhcp_enable) {
        reset_dhcp_client(drv);
        if (drv->netif) {
            ip4_addr_t ipaddr = {0};
            ip4_addr_t netmask = {0};
            ip4_addr_t gw = {0};
            netif_set_addr(drv->netif, &ipaddr, &netmask, &gw);
        }
    }
}
