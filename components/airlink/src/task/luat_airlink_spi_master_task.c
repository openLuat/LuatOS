#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_airlink_fota.h"

#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_fs.h"
#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#define MASTER_SPI_ID g_airlink_spi_conf.spi_id
#define TEST_BUFF_SIZE (1600)

#define AIRLINK_SPI_CS_PIN g_airlink_spi_conf.cs_pin
#define AIRLINK_SPI_RDY_PIN g_airlink_spi_conf.rdy_pin
#define AIRLINK_SPI_IRQ_PIN g_airlink_spi_conf.irq_pin

#ifdef TYPE_EC718M
#include "platform_def.h"
#endif

#ifndef __USER_FUNC_IN_RAM__
#define __USER_FUNC_IN_RAM__
#endif

extern airlink_statistic_t g_airlink_statistic;
extern uint32_t g_airlink_pause;
extern luat_rtos_mutex_t g_airlink_pause_mutex;

// static uint8_t start;
// static uint8_t slave_rdy;
static uint8_t thread_rdy;
static uint8_t spi_rdy;
static luat_rtos_task_handle spi_task_handle;
static luat_rtos_task_handle spi_irq_task_handle;

#if defined(LUAT_USE_AIRLINK_EXEC_MOBILE)
extern luat_airlink_dev_info_t g_airlink_self_dev_info;
#endif
static uint8_t basic_info[256];

// static uint32_t is_waiting_queue = 0;

static luat_rtos_queue_t evt_queue;
static luat_rtos_queue_t rdy_evt_queue;  // 专门用于RDY事件(id=6)的队列
static luat_rtos_queue_t rdy_task_evt_queue;

extern luat_airlink_irq_ctx_t g_airlink_irq_ctx;
extern luat_airlink_irq_ctx_t g_airlink_wakeup_irq_ctx;

luat_airlink_irq_ctx_t g_airlink_irq_ctx;
luat_airlink_irq_ctx_t g_airlink_wakeup_irq_ctx;

// RDY引脚中断等待相关变量
static volatile uint8_t rdy_ready_flag = 0;           // RDY就绪标志

// RDY引脚下降沿中断处理函数，设置就绪标志并发送事件
__USER_FUNC_IN_RAM__ static int rdy_pin_irq_handler(void* param)
{
    // 设置RDY就绪标志
    if (rdy_evt_queue == NULL) {
        return 0;
    }
    rdy_ready_flag = 1;
    // 发送通知事件，告知任务RDY已就绪
    luat_event_t evt = {.id = 6};
    luat_rtos_queue_send(rdy_evt_queue, &evt, sizeof(evt), 0);
    // LLOGD("RDY中断触发，设置就绪标志");
    return 0;
}

__USER_FUNC_IN_RAM__ static int slave_irq_cb(void *data, void *args)
{
    uint32_t len = 0;
    luat_rtos_queue_get_cnt(evt_queue, &len);
    // luat_rtos_event_send(spi_task_handle, 2, 2, 3, 4, 100);
    static uint32_t irq_seq = 0;
    luat_event_t evt = {.id = 2, .param1 = irq_seq};
    irq_seq ++;
    if (len < 128)
    {
        // 这里要发2条数据, 因为client已经准备好的数据实际上是老的,需要读2次才是最新的, 所以要发两条
        luat_rtos_queue_send(evt_queue, &evt, sizeof(evt), 0);
        luat_rtos_queue_send(evt_queue, &evt, sizeof(evt), 0);
    }
    return 0;
}

__USER_FUNC_IN_RAM__ static int wakeup_irq_cb(void *data, void *args)
{
    // g_airlink_wakeup_irq_ctx.enable = 0;
    LLOGI("触发唤醒wifi wakeup_irq_cb");
    return 0;
}


__USER_FUNC_IN_RAM__ static void on_newdata_notify(void)
{
    luat_event_t evt = {.id = 3};
    luat_rtos_queue_send(evt_queue, &evt, sizeof(evt), 0);
}

