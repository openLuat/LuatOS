#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_ch390h.h"
#include "luat_netdrv_napt.h"
#include "luat_ch390h.h"
#include "luat_malloc.h"
// #include "luat_spi.h"
#include "luat_gpio.h"
#include "net_lwip2.h"
#include "luat_ulwip.h"
#include "lwip/tcp.h"
#include "lwip/sys.h"
#include "lwip/tcpip.h"
#include "lwip/pbuf.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_wdt.h"

#include "luat_rtos.h"

#define LUAT_LOG_TAG "netdrv.ch390x"
#include "luat_log.h"

typedef struct pkg_evt
{
    uint8_t id;
    luat_ch390h_cstring_t* cs;
    ch390h_t *ch;
}pkg_evt_t;


// static void print_erp_pkg(uint8_t* buff, uint16_t len);

extern ch390h_t* ch390h_drvs[MAX_CH390H_NUM];

static luat_rtos_task_handle ch390h_task_handle;
static luat_rtos_queue_t qt;

static uint64_t warn_vid_pid_tm;
static uint64_t warn_msg_tm;

static uint32_t s_ch390h_mode; // 0 -- PULL 模式, 1 == IRQ 模式

static int pkg_mem_type = LUAT_HEAP_AUTO;

static int ch390h_irq_cb(void *data, void *args) {
    uint32_t len = 0;
    luat_rtos_queue_get_cnt(qt, &len);
    if (len > 4) {
        return 0;
    }
    pkg_evt_t evt = {
        .id = 2
    };
    luat_rtos_queue_send(qt, &evt, sizeof(pkg_evt_t), 0);
    return 0;
}

static int ch390h_bootup(ch390h_t* ch) {
    if (ch->ulwip.netif != NULL) {
        return 0;
    }
    // 初始化SPI设备, 由外部代码初始化, 因为不同bsp的速度不一样, 就不走固定值了
    luat_gpio_cfg_t gpio_cfg = {0};

    // 初始化CS脚
    luat_gpio_t gpio = {0};
    gpio.pin = ch->cspin;
    gpio.mode = LUAT_GPIO_OUTPUT;
    gpio.pull = LUAT_GPIO_PULLUP;
    gpio.irq = 1;
    luat_gpio_setup(&gpio);

    // 初始化INT脚
    if (ch->intpin != 0xff) {
        luat_gpio_set_default_cfg(&gpio_cfg);
        gpio_cfg.pin = ch->intpin;
        gpio_cfg.mode = LUAT_GPIO_IRQ;
        gpio_cfg.irq_type = LUAT_GPIO_RISING_IRQ;
        gpio_cfg.pull = 0;
        gpio_cfg.irq_cb = ch390h_irq_cb;
        luat_gpio_open(&gpio_cfg);
        LLOGI("enable irq mode in pin %d", ch->intpin);
        s_ch390h_mode = 1;
    }
    else {
        // LLOGI("enable pull mode, use pool mode");
    }

    // 初始化dhcp相关资源
    ch->ulwip.netif = ch->netif;
    ch->ulwip.adapter_index = ch->adapter_id;
    return 0;
}

static luat_ch390h_cstring_t* new_cstring(uint16_t len) {
    size_t total = 0;
    size_t used = 0;
    size_t max_used = 0;
    luat_meminfo_opt_sys(pkg_mem_type, &total, &used, &max_used);
    if (total > 0 && total - used > 32*1024) { // 最少留32k给系统用
        luat_ch390h_cstring_t* cs = luat_heap_opt_malloc(pkg_mem_type, sizeof(luat_ch390h_cstring_t) + len - 4);
        if (cs == NULL) {
            LLOGE("有剩余内存不多但分配失败! total %d used %d max_used %d len %d", total, used, max_used, len);
        }
        return cs;
    }
    LLOGE("剩余内存不多了,抛弃数据包 total %d used %d max_used %d len %d", total, used, max_used, len);
    return NULL;
}

