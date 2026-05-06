#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_airlink_devinfo.h"

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
#define UNPACK_BUFF_SIZE (8*1024)

#ifdef TYPE_EC718M
#include "platform_def.h"
#endif

#ifndef __USER_FUNC_IN_RAM__
#define __USER_FUNC_IN_RAM__
#endif



#ifdef LUAT_CONF_AIRLINK_MODE_WAIT
#define AIRLINK_MODE_WAIT_TIMEOUT 100
#else
#define AIRLINK_MODE_WAIT_TIMEOUT 15*1000
#endif

extern airlink_statistic_t g_airlink_statistic;
extern uint32_t g_airlink_pause;
extern luat_airlink_irq_ctx_t g_airlink_irq_ctx;

static uint8_t basic_info[sizeof(luat_airlink_dev_info_t) + 64];
typedef struct
{
    luat_rtos_task_handle transfer_task;
    luat_rtos_task_handle receive_task;
    luat_rtos_queue_t tx_evt_queue;
    luat_rtos_queue_t rx_evt_queue;
    uint32_t rxoffset;
    uint8_t *s_txbuff;
    uint8_t *s_rxbuff;
    uint8_t *rxbuf;
    uint8_t uart_running;
}luat_airlink_uart_ctrl_t;

static luat_airlink_uart_ctrl_t g_airlink_uart = {0};


static void luat_airlink_uart_transfer_task(void);
static void luat_airlink_uart_receive_task(void);

__USER_FUNC_IN_RAM__ static void on_newdata_notify(void)
{
    luat_event_t evt = {.id = 3};
    luat_rtos_queue_send(g_airlink_uart.tx_evt_queue, &evt, sizeof(evt), 0);
}

static void uart_cb(int uart_id, uint32_t data_len) {
    luat_event_t evt = {.id = 2};
    luat_rtos_queue_send(g_airlink_uart.rx_evt_queue, &evt, sizeof(evt), 0);
}

