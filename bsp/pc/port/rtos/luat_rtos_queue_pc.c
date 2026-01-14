/**
 * @file luat_rtos_queue_pc.c
 * @summary PC 平台 RTOS 队列实现
 * @responsible 基于 uv_queue 实现 RTOS 队列接口
 */

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include "luat_queue_pc.h"
#include "uv.h"
#include "c_common.h"
#include <string.h>

#define LUAT_LOG_TAG "rtos.queue"
#include "luat_log.h"

/** 队列结构体 */
typedef struct {
    uv_queue_item_t queue;      /**< 队列头节点 */
    uv_mutex_t mutex;           /**< 互斥锁 */
    uint32_t item_count;        /**< 队列容量 */
    uint32_t item_size;         /**< 元素大小 */
    uint32_t current_count;     /**< 当前元素数量 */
} luat_rtos_queue_pc_t;

/**
 * 创建队列
 */
int luat_rtos_queue_create(luat_rtos_queue_t *queue_handle, uint32_t item_count, uint32_t item_size)
{
    if (queue_handle == NULL || item_count == 0 || item_size == 0) {
        return -1;
    }
    
    luat_rtos_queue_pc_t *queue = luat_heap_malloc(sizeof(luat_rtos_queue_pc_t));
    if (queue == NULL) {
        return -1;
    }
    
    memset(queue, 0, sizeof(luat_rtos_queue_pc_t));
    queue->item_count = item_count;
    queue->item_size = item_size;
    queue->current_count = 0;
    queue->queue.next = NULL;
    queue->queue.size = 0;
    
    uv_mutex_init(&queue->mutex);
    
    *queue_handle = queue;
    return 0;
}

/**
 * 删除队列
 */
int luat_rtos_queue_delete(luat_rtos_queue_t queue_handle)
{
    if (queue_handle == NULL) {
        return -1;
    }
    
    luat_rtos_queue_pc_t *queue = (luat_rtos_queue_pc_t *)queue_handle;
    
    uv_mutex_lock(&queue->mutex);
    
    // 清空队列中的所有元素
    while (queue->queue.next != NULL) {
        uv_queue_item_t *item = (uv_queue_item_t *)queue->queue.next;
        queue->queue.next = item->next;
        luat_heap_free(item);
    }
    
    uv_mutex_unlock(&queue->mutex);
    uv_mutex_destroy(&queue->mutex);
    
    luat_heap_free(queue);
    return 0;
}

/**
 * 发送元素到队列
 */
int luat_rtos_queue_send(luat_rtos_queue_t queue_handle, void *item, uint32_t item_size, uint32_t timeout)
{
    if (queue_handle == NULL || item == NULL) {
        return -1;
    }
    
    luat_rtos_queue_pc_t *queue = (luat_rtos_queue_pc_t *)queue_handle;
    
    // 检查元素大小是否匹配
    if (item_size != queue->item_size) {
        return -1;
    }
    
    uv_mutex_lock(&queue->mutex);
    
    // 检查队列是否已满
    if (queue->current_count >= queue->item_count) {
        uv_mutex_unlock(&queue->mutex);
        if (timeout == 0) {
            return -1; // 非阻塞模式，立即返回
        }
        // 阻塞模式：等待空间（简化实现，实际应该使用条件变量）
        uv_mutex_unlock(&queue->mutex);
        uv_sleep(1);
        uv_mutex_lock(&queue->mutex);
        if (queue->current_count >= queue->item_count) {
            uv_mutex_unlock(&queue->mutex);
            return -1;
        }
    }
    
    // 分配队列项
    uv_queue_item_t *queue_item = luat_heap_malloc(sizeof(uv_queue_item_t) + queue->item_size - 4);
    if (queue_item == NULL) {
        uv_mutex_unlock(&queue->mutex);
        return -1;
    }
    
    queue_item->next = NULL;
    queue_item->size = queue->item_size;
    memcpy(queue_item->msg, item, queue->item_size);
    
    // 添加到队列
    int ret = luat_queue_push(&queue->queue, queue_item);
    if (ret == 0) {
        queue->current_count++;
    } else {
        luat_heap_free(queue_item);
    }
    
    uv_mutex_unlock(&queue->mutex);
    return ret;
}

/**
 * 从队列接收元素
 */
int luat_rtos_queue_recv(luat_rtos_queue_t queue_handle, void *item, uint32_t item_size, uint32_t timeout)
{
    if (queue_handle == NULL || item == NULL) {
        return -1;
    }
    
    luat_rtos_queue_pc_t *queue = (luat_rtos_queue_pc_t *)queue_handle;
    
    // 检查元素大小是否匹配
    if (item_size != queue->item_size) {
        return -1;
    }
    
    uint32_t wait_time = timeout;
    
    while (1) {
        uv_mutex_lock(&queue->mutex);

        // 直接操作队列头节点，避免使用luat_queue_pop导致的栈溢出
        uv_queue_item_t* head = (uv_queue_item_t*)queue->queue.next;
        if (head != NULL) {
            // 队列不为空，直接复制数据部分
            memcpy(item, head->msg, queue->item_size);
            // 从队列中移除节点
            if (head->next == NULL) {
                queue->queue.next = NULL;
            } else {
                queue->queue.next = head->next;
            }
            queue->current_count--;
            luat_heap_free(head);
            uv_mutex_unlock(&queue->mutex);
            return 0;
        }
        
        uv_mutex_unlock(&queue->mutex);
        
        // 队列为空
        if (timeout == 0) {
            return -1; // 非阻塞模式，立即返回
        }
        
        if (timeout != (uint32_t)(-1)) {
            if (wait_time == 0) {
                return -1; // 超时
            }
            wait_time--;
        }
        
        uv_sleep(1);
    }
}

/**
 * 获取队列中元素数量
 */
int luat_rtos_queue_get_cnt(luat_rtos_queue_t queue_handle, uint32_t *item_cnt)
{
    if (queue_handle == NULL || item_cnt == NULL) {
        return -1;
    }
    
    luat_rtos_queue_pc_t *queue = (luat_rtos_queue_pc_t *)queue_handle;
    
    uv_mutex_lock(&queue->mutex);
    *item_cnt = queue->current_count;
    uv_mutex_unlock(&queue->mutex);
    
    return 0;
}

