#ifndef LUAT_UART
#define LUAT_UART

#include "luat_msgbus.h"


//校验位
#define LUAT_PARITY_NONE                     0
#define LUAT_PARITY_ODD                      1
#define LUAT_PARITY_EVEN                     2

//高低位顺序
#define LUAT_BIT_ORDER_LSB                   0
#define LUAT_BIT_ORDER_MSB                   1

typedef struct luat_uart {
    int id;      //串口编号
    int baud_rate;  //波特率

    uint8_t data_bits;  //数据位
    uint8_t stop_bits;  //停止位
    uint8_t bit_order;  //高低位
    uint8_t parity;    // 奇偶校验位
    
    size_t bufsz;     // 接收数据缓冲区大小
    //int received;//接收回调
    //int sent;//发送成功回调
} luat_uart_t;

int l_uart_handler(lua_State *L, void* ptr);
int luat_uart_setup(luat_uart_t* uart);
int luat_uart_write(int uartid, void* data, size_t length);
int luat_uart_read(int uartid, void* buffer, size_t length);
int luat_uart_close(int uartid);
int luat_uart_exist(int uartid);

int luat_setup_cb(int uartid, int received, int sent);

#endif
