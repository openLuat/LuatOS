/**
 * @file luat_rtos_queue_pc.c
 * @summary PC 平台 RTOS 队列实现 (POSIX pthread 版)
 */

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include "luat_queue_pc.h"
#include "luat_posix_compat.h"
#include "c_common.h"
#include <string.h>

#define LUAT_LOG_TAG "rtos.queue"
#include "luat_log.h"

typedef struct {
    uv_queue_item_t queue;
    pthread_mutex_t mutex;
    pthread_cond_t  not_empty;
    pthread_cond_t  not_full;
    uint32_t        item_count;
    uint32_t        item_size;
    uint32_t        current_count;
} luat_rtos_queue_pc_t;

int luat_rtos_queue_create(luat_rtos_queue_t *queue_handle, uint32_t item_count, uint32_t item_size) {
    if (queue_handle == NULL || item_count == 0 || item_size == 0) return -1;

    luat_rtos_queue_pc_t *queue = luat_heap_malloc(sizeof(luat_rtos_queue_pc_t));
    if (queue == NULL) return -1;

    memset(queue, 0, sizeof(luat_rtos_queue_pc_t));
    queue->item_count    = item_count;
    queue->item_size     = item_size;
    queue->current_count = 0;
    queue->queue.next    = NULL;
    queue->queue.size    = 0;

    pthread_mutex_init(&queue->mutex, NULL);
    pthread_cond_init(&queue->not_empty, NULL);
    pthread_cond_init(&queue->not_full,  NULL);

    *queue_handle = queue;
    return 0;
}

int luat_rtos_queue_delete(luat_rtos_queue_t queue_handle) {
    if (queue_handle == NULL) return -1;
    luat_rtos_queue_pc_t *queue = (luat_rtos_queue_pc_t *)queue_handle;

    pthread_mutex_lock(&queue->mutex);
    while (queue->queue.next != NULL) {
        uv_queue_item_t *item = (uv_queue_item_t *)queue->queue.next;
        queue->queue.next = item->next;
        luat_heap_free(item);
    }
    pthread_mutex_unlock(&queue->mutex);

    pthread_cond_destroy(&queue->not_empty);
    pthread_cond_destroy(&queue->not_full);
    pthread_mutex_destroy(&queue->mutex);
    luat_heap_free(queue);
    return 0;
}

int luat_rtos_queue_send(luat_rtos_queue_t queue_handle, void *item, uint32_t item_size, uint32_t timeout) {
    if (queue_handle == NULL || item == NULL) return -1;
    luat_rtos_queue_pc_t *queue = (luat_rtos_queue_pc_t *)queue_handle;

    pthread_mutex_lock(&queue->mutex);

    if (queue->current_count >= queue->item_count) {
        if (timeout == 0) {
            pthread_mutex_unlock(&queue->mutex);
            return -1;
        }
        if (timeout == (uint32_t)(-1)) {
            while (queue->current_count >= queue->item_count)
                pthread_cond_wait(&queue->not_full, &queue->mutex);
        } else {
            struct timespec abs;
            luat_calc_abs_timeout(&abs, timeout);
            while (queue->current_count >= queue->item_count) {
                int r = pthread_cond_timedwait(&queue->not_full, &queue->mutex, &abs);
                if (r == ETIMEDOUT) {
                    pthread_mutex_unlock(&queue->mutex);
                    return -1;
                }
            }
        }
    }

    uv_queue_item_t *queue_item = luat_heap_malloc(sizeof(uv_queue_item_t) + queue->item_size - 4);
    if (queue_item == NULL) {
        pthread_mutex_unlock(&queue->mutex);
        return -1;
    }
    queue_item->next = NULL;
    queue_item->size = queue->item_size;
    memcpy(queue_item->msg, item, queue->item_size);

    int ret = luat_queue_push(&queue->queue, queue_item);
    if (ret == 0) {
        queue->current_count++;
        pthread_cond_signal(&queue->not_empty);
    } else {
        luat_heap_free(queue_item);
    }

    pthread_mutex_unlock(&queue->mutex);
    return ret;
}

int luat_rtos_queue_recv(luat_rtos_queue_t queue_handle, void *item, uint32_t item_size, uint32_t timeout) {
    if (queue_handle == NULL || item == NULL) return -1;
    luat_rtos_queue_pc_t *queue = (luat_rtos_queue_pc_t *)queue_handle;

    if (item_size && item_size != queue->item_size) return -1;

    pthread_mutex_lock(&queue->mutex);

    while (queue->queue.next == NULL) {
        if (timeout == 0) {
            pthread_mutex_unlock(&queue->mutex);
            return -1;
        }
        if (timeout == (uint32_t)(-1)) {
            pthread_cond_wait(&queue->not_empty, &queue->mutex);
        } else {
            struct timespec abs;
            luat_calc_abs_timeout(&abs, timeout);
            int r = pthread_cond_timedwait(&queue->not_empty, &queue->mutex, &abs);
            if (r == ETIMEDOUT) {
                pthread_mutex_unlock(&queue->mutex);
                return -1;
            }
        }
    }

    uv_queue_item_t *head = (uv_queue_item_t *)queue->queue.next;
    memcpy(item, head->msg, queue->item_size);
    queue->queue.next = head->next;
    queue->current_count--;
    luat_heap_free(head);

    pthread_cond_signal(&queue->not_full);
    pthread_mutex_unlock(&queue->mutex);
    return 0;
}

int luat_rtos_queue_get_cnt(luat_rtos_queue_t queue_handle, uint32_t *item_cnt) {
    if (queue_handle == NULL || item_cnt == NULL) return -1;
    luat_rtos_queue_pc_t *queue = (luat_rtos_queue_pc_t *)queue_handle;
    pthread_mutex_lock(&queue->mutex);
    *item_cnt = queue->current_count;
    pthread_mutex_unlock(&queue->mutex);
    return 0;
}

