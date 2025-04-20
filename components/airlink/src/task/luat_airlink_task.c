#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_crypto.h"
#include "luat_mcu.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

static luat_rtos_task_handle airlink_task_handle;

extern const luat_airlink_cmd_reg_t airlink_cmds[];

extern int luat_airlink_cmd_exec_ip_pkg(luat_airlink_cmd_t* cmd, void* userdata);

__USER_FUNC_IN_RAM__ void luat_airlink_on_data_recv(uint8_t *data, size_t len) {
    luat_airlink_cmd_t* cmd = (luat_airlink_cmd_t*)data;
    #ifdef __BK72XX__
    if (cmd->cmd == 0x100) {
        // IP数据直接处理,不走线程
        luat_airlink_cmd_exec_ip_pkg(cmd, NULL);
        return;
    }
    #endif
    void* ptr = luat_heap_opt_malloc(AIRLINK_MEM_TYPE, len);
    if (ptr == NULL) {
        LLOGE("airlink分配内存失败!!! %d", len);
        return;
    }
    memcpy(ptr, data, len);
    luat_rtos_event_send(airlink_task_handle, 1, (uint32_t)ptr, len, 0, 0);
}

__USER_FUNC_IN_RAM__ static int luat_airlink_task(void *param) {
    // LLOGD("处理线程启动");
    luat_event_t event;
    luat_airlink_cmd_t* ptr = NULL;
    // size_t len = 0;
    const luat_airlink_cmd_reg_t* cmd_reg = NULL;
    while (1) {
        luat_rtos_event_recv(airlink_task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
        if (event.id == 1) { // 收到数据了, 马上处理
            // 处理数据
            ptr = (void*)event.param1;
            // len = event.param2;
            if (ptr == NULL) {
                LLOGW("空指令!");
                continue;
            }
            if (ptr->cmd == 0) {
                goto clean;
            }
            // 真正的处理逻辑
            // if (ptr->cmd != 0x10) {
            //     LLOGD("收到指令/回复 cmd %d len %d", ptr->cmd, ptr->len);
            // }
            if (g_airlink_last_cmd_timestamp == 0) {
                uint64_t tmp = luat_mcu_tick64_ms();
                LLOGI("AIRLINK_READY %ld", (uint32_t)tmp);
                // TODO 发个系统消息
            }
            g_airlink_last_cmd_timestamp = luat_mcu_tick64_ms();
            cmd_reg = airlink_cmds;
            while (1) {
                if (cmd_reg->id == 0) {
                    break;
                }
                if (cmd_reg->id == ptr->cmd) {
                    // if (ptr->cmd != 0x10) {
                    //     LLOGI("找到CMD执行程序 %04X %p %d", ptr->cmd, cmd_reg->exec, ptr->len);
                    // }
                    cmd_reg->exec(ptr, NULL);
                    // if (ptr->cmd != 0x10) {
                    //     LLOGI("执行完毕 %d %p", ptr->cmd, cmd_reg->exec);
                    // }
                    break;
                }
                cmd_reg ++;
            }
            // if (cmd_reg->id == 0) {
            //     LLOGW("找不到CMD执行程序 %d", ptr->cmd);
            // }
            clean:
            // 处理完成, 释放内存
            luat_heap_opt_free(AIRLINK_MEM_TYPE, ptr);
        }
    }
    return 0;
}

void luat_airlink_task_start(void) {
    if (airlink_task_handle == NULL) {
        luat_rtos_task_create(&airlink_task_handle, 16 * 1024, 50, "airlink", luat_airlink_task, NULL, 1024);
    }
    else {
        LLOGD("airlink task 已经启动过了");
    }
}
