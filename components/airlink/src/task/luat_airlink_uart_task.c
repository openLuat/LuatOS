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

// static luat_rtos_task_handle g_uart_task;
static luat_rtos_task_handle g_uart_transfer_task;
static luat_rtos_task_handle g_uart_receive_task;
// static luat_rtos_queue_t evt_queue;
static luat_rtos_queue_t tx_evt_queue;// 
static luat_rtos_queue_t rx_evt_queue;
extern luat_airlink_irq_ctx_t g_airlink_irq_ctx;

static void luat_airlink_uart_transfer_task(void);
static void luat_airlink_uart_receive_task(void);

__USER_FUNC_IN_RAM__ static void on_newdata_notify(void)
{
    luat_event_t evt = {.id = 3};
    luat_rtos_queue_send(tx_evt_queue, &evt, sizeof(evt), 0);
}

static void uart_cb(int uart_id, uint32_t data_len) {
    luat_event_t evt = {.id = 2};
    luat_rtos_queue_send(rx_evt_queue, &evt, sizeof(evt), 0);
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

static uint8_t *s_txbuff;
static uint8_t *s_rxbuff;
// static airlink_link_data_t s_link;

__USER_FUNC_IN_RAM__ static void on_link_data_notify(airlink_link_data_t* link) {
    memset(&link->flags, 0, sizeof(uint32_t));
    if (g_airlink_irq_ctx.enable) {
        link->flags.irq_ready = 1;
        link->flags.irq_pin = g_airlink_irq_ctx.slave_pin - 140;
    }
}

static void parse_data(uint8_t* buff, size_t len)
{
    // luat_airlink_print_buff("反转义前的数据", buff,  len);
    // 收到数据后去除帧头帧尾和魔数，遇到0x7E/0x7D 要转义
    uint8_t* parse_buff = buff;
    size_t parse_len = len - 2;
    memcpy(parse_buff, buff+1, parse_len);//去帧头帧尾
    // //反转义
    for(int i = 0; i < parse_len; i++)
    {
        if(parse_buff[i] == 0x7D && parse_buff[i + 1] == 0x02) {
            parse_buff[i] = 0x7E;
            parse_len--;
        }
        else if(parse_buff[i] == 0x7D && parse_buff[i + 1] == 0x01) {
            parse_buff[i] = 0x7D;
            parse_len--;
        }
    }
    airlink_link_data_t *link = luat_airlink_data_unpack(parse_buff, parse_len);
    if (link == NULL)
    {
        LLOGE("luat_airlink_data_unpack failed len %d", parse_len);
        return;
    }
    // LLOGD("luat_airlink data unpacked, len: %d, data: %p", link->len, link->data);
    luat_airlink_on_data_recv(link->data, link->len);
}

static void unpack_data(uint8_t* buff, size_t len)
{
    // LLOGD("unpack_data: src len = %d", len);
    if (len < 2) {
        LLOGE("unpack_data: data too short");
        return; // 数据太短, 无法解析
    }
    // 存储最终数据到s_rxbuff
    uint8_t* unpacked_data = s_rxbuff;
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
    // LLOGD("luat_airlink data unpacked, len: %d, data: %p", link->len, link->data);
    luat_airlink_on_data_recv(link->data, link->len);
}

#define UNPACK_BUFF_SIZE (8*1024)
static uint8_t* rxbuf;
static uint32_t rxoffset = 0;
void on_airlink_uart_data_in(uint8_t* buff, size_t len)
{
    // int ret = 0;
    size_t offset = 0;
    size_t end_offset = 0;
    // 首先, 输入的数据是否为0, 也可能是太长的数据
    if (len == 0) {
        return; // 不需要处理
    }
    if (rxbuf == NULL) {
        // 分配内存
        rxbuf = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, UNPACK_BUFF_SIZE);
        if (rxbuf == NULL) {
            LLOGE("无法分配内存给rxbuf");
            return; // 内存分配失败
        }
    }
    if (s_rxbuff == NULL) {
        // 分配内存给s_rxbuff
        s_rxbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, UNPACK_BUFF_SIZE);
        if (s_rxbuff == NULL) {
            LLOGE("无法分配内存给s_rxbuff");
            return; // 内存分配失败
        }
    }
    // 按协议要求, 单个包的最大长度, 应该是 2 + 1600*2 + 2 = 3206 字节
    // 所以, 8k完全可以放入2个包
    memcpy(rxbuf + rxoffset, buff, len);
    rxoffset += len;

    // 首先, 检查首个字节是不是0x7E, 如果不是, 那么就需要查找包头, 直至找到0x7E
    if (rxbuf[0] != 0x7E) {
        offset = 1;
        // 如果不是, 那么就需要查找包头, 直至找到0x7E
        while (offset < rxoffset && rxbuf[offset] != 0x7E) {
            offset++;
        }
        if (offset >= rxoffset) {
            LLOGW("没有找到包头, 清空当前数据, 等待下次数据 %d", rxoffset);
            rxoffset = 0;
            return;
        }
        // 找到包头, 移动数据到前面
        if (offset > 1) {
            memmove(rxbuf, rxbuf + offset, rxoffset - offset);
            rxoffset -= offset;
        }
    }

    offset = 0;
    while (rxoffset - offset >= 2) {
        // 搜索包头
        if (rxbuf[offset] == 0x7E) {
            // 找到包头, 继续查找包尾
            end_offset = offset + 1;
            while (end_offset < rxoffset && rxbuf[end_offset] != 0x7E) {
                end_offset++;
                if(end_offset > 4096){
                    rxoffset = 0;
                    LLOGD("缓存数据超4k，仍未找到包尾，丢弃数据");
                    break;
                }
            }
            if (end_offset >= rxoffset) {
                // 没有找到包尾, 等待下次数据
                break;
            }
            // 找到包尾, 解析数据
            size_t data_len = end_offset - offset - 1; // 包头和包尾不算在内
            // 反转义数据
            if (data_len > 1) {
                unpack_data(rxbuf + offset + 1, data_len); // 包头和包尾不算在内
            }
            // 移动剩余数据到前面
            memmove(rxbuf, rxbuf + end_offset + 1, rxoffset - end_offset - 1);
            rxoffset -= (end_offset + 1 - offset);
        } else {
            // 没有找到包头, 移动一个字节
            offset++;
        }
    }
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

    while(1)
    {
        ret = luat_rtos_queue_recv(tx_evt_queue, &event, sizeof(luat_event_t), 15*1000);//在evt_queue队列中复制数据到指定缓冲区event，阻塞等待60s
        (void)ret;
        //LLOGD("收到airlink数据事件 ret:%d, id:%d", ret, event.id);
        record_statistic(event);
        while (1) {
            uart_id = g_airlink_spi_conf.uart_id;
            // 有数据, 要处理了
            item.len = 0;
            item.cmd = NULL;
            luat_airlink_cmd_recv_simple(&item);//从（发送）队列里取出数据存在item中
            // LLOGD("队列数据长度:%d, cmd:%p", item.len, item.cmd);
            if (item.len > 0 && item.cmd != NULL)
            {
                // 0x7E 开始, 0x7D 结束, 遇到 0x7E/0x7D 要转义
                luat_airlink_data_pack((uint8_t*)item.cmd, item.len, pbuff);
                // int temp_len = sizeof(pbuff)/sizeof(pbuff[0]);
                s_txbuff[0] = 0x7E;
                offset = 1;
                ptr = (uint8_t*)pbuff;
                for (size_t i = 0; i < item.len + sizeof(airlink_link_data_t); i++)
                {
                    if (ptr[i] == 0x7E) {
                        s_txbuff[offset++] = 0x7D;
                        s_txbuff[offset++] = 0x02;
                    }
                    else if (ptr[i] == 0x7D) {
                        s_txbuff[offset++] = 0x7D;
                        s_txbuff[offset++] = 0x01;
                    }
                    else
                    {
                        s_txbuff[offset++] = ptr[i];
                    }
                }
                s_txbuff[offset++] = 0x7E;
                luat_uart_write(uart_id, (const char *)s_txbuff, offset);
                // LLOGD ("发送数据长度:%d", offset);
                luat_airlink_cmd_free(item.cmd);
            }
            else {
                break; // 没有数据了, 退出循环
            }
        }
    }
}
__USER_FUNC_IN_RAM__ static void uart_receive_task(void *param)
{
    int ret;
    luat_event_t event = {0};
    int uart_id;
    event.id = 0;
    while (1)
    {
        ret = luat_rtos_queue_recv(rx_evt_queue, &event, sizeof(luat_event_t), 15*1000);//在evt_queue队列中复制数据到指定缓冲区event，阻塞等待60s
        //LLOGD("收到airlink数据事件 ret:%d, id:%d", ret, event.id);
        record_statistic(event);
        while (1) { 
            uart_id = g_airlink_spi_conf.uart_id;
            ret = luat_uart_read(uart_id, (char *)s_rxbuff, 1024);
            // LLOGD("uart_task:uart read buff len:%d", ret);
            if (ret <= 0)
            {
                break;
            }
            else
            {
                // LLOGD("收到uart数据长度 %d", ret);
                // 推送数据, 并解析处理
                on_airlink_uart_data_in(s_rxbuff, ret);
            }
        }
    }
}
void luat_airlink_start_uart(void)
{
    int ret = 0;
    
    ret = luat_rtos_queue_create(&tx_evt_queue, 4 * 1024, sizeof(luat_event_t));
    if (ret) {
        LLOGW("创建tx_evt_queue ret:%d", ret);
    }
    ret = luat_rtos_queue_create(&rx_evt_queue, 4 * 1024, sizeof(luat_event_t));
    if (ret) {
        LLOGW("创建rx_evt_queue ret:%d", ret);
    }
    luat_rtos_task_sleep(5);
    uart_gpio_setup();
    g_airlink_newdata_notify_cb = on_newdata_notify;
    g_airlink_link_data_cb = on_link_data_notify;

    luat_airlink_uart_transfer_task();
    luat_airlink_uart_receive_task();
}

static void luat_airlink_uart_transfer_task(void)
{
    int ret = 0;
    if (g_uart_transfer_task != NULL)
    {
        LLOGE("UART TX任务已经启动过了!!! uart %d", g_airlink_spi_conf.uart_id);
        return;
    }
    s_txbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);
    ret = luat_rtos_task_create(&g_uart_transfer_task, 8 * 1024, 50, "uart_transfer", uart_transfer_task, NULL, 0);
    if (ret) {
        LLOGW("创建uart_transfer_task ret:%d", ret);
    }
}

static void luat_airlink_uart_receive_task(void)
{
    int ret = 0;
    if (g_uart_receive_task != NULL)
    {
        LLOGE("UART RX任务已经启动过了!!! uart %d", g_airlink_spi_conf.uart_id);
        return;
    }
    s_rxbuff = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, TEST_BUFF_SIZE);
    rxbuf = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, UNPACK_BUFF_SIZE);

    ret = luat_rtos_task_create(&g_uart_receive_task, 8 * 1024, 52, "uart_receive", uart_receive_task, NULL, 0);
    if (ret) {
        LLOGW("创建uart_receive_task ret:%d", ret);
    }
}
