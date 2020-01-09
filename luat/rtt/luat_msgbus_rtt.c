
// 导入rt-thread头文件, 用它的消息队列来实现
#include <rtthread.h>

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"


static rt_uint8_t msg_pool[16*1024];
static struct rt_messagequeue mq;

void luat_msgbus_init(void) {
    rt_err_t result;

    /* 初始化消息队列 */
    result = rt_mq_init(&mq,
                        "mqt",
                        &msg_pool[0],             /* 内存池指向 msg_pool */
                        sizeof(struct rtos_msg),        /* 每个消息的大小是 8 字节 */
                        sizeof(msg_pool),        /* 内存池的大小是 msg_pool 的大小 */
                        RT_IPC_FLAG_FIFO);       /* 如果有多个线程等待，按照先来先得到的方法分配消息 */
    if (result) {
        // pass
    }
}

uint32_t luat_msgbus_put(struct rtos_msg* msg, size_t timeout) {
    return rt_mq_send(&mq, msg, timeout);
}

uint32_t luat_msgbus_get(struct rtos_msg* msg, size_t timeout) {
    rt_err_t result;
    result = rt_mq_recv(&mq, msg, sizeof(struct rtos_msg), timeout);
    if (result == RT_EOK) {
        return 0;
    }
    else {
        return result;
    }
}

uint32_t luat_msgbus_freesize(void) {
    return 1;
}
