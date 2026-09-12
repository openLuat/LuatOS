#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "lwip/ip.h"
#include "lwip/tcpip.h"
#include "luat_netdrv_drv.h"
#include "luat_netdrv_dhcp_client.h"
/*
 * IPv6 相关能力由 lwip2 适配层实现(components/network/adapter_lwip2/net_lwip2.c),
 * 但部分固件/模拟器构建里并没有链接该适配层(例如 SDK 自带 lwip 的机型走
 * lwip_with_sdk/net_lwip.c), 为避免出现未解析符号, 这里对这两个入口做弱符号兜底:
 *   - 链接到适配层时使用真实实现
 *   - 否则退化为"无 IPv6"(is_ready 恒 0, create_linklocal 恒失败)
 * 是否启用由 LUAT_USE_NETDRV_IPV6 控制(默认跟随 LWIP_IPV6, 见 luat_netdrv.h).
 */
#if LUAT_USE_NETDRV_IPV6
#if defined(_MSC_VER)
#pragma comment(linker, "/alternatename:net_lwip2_ipv6_is_ready=luat_netdrv_ipv6_is_ready_stub")
#pragma comment(linker, "/alternatename:net_lwip2_ipv6_create_linklocal=luat_netdrv_ipv6_create_linklocal_stub")
#else
__attribute__((weak)) int net_lwip2_ipv6_is_ready(uint8_t adapter_index);
__attribute__((weak)) int net_lwip2_ipv6_create_linklocal(uint8_t adapter_index);
#endif

static int luat_netdrv_ipv6_is_ready_stub(uint8_t adapter_index) {
    return 0;
}

static int luat_netdrv_ipv6_create_linklocal_stub(uint8_t adapter_index) {
    return -1;
}
#endif /* LUAT_USE_NETDRV_IPV6 */

#ifdef LUAT_USE_AIRLINK
#include "luat_airlink.h"
#endif

#ifdef LUAT_USE_MOBILE
#include "luat_mobile.h"
#endif

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

static luat_netdrv_t* drvs[NW_ADAPTER_QTY];

uint32_t g_netdrv_debug_enable;

// ---- RX 收包统计/丢包日志 ----
typedef struct netdrv_rx_stat {
    uint32_t injected;      // 成功投递到 tcpip 线程的帧数
    uint32_t drop_heap;     // netif_input_proxy 堆分配失败
    uint32_t drop_mbox;     // tcpip 回调投递失败(邮箱满/无内存)
    uint32_t drop_pbuf;     // tcpip 线程内 pbuf_alloc 失败
    uint32_t input_fail;    // netif->input 返回错误
} netdrv_rx_stat_t;

static netdrv_rx_stat_t g_rx_stat;

void luat_netdrv_rx_stat_reset(void) {
    memset(&g_rx_stat, 0, sizeof(g_rx_stat));
}

void luat_netdrv_rx_stat_print(void) {
    LLOGD("RX_STAT injected=%u drop_heap=%u drop_mbox=%u drop_pbuf=%u input_fail=%u",
          g_rx_stat.injected, g_rx_stat.drop_heap, g_rx_stat.drop_mbox,
          g_rx_stat.drop_pbuf, g_rx_stat.input_fail);
}

// 打印被丢弃的以太网帧摘要: 协议/地址/端口/TCP seq
static void netdrv_log_rx_drop(const char* reason, const uint8_t* buff, uint16_t len) {
    // 默认隐藏, 调试时通过 netdrv.debug(0, true) 打开
    if (!g_netdrv_debug_enable) {
        return;
    }
    uint8_t proto = 0;
    uint16_t sport = 0, dport = 0;
    uint32_t seq = 0;
    if (buff == NULL || len < 34) {
        LLOGD("RX_DROP %s len=%u (帧过短)", reason, len);
        return;
    }
    const uint8_t* ip = buff + 14; // 以太网头14字节
    if ((ip[0] >> 4) != 4) {
        LLOGD("RX_DROP %s len=%u (非IPv4)", reason, len);
        return;
    }
    uint16_t ihl = (uint16_t)(ip[0] & 0x0F) * 4;
    if (len < 14 + ihl + 20) {
        LLOGD("RX_DROP %s len=%u (帧被截断)", reason, len);
        return;
    }
    proto = ip[9];
    if (proto == 6) { // TCP
        sport = ((uint16_t)ip[ihl] << 8) | ip[ihl + 1];
        dport = ((uint16_t)ip[ihl + 2] << 8) | ip[ihl + 3];
        seq = ((uint32_t)ip[ihl + 4] << 24) | ((uint32_t)ip[ihl + 5] << 16) |
              ((uint32_t)ip[ihl + 6] << 8) | ip[ihl + 7];
    }
    LLOGD("RX_DROP %s len=%u proto=%u %u.%u.%u.%u:%u -> %u.%u.%u.%u:%u seq=%u",
          reason, len, proto,
          ip[12], ip[13], ip[14], ip[15], sport,
          ip[16], ip[17], ip[18], ip[19], dport, seq);
}