void luat_airlink_spi_master_pin_setup(void)
{
    if (spi_rdy)
        return;
    spi_rdy = 1;
    if (g_airlink_spi_conf.cs_pin == 0)
    {
        // if (g_airlink_spi_conf.spi_id == 0) {
        g_airlink_spi_conf.cs_pin = 8;
        // }
        // else {
        //     g_airlink_spi_conf.cs_pin = 8;
        // }
    }
    if (g_airlink_spi_conf.rdy_pin == 0)
    {
        // if (g_airlink_spi_conf.spi_id == 0) {
        g_airlink_spi_conf.rdy_pin = 22;
        // }
    }
    if (g_airlink_spi_conf.irq_pin == 0)
    {
        g_airlink_spi_conf.irq_pin = 255; // 默认禁用irq脚
    }

    LLOGI("spi master id %d cs %d rdy %d irq %d", MASTER_SPI_ID, g_airlink_spi_conf.cs_pin, g_airlink_spi_conf.rdy_pin, g_airlink_spi_conf.irq_pin);

    luat_spi_t spi_conf = {
        .id = MASTER_SPI_ID,
        .CPHA = 1,
        .CPOL = 1,
        .dataw = 8,
        .bit_dict = 1, // MSB, 大部分平台也只支持MSB
        .master = 1,
        .mode = 1, // mode设置为1，全双工
#ifdef __BK72XX__
        .bandrate = g_airlink_spi_conf.speed > 0 ? g_airlink_spi_conf.speed : 13000000,
#else
        .bandrate = g_airlink_spi_conf.speed > 0 ? g_airlink_spi_conf.speed : 31000000,
        // luat_pm_iovolt_ctrl(0, 3300);
#endif
        .cs = 255};
    luat_spi_setup(&spi_conf);
    luat_gpio_cfg_t gpio_cfg = {0};

    // 从机准备好脚
    // luat_gpio_set_default_cfg(&gpio_cfg);
    // gpio_cfg.pin = AIRLINK_SPI_RDY_PIN;
    // gpio_cfg.mode = LUAT_GPIO_INPUT;
    // gpio_cfg.irq_type = LUAT_GPIO_FALLING_IRQ;
    // gpio_cfg.pull = 0;
    // luat_gpio_open(&gpio_cfg);

    // 设置RDY引脚中断，
    luat_gpio_set_default_cfg(&gpio_cfg);
    gpio_cfg.pin = AIRLINK_SPI_RDY_PIN;
    gpio_cfg.mode = LUAT_GPIO_IRQ;
    gpio_cfg.irq_type = LUAT_GPIO_FALLING_IRQ;  // 下降沿中断
    gpio_cfg.pull = LUAT_GPIO_PULLUP;
    gpio_cfg.irq_cb = rdy_pin_irq_handler;
    luat_gpio_open(&gpio_cfg);
//     // CS片选脚
    luat_gpio_set_default_cfg(&gpio_cfg);
    gpio_cfg.pin = AIRLINK_SPI_CS_PIN;
    gpio_cfg.mode = LUAT_GPIO_OUTPUT;
    gpio_cfg.pull = LUAT_GPIO_PULLUP;
    gpio_cfg.output_level = 1;
    luat_gpio_open(&gpio_cfg);

    if (g_airlink_spi_conf.irq_pin != 255)
    {
        luat_gpio_set_default_cfg(&gpio_cfg);
        gpio_cfg.pin = g_airlink_spi_conf.irq_pin;
        gpio_cfg.mode = LUAT_GPIO_IRQ;
        gpio_cfg.irq_type = LUAT_GPIO_FALLING_IRQ;
        gpio_cfg.pull = LUAT_GPIO_PULLUP;
        gpio_cfg.irq_cb = slave_irq_cb;
        luat_gpio_open(&gpio_cfg);
    }
}

__USER_FUNC_IN_RAM__ static void record_statistic(luat_event_t event)
{
    switch (event.id)
    {
    case 0:
        g_airlink_statistic.event_timeout.total++;
        break;
    case 2:
        g_airlink_statistic.event_rdy_irq.total++;
        break;
    case 3:
        g_airlink_statistic.event_new_data.total++;
        break;
    default:
        break;
    }
}

static uint8_t *s_txbuff;
static uint8_t *s_rxbuff;
static airlink_link_data_t s_link;
static uint64_t warn_slave_no_ready = 0;
static uint64_t tnow = 0;
extern void airlink_sfota_exec();
static uint8_t slave_is_irq_ready = 0;

