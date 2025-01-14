#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_ch390h.h"
#include "luat_netdrv_napt.h"
#include "luat_ch390h.h"
#include "luat_malloc.h"
#include "luat_spi.h"
#include "luat_gpio.h"
#include "net_lwip2.h"
#include "luat_ulwip.h"
#include "lwip/tcp.h"
#include "lwip/sys.h"
#include "lwip/tcpip.h"
#include "lwip/pbuf.h"

#include "luat_rtos.h"

#define LUAT_LOG_TAG "ch390x"
#include "luat_log.h"



typedef struct pkg_msg
{
    struct netif * netif;
    uint16_t len;
    uint8_t buff[4];
}pkg_msg_t;

static void print_erp_pkg(uint8_t* buff, uint16_t len);

extern ch390h_t* ch390h_drvs[MAX_CH390H_NUM];

static luat_rtos_task_handle ch390h_task_handle;

static int is_waiting;

static int ch390h_bootup(ch390h_t* ch) {
    // 初始化SPI设备, 由外部代码初始化, 因为不同bsp的速度不一样, 就不走固定值了

    // 初始化CS脚
    luat_gpio_t gpio = {0};
    gpio.pin = ch->cspin;
    gpio.mode = LUAT_GPIO_OUTPUT;
    gpio.pull = LUAT_GPIO_PULLUP;
    gpio.irq = 1;
    luat_gpio_setup(&gpio);

    // TODO 初始化INT脚

    // 初始化dhcp相关资源
    ch->ulwip.netif = ch->netif;
    ch->ulwip.adapter_index = ch->adapter_id;
    return 0;
}

static void ch390h_dataout(void* userdata, uint8_t* buff, uint16_t len) {
    ch390h_t* ch = (ch390h_t*)userdata;
    struct pbuf *p = NULL;
    p = pbuf_alloc(PBUF_TRANSPORT, len, PBUF_RAM);
    if (p == NULL) {
        LLOGE("内存不足, 无法传递pbuf");
        return;
    }
    pbuf_take(p, buff, len);
    for (size_t j = 0; j < CH390H_MAX_TX_NUM; j++)
    {
        if (ch->txqueue[j] == NULL) {
            ch->txqueue[j] = p;
            // LLOGD("找到空位了 %d", j);
            if (is_waiting) {
                luat_rtos_event_send(ch390h_task_handle, 0, 0, 0, 0, 0);
            }
            return;
        }
    }
    pbuf_free(p);
    return;
}


static err_t netif_output(struct netif *netif, struct pbuf *p) {
    // LLOGD("lwip待发送数据 %p %d", p, p->tot_len);
    ch390h_t* ch = NULL;
    struct pbuf *p2 = NULL;

    for (size_t i = 0; i < MAX_CH390H_NUM; i++)
    {
        ch = ch390h_drvs[i];
        if (ch == NULL) {
            continue;
        }
        if (ch->netif != netif) {
            continue;
        }
        for (size_t j = 0; j < CH390H_MAX_TX_NUM; j++)
        {
            if (ch->txqueue[j] == NULL) {
                p2 = pbuf_alloc(PBUF_TRANSPORT, p->tot_len, PBUF_RAM);
                if (p2 == NULL) {
                    LLOGE("内存不足, 无法传递pbuf");
                    return 0;
                }
                pbuf_copy(p2, p);
                // TODO 改成消息传送
                ch->txqueue[j] = p2;
                // LLOGD("找到空位了 %d", j);
                if (is_waiting) {
                    luat_rtos_event_send(ch390h_task_handle, 0, 0, 0, 0, 0);
                }
                return 0;
            }
        }
    }
    return 0;
}

static err_t luat_netif_init(struct netif *netif) {
    ch390h_t* ch = (ch390h_t*)netif->state;
    netif->linkoutput = netif_output;
    netif->output     = ulwip_etharp_output;
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
    memcpy(netif->hwaddr, ch->hwaddr, ETH_HWADDR_LEN);
    netif->hwaddr_len = ETH_HWADDR_LEN;
    net_lwip2_set_netif(ch->adapter_id, ch->netif);
    net_lwip2_register_adapter(ch->adapter_id);
    netif_set_up(ch->netif);
    ch->status++;
    LLOGD("luat_netif_init 执行完成 %d", ch->status);
    return 0;
}