static void send_msg_cs(ch390h_t* ch, luat_ch390h_cstring_t* cs) {
    uint32_t len = 0;
    luat_rtos_queue_get_cnt(qt, &len);
    uint64_t tm;
    if (len >= 1000) {
        tm = luat_mcu_tick64_ms();
        if (tm - warn_msg_tm > 1000) {
            warn_msg_tm = tm;
            LLOGW("太多待处理消息了!!! %d", len);
        }
        luat_heap_opt_free(pkg_mem_type, cs);
        return;
    }
    if (len > 512) {
        tm = luat_mcu_tick64_ms();
        if (tm - warn_msg_tm > 1000) {
            warn_msg_tm = tm;
            LLOGD("当前消息数量 %d", len);
        }
    }
    
    pkg_evt_t evt = {
        .id = 1,
        .cs = cs,
        .ch = ch
    };
    int ret = luat_rtos_queue_send(qt, &evt, sizeof(pkg_evt_t), 0);
    if (ret) {
        LLOGE("消息发送失败 %d", ret);
        luat_heap_opt_free(pkg_mem_type, cs);
    }
}

static void ch390h_dataout(luat_netdrv_t* drv, void* userdata, uint8_t* buff, uint16_t len) {
    ch390h_t* ch = (ch390h_t*)userdata;
    luat_ch390h_cstring_t* cs = new_cstring(len);
    if (cs == NULL) {
        return;
    }
    cs->len = len;
    memcpy(cs->buff, buff, len);
    send_msg_cs(ch, cs);
}

static void ch390h_dataout_pbuf(ch390h_t* ch, struct pbuf* p) {
    luat_ch390h_cstring_t* cs = new_cstring(p->tot_len);
    if (cs == NULL) {
        return;
    }
    cs->len = p->tot_len;
    pbuf_copy_partial(p, cs->buff, p->tot_len, 0);
    send_msg_cs(ch, cs);
}


