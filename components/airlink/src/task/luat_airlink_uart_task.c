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

#define TEST_BUFF_SIZE (4096)

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
static luat_rtos_task_handle g_uart_task;
static uint8_t basic_info[256];
static luat_rtos_queue_t evt_queue;
extern luat_airlink_irq_ctx_t g_airlink_irq_ctx;


__USER_FUNC_IN_RAM__ static void on_newdata_notify(void)
{
    luat_event_t evt = {.id = 3};
    luat_rtos_queue_send(evt_queue, &evt, sizeof(evt), 0);
}

static void uart_cb(uint8_t *data, size_t len) {
    // nop
}

static void uart_gpio_setup(void)
{
    if (g_airlink_spi_conf.uart_id == 0) {
        g_airlink_spi_conf.uart_id = 1;
    }
    luat_uart_ctrl(g_airlink_spi_conf.uart_id, LUAT_UART_SET_RECV_CALLBACK, uart_cb);
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
static uint8_t slave_is_irq_ready = 0;

__USER_FUNC_IN_RAM__ static void on_link_data_notify(airlink_link_data_t* link) {
    memset(&link->flags, 0, sizeof(uint32_t));
    if (g_airlink_irq_ctx.enable) {
        link->flags.irq_ready = 1;
        link->flags.irq_pin = g_airlink_irq_ctx.slave_pin - 140;
    }
}

static void on_uart_data_in(uint8_t* buff, size_t len) {
    //收到数据后去除帧头帧尾和魔数，遇到0x7E/0x7D 要转义
    uint8_t* receive_data = buff;
    size_t receive_len = len-2;
    memcpy(receive_data, buff+1, receive_len);//去帧头帧尾
    for(int i = 0; i < receive_len; i++)
    {
        if(receive_data[i] == 0x7D && receive_data[i + 1] == 0x02) {
            receive_data[i] = 0x7E;
            receive_len--;
        }
        else if(receive_data[i] == 0x7D && receive_data[i + 1] == 0x01) {
            receive_data[i] = 0x7D;
            receive_len--;
        }
    }
    airlink_link_data_t *return_rxbuff = luat_airlink_data_unpack(receive_data, receive_len);
}

__USER_FUNC_IN_RAM__ static void uart_task(void *param)
{
    int ret;
    luat_event_t event = {0};
    airlink_queue_item_t item = {0};
    uint8_t* ptr = NULL;
    size_t offset = 0;
    int uart_id;
    luat_rtos_task_sleep(5); // 等5ms
    uart_gpio_setup();
    thread_rdy = 1;
    g_airlink_newdata_notify_cb = on_newdata_notify;
    g_airlink_link_data_cb = on_link_data_notify;
    uint8_t pbuff[2048] = {0};
    while (1)
    {
        uart_id = g_airlink_spi_conf.uart_id;
        LLOGD("uart_task:uart_id:%d", uart_id);
        while (1) {
            ret = luat_uart_read(uart_id, (char *)s_rxbuff, TEST_BUFF_SIZE);
            LLOGD("uart_task:uart read buff len:%d", ret);
            if (ret <= 0) {
                break;
            }
            else {
                // LLOGD("收到uart数据长度 %d", ret);
                for(int i = 0; i < (sizeof(s_rxbuff)/sizeof(s_rxbuff[0])); i++)
                    LLOGD("收到uart数据 %x", s_rxbuff[i]);
                // TODO 推送数据, 并解析处理
                on_uart_data_in(s_rxbuff, ret);
            }
        }
        ret = luat_rtos_queue_recv(evt_queue, &event, sizeof(luat_event_t), 15*1000);//在evt_queue队列中复制数据到指定缓冲区event，阻塞等待60s
        if (ret == 0) {
            // 有数据, 要处理了
            item.len = 0;
            luat_airlink_cmd_recv_simple(&item);//从（发送）队列里取出数据存在item中
            if (item.len > 0 && item.cmd != NULL)
            {
                // 0x7E 开始, 0x7D 结束, 遇到 0x7E/0x7D 要转义
                luat_airlink_data_pack((uint8_t*)item.cmd, item.len, pbuff);
                int temp_len = sizeof(pbuff)/sizeof(pbuff[0]);
                s_txbuff[0] = 0x7E;
                offset = 1;
                ptr = (uint8_t*)pbuff;
                for (size_t i = 0; i < item.len + sizeof(airlink_link_data_t); i++)
                {
                    if (ptr[i] == 0x7E) {
                        s_txbuff[offset++] = 0x7D;
                        s_txbuff[offset++] = 0x02;
                        if(i < item.len + sizeof(airlink_link_data_t) - 1)  i++;
                        else 
                        {
                            break;
                        }
                    }
                    else if (ptr[i] == 0x7D) {
                        s_txbuff[offset++] = 0x7D;
                        s_txbuff[offset++] = 0x01;
                        if(i < item.len + sizeof(airlink_link_data_t) - 1)  i++;
                        else 
                        {
                            break;
                        }
                    }
                    {
                        s_txbuff[offset++] = ptr[i];
                    }
                }
                s_txbuff[offset++] = 0x7E;
                luat_uart_write(uart_id, (const char *)s_txbuff, offset);
            }
        }
    }
}

void luat_airlink_start_uart(void)
{
    if (g_uart_task != NULL)
    {
        LLOGE("SPI主机任务已经启动过了!!!");
        return;
    }

    s_txbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);
    s_rxbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);

    luat_rtos_queue_create(&evt_queue, 4 * 1024, sizeof(luat_event_t));
    luat_rtos_task_create(&g_uart_task, 8 * 1024, 50, "uart", uart_task, NULL, 0);
}
