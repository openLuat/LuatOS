/**
 * @file easylvgl_task.h
 * @summary EasyLVGL 专职任务接口
 * @responsible LVGL 任务启动、停止、消息发送
 */

#ifndef EASYLVGL_TASK_H
#define EASYLVGL_TASK_H

#ifdef __cplusplus
extern "C" {
#endif

#include "easylvgl.h"

/** EasyLVGL 任务消息类型 */
typedef enum {
    EASYLVGL_TASK_MSG_NONE = 0,
    EASYLVGL_TASK_MSG_INIT,
    EASYLVGL_TASK_MSG_DEINIT,
    EASYLVGL_TASK_MSG_TICK,
    EASYLVGL_TASK_MSG_CUSTOM
} easylvgl_task_msg_type_t;

/**
 * 启动 EasyLVGL 专职任务
 * @param ctx 上下文指针
 * @return 0 成功，<0 失败
 */
int easylvgl_task_start(easylvgl_ctx_t *ctx);

/**
 * 停止 EasyLVGL 专职任务
 */
void easylvgl_task_stop(void);

/**
 * 发送自定义消息到 EasyLVGL 任务
 * @param msg_type 消息类型
 * @param data 消息数据
 * @param param1 参数1
 * @param param2 参数2
 * @return 0 成功，<0 失败
 */
int easylvgl_task_send_msg(easylvgl_task_msg_type_t msg_type, void *data, uint32_t param1, uint32_t param2);

#ifdef __cplusplus
}
#endif

#endif /* EASYLVGL_TASK_H */