static err_t netif_output(struct netif *netif, struct pbuf *p) {
    // LLOGD("lwip待发送数据 %p %d", p, p->tot_len);
    ch390h_t* ch = NULL;

    for (size_t i = 0; i < MAX_CH390H_NUM; i++)
    {
        ch = ch390h_drvs[i];
        if (ch == NULL) {
            continue;
        }
        if (ch->netif != netif) {
            continue;
        }
        ch390h_dataout_pbuf(ch, p);
        break;
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
    netdrv_pkg_msg_t* ptr = (netdrv_pkg_msg_t*)args;
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
    if (0 != memcmp(buff, "\x00\x1C\x51\x91", 4)) {
        uint64_t tnow = luat_mcu_tick64_ms();
        if (tnow - warn_vid_pid_tm > 2000) {
            LLOGE("读取vid/pid失败!请检查接线!! %d %d %02X%02X%02X%02X", ch->spiid, ch->cspin, buff[0], buff[1], buff[2], buff[3]);
            warn_vid_pid_tm = tnow;
        }
        return -1;
    }
    // LLOGE("读取vid/pid成功!!! %d %d %02X%02X%02X%02X", ch->spiid, ch->cspin, buff[0], buff[1], buff[2], buff[3]);
    return 0;
}


static int task_loop_one(ch390h_t* ch, luat_ch390h_cstring_t* cs) {
    uint8_t buff[32] = {0};
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
        luat_rtos_task_sleep(10);
        // 读取MAC地址, 开始初始化
        luat_ch390h_read_mac(ch, buff);
        for (size_t i = 0; i < 6; i++)
        {
            if (buff[i] == 0) {
                LLOGD("非法MAC地址 %02X%02X%02X%02X%02X%02X", buff[0], buff[1], buff[2], buff[3], buff[4], buff[5]);
                return 0;
            }
        }
        luat_ch390h_read_mac(ch, buff + 6);
        luat_ch390h_read_mac(ch, buff + 12);
        if (memcmp(buff, buff+6, 6) || memcmp(buff, buff+12, 6)) {
            LLOGE("读取3次mac地址不匹配!!! %02X%02X%02X%02X%02X%02X", buff[0], buff[1], buff[2], buff[3], buff[4], buff[5]);
            return 0;
        }
        
        LLOGD("初始化MAC %02X%02X%02X%02X%02X%02X", buff[0], buff[1], buff[2], buff[3], buff[4], buff[5]);
        // TODO 判断mac是否合法
        memcpy(ch->hwaddr, buff, 6);
        netif_add(ch->netif, IP4_ADDR_ANY4, IP4_ADDR_ANY4, IP4_ADDR_ANY4, ch, luat_netif_init, netif_input);
        ch->status++;
        ch->netdrv->dataout = ch390h_dataout;
        luat_ch390h_basic_config(ch);
        luat_ch390h_set_phy(ch, 1);
        luat_ch390h_set_rx(ch, 1);
        if (ch->intpin != 255) {
            luat_ch390h_write_reg(ch, 0x7F, 1); // 开启接收中断
        }
        return 0; // 等待下一个周期
    }
    if (check_vid_pid(ch)) {
        // TODO 是不是应该恢复到状态0
        return 0;
    }
    if (ch->status == 3) {
        LLOGD("request ch390 reset spi%d cs%d", ch->spiid, ch->cspin);
        luat_ch390h_software_reset(ch);
        ch->status = 2;
        luat_rtos_task_sleep(10);
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
        // luat_ch390h_read(ch, 0x1F, 1, buff);
        // LLOGD("PHY状态 %02X", buff[0]);
        luat_ch390h_set_phy(ch, 1);
        luat_ch390h_set_rx(ch, 1);
        if (netif_is_link_up(ch->netif)) {
            LLOGI("link is down %d %d", ch->spiid, ch->cspin);
            netif_set_link_down(ch->netif);
            ulwip_netif_ip_event(&ch->ulwip);
            if (ch->dhcp) {
                // 停止dhcp定时器
                ulwip_dhcp_client_stop(&ch->ulwip);
            }
        }
        return 0; // 网络断了, 没那么快恢复的, 等吧
    }

    if (!netif_is_link_up(ch->netif)) {
        LLOGI("link is up %d %d %s", ch->spiid, ch->cspin, (NSR & (1<<7)) ? "10M" : "100M");
        netif_set_link_up(ch->netif);
        ulwip_netif_ip_event(&ch->ulwip);
        if (ch->dhcp) {
            // 启动dhcp定时器
            ulwip_dhcp_client_start(&ch->ulwip);
        }
    }

    if (cs) {
        // LLOGD("数据写入 %p %d", cs->buff, cs->len);
        luat_ch390h_write_pkg(ch, cs->buff, cs->len);
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
            if (ch->intpin != 255) {
                luat_ch390h_write_reg(ch, 0x7F, 1); // 开启接收中断
            }
            return 0;
        }
        if (len > 0) {
            NETDRV_STAT_IN(ch->netdrv, len);
            // 收到数据, 开始后续处理
            //print_erp_pkg(ch->rxbuff, len);
            // 先经过netdrv过滤器
            // LLOGD("ETH数据包 " MACFMT " " MACFMT " %02X%02X", MAC_ARG(ch->rxbuff), MAC_ARG(ch->rxbuff + 6), ((uint16_t)ch->rxbuff[6]) + (((uint16_t)ch->rxbuff[7])));
            ret = luat_netdrv_napt_pkg_input(ch->adapter_id, ch->rxbuff, len - 4);
            // LLOGD("napt ret %d", ret);
            if (ret != 0) {
                // 不需要输入到LWIP了
                // LLOGD("napt说不需要注入lwip了");
            }
            else {
                // 如果返回值是0, 那就是继续处理, 输入到netif
                ret = luat_netdrv_netif_input_proxy(ch->netif, ch->rxbuff, len - 4);
                if (ret) {
                    LLOGE("luat_netdrv_netif_input_proxy 返回错误!!! ret %d", ret);
                    return 1;
                }
            }
        }
        // 很好, RX数据处理完成了
    }
    else {
        // LLOGD("没有数据待读取");
    }

    if (ch->intpin != 255) {
        luat_ch390h_write_reg(ch, 0x7E, 0x3F); // 清除中断
    }
    
    // 这一轮处理完成了
    // 如果rx有数据, 那就不要等待, 立即开始下一轮
    if (NSR & 0x01 || cs) {
        return 1;
    }

    return 0;
}

