/*
 * AirLink Loopback 模式 (同进程双任务, 用于 PC 模拟器自测)
 *
 * 设计:
 *   - luat_airlink_start(LUAT_AIRLINK_MODE_LOOPBACK) 创建 transport slot 队列并启动本模块
 *   - loopback slave task 阻塞在 airlink_cmd_queue 上 (= g_transport_slots[LOOPBACK].cmd_queue)
 *   - 两条路径都会写入同一个队列，slave task 自然被唤醒:
 *       REQUEST: luat_airlink_send2transport → luat_airlink_queue_send → airlink_cmd_queue
 *       RESULT:  luat_airlink_send2slave     → luat_airlink_queue_send → airlink_cmd_queue
 *   - slave task 收到 item 后通过 luat_airlink_on_data_recv() 投递给 airlink_task 处理:
 *       cmd 0x30 → exec_cmd → luat_airlink_result_send → send2slave → 队列 → slave task
 *       cmd 0x08 → exec_cmd → luat_airlink_cmd_exec_result → 释放 rpc 信号量
 */

#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_airlink_transport.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include <string.h>

#ifdef LUAT_USE_AIRLINK_LOOPBACK

#define LUAT_LOG_TAG "airlink.loopback"
#include "luat_log.h"

// airlink_cmd_queue 在 luat_airlink_start() 中初始化后与 g_transport_slots[LOOPBACK].cmd_queue 相同
extern luat_rtos_queue_t airlink_cmd_queue;

static luat_rtos_task_handle s_loopback_slave_handle = NULL;

static int loopback_slave_task(void* param) {
    LLOGD("loopback slave task 启动");
    airlink_queue_item_t item;
    while (1) {
        memset(&item, 0, sizeof(item));
        // 阻塞等待: REQUEST(cmd 0x30) 和 RESULT(cmd 0x08) 都写入同一队列
        if (luat_rtos_queue_recv(airlink_cmd_queue, &item, sizeof(item), LUAT_WAIT_FOREVER) != 0) {
            continue;
        }
        luat_airlink_cmd_t* cmd = item.cmd;
        if (cmd == NULL) {
            continue;
        }
        size_t total_len = sizeof(luat_airlink_cmd_t) + cmd->len;
        // 投递给 airlink_task 处理 (cmd 0x30 或 cmd 0x08 都走这条路)
        luat_airlink_on_data_recv((uint8_t*)cmd, total_len);
        luat_airlink_cmd_free(cmd);
    }
    return 0;
}

int luat_airlink_start_loopback(void) {
    LLOGD("loopback 模式启动");

    // 注册 transport slot (notify_cb=NULL, 不再需要信号量唤醒)
    luat_airlink_slot_register(LUAT_AIRLINK_MODE_LOOPBACK, NULL);

    // 各模块 nanopb RPC exec handler 已通过静态表自动注册，无需手动调用

    // 启动 slave task
    if (s_loopback_slave_handle == NULL) {
        int ret = luat_rtos_task_create(&s_loopback_slave_handle, 8 * 1024, 50,
                                        "airlink_lb", loopback_slave_task, NULL, 0);
        if (ret != 0) {
            LLOGE("loopback: slave task 创建失败 %d", ret);
            return -1;
        }
    }

    LLOGD("loopback 模式启动完成");
    return 0;
}

#endif /* LUAT_USE_AIRLINK_LOOPBACK */