luat_netdrv_t* luat_netdrv_setup(luat_netdrv_conf_t *conf) {
    int id = conf->id;
    if (id < 0 || id >= NW_ADAPTER_QTY) {
        return NULL;
    }
    int ret = 0;
    if (drvs[id] == NULL) {
        // 注册新的设备?
        #ifdef __LUATOS__
        #ifdef LUAT_USE_NETDRV_CH390H
        if (conf->impl == LUAT_NETDRV_IMPL_CH390H) { // CH390H
            drvs[id] = luat_netdrv_ch390h_setup(conf);
            return drvs[id];
        }
        #endif
        #ifdef LUAT_USE_AIRLINK
        if (conf->impl == LUAT_NETDRV_IMPL_WHALE) { // WHALE
            drvs[id] = luat_netdrv_whale_setup(conf);
            return drvs[id];
        }
        #endif
        #ifdef LUAT_USE_NETDRV_WG
        if (conf->impl == LUAT_NETDRV_IMPL_WG) { // WG
            drvs[id] = luat_netdrv_wg_setup(conf);
            return drvs[id];
        }
        #endif
        #ifdef LUAT_USE_NETDRV_OPENVPN
        if (conf->impl == LUAT_NETDRV_IMPL_OPENVPN) { // OPENVPN
            drvs[id] = luat_netdrv_openvpn_setup(conf);
            return drvs[id];
        }
        #endif
        #ifdef LUAT_USE_NETDRV_L2TP
        if (conf->impl == LUAT_NETDRV_IMPL_L2TP) { // L2TP
            drvs[id] = luat_netdrv_l2tp_setup(conf);
            return drvs[id];
        }
        #endif
        #ifdef LUAT_USE_NETDRV_IPSEC
        if (conf->impl == LUAT_NETDRV_IMPL_IPSEC) { // IPSEC
            drvs[id] = luat_netdrv_ipsec_setup(conf);
            return drvs[id];
        }
        #endif
        #endif
    }
    else {
        if (drvs[conf->id]->boot) {
            //LLOGD("启动网络设备 %p", drvs[conf->id]);
            ret = drvs[conf->id]->boot(drvs[conf->id], NULL);
            if (ret) {
                return NULL;
            }
        }
        return drvs[conf->id];
    }
    LLOGW("无效的注册id或类型 id=%d, impl=%d", conf->id, conf->impl);
    return NULL;
}

int luat_netdrv_dhcp(int32_t id, int32_t enable) {
    if (id < 0 || id >= NW_ADAPTER_QTY) {
        return -1;
    }
    if (drvs[id] == NULL) {
        return -1;
    }
    if (drvs[id]->dhcp == NULL) {
        LLOGW("该netdrv不支持设置dhcp开关");
        return -1;
    }
    return drvs[id]->dhcp(drvs[id], drvs[id]->userdata, enable);
}

int luat_netdrv_ready(int32_t id) {
    if (id < 0 || id >= NW_ADAPTER_QTY) {
        return -1;
    }
    if (drvs[id] == NULL) {
        return -1;
    }
    return drvs[id]->ready(drvs[id], drvs[id]->userdata);
}

int luat_netdrv_register(int32_t id, luat_netdrv_t* drv) {
    if (id < 0 || id >= NW_ADAPTER_QTY) {
        return -1;
    }
    if (drvs[id] != NULL) {
        return -1;
    }
    drvs[id] = drv;
    return 0;
}

int luat_netdrv_mac(int32_t id, const char* new, char* old) {
    if (id < 0 || id >= NW_ADAPTER_QTY) {
        return -1;
    }
    if (drvs[id] == NULL || drvs[id]->netif == NULL) {
        return -1;
    }
    memcpy(old, drvs[id]->netif->hwaddr, 6);
    if (new) {
        memcpy(drvs[id]->netif->hwaddr, new, 6);
    }
    return 0;
}

