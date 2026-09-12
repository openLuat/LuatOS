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
#include "lwip/tcp.h"
#include "lwip/sys.h"
#include "lwip/tcpip.h"
#include "lwip/pbuf.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_wdt.h"

#include "luat_rtos.h"
#include "luat_netdrv_pkg.h"

#define LUAT_LOG_TAG "netdrv.ch390x"
#include "luat_log.h"

#ifndef LUAT_CONF_CH390H_LOOP_TIMEOUT
#define LUAT_CONF_CH390H_LOOP_TIMEOUT 5
#endif

typedef struct pkg_evt
{
    uint8_t id;
    luat_ch390h_cstring_t* cs;
    ch390h_t *ch;
}pkg_evt_t;

extern err_t luat_netdrv_netif_input_main(struct pbuf *p, struct netif *inp);
extern err_t luat_netdrv_etharp_output(struct netif *netif, struct pbuf *q, const ip4_addr_t *ipaddr);

extern ch390h_t* ch390h_drvs[MAX_CH390H_NUM];

static luat_rtos_task_handle ch390h_task_handle;
static luat_rtos_queue_t qt;

static uint64_t warn_vid_pid_tm;
static uint64_t warn_msg_tm;
static uint64_t warn_rxov_tm;

// 批量收包缓冲: 先把芯片RX内存快速读空(纯SPI读), 再统一处理, 防止13K RX缓冲溢出
#define CH390H_RX_BATCH_NUM 16
static uint8_t* s_rx_batch;                         // CH390H_RX_BATCH_NUM x 1600B, PSRAM
static uint16_t s_rx_batch_len[CH390H_RX_BATCH_NUM];

static uint32_t s_ch390h_mode; // 0 -- PULL 模式, 1 == IRQ 模式

static int ch390h_irq_cb(int pin, void *args) {
    (void)pin;
    (void)args;
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
    if (ch->init_done) {
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
        gpio_cfg.pull = Luat_GPIO_PULLDOWN;
        gpio_cfg.irq_cb = ch390h_irq_cb;
        luat_gpio_open(&gpio_cfg);
        LLOGI("enable irq mode in pin %d", ch->intpin);
        s_ch390h_mode = 1;
    }
    else {
        // LLOGI("enable pull mode, use pool mode");
    }

    ch->init_done = 1;
    return 0;
}

static luat_ch390h_cstring_t* new_cstring(ch390h_t* ch, uint16_t len) {
    size_t total = 0;
    size_t used = 0;
    size_t max_used = 0;
    size_t need = sizeof(luat_ch390h_cstring_t) + len - 4;
    luat_meminfo_opt_sys(ch->pkg_mem_type, &total, &used, &max_used);
    if (total > 0 && total - used > need + 32*1024) { // 最少甲32k给系统用,且留出本次分配所需
        luat_ch390h_cstring_t* cs = luat_heap_opt_malloc(ch->pkg_mem_type, sizeof(luat_ch390h_cstring_t) + len - 4);
        if (cs == NULL) {
            LLOGE("有剩余内存不多但分配失败! total %d used %d max_used %d len %d", total, used, max_used, len);
        }
        return cs;
    }
    LLOGW("剩余内存不多了,抛弃数据包 total %d used %d max_used %d len %d", total, used, max_used, len);
    return NULL;
}

