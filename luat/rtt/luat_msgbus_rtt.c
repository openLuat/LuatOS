
// 导入rt-thread头文件, 用它的消息队列来实现
#include <rtthread.h>

#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"

#define DBG_TAG           "luat.msgbus"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>


ALIGN(RT_ALIGN_SIZE)
static rt_uint8_t msg_pool[4*1024];
static struct rt_messagequeue mq = {0};
// static void *msgdata = {0};

void luat_msgbus_init(void) {
    rt_err_t result;

    /* 初始化消息队列 */
    result = rt_mq_init(&mq,
                        "mqt",
                        &msg_pool[0],              /* 内存池指向 msg_pool */
                        sizeof(rtos_msg_t),        /* 每个消息的大小是 8 字节 */
                        4*1024,                    /* 内存池的大小是 msg_pool 的大小 */
                        RT_IPC_FLAG_FIFO);         /* 如果有多个线程等待，按照先来先得到的方法分配消息 */
    if (result) {
        // pass
    }
}

// void* luat_msgbus_data() {
//     return msgdata;
// }

uint32_t luat_msgbus_put(rtos_msg_t* msg, size_t timeout) {
    if (!mq.msg_size) // 未初始化
        return 0;
    LOG_D(">>luat_msgbus_put msg->ptr= %08X", msg->ptr);
    int re = rt_mq_send(&mq, msg, sizeof(rtos_msg_t));
    if (re) {
        LOG_W("msgbus is FULL!!!!");
    }
    return re;
}

uint32_t luat_msgbus_get(rtos_msg_t* msg, size_t timeout) {
    rt_err_t result;
    result = rt_mq_recv(&mq, msg, sizeof(rtos_msg_t), timeout);
    if (result == RT_EOK) {
        // msgdata = msg->ptr;
        LOG_D("luat_msgbus_get msg->ptr= %08X", msg->ptr);
        return 0;
    }
    else {
        // msgdata = NULL;
        return result;
    }
}

uint32_t luat_msgbus_freesize(void) {
    return 1;
}
