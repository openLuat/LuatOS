#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_uart.h"
#include "luat_log.h"

#include "rtthread.h"
#include <rtdevice.h>

#ifdef RT_USING_SERIAL_V2
#include "drivers/serial_v2.h"
#else
#include "drivers/serial.h"
#endif

#define DBG_TAG           "rtt.uart"
#define DBG_LVL           DBG_WARNING
#include <rtdbg.h>

//串口数量，编号从0开始
#define MAX_DEVICE_COUNT 10
//存放串口设备句柄
static rt_device_t serials[MAX_DEVICE_COUNT];
static uint8_t serials_marks[MAX_DEVICE_COUNT];
static uint8_t uart_init_complete = 0;
rt_device_t luat_log_uart_device;

int luat_uart_rtt_init() {
    if (uart_init_complete) return 0;
    char name[8];
    name[0] = 'u';
    name[1] = 'a';
    name[2] = 'r';
    name[3] = 't';
    name[5] = 0;
    
    // 搜索uart0, uart1, ....
    for (size_t i = 0; i < MAX_DEVICE_COUNT; i++)
    {
        name[4] = '0' + i;
        serials[i] = rt_device_find(name);
        //LOG_I("uart device dev=0x%08X uart.id=%ld", serials[i], i);
    }
    luat_log_uart_device = rt_device_find(RT_CONSOLE_DEVICE_NAME);
    uart_init_complete = 1;
    return 0;
}
INIT_COMPONENT_EXPORT(luat_uart_rtt_init);

static int get_uart_id(rt_device_t dev) {
    int i;
    for(i=0;i<MAX_DEVICE_COUNT;i++)
    {
        if (serials[i] == dev) {
            //LOG_I("uart device dev->id=%d uart.id=%ld", dev->device_id, i);
            return i;
        }
    }
    LOG_W("not uart device dev=0x%08X", dev);
    return -1;
}

int luat_uart_exist(int uartid) {
    if (uartid < 0 || uartid >= MAX_DEVICE_COUNT) {
        return 0;
    }
    luat_uart_rtt_init();
    return serials[uartid] ? 1 : 0;
}

//接收数据回调
static rt_err_t uart_input_cb(rt_device_t dev, rt_size_t size)
{
    int uart_id = get_uart_id(dev);
    LOG_I("uart receive rtt cb, id=%ld", uart_id);
    if (uart_id < 0) {
        return RT_EOK;
    }
    if (serials_marks[uart_id]) {
        // 前一个回调都还没读呢
        return RT_EOK;
    }
    serials_marks[uart_id] = 1;
    rtos_msg_t msg;
    msg.handler = l_uart_handler;
    msg.ptr = RT_NULL;
    msg.arg1 = uart_id;
    msg.arg2 = size;
    luat_msgbus_put(&msg, 1);
    return RT_EOK;
}

//串口发送完成事件回调
static rt_err_t uart_sent_cb(rt_device_t dev, void *buffer)
{
    int uart_id = get_uart_id(dev);
    LOG_I("uart sent rtt cb, id=%ld", uart_id);
    if (uart_id < 0) {
        return RT_EOK;
    }
    rtos_msg_t msg;
    msg.handler = l_uart_handler;
    msg.arg1 = uart_id;
    msg.arg2 = 0;
    msg.ptr = buffer;
    luat_msgbus_put(&msg, 1);
    return RT_EOK;
}

int luat_uart_setup(luat_uart_t* uart)
{
    if(uart->id > MAX_DEVICE_COUNT)
    {
        return -1;
    }
    rt_device_t dev = serials[uart->id];
    if (dev == RT_NULL) {
        return -2;
    }

    struct serial_configure config = RT_SERIAL_CONFIG_DEFAULT;
    config.baud_rate = uart->baud_rate;
    config.data_bits = uart->data_bits;
    config.stop_bits = uart->stop_bits - 1;
#ifdef RT_USING_SERIAL_V2
    config.rx_bufsz     = 512;
    config.tx_bufsz     = 1024;
#else
    //config.bufsz     = uart->bufsz;
    config.bufsz     = 512;
#endif
    config.parity    = uart->parity;
    config.bit_order = uart->bit_order;
    rt_device_control(dev, RT_DEVICE_CTRL_CONFIG, &config);

    rt_err_t re = rt_device_open(dev, RT_DEVICE_FLAG_INT_RX);
    if(re != RT_EOK)
        return re;//失败了
    return re;
}
#ifdef FALSE123
#include "wm_uart.h"
int tls_uart_dma_write(char *buf, u16 writesize, void (*cmpl_callback) (void *p), u16 uart_no);
#endif
int luat_uart_write(int uartid, void* data, size_t length)
{
    if(!luat_uart_exist(uartid)) {
        LOG_W("luat_uart_write uart id=%d not exist", uartid);
        return -1;
    }
    if (serials[uartid]->open_flag == 0) {
        LOG_W("uart id=%d is closed", uartid);
        return -1;
    }
    if (uartid == 1)
    {
    #ifdef FALSE123
        int re = tls_uart_dma_write(data, length, RT_NULL, 1);
        LOG_I("tls_uart_dma_write re=%d", re);
        return 0;
    #endif
    }
    int re = rt_device_write(serials[uartid], 0, data, length);
    LOG_I("luat_uart_write id=%ld re=%ld length=%ld", uartid, re, length);
    return re;
}

int luat_uart_read(int uartid, void* buffer, size_t length)
{
    if(!luat_uart_exist(uartid)) {
        LOG_W("uart id=%d not exist", uartid);
        return -1;
    }
    if (serials[uartid]->open_flag == 0) {
        LOG_W("uart id=%d is closed", uartid);
        return -1;
    }
    serials_marks[uartid] = 0;
    int re = rt_device_read(serials[uartid], -1, buffer, length);
    return re;
}

int luat_uart_close(int uartid)
{
    if(!luat_uart_exist(uartid)) {
        LOG_W("uart id=%d not exist", uartid);
        return 0;
    }
    int re = rt_device_close(serials[uartid]);
    return re;
}

int luat_setup_cb(int uartid, int received, int sent) {
    if (!luat_uart_exist(uartid)) {
        LOG_W("uart id=%d not exist", uartid);
        return -1;
    }
    if (received) {
        LOG_I("uart id=%d set rx_indicate", uartid);
        rt_device_set_rx_indicate(serials[uartid], uart_input_cb);
    }
    else {
        LOG_I("uart id=%d unset rx_indicate", uartid);
        rt_device_set_rx_indicate(serials[uartid], RT_NULL);
    }

    if (sent) {
        LOG_I("uart id=%d set tx_complete", uartid);
        rt_device_set_tx_complete(serials[uartid], uart_sent_cb);
    }
    else {
        LOG_I("uart id=%d unset tx_complete", uartid);
        rt_device_set_tx_complete(serials[uartid], RT_NULL);
    }
    return 0;
}
