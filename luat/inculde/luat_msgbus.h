
#ifndef LUAT_MSGBUS
#define LUAT_MSGBUS

#include "luat_base.h"

typedef int (*luat_msg_handler) (lua_State *L, const void *ptr);

typedef struct{
    luat_msg_handler handler;
    void* ptr;
}rtos_msg;


// 定义接口方法
void luat_msgbus_init(void);
uint32_t luat_msgbus_put(rtos_msg* msg, size_t timeout);
uint32_t luat_msgbus_get(rtos_msg* msg, size_t timeout);
uint32_t luat_msgbus_freesize(void);

#endif