__USER_FUNC_IN_RAM__ void airlink_transfer_and_exec(uint8_t *txbuff, uint8_t *rxbuff)
{
    // 清除link
    memset(&s_link, 0, sizeof(airlink_link_data_t));
    airlink_link_data_t *link = NULL;

    g_airlink_statistic.tx_pkg.total++;
    // 拉低片选, 准备发送数据
    luat_gpio_set(AIRLINK_SPI_CS_PIN, 0);
    
    // luat_spi_lock(MASTER_SPI_ID);
    // 发送数据
    luat_spi_transfer(MASTER_SPI_ID, (const char *)txbuff, TEST_BUFF_SIZE, (char *)rxbuff, TEST_BUFF_SIZE);
    // luat_spi_unlock(MASTER_SPI_ID);
    // 拉高片选之前，先检查一下是否有RDY事件未处理，如果有，则全部清除
    size_t qlen = 0;
    luat_rtos_queue_get_cnt(rdy_evt_queue, &qlen);
    if (qlen > 0) {
        // LLOGW("发送数据后发现有%d个RDY事件未处理", (int)qlen);
        // 清除掉这些冗余的RDY事件
        luat_event_t evt = {0};
        luat_rtos_queue_recv(rdy_evt_queue, &evt, sizeof(evt), 0);
    }
    rdy_ready_flag = 0;
    // 拉高片选, 数据发送完毕
    luat_gpio_set(AIRLINK_SPI_CS_PIN, 1);
    // luat_airlink_print_buff("RX", rxbuff, 64);
    // 对接收到的数据进行解析
    link = luat_airlink_data_unpack(rxbuff, TEST_BUFF_SIZE);
    if (link)
    {
        g_airlink_statistic.tx_pkg.ok++;
        memcpy(&s_link, link, sizeof(airlink_link_data_t));
        if (slave_is_irq_ready == 0 && link->flags.irq_ready) {
            LLOGI("slave回复irq模式已经开启,正式开始IRQ交互模式");
            slave_is_irq_ready = 1;
        }
        luat_airlink_on_data_recv(link->data, link->len);
    }
    else
    {
        g_airlink_statistic.tx_pkg.err++;
        // luat_airlink_print_buff("RX", rxbuff, 8);
        // LLOGE("接收到数据不正确, 丢弃");
    }
}

__USER_FUNC_IN_RAM__ int airlink_wait_for_slave_reply(size_t timeout_ms)
{
    uint64_t timeout = 0;
    luat_event_t event = {0};
    while (timeout < timeout_ms)
    {
        event.id = 0;
        luat_rtos_queue_recv(rdy_evt_queue, &event, sizeof(luat_event_t), 10);
        if (event.id != 0) {
            // LLOGD("airlink_wait_for_slave_reply event.id %d", event.id);
            return 0;
        }
        timeout += 10;
    }
    return -1;
}

static int queue_emtry_counter; // 上一个循环里, 是否待发送的数据, 如果有, 则需要立即发送

