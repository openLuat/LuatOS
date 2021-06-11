#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_uart.h"
#include "luat_log.h"

#include "stdio.h"
#include "pico/stdlib.h"
#include "hardware/uart.h"

//串口数量，编号从0开始
#define MAX_DEVICE_COUNT 2
//存放串口设备句柄
static uint8_t serials_marks[MAX_DEVICE_COUNT] ={0};

int luat_uart_exist(int uartid)
{
    if (uartid < 0 || uartid >= MAX_DEVICE_COUNT)
    {
        return 0;
    }
    return 1;
}

int uart_input_cb(uint16_t len, void *uartid)
{

    if (serials_marks[(int)uartid])
    {
        // 前一个回调都还没读呢
        return 0;
    }
    serials_marks[(int)uartid] = 1;
    rtos_msg_t msg;
    msg.handler = l_uart_handler;
    msg.ptr = NULL;
    msg.arg1 = (int)uartid;
    msg.arg2 = len;
    luat_msgbus_put(&msg, 1);
    return 0;
}

//串口发送完成事件回调
// int uart_sent_cb(struct tls_uart_port *port)
// {
//     rtos_msg_t msg;
//     msg.handler = l_uart_handler;
//     msg.arg1 = port->uart_no;
//     msg.arg2 = 0;
//     msg.ptr = NULL;
//     luat_msgbus_put(&msg, 1);
//     return 0;
// }

int luat_uart_setup(luat_uart_t *uart)
{
    int ret;
    // tls_uart_options_t opt;
    if (uart->id > MAX_DEVICE_COUNT)
    {
        return -1;
    }

    switch (uart->id)
    {
    case 0:
        uart_init(uart0, 115200);
        gpio_set_function(0, GPIO_FUNC_UART);
        gpio_set_function(1, GPIO_FUNC_UART);
        uart_set_baudrate(uart0, uart->baud_rate);
        uart_set_hw_flow(uart0, false, false);
        uart_set_format(uart0, uart->data_bits, uart->stop_bits, uart->parity);
        uart_set_fifo_enabled(uart0, false);
        break;
    case 1:
        uart_init(uart1, 115200);
        gpio_set_function(4, GPIO_FUNC_UART);
        gpio_set_function(5, GPIO_FUNC_UART);
        uart_set_baudrate(uart1, uart->baud_rate);
        uart_set_hw_flow(uart1, false, false);
        uart_set_format(uart1, uart->data_bits, uart->stop_bits, uart->parity);
        uart_set_fifo_enabled(uart1, false);
        break;
    default:
        break;
    }
        return 0;
}


int luat_uart_write(int uartid, void *data, size_t length)
{
    int ret;
    // printf("uid:%d,data:%s,length = %d\r\n",uartid, (char *)data, length);
    if (!luat_uart_exist(uartid))
    {

    }
    // ret = tls_uart_write(uartid, data,length);
    if (uartid == 0)
        uart_puts(uart0, data);
    else if(uartid == 1)
        uart_puts(uart1, data);
    return ret;
}

int luat_uart_read(int uartid, void *buffer, size_t length)
{
    int ret;
    if (!luat_uart_exist(uartid))
    {

        return -1;
    }
    serials_marks[uartid] = 0;

    // ret =  tls_uart_read(uartid,(u8 *) buffer,(u16)length);
    // return ret;
}

int luat_uart_close(int uartid)
{
    if (!luat_uart_exist(uartid))
    {
        return 0;
    }
    if (uartid == 0)
        uart_deinit(uart0);
    else if(uartid == 1)
        uart_deinit(uart1);
    return 0;
}

int luat_setup_cb(int uartid, int received, int sent)
{
    if (!luat_uart_exist(uartid))
    {
        return -1;
    }
    if (received)
    {

        // tls_uart_rx_callback_register(uartid,(s16(*)(u16, void*))uart_input_cb, &uartid);
    }

    if (sent)
    {

        // tls_uart_tx_callback_register(uartid, (s16(*)(struct tls_uart_port *))uart_sent_cb);
    }

    return 0;
}
