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

// static uint8_t start;
// static uint8_t slave_rdy;
static uint8_t thread_rdy;
static luat_rtos_task_handle spi_task_handle;

static uint8_t basic_info[256];

static uint32_t is_waiting_queue = 0;

static luat_rtos_queue_t evt_queue;

__USER_FUNC_IN_RAM__ static int slave_irq_cb(void *data, void *args)
{
    uint32_t len = 0;
    // if (is_waiting_queue) {
    //     is_waiting_queue = 0;
    luat_rtos_queue_get_cnt(evt_queue, &len);
    // luat_rtos_event_send(spi_task_handle, 2, 2, 3, 4, 100);
    luat_event_t evt = {.id = 2};
    if (len < 24)
    {
        luat_rtos_queue_send(evt_queue, &evt, sizeof(evt), 0);
    }
    // }
    return 0;
}

__USER_FUNC_IN_RAM__ static void on_newdata_notify(void)
{
    // if (is_waiting_queue) {
    // is_waiting_queue = 0;
    // LLOGD("新消息通知, 通知spi线程进行下一次传输!!");
    // luat_rtos_event_send(spi_task_handle, 3, 2, 3, 4, 0);
    // }
    luat_event_t evt = {.id = 3};
    luat_rtos_queue_send(evt_queue, &evt, sizeof(evt), 0);
}