void luat_netdrv_stat_inc(luat_netdrv_statics_item_t* stat, size_t len) {
    stat->bytes += len;
    stat->counter ++;
}

luat_netdrv_t* luat_netdrv_get(int id) {
    if (id < 0 || id >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        return NULL;
    }
    return drvs[id];
}

void luat_netdrv_print_pkg(const char* tag, uint8_t* buff, size_t len) {
    char tmpbuff[1024];
    if (len > 511) {
        len = 511;
    }
    memset(tmpbuff, 0, sizeof(tmpbuff));
    for (size_t i = 0; i < len; i++)
    {
        sprintf(tmpbuff + i * 2, "%02X", buff[i]);
    }
    LLOGD("%s %s", tag, tmpbuff);
}



void luat_netdrv_netif_input(void* args) {
    netdrv_pkg_msg_t* ptr = (netdrv_pkg_msg_t*)args;
    if (ptr == NULL || ptr->p == NULL) {
        return;
    }
    // pbuf已在RX任务里分配并拷好数据, 这里直接进netif, 不再二次分配/拷贝
    int ret = ptr->netif->input(ptr->p, ptr->netif);
    if (ret) {
        g_rx_stat.input_fail++;
        LLOGW("netif->input ret %d", ret);
        pbuf_free(ptr->p);
    }
    luat_heap_free(ptr);
}

int luat_netdrv_netif_input_proxy(struct netif * netif, uint8_t* buff, uint16_t len) {
    // 单次分配+单次拷贝: 直接在RX任务里把帧拷进pbuf, 投递pbuf给TCPIP线程
    struct pbuf* p = pbuf_alloc(PBUF_RAW, len, PBUF_RAM);
    if (p == NULL) {
        g_rx_stat.drop_pbuf++;
        netdrv_log_rx_drop("pbuf_alloc", buff, len);
        return 1; // 需要处理下一个包
    }
    pbuf_take(p, buff, len);
    netdrv_pkg_msg_t* ptr = luat_heap_malloc(sizeof(netdrv_pkg_msg_t));
    if (ptr == NULL) {
        g_rx_stat.drop_heap++;
        netdrv_log_rx_drop("heap", buff, len);
        pbuf_free(p);
        return 1;
    }
    ptr->netif = netif;
    ptr->p = p;
    // 非阻塞投递: 邮箱满/无内存时返回非0, 失败时pbuf和结构体都归调用方释放
    int ret = tcpip_callback_with_block(luat_netdrv_netif_input, ptr, 0);
    if (ret != ERR_OK) {
        g_rx_stat.drop_mbox++;
        netdrv_log_rx_drop("mbox", buff, len);
        pbuf_free(p);
        luat_heap_free(ptr);
        return 1;
    }
    g_rx_stat.injected++;
    return 0;
}



void luat_netdrv_print_tm(const char * tag) {
    uint64_t tnow = luat_mcu_tick64();
    uint64_t t_us = tnow / luat_mcu_us_period();
    LLOGI("tag %s time %lld", tag, t_us);
}

void luat_netdrv_debug_set(int id, int enable) {
    if (id == 0) {
        g_netdrv_debug_enable = enable;
        LLOGD("debug is %d now", enable);
    }
    else if (id >= NW_ADAPTER_INDEX_LWIP_GPRS && id < NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        luat_netdrv_t* drv = luat_netdrv_get(id);
        if (drv && drv->debug) {
            drv->debug(drv, drv->userdata, enable);
        }
        else {
            LLOGW("netdrv %d not support debug", id);
        }
    }
    else {
        LLOGW("netdrv %d not support debug", id);
    }
}

#include "lwip/etharp.h"
#include "netif/ethernet.h"
// #include "luat_netdrv_etharp.h"
extern err_t luat_netdrv_ethernet_input(struct pbuf *p, struct netif *netif);
extern void luat_netdrv_etharp_cleanup_netif(struct netif *netif);

err_t luat_netdrv_netif_input_main(struct pbuf *p, struct netif *inp)
{
//   LWIP_ASSERT_CORE_LOCKED();

  LWIP_ASSERT("netif_input: invalid pbuf", p != NULL);
  LWIP_ASSERT("netif_input: invalid netif", inp != NULL);

#if LWIP_ETHERNET
  if (inp->flags & (NETIF_FLAG_ETHARP | NETIF_FLAG_ETHERNET)) {
    #if defined(LUAT_USE_NETDRV_LWIP_ARP)
    return luat_netdrv_ethernet_input(p, inp);
    #else
    return ethernet_input(p, inp);
    #endif /* LUAT_USE_NETDRV_LWIP_ARP */
  } else
#endif /* LWIP_ETHERNET */
    return ip_input(p, inp);
}

