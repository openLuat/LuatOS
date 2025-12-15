#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_ch390h.h"
#include "luat_ch390h.h"
#include "luat_malloc.h"
#include "luat_spi.h"
#include "luat_gpio.h"
#include "net_lwip2.h"
#include "luat_ulwip.h"
#include "lwip/tcp.h"
#include "lwip/sys.h"
#include "lwip/tcpip.h"
#include "luat_ulwip.h"

#define LUAT_LOG_TAG "ch390h"
#include "luat_log.h"

ch390h_t* ch390h_drvs[MAX_CH390H_NUM]; // 最多支持5个CH390H同时操作

#ifdef LUAT_USE_NETDRV_LWIP_ARP
extern err_t luat_netdrv_netif_input_main(struct pbuf *p, struct netif *inp);
extern err_t luat_netdrv_etharp_output(struct netif *netif, struct pbuf *q, const ip4_addr_t *ipaddr);
#else
#define luat_netdrv_netif_input_main netif_input
#define luat_netdrv_etharp_output ulwip_etharp_output
#endif

extern err_t ch390_netif_output(struct netif *netif, struct pbuf *p);

// 检查设备是否已注册
static int check_device_duplicate(ch390h_t* ch) {
    for (size_t i = 0; i < MAX_CH390H_NUM; i++) {
        if (ch390h_drvs[i] == NULL) continue;
        
        if (ch390h_drvs[i]->adapter_id == ch->adapter_id) {
            LLOGE("已经注册过相同的adapter_id %d", ch->adapter_id);
            return -1;
        }
        if (ch390h_drvs[i]->spiid == ch->spiid && ch390h_drvs[i]->cspin == ch->cspin) {
            LLOGE("已经注册过相同的spi+cs %d %d", ch->spiid, ch->cspin);
            return -2;
        }
        if (ch390h_drvs[i]->intpin != 255 && ch390h_drvs[i]->intpin == ch->intpin) {
            LLOGE("已经注册过相同的int脚 %d", ch->intpin);
            return -3;
        }
    }
    return 0;
}

static int ch390h_ctrl(luat_netdrv_t* drv, void* userdata, int cmd, void* buff, size_t len) {
    ch390h_t* ch = (ch390h_t*)userdata;
    if (ch == NULL) {
        return -2;
    }
    switch (cmd) {
        case LUAT_NETDRV_CTRL_RESET:
            if (ch->status == 2) {
                ch->status = 3;
            }
            else {
                LLOGD("ch390并非处于已初始化状态, 不能重置");
                return -3;
            }
            return 0;
    }
    return 0;
}


static err_t ch390_netif_init(struct netif *netif) {
    ch390h_t* ch = (ch390h_t*)netif->state;
    netif->linkoutput = ch390_netif_output;
    netif->output     = luat_netdrv_etharp_output;
    #if ENABLE_PSIF
    netif->primary_ipv4_cid = LWIP_PS_INVALID_CID;
    #endif
    #if LWIP_IPV6
    netif->output_ip6 = ethip6_output;
    #if ENABLE_PSIF
    netif->primary_ipv6_cid = LWIP_PS_INVALID_CID;
    #endif
    #endif
    netif->mtu        = 1460;
    netif->flags      = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP | NETIF_FLAG_ETHERNET | NETIF_FLAG_IGMP | NETIF_FLAG_MLD6;
    netif->hwaddr_len = ETH_HWADDR_LEN;
    netif_set_up(ch->netdrv->netif);
    net_lwip2_set_netif(ch->adapter_id, ch->netdrv->netif);
    net_lwip2_register_adapter(ch->adapter_id);
    ch->status = 0;
    LLOGD("adapter %d netif init ok", ch->adapter_id);
    return 0;
}

static void ch390_lwip_init(void* args) {
    ch390h_t* ch = (ch390h_t*)args;
    netif_add(ch->netdrv->netif, IP4_ADDR_ANY4, IP4_ADDR_ANY4, IP4_ADDR_ANY4, ch, ch390_netif_init, luat_netdrv_netif_input_main);
}

luat_netdrv_t* luat_netdrv_ch390h_setup(luat_netdrv_conf_t *cfg) {

    LLOGD("注册CH390H设备(%d) SPI id %d cs %d irq %d", cfg->id, cfg->spiid, cfg->cspin, cfg->irqpin);
    ch390h_t* ch = luat_heap_malloc(sizeof(ch390h_t));
    struct netif* netif = luat_heap_malloc(sizeof(struct netif));
    luat_netdrv_t* drv = luat_heap_malloc(sizeof(luat_netdrv_t));
    ulwip_ctx_t* ulwip = luat_heap_malloc(sizeof(ulwip_ctx_t));
    if (ch == NULL || netif == NULL || drv == NULL || ulwip == NULL) {
        LLOGD("分配CH390H内存失败!!!");
        goto clean;
    }
    
    memset(ch, 0, sizeof(ch390h_t));
    memset(netif, 0, sizeof(struct netif));
    memset(drv, 0, sizeof(luat_netdrv_t));
    memset(ulwip, 0, sizeof(ulwip_ctx_t));

    ch->txtmp = NULL;  // 延迟分配
    ch->pkg_mem_type = LUAT_HEAP_AUTO;  // 默认使用AUTO内存
    ch->rx_error_count = 0;
    ch->tx_busy_count = 0;
    ch->vid_pid_error_count = 0;
    ch->last_reset_time = 0;
    ch->total_reset_count = 0;
    ch->total_tx_drop = 0;
    ch->total_rx_drop = 0;
    ch->flow_control = 0;
    ch->adapter_id = cfg->id;
    ch->cspin = cfg->cspin;
    ch->spiid = cfg->spiid;
    ch->intpin = cfg->irqpin;
    // ch->dhcp = 1;
    ulwip->dhcp_enable = 1;
    ulwip->adapter_index = cfg->id;
    ulwip->netif = netif;

    drv->ulwip = ulwip;

    // 检查设备是否重复注册
    if (check_device_duplicate(ch) != 0) {
        goto clean;
    }

    // 查找空位并注册设备
    for (size_t i = 0; i < MAX_CH390H_NUM; i++)
    {
        if (ch390h_drvs[i] != NULL) {
            continue;
        }
        ch390h_drvs[i] = ch;
        // ch390h_drvs[i]->netif = netif;
        
        drv->netif = netif;
        drv->userdata = ch390h_drvs[i];
        drv->id = ch->adapter_id;
        drv->dataout = NULL;
        drv->boot = NULL;
        drv->dhcp = luat_netdrv_dhcp_opt;
        drv->ctrl = ch390h_ctrl;
        ch->netdrv = drv;
        tcpip_callback_with_block((tcpip_callback_fn)ch390_lwip_init, ch, 1);
        ch->init_step = 1; // 已经完成基础初始化
        extern void luat_ch390h_task_start(void);
        luat_ch390h_task_start();
        LLOGD("注册完成 adapter %d spi %d cs %d irq %d", ch->adapter_id, ch->spiid, ch->cspin, ch->intpin);
        return drv;
    }
    LLOGE("已经没有CH390H空位了!!!");
clean:
    if (ch) {
        if (ch->txtmp) luat_heap_free(ch->txtmp);
        luat_heap_free(ch);
    }
    if (netif) luat_heap_free(netif);
    if (drv) luat_heap_free(drv);
    if (ulwip) luat_heap_free(ulwip);
    return NULL;
}
