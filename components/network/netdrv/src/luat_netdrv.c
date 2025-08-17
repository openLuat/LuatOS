#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_mem.h"
#include "luat_mcu.h"

#ifdef LUAT_USE_AIRLINK
#include "luat_airlink.h"
#endif

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

static luat_netdrv_t* drvs[NW_ADAPTER_QTY];

uint32_t g_netdrv_debug_enable;

luat_netdrv_t* luat_netdrv_ch390h_setup(luat_netdrv_conf_t *conf);
luat_netdrv_t* luat_netdrv_uart_setup(luat_netdrv_conf_t *conf);
luat_netdrv_t* luat_netdrv_whale_setup(luat_netdrv_conf_t *conf);

luat_netdrv_t* luat_netdrv_setup(luat_netdrv_conf_t *conf) {
    if (conf->id < 0 || conf->id >= NW_ADAPTER_QTY) {
        return NULL;
    }
    int ret = 0;
    if (drvs[conf->id] == NULL) {
        // 注册新的设备?
        #ifdef __LUATOS__
        #ifdef LUAT_USE_NETDRV_CH390H
        if (conf->impl == 1) { // CH390H
            drvs[conf->id] = luat_netdrv_ch390h_setup(conf);
            return drvs[conf->id];
        }
        #endif
        #ifdef LUAT_USE_AIRLINK
        if (conf->impl == 64) { // WHALE
            drvs[conf->id] = luat_netdrv_whale_setup(conf);
            return drvs[conf->id];
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
    if (drvs[id] == NULL) {
        return -1;
    }
    return drvs[id]->ready(drvs[id], drvs[id]->userdata);
}

int luat_netdrv_register(int32_t id, luat_netdrv_t* drv) {
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

static char tmpbuff[1024];
void luat_netdrv_print_pkg(const char* tag, uint8_t* buff, size_t len) {
    if (len > 511) {
        len = 511;
    }
    memset(tmpbuff, 0, 1024);
    for (size_t i = 0; i < len; i++)
    {
        sprintf(tmpbuff + i * 2, "%02X", buff[i]);
    }
    LLOGD("%s %s", tag, tmpbuff);
}

#define NAPT_CHKSUM_16BIT_LEN        sizeof(uint16_t)

__NETDRV_CODE_IN_RAM__ uint32_t alg_hdr_16bitsum(const uint16_t *buff, uint16_t len)
{
    uint32_t sum = 0;

    uint16_t *pos = (uint16_t *)buff;
    uint16_t remainder_size = len;

    while (remainder_size > 1)
    {
        sum += *pos ++;
        remainder_size -= NAPT_CHKSUM_16BIT_LEN;
    }

    if (remainder_size > 0)
    {
        sum += *(uint8_t*)pos;
    }

    return sum;
}

__NETDRV_CODE_IN_RAM__ uint16_t alg_iphdr_chksum(const uint16_t *buff, uint16_t len)
{
    uint32_t sum = alg_hdr_16bitsum(buff, len);

    sum = (sum >> 16) + (sum & 0xFFFF);
    sum += (sum >> 16);

    return (uint16_t)(~sum);
}

__NETDRV_CODE_IN_RAM__ uint16_t alg_tcpudphdr_chksum(uint32_t src_addr, uint32_t dst_addr, uint8_t proto, const uint16_t *buff, uint16_t len)
{
    uint32_t sum = 0;

    sum += (src_addr & 0xffffUL);
    sum += ((src_addr >> 16) & 0xffffUL);
    sum += (dst_addr & 0xffffUL);
    sum += ((dst_addr >> 16) & 0xffffUL);
    sum += (uint32_t)htons((uint16_t)proto);
    sum += (uint32_t)htons(len);

    sum += alg_hdr_16bitsum(buff, len);

    sum = (sum >> 16) + (sum & 0xFFFF);
    sum += (sum >> 16);

    return (uint16_t)(~sum);
}


void luat_netdrv_netif_input(void* args) {
    netdrv_pkg_msg_t* ptr = (netdrv_pkg_msg_t*)args;
    if (ptr == NULL) {
        return;
    }
    if (ptr->len == 0) {
        LLOGE("什么情况,ptr->len == 0?!");
        return;
    }
    struct pbuf* p = pbuf_alloc(PBUF_TRANSPORT, ptr->len, PBUF_RAM);
    if (p == NULL) {
        LLOGD("分配pbuf失败!!! %d", ptr->len);
        luat_heap_free(ptr);
        return;
    }
    if (p->tot_len != ptr->len) {
        LLOGE("p->tot_len != ptr->len %d %d", p->tot_len, ptr->len);
        return;
    }
    pbuf_take(p, ptr->buff, ptr->len);
    if (g_netdrv_debug_enable) {
        luat_netdrv_print_pkg("收到IP数据,注入到netif", ptr->buff, ptr->len);
    }
    int ret = ptr->netif->input(p, ptr->netif);
    if (ret) {
        LLOGW("netif->input ret %d", ret);
        pbuf_free(p);
    }
    luat_heap_free(ptr);
}

int luat_netdrv_netif_input_proxy(struct netif * netif, uint8_t* buff, uint16_t len) {
    netdrv_pkg_msg_t* ptr = luat_heap_malloc(sizeof(netdrv_pkg_msg_t) + len);
    if (ptr == NULL) {
        LLOGE("收到rx数据,但内存已满, 无法处理只能抛弃 %d", len - 4);
        return 1; // 需要处理下一个包
    }
    memcpy(ptr->buff, buff, len);
    ptr->netif = netif;
    ptr->len = len;
    // uint64_t tbegin = luat_mcu_tick64();
    int ret = tcpip_callback_with_block(luat_netdrv_netif_input, ptr, 1);
    // uint64_t tend = luat_mcu_tick64();
    // uint64_t tused = (tend - tbegin) / luat_mcu_us_period();
    // if (tused > 50) {
    //     LLOGD("tcpip_callback!! use %lld us", tused);
    // }
    if (ret) {
        luat_heap_free(ptr);
        LLOGE("tcpip_callback 返回错误!!! ret %d", ret);
        return 1;
    }
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
