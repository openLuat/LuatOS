#ifndef LUAT_UART_H
#define LUAT_UART_H

#include "luat_msgbus.h"


//校验位
#define LUAT_PARITY_NONE                     0
#define LUAT_PARITY_ODD                      1
#define LUAT_PARITY_EVEN                     2

//高低位顺序
#define LUAT_BIT_ORDER_LSB                   0
#define LUAT_BIT_ORDER_MSB                   1

//停止位
#define LUAT_0_5_STOP_BITS                   0xf0
#define LUAT_1_5_STOP_BITS                   0xf1

typedef struct luat_uart {
    int id;         //串口编号
    int baud_rate;  //波特率

    uint8_t data_bits;  //数据位
    uint8_t stop_bits;  //停止位 特别规定：LUAT_0_5_STOP_BITS:0.5位停止位，LUAT_1_5_STOP_BITS:1.5位停止位
    uint8_t bit_order;  //高低位
    uint8_t parity;     //奇偶校验位

    size_t bufsz;       // 接收数据缓冲区大小
    uint32_t pin485;    //转换485的pin, 如果没有则是0xffffffff
    uint32_t delay;     //延迟时间，单位us
    uint8_t rx_level;   //接收方向的电平
} luat_uart_t;

int l_uart_handler(lua_State *L, void* ptr);
int luat_uart_setup(luat_uart_t* uart);
int luat_uart_write(int uartid, void* data, size_t length);
int luat_uart_read(int uartid, void* buffer, size_t length);
int luat_uart_close(int uartid);
int luat_uart_exist(int uartid);


int luat_setup_cb(int uartid, int received, int sent);
/*
上报接收数据中断的逻辑：
1.串口初始化时，新建一个缓冲区
2.可以考虑多为用户申请几百字节的缓冲长度，用户处理时防止丢包
3.每次串口收到数据时，先存入缓冲区，记录长度
4.遇到以下情况时，再调用串口中断
    a)缓冲区满（帮用户多申请的的情况）/缓冲区只剩几百字节（按实际长度申请缓冲区的情况）
    b)收到fifo接收超时中断（此时串口数据应该是没有继续收了）
5.触发收到数据中断时，返回的数据应是缓冲区的数据
6.关闭串口时，释放缓冲区资源
*/

#endif
