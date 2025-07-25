#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"

#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#define TEST_BUFF_SIZE (1600)
#define SLAVE_SPI_ID g_airlink_spi_conf.spi_id
#define AIRLINK_SPI_CS_PIN g_airlink_spi_conf.cs_pin
#define AIRLINK_SPI_RDY_PIN g_airlink_spi_conf.rdy_pin
#define AIRLINK_SPI_IRQ_PIN g_airlink_spi_conf.irq_pin

#ifdef TYPE_EC718M
#include "platform_def.h"
#endif

static uint8_t thread_rdy;
static luat_rtos_task_handle spi_task_handle;
extern airlink_statistic_t g_airlink_statistic;
extern uint32_t g_airlink_pause;

static uint8_t *s_txbuff;
static uint8_t *s_rxbuff;
static int self_ready;
static int pin_rdy_state;
static uint8_t g_sys_need_reboot;
static int is_irq_mode;
static uint32_t irq_counter; // 中断计数

static uint8_t basic_info[sizeof(luat_airlink_dev_info_t) + 64];
static inline luat_airlink_dev_info_t * self_devinfo(void) {
    luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)basic_info;
    return (luat_airlink_dev_info_t *)(cmd->data);
}

static void print_tm(const char* tag) {
    uint32_t tm = (uint32_t)luat_mcu_tick64_ms();
    LLOGD("TM[%s] %8ld", tag, tm);
}

// 更新link的链路状态
// extern uint32_t g_fota_busy;
static int link_data_cb(airlink_link_data_t* link) {
    link->flags.irq_ready = is_irq_mode;
    // if (MEM_MAX_TX_SIZE - lwip_stats.mem.tx_used < 8 * 1024) {
    //     LLOGD("TX内存高水位 %d %d %d", MEM_MAX_TX_SIZE, lwip_stats.mem.tx_used, MEM_MAX_TX_SIZE - lwip_stats.mem.tx_used);
    
    //     link->flags.mem_is_high = 1; // 链路繁忙!!!
    //     return 0;
    // }
    // if (g_fota_busy) {
    //     link->flags.mem_is_high = 1; // 链路繁忙!!
    //     return 0;
    // }

    size_t len = 0;
    len = luat_airlink_queue_get_cnt(LUAT_AIRLINK_QUEUE_CMD);
    if (len > 0) {
        link->flags.queue_cmd = 1;
        // LLOGD("剩余CMD数据队列长度 %d", len);
    }
    len = luat_airlink_queue_get_cnt(LUAT_AIRLINK_QUEUE_IPPKG);
    if (len > 0) {
        link->flags.queue_ip = 1;
        // LLOGD("剩余IP数据队列长度 %d", len);
    }
    return 0;
}

__USER_FUNC_IN_RAM__ static void on_newdata_notify(void) {
    if (is_irq_mode) {
        // LLOGD("is_irq_mode %d pin %d count %ld", is_irq_mode, s_irq_pin, irq_counter);
        luat_gpio_set(AIRLINK_SPI_IRQ_PIN, 0);
        luat_gpio_set(AIRLINK_SPI_IRQ_PIN, 1);
        irq_counter ++;
    }
}

static void send_devinfo_update_evt(void) {
    airlink_queue_item_t item = {0};
    // 发送空消息, 会自动转为devinfo消息
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item); 
}

__USER_FUNC_IN_RAM__ static int spi_slave_irq(void* param) {
    if (self_ready == 0) {
        return 0;
    }
    // 立即拉高RDY脚, 阻止主机的发送
    pin_rdy_state = 1;
    luat_gpio_set(AIRLINK_SPI_RDY_PIN, 0);
    luat_rtos_event_send(spi_task_handle, 1, 0, 0, 0, 0);
    return 0;
}

static void slave_irq_mode_startup(airlink_link_data_t* link) {
    luat_gpio_cfg_t gpio  = {0};
    int ret = 0;
    gpio.pin = AIRLINK_SPI_IRQ_PIN;
    gpio.mode = LUAT_GPIO_OUTPUT;
    gpio.pull = LUAT_GPIO_PULLUP;
    gpio.output_level = 1;
    ret = luat_gpio_open(&gpio);
    LLOGD("IRQ模式开启, GPIO %d %d", gpio.pin, ret);
    // s_irq_pin = gpio.pin;
    // is_irq_mode = 1;
}


static void spi_slave_transfer_cb()
{
    
}