static int task_loop(ch390h_t *ch, luat_ch390h_cstring_t* cs) {
    int ret = 0;
    for (size_t i = 0; i < MAX_CH390H_NUM; i++)
    {
        if (ch390h_drvs[i] != NULL && ch390h_drvs[i]->netif != NULL) {
            ret += task_loop_one(ch390h_drvs[i], ch == ch390h_drvs[i] ? cs : NULL);
        }
    }
    if (ret) {
        uint32_t len = 0;
        pkg_evt_t evt = {0};
        luat_rtos_queue_get_cnt(qt, &len);
        if (len < 16) { // 插入空指令,马上执行下一次轮询
            luat_rtos_queue_send(qt, &evt, sizeof(pkg_evt_t), 0);
        }
    }
    return ret;
}

static int task_wait_msg(uint32_t timeout) {
    luat_ch390h_cstring_t* cs = NULL;
    ch390h_t *ch = NULL;
    pkg_evt_t evt = {0};
    int ret = luat_rtos_queue_recv(qt, &evt, sizeof(pkg_evt_t), timeout);
    // LLOGD("evt id %d ret %d timeout %d", evt.id, ret, timeout);
    if (ret == 0 && evt.id == 1) {
        // 收到消息了
        ch = (ch390h_t *)evt.ch;
        cs = (luat_ch390h_cstring_t*)evt.cs;
        // LLOGD("收到消息 %p %p", ch, cs);
        ret = task_loop(ch, cs);
        if (cs) {
            // remain_tx_size -= cs->len;
            luat_heap_opt_free(pkg_mem_type, cs);
            cs = NULL;
        }
        return 1; // 拿到消息, 那队列里可能还有消息, 马上执行下一轮操作
    }
    else {
        // if (evt.id == 2) {
        //     LLOGD("CH390中断触发");
        // }
        ret = task_loop(NULL, NULL);
    }
    return ret;
}

static void ch390_task_main(void* args) {
    (void)args;
    int ret = 0;
    uint32_t count = 0;
    while (1) {
        count ++;
        if (count % 10 == 0) {
            luat_wdt_feed();
        }
        if (count > 256) {
            if (ret) {
                // LLOGD("强制休眠20ms");
                // luat_rtos_task_sleep(20);
            }
            count = 0;
        }
        if (s_ch390h_mode == 0) {
            ret = task_wait_msg(5);
        }
        else {
            ret = task_wait_msg(1000);
        }
    }
}

void luat_ch390h_task_start(void) {
    int ret = 0;
    if (ch390h_task_handle == NULL) {
        size_t total = 0;
        size_t used = 0;
        size_t max_used = 0;
        luat_meminfo_opt_sys(LUAT_HEAP_PSRAM, &total, &used, &max_used);
        if (total > 1024 * 512) {
            pkg_mem_type = LUAT_HEAP_PSRAM;
        }
        ret = luat_rtos_queue_create(&qt, 1024, sizeof(pkg_evt_t));
        if (ret) {
            LLOGE("queue create fail %d", ret);
            return;
        }
        ret = luat_rtos_task_create(&ch390h_task_handle, 8*1024, 50, "ch390h", ch390_task_main, NULL, 0);
        if (ret) {
            LLOGE("task create fail %d", ret);
            return;
        }
        LLOGD("task started");
    }
}

// 辅助函数
#if 0
static void print_erp_pkg(uint8_t* buff, uint16_t len) {
    // LLOGD("pkg len %d head " MACFMT " " MACFMT, len, MAC_ARG(buff), MAC_ARG(buff+6));
    if (len < 24 || len > 1600) {
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
#endif
