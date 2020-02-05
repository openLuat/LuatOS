#ifndef LUAT_UART
#define LUAT_UART

#include "luat_msgbus.h"


//校验位
#define PARITY_NONE                     0
#define PARITY_ODD                      1
#define PARITY_EVEN                     2

//高低位顺序
#define BIT_ORDER_LSB                   0
#define BIT_ORDER_MSB                   1

typedef struct luat_uart_t {
    uint8_t id;      //串口编号
    uint8_t data_bits;  //数据位
    uint8_t stop_bits;  //停止位
    uint8_t baud_rate;  //波特率
    uint8_t bit_order;  //高低位

    uint32_t parity;    // 奇偶校验位
    uint32_t bufsz;     // 接收数据缓冲区大小
    luat_msg_handler func;
} luat_uart_t;

int8_t luat_uart_setup(luat_uart_t* uart);
uint32_t luat_uart_write(uint8_t uartid, uint8_t* data, uint32_t length);
uint32_t luat_uart_read(uint8_t uartid, uint8_t* buffer, uint32_t length);
uint8_t luat_uart_close(uint8_t uartid);
#endif