static void spi_gpio_setup(void)
{
    LLOGD("spi_gpio_setup");
    LLOGD("g_airlink_spi_conf %p", &g_airlink_spi_conf);
    int ret = 0;
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

    LLOGI("spi slave id %d cs %d rdy %d irq %d", SLAVE_SPI_ID, g_airlink_spi_conf.cs_pin, g_airlink_spi_conf.rdy_pin, g_airlink_spi_conf.irq_pin);

    luat_pm_iovolt_ctrl(0, 3300);

    luat_gpio_cfg_t gpio_cfg = {0};

    // 从机准备好脚
    luat_spi_t spi_conf = {
        .id = SLAVE_SPI_ID,
        .CPOL = 1,
        .CPHA = 1,
        .dataw = 8,
        .bit_dict = 0,
        .master = 0,    // 1 主模式; 0 从模式
        .mode = 1, // mode设置为1，全双工
        .bandrate = 31000000,
        .cs = 255};
    
    ret = luat_spi_setup(&spi_conf);
    LLOGD("luat_spi_setup result %d", ret);

    // CS片选脚
    luat_gpio_set_default_cfg(&gpio_cfg);
    gpio_cfg.pin = AIRLINK_SPI_CS_PIN;
    gpio_cfg.mode = LUAT_GPIO_IRQ;
    gpio_cfg.irq_type = LUAT_GPIO_FALLING_IRQ;
    gpio_cfg.pull = LUAT_GPIO_PULLUP;
    gpio_cfg.irq_cb = spi_slave_irq;
    ret = luat_gpio_open(&gpio_cfg);
    if (ret) {
        LLOGW("初始化CS(GPIO %d) ret %d", AIRLINK_SPI_CS_PIN, ret);
    }

    if (g_airlink_spi_conf.rdy_pin != 255)
    {
        luat_gpio_set_default_cfg(&gpio_cfg);
        gpio_cfg.pin = g_airlink_spi_conf.rdy_pin;
        gpio_cfg.mode = LUAT_GPIO_OUTPUT;
        gpio_cfg.pull = LUAT_GPIO_PULLUP;
        gpio_cfg.output_level = 1;
        ret = luat_gpio_open(&gpio_cfg);
        if (ret) {
            LLOGW("初始化RDY(GPIO %d) ret %d", AIRLINK_SPI_RDY_PIN, ret);
        }
        pin_rdy_state = 1;
    }
}

static uint32_t sta_ap_info_update_tm;

__USER_FUNC_IN_RAM__ static void start_spi_trans(void) {
    // 首先, 把rxbuff填0, 不要收到老数据的干扰
    LLOGD("执行start_spi_trans");
    memset(s_rxbuff, 0, TEST_BUFF_SIZE);
    airlink_queue_item_t item = {0};
    // print_tm("准备执行luat_airlink_cmd_recv_simple");
    luat_airlink_cmd_recv_simple(&item);
    LLOGD("执行完luat_airlink_cmd_recv_simple cmd %p len %d", item.cmd, item.len);
    if (item.len > 0 && item.cmd != NULL) {
        // LLOGD("发送待传输的数据, 塞入SPI的FIFO %d", item.len);
        luat_airlink_data_pack(item.cmd, item.len, s_txbuff);
        luat_airlink_cmd_free(item.cmd);
    }
    else {
        // LLOGD("填充PING数据");
        sta_ap_info_update_tm ++;
        luat_airlink_data_pack(basic_info, sizeof(basic_info), s_txbuff);
    }

    // luat_spi_slave_transfer(SLAVE_SPI_ID, (const char *)s_txbuff, (char *)s_rxbuff, TEST_BUFF_SIZE);
    luat_spi_slave_transfer(SLAVE_SPI_ID, (const char*)s_txbuff, (char*)s_rxbuff, TEST_BUFF_SIZE);
    // luat_spi_no_block_transfer(SLAVE_SPI_ID, s_txbuff, s_rxbuff, TEST_BUFF_SIZE * 2, spi_slave_transfer_cb, NULL);
    LLOGD("spi slave transfer done");
    LLOGD("slave 接收的数据");
    // print_hex(s_rxbuff, TEST_BUFF_SIZE);
    LLOGD("slave 发送的数据");
    // print_hex(s_txbuff, TEST_BUFF_SIZE);

    // 通知主机已经准备好了
    luat_gpio_set(AIRLINK_SPI_RDY_PIN, 1);
    pin_rdy_state = 0;
}

void print_hex(const unsigned char *buffer, size_t size) {
    char hex_str[3 * size + 1]; // 每个字节需要3个字符（2个十六进制字符+1个空格），最后加一个终止符
    for (size_t i = 0; i < size; i++) {
        snprintf(&hex_str[i * 3], 4, "%02X ", buffer[i]);
    }
    hex_str[3 * size] = '\0'; // 确保字符串以空字符结尾
    LLOGD("数据 %s\n", hex_str);
}