static void uart_gpio_setup(void)
{
    int ret = 0;
    if (g_airlink_spi_conf.uart_id == 0) {
        g_airlink_spi_conf.uart_id = 1;
    }
    ret = luat_uart_ctrl(g_airlink_spi_conf.uart_id, LUAT_UART_SET_RECV_CALLBACK, uart_cb);
    if (ret) {
        LLOGW("luat_uart_ctrl ret:%d", ret);
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


__USER_FUNC_IN_RAM__ static int on_link_data_notify(airlink_link_data_t* link) {
    // memset(&link->flags, 0, sizeof(uint32_t));
    if (g_airlink_irq_ctx.enable) {
        link->flags.irq_ready = 1;
        link->flags.irq_pin = g_airlink_irq_ctx.slave_pin - 140;
    }
    return 0;
}

static void unpack_data(uint8_t* buff, size_t len)
{
    // LLOGD("unpack_data: src len = %d", len);
    if (len < 2) {
        LLOGE("unpack_data: data too short");
        return; // 数据太短, 无法解析
    }
    // 存储最终数据到s_rxbuff
    uint8_t* unpacked_data = g_airlink_uart.s_rxbuff;
    size_t unpacked_len = 0;
    for (size_t i = 0; i < len; i++) {
        if (buff[i] == 0x7D) {
            // 转义字符, 下一个字节是转义码
            if (i + 1 < len) {
                if (buff[i + 1] == 0x02) {
                    unpacked_data[unpacked_len++] = 0x7E; // 转义为0x7E
                } else if (buff[i + 1] == 0x01) {
                    unpacked_data[unpacked_len++] = 0x7D; // 转义为0x7D
                }
                i++; // 跳过下一个字节
            }
        } else {
            unpacked_data[unpacked_len++] = buff[i]; // 普通数据直接复制
        }
    }
    if (unpacked_len < sizeof(airlink_link_data_t)) {
        // LLOGE("unpack_data: unpacked data too short, len %d", unpacked_len);
        return; // 解包后的数据太短, 无法解析
    }
    airlink_link_data_t *link = NULL;
    link = luat_airlink_data_unpack(unpacked_data, unpacked_len);
    if (link == NULL) {
        // LLOGE("luat_airlink_data_unpack failed, unpacked_len %d", unpacked_len);
        return; // 解析失败
    }
    // 解析成功了, 那就是走uart为主模式了
    if (luat_airlink_current_mode_get() == LUAT_AIRLINK_MODE_UNKNOW) {
        // LLOGD("luat_airlink_current_mode_get is UNKNOW, set to UART");
        luat_airlink_current_mode_set(LUAT_AIRLINK_MODE_UART);
    }
    // 更新最后通讯时间戳，用于airlink.ready()判断
    g_airlink_last_cmd_timestamp = luat_mcu_tick64_ms();
    // LLOGD("luat_airlink data unpacked, len: %d, data: %p", link->len, link->data);
    luat_airlink_on_data_recv(link->data, link->len);
}


void on_airlink_uart_data_in(uint8_t* buff, size_t len)
{
    // int ret = 0;
    size_t offset = 0;
    size_t end_offset = 0;
    // 首先, 输入的数据是否为0, 也可能是太长的数据
    if (len == 0) {
        return; // 不需要处理
    }
    // 按协议要求, 单个包的最大长度, 应该是 2 + 1600*2 + 2 = 3206 字节
    // 所以, 8k完全可以放入2个包
    if (g_airlink_uart.rxoffset + len > UNPACK_BUFF_SIZE) {
        LLOGW("rxbuf溢出, 重置 rxoffset=%d len=%d", g_airlink_uart.rxoffset, len);
        g_airlink_uart.rxoffset = 0;
        if (len > UNPACK_BUFF_SIZE) return;
    }
    uint8_t *rxbuff = g_airlink_uart.rxbuf;
    memcpy(rxbuff + g_airlink_uart.rxoffset, buff, len);
    g_airlink_uart.rxoffset += len;

    // 首先, 检查首个字节是不是0x7E, 如果不是, 那么就需要查找包头, 直至找到0x7E
    if (rxbuff[0] != 0x7E) {
        offset = 1;
        // 如果不是, 那么就需要查找包头, 直至找到0x7E
        while (offset < g_airlink_uart.rxoffset && rxbuff[offset] != 0x7E) {
            offset++;
        }
        if (offset >= g_airlink_uart.rxoffset) {
            //LLOGD("没有找到包头, 清空当前数据, 等待下次数据 %d", g_airlink_uart.rxoffset);
            g_airlink_uart.rxoffset = 0;
            return;
        }
        // 找到包头, 移动数据到前面
        if (offset > 1) {
            memmove(rxbuff, rxbuff + offset, g_airlink_uart.rxoffset - offset);
            g_airlink_uart.rxoffset -= offset;
        }
    }

    offset = 0;
    while (g_airlink_uart.rxoffset - offset >= 2) {
        // 搜索包头
        if (rxbuff[offset] == 0x7E) {
            // 找到包头, 继续查找包尾
            end_offset = offset + 1;
            while (end_offset < g_airlink_uart.rxoffset && rxbuff[end_offset] != 0x7E) {
                end_offset++;
                if(end_offset > 4096){
                    g_airlink_uart.rxoffset = 0;
                    LLOGE("缓存数据超4k，仍未找到包尾，丢弃数据");
                    break;
                }
            }
            if (end_offset >= g_airlink_uart.rxoffset) {
                // 没有找到包尾, 等待下次数据
                break;
            }
            // 找到包尾, 解析数据
            size_t data_len = end_offset - offset - 1; // 包头和包尾不算在内
            // 反转义数据
            if (data_len > 1) {
                unpack_data(rxbuff + offset + 1, data_len); // 包头和包尾不算在内
            }
            // 移动剩余数据到前面
            memmove(rxbuff, rxbuff + end_offset + 1, g_airlink_uart.rxoffset - end_offset - 1);
            g_airlink_uart.rxoffset -= (end_offset + 1 - offset);
        } else {
            // 没有找到包头, 移动一个字节
            offset++;
        }
    }
}

static void send_devinfo_update_evt(void) {
    airlink_queue_item_t item = {0};
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item); 
}

__USER_FUNC_IN_RAM__ static void uart_transfer_task(void *param)
{
    int ret;
    luat_event_t event = {0};
    airlink_queue_item_t item = {0};
    uint8_t* ptr = NULL;
    size_t offset = 0;
    int uart_id;
    // 单个link data的长度最大是1600字节,极端情况下所有数据都要转义,那就是3200字节,所以这里预留4K
    uint8_t *pbuff = luat_heap_malloc(4*1024);
    event.id = 0;

    while(g_airlink_uart.uart_running)
    {
        ret = luat_rtos_queue_recv(g_airlink_uart.tx_evt_queue, &event, sizeof(luat_event_t), AIRLINK_MODE_WAIT_TIMEOUT);//在evt_queue队列中复制数据到指定缓冲区event，阻塞等待60s
        if (ret == 0) {
            record_statistic(event);
        }
        #ifdef LUAT_CONF_AIRLINK_MODE_WAIT
        if (luat_airlink_current_mode_get() != LUAT_AIRLINK_MODE_UNKNOW && luat_airlink_current_mode_get() != LUAT_AIRLINK_MODE_UART) {
            luat_airlink_mode_cb_unregister(LUAT_AIRLINK_MODE_UART);
            break; // 如果当前模式已经确定了, 并且不是UART模式, 那么就退出这个任务
        }
        if (ret < 0) {
            continue; // 等待事件超时了, 继续等待
        }
        #endif
        while (1) {
            uart_id = g_airlink_spi_conf.uart_id;
            // 有数据, 要处理了
            item.len = 0;
            item.cmd = NULL;
            ret = luat_airlink_cmd_recv_for_mode(LUAT_AIRLINK_MODE_UART, &item);//从（发送）队列里取出数据存在item中
            if (ret != 0) {
                break; // 没有数据了, 退出循环
            }
            size_t len = item.len;
            uint8_t *txbuff = g_airlink_uart.s_txbuff;
            if (item.len == 0 || item.cmd == NULL) {
                memcpy(basic_info + sizeof(luat_airlink_cmd_t), luat_airlink_self_dev_info_ptr(), sizeof(luat_airlink_dev_info_t));
                luat_airlink_data_pack(basic_info, 128, pbuff);
                LLOGE("uart_transfer_task send basic info %d", sizeof(basic_info));
                len = 128;
            } else {
                luat_airlink_data_pack((uint8_t*)item.cmd, item.len, pbuff);
                luat_airlink_cmd_free(item.cmd);
            }            
            // 0x7E 开始, 0x7D 结束, 遇到 0x7E/0x7D 要转义
            txbuff[0] = 0x7E;
            offset = 1;
            ptr = (uint8_t*)pbuff;
            for (size_t i = 0; i < len + sizeof(airlink_link_data_t); i++)
            {
                if (ptr[i] == 0x7E) {
                    txbuff[offset++] = 0x7D;
                    txbuff[offset++] = 0x02;
                }
                else if (ptr[i] == 0x7D) {
                    txbuff[offset++] = 0x7D;
                    txbuff[offset++] = 0x01;
                }
                else
                {
                    txbuff[offset++] = ptr[i];
                }
            }
            txbuff[offset++] = 0x7E;
            luat_uart_write(uart_id, (const char *)txbuff, offset);
            // LLOGD("发送数据长度:%d", offset);
        }
    }
    luat_airlink_mode_cb_unregister(LUAT_AIRLINK_MODE_UART);
    LLOGI("uart_transfer_task exit");
    luat_heap_free(pbuff);
    g_airlink_uart.transfer_task = NULL;
    luat_rtos_task_delete(NULL); // 删除当前任务
}
__USER_FUNC_IN_RAM__ static void uart_receive_task(void *param)
{
    int ret;
    luat_event_t event = {0};
    int uart_id;
    event.id = 0;
    while (g_airlink_uart.uart_running)
    {
        ret = luat_rtos_queue_recv(g_airlink_uart.rx_evt_queue, &event, sizeof(luat_event_t), AIRLINK_MODE_WAIT_TIMEOUT);//在evt_queue队列中复制数据到指定缓冲区event，阻塞等待60s
        //LLOGD("收到airlink数据事件 ret:%d, id:%d", ret, event.id);
        if (ret == 0) {
            record_statistic(event);
        }
        #ifdef LUAT_CONF_AIRLINK_MODE_WAIT
        if (luat_airlink_current_mode_get() != LUAT_AIRLINK_MODE_UNKNOW && luat_airlink_current_mode_get() != LUAT_AIRLINK_MODE_UART) {
            luat_airlink_mode_cb_unregister(LUAT_AIRLINK_MODE_UART);
            break; // 如果当前模式已经确定了, 并且不是UART模式, 那么就退出这个任务
        }
        #endif

        while (1) { 
            uart_id = g_airlink_spi_conf.uart_id;
            ret = luat_uart_read(uart_id, (char *)g_airlink_uart.s_rxbuff, 1024);
            if (ret <= 0)
            {
                break;
            }
            // LLOGD("收到uart数据长度 %d", ret);
            // 推送数据, 并解析处理
            on_airlink_uart_data_in(g_airlink_uart.s_rxbuff, ret);
        }
    }
    luat_airlink_mode_cb_unregister(LUAT_AIRLINK_MODE_UART);
    LLOGI("uart_receive_task exit");
    g_airlink_uart.receive_task = NULL;
    luat_rtos_task_delete(NULL); // 删除当前任务
}

int luat_airlink_start_uart(void)
{
    
    luat_airlink_cmd_t *cmd = (luat_airlink_cmd_t *)basic_info;
    cmd->cmd = 0x10;
    cmd->len = 128;
    int ret = 0;
    g_airlink_uart.uart_running = 1;
    AIRLINK_DEV_INFO_UPDATE_CB device_info_update_cb = NULL;
#if defined(LUAT_USE_AIRLINK_EXEC_MOBILE) || defined(LUAT_USE_AIRLINK_EXEC_WLAN)
    device_info_update_cb = send_devinfo_update_evt;
    extern void luat_airlink_devinfo_init();
    luat_airlink_devinfo_init(device_info_update_cb);
#endif
    ret = luat_rtos_queue_create(&g_airlink_uart.tx_evt_queue, 128, sizeof(luat_event_t));
    if (ret) {
        LLOGW("创建tx_evt_queue ret:%d", ret);
    }
    ret = luat_rtos_queue_create(&g_airlink_uart.rx_evt_queue, 128, sizeof(luat_event_t));
    if (ret) {
        LLOGW("创建rx_evt_queue ret:%d", ret);
    }
    luat_airlink_ip2br_init();
    luat_rtos_task_sleep(5);
    uart_gpio_setup();
    luat_airlink_mode_cb_register(LUAT_AIRLINK_MODE_UART, on_newdata_notify, on_link_data_notify, device_info_update_cb);
    luat_airlink_slot_register(LUAT_AIRLINK_MODE_UART, on_newdata_notify);

    if (g_airlink_uart.s_txbuff == NULL) {
        g_airlink_uart.s_txbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);
    }
    if (g_airlink_uart.s_rxbuff == NULL) {
        g_airlink_uart.s_rxbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);
    }
    
    if (g_airlink_uart.rxbuf == NULL) {
        g_airlink_uart.rxbuf = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, UNPACK_BUFF_SIZE);
    }

    luat_airlink_uart_transfer_task();
    luat_airlink_uart_receive_task();

    return ret;
}

