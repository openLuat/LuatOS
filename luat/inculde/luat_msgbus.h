
#ifndef LUAT_MSGBUS
#define LUAT_MSGBUS

#include "luat_base.h"

typedef struct{
    uint32_t id;
    void* data;
}rtos_msg;

// 定义msgtype
#define LUAT_MSG_TIMER       (1)
#define LUAT_MSG_GPIO        (2)
#define LUAT_MSG_UART_RX     (3)
#define LUAT_MSG_UART_TXDONE (4)

// 定义接口方法
void luat_msgbus_init(void);
uint32_t luat_msgbus_put(rtos_msg* msg, size_t timeout);
uint32_t luat_msgbus_get(rtos_msg* msg, size_t timeout);
uint32_t luat_msgbus_freesize(void);

#endif