__USER_FUNC_IN_RAM__ static void spi_slave_task(void *param)
{
    LLOGE("spi_slave_task!!!");
    int ret = 0;
    int i;
    airlink_link_data_t* link = NULL;
    luat_event_t event = {0};

    luat_rtos_task_sleep(5); // 等5ms
    s_txbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);
    s_rxbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);

    luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)basic_info;
    cmd->cmd = 0x10;
    cmd->len = 128;
    
    luat_airlink_dev_info_t *devinfo = self_devinfo();
    devinfo->tp = 0x01;

    // // 执行主循环
    self_ready = 1;
    g_airlink_link_data_cb = link_data_cb;
    g_airlink_newdata_notify_cb = on_newdata_notify;
    // // bk_spi_dma_duplex_init(SLAVE_SPI_ID);
    start_spi_trans();
    while (1) {   
        // // 执行主循环
        event.id = 0;
        // print_tm("执行luat_rtos_event_recv");
        luat_rtos_event_recv(spi_task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
        // print_tm("执行完luat_rtos_event_recv");
        int cs_level = luat_gpio_get(AIRLINK_SPI_CS_PIN);
        LLOGD("CS脚状态 %d %s %s event.id %d ret %d %p", cs_level, __DATE__, __TIME__, event.id, ret, spi_task_handle);
        if (cs_level == 1) {
            #if 1
            print_tm("执行luat_spi_slave_transfer_pause_and_read_data");
            int len = luat_spi_slave_transfer_pause_and_read_data(SLAVE_SPI_ID);
            g_airlink_statistic.tx_pkg.total++;
            // if (len > 0 && len < 2024) {
                LLOGD("数据长度 %d %d", len, SLAVE_SPI_ID);
            //     link = luat_airlink_data_unpack(s_rxbuff, len);
            //     if (link) {
            //         g_airlink_statistic.tx_pkg.ok++;
            //         luat_airlink_on_data_recv(link->data, link->len);
            //         g_airlink_last_cmd_timestamp = luat_mcu_tick64_ms();
            //     }
            //     else {
            //         g_airlink_statistic.tx_pkg.err++;
            //         LLOGW("数据包错误, 重置SPI");
            //         luat_spi_close(SLAVE_SPI_ID);
            //         spi_gpio_setup();
            //     }
            //     // print_tm("执行完luat_airlink_data_unpack");
            // }
            // else {
            //     LLOGW("数据长度错误 %d %d", len, SLAVE_SPI_ID);
            // }
            // LLOGD("恢复到普通状态, 等待下一轮传输 %d", ret);
            
            memcpy(s_txbuff, s_rxbuff, len);
            // print_hex(s_rxbuff, len);
            luat_airlink_print_buff("slave RX", s_rxbuff, len);
            // print_hex(s_txbuff, len);
            luat_airlink_print_buff("slave TX", s_txbuff, len);
            // luat_spi_slave_transfer(SLAVE_SPI_ID, (const char* )s_txbuff, (char*)s_rxbuff, TEST_BUFF_SIZE);
            luat_spi_slave_transfer(SLAVE_SPI_ID, (const char*)s_txbuff, (char*)s_rxbuff, TEST_BUFF_SIZE);
            // LLOGD("slave 接收的数据 %s", s_rxbuff);
            luat_airlink_print_buff("send done slave RX", s_rxbuff, len);
            // print_hex(s_rxbuff, len);
            memset(s_rxbuff, 0, len);
            luat_gpio_set(AIRLINK_SPI_RDY_PIN, 0);
            // pin_rdy_state = 0;
            #endif
        }
        // LLOGD("g_sys_need_reboot %d, 退出SPI从机任务!!", g_sys_need_reboot);
    }
    // // luat_spislave_stop(SLAVE_SPI_ID);
    // // bk_spi_deinit(SLAVE_SPI_ID);
    while (1) {
    //     // 循环执行复位
        luat_rtos_task_sleep(1000);
    //     LLOGD("尝试重启系统 %d", g_sys_need_reboot);
    //     // bk_reboot();
    }
}

#ifndef __BK72XX__
void luat_airlink_start_slave(void)
{
    LLOGE("luat_airlink_start_slave!!!");
    if (spi_task_handle != NULL)
    {
        LLOGE("SPI从机任务已经启动过了!!!");
        return;
    }
    
    spi_gpio_setup();

    luat_rtos_task_create(&spi_task_handle, 8 * 1024, 50, "spi_slave", spi_slave_task, NULL, 1024);
}
#endif
