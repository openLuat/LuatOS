
#include "luat_msgbus.h"

#include "cmsis_os2.h"

#define LUAT_MSGBUS_MAXCOUNT 0xFF
//#define LUAT_MSGBUS_MAXSIZE 8
static osMessageQueueId_t queue = {0}; 

void luat_msgbus_init(void) {
    if (!queue) {
        queue = osMessageQueueNew(LUAT_MSGBUS_MAXCOUNT, sizeof(rtos_msg_t), NULL);
    }
}
uint32_t luat_msgbus_put(rtos_msg_t* msg, size_t timeout) {
    if (queue == NULL)
        return 1;
    return osMessageQueuePut(queue, msg, 0, timeout);
}
uint32_t luat_msgbus_get(rtos_msg_t* msg, size_t timeout) {
    if (queue == NULL)
        return 1;
    return osMessageQueueGet(queue, msg, 0, timeout);
}
uint32_t luat_msgbus_freesize(void) {
    if (queue == NULL)
        return 1;
    return osMessageQueueGetSpace(queue);
}
