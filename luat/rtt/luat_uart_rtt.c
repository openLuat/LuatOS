#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_uart.h"

#include "rtthread.h"
#include <rtdevice.h>
#include "drivers/serial.h"

//串口数量，编号从0开始
#define MAX_DEVICE_COUNT 2
//存放串口设备句柄
static rt_device_t serials[MAX_DEVICE_COUNT] = {NULL};

typedef struct callback {
    int received;//回调函数
    int sent;//回调函数
} callback;
static callback uart_funcion[MAX_DEVICE_COUNT] = {NULL};

//接收数据回调
static rt_err_t uart_input(rt_device_t dev, rt_size_t size)
{
    uint8_t i;
    for(i=0;i<MAX_DEVICE_COUNT;i++)
    {
        if(serials[i] != NULL && serials[i]->device_id == dev->device_id)
        {
            rtos_msg_t msg;
            msg.handler = l_uart_handler;
            msg.ptr = uart_funcion[i].received;
            luat_msgbus_put(&msg, 1);
            break;
        }
    }
    return RT_EOK;
}

//串口发送完成事件回调
static rt_err_t uart_sent(rt_device_t dev, void *buffer)
{
    uint8_t i;
    for(i=0;i<MAX_DEVICE_COUNT;i++)
    {
        if(serials[i] != NULL && serials[i]->device_id == dev->device_id)
        {
            rtos_msg_t msg;
            msg.handler = l_uart_handler;
            msg.ptr = uart_funcion[i].sent;
            luat_msgbus_put(&msg, 1);
            break;
        }
    }
    return RT_EOK;
}

int8_t luat_uart_setup(luat_uart_t* uart)
{
    if(uart->id > MAX_DEVICE_COUNT)//目前只有一个串口
    {
        return -1;
    }
    char utemp[] = "uart_";
    utemp[4] = 0x30 + uart->id;//拼一个uart名
    serials[uart->id] = rt_device_find(utemp);

    struct serial_configure config = RT_SERIAL_CONFIG_DEFAULT;
    config.baud_rate = uart->baud_rate;
    config.data_bits = uart->data_bits;
    config.stop_bits = uart->stop_bits - 1;
    config.bufsz     = uart->bufsz;
    config.parity    = uart->parity;
    config.bit_order = uart->bit_order;
    rt_device_control(serials[uart->id], RT_DEVICE_CTRL_CONFIG, &config);

    rt_err_t re = rt_device_open(serials[uart->id], RT_DEVICE_FLAG_INT_RX);
    if(re != RT_EOK)
        return re;//失败了

    uart_funcion[uart->id].received = uart->received;//接收回调
    uart_funcion[uart->id].sent = uart->sent;//发送回调
    //回调
    rt_device_set_rx_indicate(serials[uart->id], uart_input);
    rt_device_set_tx_complete(serials[uart->id], uart_sent);
    return re;
}

uint32_t luat_uart_write(uint8_t uartid, uint8_t* data, uint32_t length)
{
    if(serials[uartid] == NULL)
        return 0;
    int re = rt_device_write(serials[uartid], 0, data, length);
    return re;
}

uint32_t luat_uart_read(uint8_t uartid, uint8_t* buffer, uint32_t length)
{
    if(serials[uartid] == NULL)
        return 0;
    int re = rt_device_read(serials[uartid], -1, buffer, length);
    return re;
}

uint8_t luat_uart_close(uint8_t uartid)
{
    if(serials[uartid] == NULL)
        return RT_EOK;
    int re = rt_device_close(serials[uartid]);
    if(re == RT_EOK)
        serials[uartid] = NULL;
    return re;
}