static void netdrv_netif_input(void* args) {
    pkg_msg_t* ptr = (pkg_msg_t*)args;
    struct pbuf* p = pbuf_alloc(PBUF_TRANSPORT, ptr->len, PBUF_RAM);
    if (p == NULL) {
        LLOGD("分配pbuf失败!!! %d", ptr->len);
        luat_heap_free(ptr);
        return;
    }
    pbuf_take(p, ptr->buff, ptr->len);
    // LLOGD("数据注入到netif " MACFMT, MAC_ARG(p->payload));
    int ret = ptr->netif->input(p, ptr->netif);
    if (ret) {
        pbuf_free(p);
    }
    luat_heap_free(ptr);
}

static int check_vid_pid(ch390h_t* ch) {
    uint8_t buff[6] = {0};
    luat_ch390h_read_vid_pid(ch, buff);
    if (0 == memcmp(buff, "\x00\x01\x51\x91", 4)) {
        LLOGE("读取vid/pid失败!!! %d %d %02X%02X%02X%02X", ch->spiid, ch->cspin, buff[0], buff[1], buff[2], buff[3]);
        return -1;
    }
    return 0;
}


static int task_loop_one(ch390h_t* ch) {
    uint8_t buff[16] = {0};
    int ret = 0;
    uint16_t len = 0;
    
    // LLOGD("状态 spi %d cs %d stat %d", ch->spiid, ch->cspin, ch->status);
    // 首先, 判断设备状态
    if (ch->status == 0) {
        // 状态0, 代表刚加入, 还没成功通信过!!
        ch390h_bootup(ch);
        luat_ch390h_software_reset(ch);
        if (check_vid_pid(ch)) {
            return 0;
        }
        // 读取MAC地址, 开始初始化
        luat_ch390h_read_mac(ch, buff);
        LLOGD("初始化MAC %02X%02X%02X%02X%02X%02X", buff[0], buff[1], buff[2], buff[3], buff[4], buff[5]);
        // TODO 判断mac是否合法
        memcpy(ch->hwaddr, buff, 6);
        netif_add(ch->netif, IP4_ADDR_ANY4, IP4_ADDR_ANY4, IP4_ADDR_ANY4, ch, luat_netif_init, netif_input);
        ch->status++;
        ch->netdrv->dataout = ch390h_dataout;
        luat_ch390h_basic_config(ch);
        luat_ch390h_set_phy(ch, 1);
        luat_ch390h_set_rx(ch, 1);
        return 0; // 等待下一个周期
    }
    if (check_vid_pid(ch)) {
        // TODO 是不是应该恢复到状态0
        return 0;
    }
    if (ch->status != 2) {
        // 处于中间状态, 暂不管它
        LLOGI("wait for netif init %d %d", ch->spiid, ch->cspin);
        return 0;
    }

    // 然后判断link的状态
    luat_ch390h_read(ch, 0x01, 1, buff);
    uint8_t NSR = buff[0];
    // LLOGD("网络状态寄存器 %02X %d", buff[0], (NSR & (1 << 6)) != 0);
    if (0 == (NSR & (1 << 6))) {
        // 网线没插, 或者phy没有上电
        // 首先, 确保phy上电
        luat_ch390h_read(ch, 0x1F, 1, buff);
        // LLOGD("PHY状态 %02X", buff[0]);
        luat_ch390h_set_phy(ch, 1);
        luat_ch390h_set_rx(ch, 1);
        if (netif_is_link_up(ch->netif)) {
            netif_set_link_down(ch->netif);
            net_lwip2_set_link_state(ch->adapter_id, 0);
            if (ch->dhcp) {
                // 停止dhcp定时器
                ulwip_dhcp_client_stop(&ch->ulwip);
            }
        }
        return 0; // 网络断了, 没那么快恢复的, 等吧
    }

    if (!netif_is_link_up(ch->netif)) {
        netif_set_link_up(ch->netif);
        net_lwip2_set_link_state(ch->adapter_id, 1);
        if (ch->dhcp) {
            // 启动dhcp定时器
            ulwip_dhcp_client_start(&ch->ulwip);
        }
    }

    // 有没有数据待读取
    if (NSR & 0x01) {
        ret = luat_ch390h_read_pkg(ch, ch->rxbuff, &len);
        if (ret) {
            LLOGE("读数据包报错,立即复位模组 ret %d spi %d cs %d", ret, ch->spiid, ch->cspin);
            luat_ch390h_write_reg(ch, 0x05, 0);
            luat_ch390h_write_reg(ch, 0x55, 1);
            luat_ch390h_write_reg(ch, 0x75, 0);
            luat_rtos_task_sleep(1); // 是否真的需要呢??
            luat_ch390h_basic_config(ch);
            luat_ch390h_set_phy(ch, 1);
            luat_ch390h_set_rx(ch, 1);
            return 0;
        }
        if (len > 0) {
            NETDRV_STAT_IN(ch->netdrv, len);
            // 收到数据, 开始后续处理
            print_erp_pkg(ch->rxbuff, len);
            // 先经过netdrv过滤器
            // LLOGD("ETH数据包 " MACFMT " " MACFMT " %02X%02X", MAC_ARG(ch->rxbuff), MAC_ARG(ch->rxbuff + 6), ((uint16_t)ch->rxbuff[6]) + (((uint16_t)ch->rxbuff[7])));
            ret = luat_netdrv_napt_pkg_input(ch->adapter_id, ch->rxbuff, len - 4);
            if (ret == 0) {

            }
            
            // 如果返回值是0, 那就是继续处理, 输入到netif
            pkg_msg_t* ptr = luat_heap_malloc(sizeof(pkg_msg_t) + len - 4);
            if (ptr == NULL) {
                LLOGE("收到rx数据,但内存已满, 无法处理只能抛弃 %d", len - 4);
                return 1; // 需要处理下一个包
            }
            memcpy(ptr->buff, ch->rxbuff, len - 4);
            ptr->netif = ch->netif;
            ptr->len = len - 4;
            ret = tcpip_callback(netdrv_netif_input, ptr);
            if (ret) {
                luat_heap_free(ptr);
                LLOGE("tcpip_callback 返回错误!!! ret %d", ret);
                return 1;
            }
        }
        // 很好, RX数据处理完成了
    }
    else {
        // LLOGD("没有数据待读取");
    }

    // 那有没有需要发送的数据呢?
    struct pbuf* p = NULL;
    int has_tx = 0;
    for (size_t i = 0; i < CH390H_MAX_TX_NUM; i++)
    {
        p = ch->txqueue[i];
        if (p == NULL) {
            continue;
        }
        // LLOGD("txqueue收到数据包 %p", p);
        len = p->tot_len;
        pbuf_copy_partial(p, ch->txbuff, len, 0);
        pbuf_free(p);
        ch->txqueue[i] = NULL;
        luat_ch390h_write_pkg(ch, ch->txbuff, len);
        has_tx = 1;
    }
    
    // 这一轮处理完成了
    // 如果rx有数据, 那就不要等待, 立即开始下一轮
    if (NSR & 0x01 || has_tx) {
        return 1;
    }

    return 0;
}