__USER_FUNC_IN_RAM__ void airlink_wait_and_prepare_data(uint8_t *txbuff)
{
    luat_event_t event = {0};
    airlink_queue_item_t item = {0};
    uint32_t timeout = 5;
    int ret = 0;
    uint32_t qlen = 0;
    luat_rtos_queue_get_cnt(evt_queue, &qlen);
    if (qlen == 0)
    {
        if (g_airlink_pause)
        {
            if (g_airlink_pause_mutex)
            {
                // LLOGD("airlink entering pause, waiting on mutex");
                luat_rtos_mutex_lock(g_airlink_pause_mutex, LUAT_WAIT_FOREVER);
                // LLOGD("airlink resumed from pause");
                luat_rtos_mutex_unlock(g_airlink_pause_mutex);  // 立即释放，避免占用
            }
            else
            {
                // 若未创建则轮询等待
                while (g_airlink_pause) 
                {
                    LLOGD("airlink spi 交互暂停中,允许主控休眠, 监测周期1000ms");
                    luat_rtos_task_sleep(1000);
                }
            }
        }
    }
    if (g_airlink_wakeup_irq_ctx.enable)
    {
        luat_gpio_cfg_t gpio_cfg = {0};
        luat_gpio_set_default_cfg(&gpio_cfg);
        int pin = g_airlink_wakeup_irq_ctx.master_pin;
        int val = g_airlink_wakeup_irq_ctx.irq_mode == Luat_GPIO_FALLING ? 1 : 0;
        gpio_cfg.pin = pin;
        gpio_cfg.mode = LUAT_GPIO_OUTPUT;
        gpio_cfg.pull = g_airlink_wakeup_irq_ctx.irq_mode == Luat_GPIO_FALLING ? LUAT_GPIO_PULLUP : LUAT_GPIO_PULLDOWN;
        gpio_cfg.output_level = val;
        luat_gpio_open(&gpio_cfg);
        LLOGI("g_airlink_wakeup_irq_ctx %p, state %d, slave_pin %d", g_airlink_wakeup_irq_ctx, g_airlink_wakeup_irq_ctx.enable, g_airlink_wakeup_irq_ctx.slave_pin);
        luat_gpio_set(pin, val);
        luat_rtos_task_sleep(120);
        luat_gpio_set(pin, !val);
        luat_rtos_task_sleep(120);
        luat_gpio_set(pin, val);
        g_airlink_wakeup_irq_ctx.enable = 0;
    }
    // 等到消息
    // LLOGD("link irq %d cmd %d ip %d", s_link.flags.irq_ready, s_link.flags.queue_cmd, s_link.flags.queue_ip);
    if (s_link.flags.irq_ready) {
        if (g_airlink_spi_conf.irq_timeout == 0) {
            g_airlink_spi_conf.irq_timeout = 500;
        }
        timeout = g_airlink_spi_conf.irq_timeout;
    }
    if (s_link.flags.queue_cmd || s_link.flags.queue_ip)
    {
        // 立即进行下一轮操作
        event.id = 4;
    }
    else if (queue_emtry_counter == 0) {
        event.id = 5;
    }
    else
    {
        // is_waiting_queue = 1;
        ret = luat_rtos_queue_recv(evt_queue, &event, sizeof(luat_event_t), timeout);
        // is_waiting_queue = 0;
        if (2 == event.id) {
            // LLOGD("从机通知IRQ中断");
        }
        else if (ret) {
            // LLOGD("irq timeout %d", timeout);
        }
    }

    record_statistic(event);

    // LLOGD("事件id %p %d", spi_task_handle, event.id);
    if (s_link.flags.mem_is_high == 0)
    {
        luat_airlink_cmd_recv_simple(&item);
    }
    else
    {
        if (g_airlink_debug) {
            LLOGI("从机内存高水位, 停止下发IP数据");
        }
    }
    if (item.len > 0 && item.cmd != NULL)
    {
        // LLOGD("发送待传输的数据, 塞入SPI的FIFO cmd id 0x%04X", item.cmd->cmd);
        luat_airlink_data_pack(item.cmd, item.len, txbuff);
        luat_airlink_cmd_free(item.cmd);
        queue_emtry_counter = 0;
    }
    else
    {
        // LLOGD("填充PING数据");
        #if defined(LUAT_USE_AIRLINK_EXEC_MOBILE)
        memcpy(basic_info + sizeof(luat_airlink_cmd_t), &g_airlink_self_dev_info, sizeof(g_airlink_self_dev_info));
        #endif
        luat_airlink_data_pack(basic_info, sizeof(basic_info), txbuff);
        queue_emtry_counter ++;
    }
}

__USER_FUNC_IN_RAM__ static void on_link_data_notify(airlink_link_data_t* link) {
    memset(&link->flags, 0, sizeof(uint32_t));
    if (g_airlink_irq_ctx.enable) {
        link->flags.irq_ready = 1;
        link->flags.irq_pin = g_airlink_irq_ctx.slave_pin - 140;
    }
}

#if defined(LUAT_USE_AIRLINK_EXEC_MOBILE)
static void send_devinfo_update_evt(void) {
    airlink_queue_item_t item = {0};
    // 发送空消息, 会自动转为devinfo消息
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item); 
}
#endif