void luat_netdrv_netif_set_down(struct netif* netif) {
    if (netif == NULL) {
        return;
    }
    netif_set_down(netif);
    #if LWIP_IPV4 && LWIP_ARP
    #ifdef LUAT_USE_NETDRV_LWIP_ARP
    if (netif->flags & NETIF_FLAG_ETHARP) {
        luat_netdrv_etharp_cleanup_netif(netif);
    }
    #endif
    #endif /* LWIP_IPV4 && LWIP_ARP */

    #if LWIP_IPV6
    nd6_cleanup_netif(netif);
    #endif /* LWIP_IPV6 */
}

void luat_netdrv_netif_set_link_down(struct netif* netif) {
    if (netif == NULL) {
        return;
    }
    netif_set_link_down(netif);
    #if LWIP_IPV4 && LWIP_ARP
    #ifdef LUAT_USE_NETDRV_LWIP_ARP
    if (netif->flags & NETIF_FLAG_ETHARP) {
        luat_netdrv_etharp_cleanup_netif(netif);
    }
    #endif
    #endif /* LWIP_IPV4 && LWIP_ARP */

    #if LWIP_IPV6
    nd6_cleanup_netif(netif);
    #endif /* LWIP_IPV6 */
}

// DHCP操作

int luat_netdrv_dhcp_opt(luat_netdrv_t* drv, void* userdata, int enable) {
    if (drv->dhcp_enable == enable) {
        return 0;
    }
    // cfg->dhcp = (uint8_t)enable;
    drv->dhcp_enable = (uint8_t)enable;
    if (drv->netif == NULL) {
        return 0;
    }
    if (enable) {
        tcpip_callback_with_block(luat_netdrv_dhcp_client_start, drv, 0);
    }
    else {
        tcpip_callback_with_block(luat_netdrv_dhcp_client_stop, drv, 0);
    }
    return 0;
}



int luat_netdrv_is_ready(int id) {
    int ret = 0;
    luat_netdrv_t* netdrv = NULL;
    netdrv = luat_netdrv_get(id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        return 0;
    }

    ret = netif_is_link_up(netdrv->netif);
    ret &= netif_is_up(netdrv->netif);
    #if LUAT_USE_NETDRV_IPV6
    // IPv4 非 0, 或者存在有效的 IPv6 地址, 都算就绪
    if (ip_addr_isany(&netdrv->netif->ip_addr)
        && !net_lwip2_ipv6_is_ready(id)) {
        ret = 0;
    }
    #else
    ret &= !ip_addr_isany(&netdrv->netif->ip_addr);
    #endif
    // 对于移动网络，还要检查注册状态
    #ifdef LUAT_USE_MOBILE
    if (NW_ADAPTER_INDEX_LWIP_GPRS == id && !luat_mobile_is_ip_ready()) {
        return 0;
    }
    #endif
    return ret;
}

#ifdef TYPE_EC718M
extern void soc_info(const char *fmt, ...);
#define LUAT_DBG_PRINT(...) soc_info(__VA_ARGS__)
#else
#define LUAT_DBG_PRINT(...)
#endif


int luat_netdrv_simple_stat(void) {
    // 特殊处理
    uint32_t stat = 0;
    luat_netdrv_t* netdrv = NULL;
    char ip[64] = {0};
    char gw[64] = {0};
    char nm[64] = {0};
    for (size_t i = 0; i < NW_ADAPTER_QTY; i++)
    {
        if (luat_netdrv_is_ready(i)) {
            stat |= (1 << i);
        }
        netdrv = luat_netdrv_get(i);
        if (netdrv && netdrv->netif) {
            ipaddr_ntoa_r(&netdrv->netif->ip_addr, ip, 64);
            ipaddr_ntoa_r(&netdrv->netif->gw, gw, 64);
            ipaddr_ntoa_r(&netdrv->netif->netmask, nm, 64);
            LUAT_DBG_PRINT("+NETDRV: %d,%s,%s,%s", i, ip, gw, nm);
        }
    }
    LUAT_DBG_PRINT("+NETSTAT: 0x%08X,%d", stat, network_register_get_default());
    return 1;
}
