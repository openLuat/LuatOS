/**
 * @file luat_easylvgl_task.c
 * @summary EasyLVGL 专职任务实现
 * @responsible LVGL 消息队列、单线程串行化、lv_timer_handler 循环
 */

#include "luat_easylvgl.h"
#include "luat_easylvgl_task.h"
#include "luat_rtos.h"
#include "luat_timer.h"
#include "luat_log.h"
#include "lvgl9/lvgl.h"
#include <string.h>

#define LUAT_LOG_TAG "easylvgl.task"
#include "luat_log.h"

/** EasyLVGL 任务消息 */
typedef struct {
    easylvgl_task_msg_type_t type;
    void *data;
    uint32_t param1;
    uint32_t param2;
} easylvgl_task_msg_t;

/** EasyLVGL 任务上下文 */
typedef struct {
    easylvgl_ctx_t *ctx;
    luat_rtos_task_handle task_handle;
    luat_rtos_queue_t msg_queue;
    bool running;
    luat_timer_t tick_timer;
} easylvgl_task_ctx_t;

static easylvgl_task_ctx_t g_task_ctx = {0};

/**
 * Tick 定时器回调
 */
static int easylvgl_tick_timer_handler(lua_State *L, void *ptr)
{
    (void)L;
    (void)ptr;
    
    // 发送 tick 消息到任务
    easylvgl_task_msg_t msg = {
        .type = EASYLVGL_TASK_MSG_TICK,
        .data = NULL,
        .param1 = 0,
        .param2 = 0
    };
    
    if (g_task_ctx.msg_queue != NULL) {
        luat_rtos_queue_send(g_task_ctx.msg_queue, &msg, sizeof(msg), 0);
    }
    
    return 0;
}

/**
 * EasyLVGL 专职任务主循环
 */
static void easylvgl_task_main(void *user_data)
{
    easylvgl_task_ctx_t *task_ctx = (easylvgl_task_ctx_t *)user_data;
    easylvgl_task_msg_t msg;
    
    LLOGD("easylvgl task started");
    
    while (task_ctx->running) {
        // 接收消息（阻塞等待，超时 10ms）
        int ret = luat_rtos_queue_recv(task_ctx->msg_queue, &msg, sizeof(msg), 10);
        
        if (ret == 0) {
            // 处理消息
            switch (msg.type) {
                case EASYLVGL_TASK_MSG_TICK:
                    // 更新 LVGL tick
                    lv_tick_inc(5);  // 5ms tick
                    break;
                    
                case EASYLVGL_TASK_MSG_INIT:
                    // 初始化消息（已通过 easylvgl_init 完成）
                    break;
                    
                case EASYLVGL_TASK_MSG_DEINIT:
                    // 反初始化消息
                    task_ctx->running = false;
                    break;
                    
                case EASYLVGL_TASK_MSG_CUSTOM:
                    // 自定义消息处理
                    // TODO: 实现自定义消息处理逻辑
                    break;
                    
                default:
                    break;
            }
        }
        
        // 调用 LVGL 定时器处理（必须在任务中调用）
        if (task_ctx->ctx != NULL && task_ctx->ctx->display != NULL) {
            lv_timer_handler();
        }
    }
    
    LLOGD("easylvgl task stopped");
}

/**
 * 启动 EasyLVGL 专职任务
 * @param ctx 上下文指针
 * @return 0 成功，<0 失败
 */
int easylvgl_task_start(easylvgl_ctx_t *ctx)
{
    if (ctx == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }
    
    if (g_task_ctx.running) {
        LLOGD("easylvgl task already running");
        return EASYLVGL_OK;
    }
    
    // 创建消息队列
    int ret = luat_rtos_queue_create(&g_task_ctx.msg_queue, 32, sizeof(easylvgl_task_msg_t));
    if (ret != 0) {
        LLOGE("failed to create message queue: %d", ret);
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    // 初始化任务上下文
    g_task_ctx.ctx = ctx;
    g_task_ctx.running = true;
    
    // 创建任务
    ret = luat_rtos_task_create(
        &g_task_ctx.task_handle,
        8192,  // 8KB 栈大小
        20,    // 优先级
        "easylvgl",
        easylvgl_task_main,
        &g_task_ctx,
        16     // 事件数量
    );
    
    if (ret != 0) {
        LLOGE("failed to create task: %d", ret);
        luat_rtos_queue_delete(g_task_ctx.msg_queue);
        g_task_ctx.msg_queue = NULL;
        g_task_ctx.running = false;
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    // 创建 tick 定时器（5ms）
    memset(&g_task_ctx.tick_timer, 0, sizeof(luat_timer_t));
    g_task_ctx.tick_timer.id = 0xE5E5;
    g_task_ctx.tick_timer.repeat = 1;
    g_task_ctx.tick_timer.timeout = 5;
    g_task_ctx.tick_timer.func = easylvgl_tick_timer_handler;
    g_task_ctx.tick_timer.type = 0;
    
    ret = luat_timer_start(&g_task_ctx.tick_timer);
    if (ret != 0) {
        LLOGE("failed to start tick timer: %d", ret);
        easylvgl_task_stop();
        return EASYLVGL_ERR_INIT_FAILED;
    }
    
    LLOGD("easylvgl task started successfully");
    return EASYLVGL_OK;
}

/**
 * 停止 EasyLVGL 专职任务
 */
void easylvgl_task_stop(void)
{
    if (!g_task_ctx.running) {
        return;
    }
    
    // 停止 tick 定时器
    luat_timer_stop(&g_task_ctx.tick_timer);
    
    // 发送停止消息
    easylvgl_task_msg_t msg = {
        .type = EASYLVGL_TASK_MSG_DEINIT,
        .data = NULL,
        .param1 = 0,
        .param2 = 0
    };
    
    if (g_task_ctx.msg_queue != NULL) {
        luat_rtos_queue_send(g_task_ctx.msg_queue, &msg, sizeof(msg), 0);
    }
    
    // 等待任务结束
    if (g_task_ctx.task_handle != NULL) {
        luat_rtos_task_delete(g_task_ctx.task_handle);
        g_task_ctx.task_handle = NULL;
    }
    
    // 删除消息队列
    if (g_task_ctx.msg_queue != NULL) {
        luat_rtos_queue_delete(g_task_ctx.msg_queue);
        g_task_ctx.msg_queue = NULL;
    }
    
    g_task_ctx.running = false;
    g_task_ctx.ctx = NULL;
    
    LLOGD("easylvgl task stopped");
}

/**
 * 发送自定义消息到 EasyLVGL 任务
 * @param msg_type 消息类型
 * @param data 消息数据
 * @param param1 参数1
 * @param param2 参数2
 * @return 0 成功，<0 失败
 */
int easylvgl_task_send_msg(easylvgl_task_msg_type_t msg_type, void *data, uint32_t param1, uint32_t param2)
{
    if (!g_task_ctx.running || g_task_ctx.msg_queue == NULL) {
        return EASYLVGL_ERR_NOT_INITIALIZED;
    }
    
    easylvgl_task_msg_t msg = {
        .type = msg_type,
        .data = data,
        .param1 = param1,
        .param2 = param2
    };
    
    int ret = luat_rtos_queue_send(g_task_ctx.msg_queue, &msg, sizeof(msg), 0);
    if (ret != 0) {
        return EASYLVGL_ERR_PLATFORM_ERROR;
    }
    
    return EASYLVGL_OK;
}

