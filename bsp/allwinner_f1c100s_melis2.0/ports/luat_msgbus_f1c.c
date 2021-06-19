
#include "luat_base.h"
#include "luat_msgbus.h"

// 定义接口方法
void luat_msgbus_init(void) {

}


uint32_t luat_msgbus_put(rtos_msg_t* msg, size_t timeout) {
    return 0;
}

uint32_t luat_msgbus_get(rtos_msg_t* msg, size_t timeout) {
    return -1;
}

uint32_t luat_msgbus_freesize(void) {
    return 1;
}