static void spi_gpio_setup(void)
{
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
        .bit_dict = 0,
        .master = 1,
        .mode = 1, // mode设置为1，全双工
        .bandrate = 31000000,
        .cs = 255};
    luat_pm_iovolt_ctrl(0, 3300);

    luat_spi_setup(&spi_conf);
    luat_gpio_cfg_t gpio_cfg = {0};

    // 从机准备好脚
    luat_gpio_set_default_cfg(&gpio_cfg);
    gpio_cfg.pin = AIRLINK_SPI_RDY_PIN;
    gpio_cfg.mode = LUAT_GPIO_INPUT;
    gpio_cfg.irq_type = LUAT_GPIO_FALLING_IRQ;
    gpio_cfg.pull = 0;
    luat_gpio_open(&gpio_cfg);

    // CS片选脚
    luat_gpio_set_default_cfg(&gpio_cfg);
    gpio_cfg.pin = AIRLINK_SPI_CS_PIN;
    gpio_cfg.mode = LUAT_GPIO_OUTPUT;
    gpio_cfg.pull = LUAT_GPIO_PULLUP;
    gpio_cfg.output_level = 1;
    luat_gpio_open(&gpio_cfg);

    if (g_airlink_spi_conf.irq_pin != 255)
    {
        luat_gpio_set_default_cfg(&gpio_cfg);
        gpio_cfg.pin = AIRLINK_SPI_RDY_PIN;
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
static airlink_link_data_t *link = NULL;
static uint64_t warn_slave_no_ready = 0;
static uint64_t tnow = 0;
extern void airlink_sfota_exec();

__USER_FUNC_IN_RAM__ void airlink_transfer_and_exec(uint8_t *txbuff, uint8_t *rxbuff)
{
    // 清除link
    link = NULL;

    g_airlink_statistic.tx_pkg.total++;
    luat_spi_transfer(MASTER_SPI_ID, (const char *)txbuff, TEST_BUFF_SIZE, (char *)rxbuff, TEST_BUFF_SIZE);
    luat_gpio_set(AIRLINK_SPI_CS_PIN, 1);
    // luat_airlink_print_buff("RX", rxbuff, 32);
    // 对接收到的数据进行解析
    link = luat_airlink_data_unpack(rxbuff, TEST_BUFF_SIZE);
    if (link)
    {
        g_airlink_statistic.tx_pkg.ok++;
        luat_airlink_on_data_recv(link->data, link->len);
    }
    else
    {
        g_airlink_statistic.tx_pkg.err++;
        // LLOGE("接收到数据不正确, 丢弃");
    }
}

__USER_FUNC_IN_RAM__ void airlink_wait_for_slave_ready(size_t timeout_ms)
{
    luat_gpio_set(AIRLINK_SPI_CS_PIN, 0); // 拉低片选, 等待从机就绪
    int tmpval = 0;
    for (size_t i = 0; i < timeout_ms; i++)
    {
        tmpval = luat_gpio_get(AIRLINK_SPI_RDY_PIN);
        if (tmpval == 1)
        {
            g_airlink_statistic.wait_rdy.total++;
            if (g_airlink_debug)
            {
                tnow = luat_mcu_tick64_ms();
                if (tnow - warn_slave_no_ready > 1000)
                {
                    warn_slave_no_ready = tnow;
                    LLOGD("从机未就绪,等1ms");
                }
            }
            luat_rtos_task_sleep(1);
            continue;
        }
        // LLOGD("从机已就绪!! %s %s", __DATE__, __TIME__);
        break;
    }
}

__USER_FUNC_IN_RAM__ void airlink_wait_and_prepare_data(uint8_t *txbuff)
{
    luat_event_t event = {0};
    airlink_queue_item_t item = {0};
    if (g_airlink_pause) {
        while (g_airlink_pause) {
            LLOGD("airlink spi 交互暂停中,允许主控休眠, 监测周期1000ms");
            luat_rtos_task_sleep(1000);
        }
    }
    // 等到消息
    if (link != NULL && (link->flags.queue_cmd != 0 || link->flags.queue_cmd != 0))
    {
        // 立即进行下一轮操作
        event.id = 2;
    }
    else
    {
        is_waiting_queue = 1;
        luat_rtos_queue_recv(evt_queue, &event, sizeof(luat_event_t), 5);
        is_waiting_queue = 0;
    }

    record_statistic(event);

    // LLOGD("事件id %p %d", spi_task_handle, event.id);
    if (link == NULL || (link->flags.mem_is_high) == 0)
    {
        luat_airlink_cmd_recv_simple(&item);
    }
    else
    {
        LLOGI("从机内存高水位, 停止下发IP数据");
    }
    if (item.len > 0 && item.cmd != NULL)
    {
        // LLOGD("发送待传输的数据, 塞入SPI的FIFO cmd id 0x%04X", item.cmd->cmd);
        luat_airlink_data_pack(item.cmd, item.len, txbuff);
        luat_airlink_cmd_free(item.cmd);
    }
    else
    {
        // LLOGD("填充PING数据");
        luat_airlink_data_pack(basic_info, sizeof(basic_info), txbuff);
    }
}


__USER_FUNC_IN_RAM__ static void spi_master_task(void *param)
{
    int i;
    luat_event_t event = {0};
    luat_rtos_task_sleep(5); // 等5ms
    spi_gpio_setup();
    thread_rdy = 1;
    g_airlink_newdata_notify_cb = on_newdata_notify;
    while (1)
    {
        if (g_airlink_fota != NULL && g_airlink_fota->state == 1) {
            airlink_sfota_exec();
        }

        airlink_wait_and_prepare_data(s_txbuff);
        // slave_rdy = 0;
        airlink_wait_for_slave_ready(1000); // 最多等1秒

        airlink_transfer_and_exec(s_txbuff, s_rxbuff);

        memset(s_rxbuff, 0, TEST_BUFF_SIZE);
        // start = 0;
    }
}

void luat_airlink_start_master(void)
{
    if (spi_task_handle != NULL)
    {
        LLOGE("SPI主机任务已经启动过了!!!");
        return;
    }

    s_txbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);
    s_rxbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);

    luat_rtos_queue_create(&evt_queue, 4 * 1024, sizeof(luat_event_t));
    luat_rtos_task_create(&spi_task_handle, 8 * 1024, 50, "spi", spi_master_task, NULL, 0);
}
