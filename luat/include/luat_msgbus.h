
#ifndef LUAT_MSGBUS_H
#define LUAT_MSGBUS_H

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
uint8_t luat_msgbus_is_empty(void);
uint8_t luat_msgbus_is_ready(void);

#define luat_msgbug_put2(ABC1,ABC2,ABC3,ABC4,ABC5) {\
    rtos_msg_t _msg = {.handler=ABC1,.ptr=ABC2,.arg1=ABC3,.arg2=ABC4};\
    luat_msgbus_put(&_msg, ABC5);\
}

#endif
