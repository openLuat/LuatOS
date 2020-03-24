
#ifndef LUAT_MSGBUS
#define LUAT_MSGBUS

#include "luat_base.h"

#define MSG_TIMER 1
#define MSG_GPIO 2
#define MSG_UART_RX 3
#define MSG_UART_TXDONE 4

typedef int (*luat_msg_handler) (lua_State *L, void* ptr);

typedef struct rtos_msg{
    luat_msg_handler handler;
    void* ptr;
    int arg1;
    int arg2;
}rtos_msg_t;


// 定义接口方法
void luat_msgbus_init(void);
//void* luat_msgbus_data();
uint32_t luat_msgbus_put(rtos_msg_t* msg, size_t timeout);
uint32_t luat_msgbus_get(rtos_msg_t* msg, size_t timeout);
uint32_t luat_msgbus_freesize(void);

#endif
