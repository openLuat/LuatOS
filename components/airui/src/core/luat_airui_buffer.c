/**
 * @file luat_airui_buffer.c
 * @summary AIRUI 缓冲管理
 * @responsible 缓冲分配、所有权追踪、集中释放
 */

#include "luat_airui.h"
#include "luat_malloc.h"
#include <string.h>

/**
 * 缓冲管理器
 */
struct airui_buffer {
    void **buffers;                   /**< 缓冲指针数组 */
    size_t *sizes;                    /**< 缓冲大小数组 */
    airui_buffer_owner_t *owners;  /**< 缓冲所有权数组 */
    size_t count;                     /**< 缓冲数量 */
    size_t capacity;                  /**< 数组容量 */
};

/**
 * 分配缓冲
 * @param ctx 上下文指针
 * @param size 缓冲大小（字节）
 * @param owner 缓冲所有权
 * @return 缓冲指针，失败返回 NULL
 */
void *airui_buffer_alloc(airui_ctx_t *ctx, size_t size, airui_buffer_owner_t owner)
{
    if (ctx == NULL || ctx->buffer == NULL || size == 0) {
        return NULL;
    }
    
    airui_buffer_t *buf_mgr = ctx->buffer;
    
    // 扩展数组容量
    if (buf_mgr->count >= buf_mgr->capacity) {
        size_t new_capacity = buf_mgr->capacity == 0 ? 4 : buf_mgr->capacity * 2;
        void **new_buffers = luat_heap_malloc(new_capacity * sizeof(void *));
        size_t *new_sizes = luat_heap_malloc(new_capacity * sizeof(size_t));
        airui_buffer_owner_t *new_owners = luat_heap_malloc(new_capacity * sizeof(airui_buffer_owner_t));

        if (new_buffers == NULL || new_sizes == NULL || new_owners == NULL) {
            if (new_buffers != NULL) {
                luat_heap_free(new_buffers);
            }
            if (new_sizes != NULL) {
                luat_heap_free(new_sizes);
            }
            if (new_owners != NULL) {
                luat_heap_free(new_owners);
            }
            return NULL;
        }

        if (buf_mgr->count > 0) {
            memcpy(new_buffers, buf_mgr->buffers, buf_mgr->count * sizeof(void *));
            memcpy(new_sizes, buf_mgr->sizes, buf_mgr->count * sizeof(size_t));
            memcpy(new_owners, buf_mgr->owners, buf_mgr->count * sizeof(airui_buffer_owner_t));
        }

        luat_heap_free(buf_mgr->buffers);
        luat_heap_free(buf_mgr->sizes);
        luat_heap_free(buf_mgr->owners);

        buf_mgr->buffers = new_buffers;
        buf_mgr->sizes = new_sizes;
        buf_mgr->owners = new_owners;
        buf_mgr->capacity = new_capacity;
    }
    
    // 分配缓冲
    void *buffer = NULL;
    if (owner == AIRUI_BUFFER_OWNER_SYSTEM) {
        buffer = luat_heap_malloc(size);
    } else if (owner == AIRUI_BUFFER_OWNER_LUA) {
        buffer = luat_heap_malloc(size);
    }
    
    if (buffer == NULL) {
        return NULL;
    }
    
    // 记录缓冲信息
    buf_mgr->buffers[buf_mgr->count] = buffer;
    buf_mgr->sizes[buf_mgr->count] = size;
    buf_mgr->owners[buf_mgr->count] = owner;
    buf_mgr->count++;
    
    return buffer;
}

/**
 * 释放单个缓冲（独立释放后会从列表中移除）
 * @param ctx 上下文指针
 * @param buffer 缓冲指针
 */
void airui_buffer_free(airui_ctx_t *ctx, void *buffer)
{
    if (ctx == NULL || ctx->buffer == NULL || buffer == NULL) {
        return;
    }
    
    airui_buffer_t *buf_mgr = ctx->buffer;
    for (size_t i = 0; i < buf_mgr->count; i++) {
        if (buf_mgr->buffers[i] == buffer) {
            if (buf_mgr->owners[i] == AIRUI_BUFFER_OWNER_SYSTEM ||
                buf_mgr->owners[i] == AIRUI_BUFFER_OWNER_LUA) {
                luat_heap_free(buf_mgr->buffers[i]);
            }

            buf_mgr->buffers[i] = buf_mgr->buffers[buf_mgr->count - 1];
            buf_mgr->sizes[i] = buf_mgr->sizes[buf_mgr->count - 1];
            buf_mgr->owners[i] = buf_mgr->owners[buf_mgr->count - 1];
            buf_mgr->count--;
            return;
        }
    }
}

/**
 * 创建缓冲管理器
 * @return 缓冲管理器指针，失败返回 NULL
 */
airui_buffer_t *airui_buffer_create(void)
{
    airui_buffer_t *buf_mgr = luat_heap_malloc(sizeof(airui_buffer_t));
    if (buf_mgr == NULL) {
        return NULL;
    }
    
    memset(buf_mgr, 0, sizeof(airui_buffer_t));
    return buf_mgr;
}

/**
 * 释放所有缓冲
 * @param ctx 上下文指针
 * @pre-condition ctx 必须非空
 * @post-condition 所有缓冲已按所有权释放
 */
void airui_buffer_free_all(airui_ctx_t *ctx)
{
    if (ctx == NULL || ctx->buffer == NULL) {
        return;
    }
    
    airui_buffer_t *buf_mgr = ctx->buffer;
    
    // 按所有权释放缓冲
    for (size_t i = 0; i < buf_mgr->count; i++) {
        if (buf_mgr->buffers[i] != NULL) {
            if (buf_mgr->owners[i] == AIRUI_BUFFER_OWNER_SYSTEM) {
                luat_heap_free(buf_mgr->buffers[i]);
            } else if (buf_mgr->owners[i] == AIRUI_BUFFER_OWNER_LUA) {
                luat_heap_free(buf_mgr->buffers[i]);
            }
        }
    }
    
    // 释放数组
    luat_heap_free(buf_mgr->buffers);
    luat_heap_free(buf_mgr->sizes);
    luat_heap_free(buf_mgr->owners);
    
    // 释放管理器
    luat_heap_free(buf_mgr);
    ctx->buffer = NULL;
}