int luat_airlink_stop_uart(void)
{
    g_airlink_uart.uart_running = 0;
    luat_airlink_mode_cb_unregister(LUAT_AIRLINK_MODE_UART);
    if (g_airlink_uart.tx_evt_queue) {
        luat_event_t evt = {.id = 0};
        luat_rtos_queue_send(g_airlink_uart.tx_evt_queue, &evt, sizeof(evt), 0);
    }
    if (g_airlink_uart.rx_evt_queue) {
        luat_event_t evt = {.id = 0};
        luat_rtos_queue_send(g_airlink_uart.rx_evt_queue, &evt, sizeof(evt), 0);
    }
    return 0;
}

static void luat_airlink_uart_transfer_task(void)
{
    int ret = 0;
    if (g_airlink_uart.transfer_task != NULL)
    {
        LLOGE("UART TX任务已经启动过了!!! uart %d", g_airlink_spi_conf.uart_id);
        return;
    }
    ret = luat_rtos_task_create(&g_airlink_uart.transfer_task, 4 * 1024, 50, "uart_transfer", uart_transfer_task, NULL, 0);
    if (ret) {
        LLOGW("创建uart_transfer_task ret:%d", ret);
    }
}

static void luat_airlink_uart_receive_task(void)
{
    int ret = 0;
    if (g_airlink_uart.receive_task != NULL)
    {
        LLOGE("UART RX任务已经启动过了!!! uart %d", g_airlink_spi_conf.uart_id);
        return;
    }
    ret = luat_rtos_task_create(&g_airlink_uart.receive_task, 4 * 1024, 52, "uart_receive", uart_receive_task, NULL, 0);
    if (ret) {
        LLOGW("创建uart_receive_task ret:%d", ret);
    }
}