static void send_msg_cs(ch390h_t* ch, luat_ch390h_cstring_t* cs) {
    uint32_t len = 0;
    luat_rtos_queue_get_cnt(qt, &len);
    uint64_t tm;
    
    // 流控背压机制
    if (len >= 800) {
        ch->flow_control = 1;  // 进入背压状态
    } else if (len < 400) {
        ch->flow_control = 0;  // 解除背压
    }
    
    if (len >= 1000) {
        tm = luat_mcu_tick64_ms();
        if (tm - warn_msg_tm > 1000) {
            warn_msg_tm = tm;
            LLOGW("队列已满，丢弃数据包 len=%d", len);
        }
        ch->total_tx_drop++;
        luat_heap_opt_free(ch->pkg_mem_type, cs);
        return;
    }
    if (len > 600) {
        tm = luat_mcu_tick64_ms();
        if (tm - warn_msg_tm > 1000) {
            warn_msg_tm = tm;
            LLOGW("队列负载较高 len=%d flow_control=%d", len, ch->flow_control);
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
        luat_heap_opt_free(ch->pkg_mem_type, cs);
    }
}

static void ch390h_dataout(luat_netdrv_t* drv, void* userdata, uint8_t* buff, uint16_t len) {
    (void)drv;
    ch390h_t* ch = (ch390h_t*)userdata;
    if (ch->status == CH390H_STATUS_STOPPED) {
        return;
    }
    luat_ch390h_cstring_t* cs = new_cstring(ch, len);
    if (cs == NULL) {
        return;
    }
    cs->len = len;
    memcpy(cs->buff, buff, len);
    send_msg_cs(ch, cs);
}

static void ch390h_dataout_pbuf(ch390h_t* ch, struct pbuf* p) {
    if (ch->status == CH390H_STATUS_STOPPED) {
        return;
    }
    // LLOGI("lwip待发送到硬件层 %p %d", p, p->tot_len);
    luat_ch390h_cstring_t* cs = new_cstring(ch, p->tot_len);
    if (cs == NULL) {
        return;
    }
    cs->len = p->tot_len;
    pbuf_copy_partial(p, cs->buff, p->tot_len, 0);
    send_msg_cs(ch, cs);
}


err_t ch390_netif_output(struct netif *netif, struct pbuf *p) {
    // LLOGD("lwip待发送数据 %p %d", p, p->tot_len);
    ch390h_t* ch = NULL;

    for (size_t i = 0; i < MAX_CH390H_NUM; i++)
    {
        ch = ch390h_drvs[i];
        if (ch == NULL) {
            continue;
        }
        if (ch->netdrv->netif != netif) {
            continue;
        }
        if (ch->status == CH390H_STATUS_STOPPED) {
            return ERR_IF;
        }
        // LWIP 层拦截: 用户已声明拦截 (layer="lwip") 则原 dataout 流程被吞掉.
        // 注意: pbuf 可能是多片链表, 仅当单片 (p->next == NULL) 且
        // 首片 payload 长度 >= tot_len 时才能直接传 payload 指针.
        // 返回 0 = 未拦截, 1 = 已拦截 (跳过 ch390h_dataout_pbuf).
        if (p != NULL && p->tot_len > 0 && p->next == NULL && p->len >= p->tot_len) {
            int intercepted = luat_netdrv_pkg_input(ch->netdrv->id, LUAT_NETDRV_CH_LWIP, p->payload, p->tot_len);
            if (intercepted != 0) {
                // Lua 已拿走控制权, 原 TX 包不入 spi 队列 (Lua 自己 send_raw)
                break;
            }
        }
        ch390h_dataout_pbuf(ch, p);
        break;
    }
    return 0;
}

static int check_vid_pid(ch390h_t* ch) {
    uint8_t buff[6] = {0};
    luat_ch390h_read_vid_pid(ch, buff);
    if (0 == memcmp(buff, "\x00\x1C\x51\x91", 4)) {
        ch->vid_pid_error_count = 0;  // 成功后清零计数器
        return 0;
    }
    // 再读一次
    luat_ch390h_read_vid_pid(ch, buff);
    if (0 != memcmp(buff, "\x00\x1C\x51\x91", 4)) {
        ch->vid_pid_error_count++;
        uint64_t tnow = luat_mcu_tick64_ms();
        if (tnow - warn_vid_pid_tm > 2000) {
            // 前几次用WARN，多次失败用ERROR
            if (ch->vid_pid_error_count < 10) {
                LLOGW("读取vid/pid失败 spi=%d cs=%d %02X%02X%02X%02X error_count=%d", 
                      ch->spiid, ch->cspin, buff[0], buff[1], buff[2], buff[3], ch->vid_pid_error_count);
            } else {
                LLOGE("读取vid/pid持续失败!请检查接线!! spi=%d cs=%d %02X%02X%02X%02X error_count=%d", 
                      ch->spiid, ch->cspin, buff[0], buff[1], buff[2], buff[3], ch->vid_pid_error_count);
            }
            warn_vid_pid_tm = tnow;
        }
        // 连续多次失败后回退到初始状态
        // 注意: STOPPED (=4) 也满足 status >= 2, 必须排除, 否则休眠时 SPI 读不到 VID/PID
        // 会把人为设的 STOPPED 错误回退成 0, 引发 ch390_task_main 退出 FOREVER 等待.
        if (ch->vid_pid_error_count >= 20 && ch->status >= 2 && ch->status != CH390H_STATUS_STOPPED) {
            LLOGE("VID/PID检查连续失败超过阈值，回退到初始状态");
            ch->status = 0;
            ch->init_done = 0;
            ch->vid_pid_error_count = 0;
        }
        /* 仅当业务侧通过 CTRL_UPDOWN=0 显式请求了休眠 (sleep_requested=1) 时,
         * 才允许在 VID/PID 持续失败后自杀转 STOPPED. 这样:
         *  - 正常运行期间瞬时干扰 / 网线意外抖动 / SPI 偶发失败 ->
         *    走 status=2->0->2 自愈循环, 不会卡 STOPPED;
         *  - 业务侧主动请求休眠后, 若 SPI 已停 / PHY 已下电导致读不到 VID/PID ->
         *    转 STOPPED 让 task 进 FOREVER, 不再贡献 1Hz 唤醒. */
        if (ch->vid_pid_error_count >= 50 && ch->status == 0 && ch->sleep_requested) {
            LLOGW("VID/PID 持续失败 %d 次 (休眠请求中), 进入 STOPPED 节能态. "
                  "spi=%d cs=%d. 唤醒后会通过 netdrv.ctrl(CTRL_UPDOWN,1) 重新拉起.",
                  ch->vid_pid_error_count, ch->spiid, ch->cspin);
            ch->status = CH390H_STATUS_STOPPED;
            ch->init_done = 0;
            ch->vid_pid_error_count = 0;
        }
        return -1;
    }
    ch->vid_pid_error_count = 0;
    return 0;
}

static int ch390_status_on_0(ch390h_t* ch) {
    uint8_t buff[32] = {0};
    // 状态0, 代表刚加入, 还没成功通信过!!
    ch390h_bootup(ch);
    luat_ch390h_software_reset(ch);
    if (check_vid_pid(ch)) {
        return 0;
    }
    luat_rtos_task_sleep(10);
    // 读取MAC地址, 开始初始化
    luat_ch390h_read_mac(ch, buff);
    size_t tmpc = 0;
    for (size_t i = 0; i < 6; i++)
    {
        if (buff[i] == 0) {
            tmpc ++;
            if (tmpc == 2) {
                LLOGD("非法MAC地址 %02X%02X%02X%02X%02X%02X", buff[0], buff[1], buff[2], buff[3], buff[4], buff[5]);
                return 0;
            }
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
    memcpy(ch->netdrv->netif->hwaddr, buff, 6);
    // IPv6: MAC 就绪后才能生成合法的链路本地地址(EUI-64).
    // ch390_netif_init 里无法生成, 因为那时 hwaddr 还是全 0.
    // 未链接 lwip2 适配层的构建里, 该符号由 luat_netdrv.c 的弱符号兜底, 返回失败即可.
    #if LUAT_USE_NETDRV_IPV6
    {
        extern int net_lwip2_ipv6_create_linklocal(uint8_t adapter_index);
        if (net_lwip2_ipv6_create_linklocal(ch->adapter_id) != 0) {
            LLOGD("adapter %d 暂未生成IPv6链路本地地址", ch->adapter_id);
        }
    }
    #endif
    ch->status = 2;
    ch->netdrv->dataout = ch390h_dataout;
    luat_ch390h_basic_config(ch);
    luat_ch390h_set_phy(ch, 1);
    luat_ch390h_set_rx(ch, 1);
    if (ch->intpin != 255) {
        luat_ch390h_write_reg(ch, CH390H_REG_IMR, 1); // 开启接收中断
    }
    return 0; // 等待下一个周期
}

// 处理一帧: 统计/注入lwIP (单帧与批量模式共用)
static void ch390_process_rx_frame(ch390h_t* ch, uint8_t* buf, uint16_t len) {
    NETDRV_STAT_IN(ch->netdrv, len);
    // 替换原 napt_pkg_input 调用为 pkg_input (内含 EVT_PKG 截获检查)
    int ret = luat_netdrv_pkg_input(ch->adapter_id, LUAT_NETDRV_CH_HW, buf, (uint16_t)(len - 4));
    if (ret == 0) {
        // napt 未消费, 继续注入 netif (原逻辑)
        ret = luat_netdrv_netif_input_proxy(ch->netdrv->netif, buf, len - 4);
        if (ret) {
            LLOGE("luat_netdrv_netif_input_proxy 返回错误!!! ret %d", ret);
            return;
        }
    }
}

static int ch390_on_rx_wait_for_read(ch390h_t* ch) {
    int ret = 0;
    uint16_t len = 0;

    if (s_rx_batch == NULL) {
        // 批量缓冲未分配, 回退到单帧处理
        ret = luat_ch390h_read_pkg(ch, ch->rxbuff, &len);
        if (ret) {
            ch->rx_error_count++;
            LLOGW("读数据包报错 ret=%d spi=%d cs=%d, error_count=%d", ret, ch->spiid, ch->cspin, ch->rx_error_count);
            // 只有连续多次错误且距离上次复位超过3秒才执行复位
            uint32_t now = (uint32_t)luat_mcu_tick64_ms();
            if (ch->rx_error_count >= 5 && (now - ch->last_reset_time > 3000)) {
                LLOGE("连续读包错误超过阈值，执行复位");
                luat_ch390h_write_reg(ch, CH390H_REG_RCR, 0);
                luat_ch390h_write_reg(ch, CH390H_REG_TP_PTR, 1);
                luat_ch390h_write_reg(ch, CH390H_REG_RX_LEN, 0);
                luat_rtos_task_sleep(1);
                luat_ch390h_basic_config(ch);
                luat_ch390h_set_phy(ch, 1);
                luat_ch390h_set_rx(ch, 1);
                if (ch->intpin != 255) {
                    luat_ch390h_write_reg(ch, CH390H_REG_IMR, 1);
                }
                ch->rx_error_count = 0;
                ch->last_reset_time = now;
                ch->total_reset_count++;
            }
            return 0;
        }
        ch->rx_error_count = 0;
        if (len > 0) {
            ch390_process_rx_frame(ch, ch->rxbuff, len);
        }
        return 2;
    }

    // 批量模式: 阶段1, 快速把芯片RX内存里的帧全部读出(纯SPI读, 不做处理), 防止13K RX缓冲溢出
    int n = 0;
    while (n < CH390H_RX_BATCH_NUM) {
        len = 0;
        ret = luat_ch390h_read_pkg(ch, s_rx_batch + (size_t)n * 1600, &len);
        if (ret) {
            ch->rx_error_count++;
            LLOGW("读数据包报错 ret=%d spi=%d cs=%d, error_count=%d", ret, ch->spiid, ch->cspin, ch->rx_error_count);
            uint32_t now = (uint32_t)luat_mcu_tick64_ms();
            if (ch->rx_error_count >= 5 && (now - ch->last_reset_time > 3000)) {
                LLOGE("连续读包错误超过阈值，执行复位");
                luat_ch390h_write_reg(ch, CH390H_REG_RCR, 0);
                luat_ch390h_write_reg(ch, CH390H_REG_TP_PTR, 1);
                luat_ch390h_write_reg(ch, CH390H_REG_RX_LEN, 0);
                luat_rtos_task_sleep(1);
                luat_ch390h_basic_config(ch);
                luat_ch390h_set_phy(ch, 1);
                luat_ch390h_set_rx(ch, 1);
                if (ch->intpin != 255) {
                    luat_ch390h_write_reg(ch, CH390H_REG_IMR, 1);
                }
                ch->rx_error_count = 0;
                ch->last_reset_time = now;
                ch->total_reset_count++;
            }
            break; // 出错后停止批量读取, 已读出的帧仍处理
        }
        if (len == 0) {
            break; // RX内存已清空
        }
        s_rx_batch_len[n] = len;
        n++;
    }
    if (n > 0) {
        ch->rx_error_count = 0;
    }
    // 阶段2: 逐个处理已读出的帧
    for (int i = 0; i < n; i++) {
        ch390_process_rx_frame(ch, s_rx_batch + (size_t)i * 1600, s_rx_batch_len[i]);
    }
    return 2;
}


static int task_loop_one(ch390h_t* ch, luat_ch390h_cstring_t* cs) {
    uint8_t buff[32] = {0};
    int ret = 0;
    // uint16_t len = 0;

    if (ch->status == CH390H_STATUS_STOPPED) {
        return 0;
    }
    
    // LLOGD("状态 spi %d cs %d stat %d", ch->spiid, ch->cspin, ch->status);
    // 首先, 判断设备状态
    if (ch->status == 0) {
        return ch390_status_on_0(ch);
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
    luat_ch390h_read(ch, CH390H_REG_NSR, 1, buff);
    uint8_t NSR = buff[0];
    // LLOGD("网络状态寄存器 %02X %d", buff[0], (NSR & (1 << 6)) != 0);
    // NSR bit1 = RXOV: RX内存溢出标志(手册5.2节)
    if (NSR & 0x02) {
        uint64_t tnow = luat_mcu_tick64_ms();
        if (tnow - warn_rxov_tm > 1000) {
            uint8_t rsr = 0, rocr = 0;
            luat_ch390h_read(ch, CH390H_REG_RSR, 1, &rsr);
            luat_ch390h_read(ch, CH390H_REG_ROCR, 1, &rocr); // R/C: 读后清除
            warn_rxov_tm = tnow;
            ch->rx_ov_cnt++;
            // LLOGD("CH390 RX内存溢出! NSR=0x%02X RSR=0x%02X ROCR=0x%02X 累计=%u fifo_reset_drop=%u",
            //       NSR, rsr, rocr, ch->rx_ov_cnt, ch->total_rx_drop);
        }
    }
    if (0 == (NSR & (1 << 6))) {
        // 网线没插, 或者phy没有上电
        // 首先, 确保phy上电
        // luat_ch390h_read(ch, CH390H_REG_GPR, 1, buff);
        // LLOGD("PHY状态 %02X", buff[0]);
        luat_ch390h_set_phy(ch, 1);
        luat_ch390h_set_rx(ch, 1);
        if (netif_is_link_up(ch->netdrv->netif)) {
            LLOGI("link is down %d %d %p", ch->spiid, ch->cspin, ch->netdrv->netif);
            luat_netdrv_set_link_updown(ch->netdrv, 0);
        }
        return 0; // 网络断了, 没那么快恢复的, 等吧
    }

    if (!netif_is_link_up(ch->netdrv->netif)) {
        LLOGI("link is up %d %d %s", ch->spiid, ch->cspin, (NSR & (1<<7)) ? "10M" : "100M");
        // 链路UP时清零统计, 保证每次测试从干净计数开始
        luat_netdrv_rx_stat_reset();
        ch->total_rx_drop = 0;
        ch->rx_ov_cnt = 0;
        ch->rx_status_err_cnt = 0;
        luat_netdrv_set_link_updown(ch->netdrv, 1);
    }

    if (cs) {
        // LLOGD("数据写入 %p %d", cs->buff, cs->len);
        luat_ch390h_write_pkg(ch, cs->buff, cs->len);
    }

    // 有没有数据待读取
    if (NSR & 0x01) {
        ret = ch390_on_rx_wait_for_read(ch);
        if (ret != 2) {
            return ret;
        }
    }
    else {
        // LLOGD("没有数据待读取");
    }

    if (ch->intpin != 255) {
        luat_ch390h_write_reg(ch, CH390H_REG_ISR, 0x3F); // 清除中断
    }
    
    // 这一轮处理完成了
    // 如果rx有数据, 那就不要等待, 立即开始下一轮
    if (NSR & 0x01 || cs) {
        // 加快处理速度, 避免数据包堆积, 但也要避免死循环
        #if 1
        for (size_t i = 0; i < 10; i++)
        {
            luat_ch390h_read(ch, CH390H_REG_NSR, 1, buff);
            NSR = buff[0];
            if ((NSR & 0x01) == 0) {
                break;
            }
            ret = ch390_on_rx_wait_for_read(ch);
            if (ret != 2) {
                return ret;
            }
        }
        #endif
        return 1;
    }

    return 0;
}

static int task_loop(ch390h_t *ch, luat_ch390h_cstring_t* cs) {
    int ret = 0;
    for (size_t i = 0; i < MAX_CH390H_NUM; i++)
    {
        /* 修复: 进入 task_loop_one 之前必须排除 STOPPED 设备.
         * 否则 task_loop_one 会执行 check_vid_pid -> 失败累加 vid_pid_error_count
         * -> >=20 次时把 status 从 STOPPED 错误回退成 0 -> any_active 永远为 1
         * -> ch390_task_main 永远不进 LUAT_WAIT_FOREVER, 1Hz 唤醒回不去低功耗. */
        if (ch390h_drvs[i] != NULL
            && ch390h_drvs[i]->init_step
            && ch390h_drvs[i]->status != CH390H_STATUS_STOPPED) {
            ret += task_loop_one(ch390h_drvs[i], ch == ch390h_drvs[i] ? cs : NULL);
        }
    }
    if (ret) {
        pkg_evt_t evt = {0};
        size_t t = 0;
        luat_rtos_queue_get_cnt(qt, &t);
        if (t < 4) {
            luat_rtos_queue_send(qt, &evt, sizeof(pkg_evt_t), 0);
        }
        else {
            // LLOGE("队列已满(%d), 不再发送空消息唤醒 task_loop", t);
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
            luat_heap_opt_free(ch->pkg_mem_type, cs);
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
    // 延时30ms，等待CH390H芯片完全启动，避免直接初始化导致异常
    luat_rtos_task_sleep(30);
    while (1) {
        count ++;
        if (count % 10 == 0) {
            luat_wdt_feed();
        }
        if (count > 1024) {
            // 每隔1024次循环, 休眠10ms, 不然CP会被饿死
            if (ret) {
                // LLOGD("强制休眠20ms");
                // luat_rtos_task_sleep(10);
            }
            count = 0;
        }
        // 进入低功耗前会通过 netdrv.ctrl(LWIP_ETH, CTRL_UPDOWN, 0) 把所有 CH390 设备置为 STOPPED
        // 此时既无需 5ms 轮询，也无需 1Hz 心跳，直接 FOREVER 等待新消息（CTRL_UPDOWN=1 重新启动时会派发新事件）
        int any_active = 0;
        for (size_t i = 0; i < MAX_CH390H_NUM; i++) {
            if (ch390h_drvs[i] != NULL && ch390h_drvs[i]->status != CH390H_STATUS_STOPPED) {
                any_active = 1;
                break;
            }
        }
        if (!any_active) {
            ret = task_wait_msg(LUAT_WAIT_FOREVER);
        }
        else if (s_ch390h_mode == 0) {
            ret = task_wait_msg(LUAT_CONF_CH390H_LOOP_TIMEOUT);
        }
        else {
            ret = task_wait_msg(1000);
        }
    }
}

void luat_ch390h_task_wakeup(void) {
    if (qt == NULL) {
        return;
    }
    uint32_t len = 0;
    luat_rtos_queue_get_cnt(qt, &len);
    if (len > 4) {
        return;
    }
    pkg_evt_t evt = {
        .id = 2
    };
    luat_rtos_queue_send(qt, &evt, sizeof(pkg_evt_t), 0);
}

void luat_ch390h_task_start(void) {
    int ret = 0;
    if (ch390h_task_handle == NULL) {
        // 为所有CH390H设备初始化pkg_mem_type
        size_t total = 0;
        size_t used = 0;
        size_t max_used = 0;
        luat_meminfo_opt_sys(LUAT_HEAP_PSRAM, &total, &used, &max_used);
        int default_mem_type = (total > 1024 * 512) ? LUAT_HEAP_PSRAM : LUAT_HEAP_AUTO;
        for (size_t i = 0; i < MAX_CH390H_NUM; i++) {
            if (ch390h_drvs[i] != NULL) {
                ch390h_drvs[i]->pkg_mem_type = default_mem_type;
            }
        }
        // 分配批量收包缓冲(PSRAM), 用于快速清空芯片RX内存, 防止13K RX缓冲溢出
        if (s_rx_batch == NULL) {
            s_rx_batch = (uint8_t*)luat_heap_opt_malloc(default_mem_type, 1600 * CH390H_RX_BATCH_NUM);
            if (s_rx_batch == NULL) {
                LLOGW("RX批量缓冲分配失败, 回退到单帧模式!");
            }
            else {
                LLOGI("RX批量缓冲 %d x 1600B 分配成功", CH390H_RX_BATCH_NUM);
            }
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