static int task_loop() {
    int ret = 0;
    for (size_t i = 0; i < MAX_CH390H_NUM; i++)
    {
        if (ch390h_drvs[i] != NULL && ch390h_drvs[i]->netif != NULL) {
            ret += task_loop_one(ch390h_drvs[i]);
        }
    }
    return ret;
}

static void ch390_task_main(void* args) {
    (void)args;
    luat_event_t evt;
    while (1) {
        // LLOGD("开始新的循环");
        // luat_rtos_task_sleep(10);
        if (task_loop() == 0) {
            is_waiting = 1;
            luat_rtos_event_recv(ch390h_task_handle, 0, &evt, NULL, 10);
            is_waiting = 0;
        }
    }
}

void luat_ch390h_task_start(void) {
    int ret = 0;
    if (ch390h_task_handle == NULL) {
        ret = luat_rtos_task_create(&ch390h_task_handle, 8*1024, 50, "ch390h", ch390_task_main, NULL, 1024);
        if (ret) {
            LLOGE("task create fail %d", ret);
            return;
        }
        LLOGD("task started");
    }
}

// 辅助函数
static void print_erp_pkg(uint8_t* buff, uint16_t len) {
    // LLOGD("pkg len %d head " MACFMT " " MACFMT, len, MAC_ARG(buff), MAC_ARG(buff+6));
    if (len < 40 || len > 1600) {
        LLOGW("非法的pkg长度 %d", len);
        return;
    }
    struct eth_hdr* eth = (struct eth_hdr*)buff;
    struct ip_hdr* iphdr = (struct ip_hdr*)(buff + SIZEOF_ETH_HDR);
    struct etharp_hdr* arp = (struct etharp_hdr*)(buff + SIZEOF_ETH_HDR);
    // LLOGD("eth " MACFMT " -> " MACFMT " tp %02X", MAC_ARG(eth->src.addr), MAC_ARG(eth->dest.addr), (u16_t)lwip_htons(eth->type));
    switch (eth->type) {
        case PP_HTONS(ETHTYPE_IP):
            // LLOGD("  ipv%d %d len %d", (u16_t)IPH_V(iphdr), (u16_t)IPH_PROTO(iphdr),(u16_t)IPH_LEN(iphdr));
            break;
        case PP_HTONS(ETHTYPE_ARP):
            // LLOGD("  arp proto %d", arp->proto);
            break;
    }
}
