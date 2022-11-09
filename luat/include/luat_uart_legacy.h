#ifndef LUAT_UART_LEGACY_H
#define LUAT_UART_LEGACY_H

#include "luat_base.h"

#ifdef __LUATOS__
int l_uart_handler(lua_State *L, void* ptr);
#endif

#ifdef LUAT_FORCE_WIN32
int luat_uart_list(uint8_t* list, size_t buff_len);
#endif

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