__USER_FUNC_IN_RAM__ static void spi_master_task(void *param)
{
    // int i;
    // luat_event_t event = {0};
    #if defined(LUAT_USE_AIRLINK_EXEC_MOBILE)
    luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)basic_info;
    cmd->cmd = 0x10;
    cmd->len = 128;

    extern void luat_airlink_devinfo_init();
    luat_airlink_devinfo_init(send_devinfo_update_evt);
    #endif

    luat_rtos_task_sleep(5); // 等5ms
    luat_airlink_spi_master_pin_setup();
    g_airlink_newdata_notify_cb = on_newdata_notify;
    g_airlink_link_data_cb = on_link_data_notify;
    thread_rdy = 1;
    while (luat_gpio_get(AIRLINK_SPI_RDY_PIN) == 1) {
        luat_rtos_task_sleep(10);
    }
    int res = 0;
    while (1)
    {
        if (g_airlink_fota != NULL && g_airlink_fota->state == 1) {
            airlink_sfota_exec();
        }

        memset(s_txbuff, 0, TEST_BUFF_SIZE);
        airlink_wait_and_prepare_data(s_txbuff);

        // 立即发送数据给从机
        memset(s_rxbuff, 0, TEST_BUFF_SIZE);
        airlink_transfer_and_exec(s_txbuff, s_rxbuff);

        // 发送完成后，等待从机的响应/确认
        res = airlink_wait_for_slave_reply(2000);
        if (res != 0) {
            LLOGD("slave timeout");
        }
        // LLOGD("spi master task loop");
    }
}


void luat_airlink_start_master(void)
{
    if (s_txbuff != NULL)
    {
        LLOGE("SPI主机任务已经启动过了!!!");
        return;
    }

    s_txbuff = luat_heap_opt_malloc(LUAT_HEAP_SRAM, TEST_BUFF_SIZE);
    s_rxbuff = luat_heap_opt_malloc(LUAT_HEAP_SRAM, TEST_BUFF_SIZE);

    // 创建通用事件队列 (id=2,3等)
    luat_rtos_queue_create(&evt_queue, 4 * 1024, sizeof(luat_event_t));
    // 创建专门的RDY事件队列 (id=6)
    luat_rtos_queue_create(&rdy_evt_queue, 10, sizeof(luat_event_t));
    luat_rtos_task_create(&spi_task_handle, 8 * 1024, 50, "spi", spi_master_task, NULL, 0);
}

int luat_airlink_irqmode(luat_airlink_irq_ctx_t *ctx) {
    if (!ctx) {
        return -1;
    }
    luat_gpio_cfg_t gpio_cfg = {0};
    ctx->slave_ready = 0;
    memcpy(&g_airlink_irq_ctx, ctx, sizeof(luat_airlink_irq_ctx_t));
    g_airlink_spi_conf.irq_pin = ctx->master_pin;
    if (ctx->enable) {
        luat_gpio_set_default_cfg(&gpio_cfg);
        gpio_cfg.pin = g_airlink_spi_conf.irq_pin;
        gpio_cfg.mode = LUAT_GPIO_IRQ;
        gpio_cfg.irq_type = LUAT_GPIO_FALLING_IRQ;
        gpio_cfg.pull = LUAT_GPIO_PULLUP;
        gpio_cfg.irq_cb = slave_irq_cb;
        luat_gpio_open(&gpio_cfg);
        LLOGD("中断模式(GPIO%d)开启,等待slave就绪", g_airlink_spi_conf.irq_pin);
    }
    return 0;
}

int luat_airlink_wakeup_irqmode(luat_airlink_irq_ctx_t *ctx) {
    if (!ctx) {
        return -1;
    }
    luat_gpio_cfg_t gpio_cfg = {0};
    ctx->slave_ready = 0;
    memcpy(&g_airlink_wakeup_irq_ctx, ctx, sizeof(luat_airlink_irq_ctx_t));
    if (ctx->enable) {
        luat_gpio_set_default_cfg(&gpio_cfg);
        gpio_cfg.pin = ctx->master_pin;
        gpio_cfg.mode = LUAT_GPIO_IRQ;
        gpio_cfg.irq_type = ctx->irq_mode;
        gpio_cfg.pull = ctx->irq_mode == Luat_GPIO_FALLING ? LUAT_GPIO_PULLUP : LUAT_GPIO_PULLDOWN;
        gpio_cfg.irq_cb = wakeup_irq_cb;
        luat_gpio_open(&gpio_cfg);
        LLOGD("WAKEUP中断模式(GPIO%d)开启,等待slave就绪", ctx->master_pin);
    }
    return 0;
}
