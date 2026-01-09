/**
 * @file luat_easylvgl_buffer.c
 * @summary EasyLVGL 缓冲管理
 * @responsible 缓冲分配、所有权追踪、集中释放
 */

#include "luat_easylvgl.h"
#include <stdlib.h>
#include <string.h>

/**
 * 缓冲管理器
 */
struct easylvgl_buffer {
    void **buffers;                   /**< 缓冲指针数组 */
    size_t *sizes;                    /**< 缓冲大小数组 */
    easylvgl_buffer_owner_t *owners;  /**< 缓冲所有权数组 */
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
void *easylvgl_buffer_alloc(easylvgl_ctx_t *ctx, size_t size, easylvgl_buffer_owner_t owner)
{
    if (ctx == NULL || ctx->buffer == NULL || size == 0) {
        return NULL;
    }
    
    easylvgl_buffer_t *buf_mgr = ctx->buffer;
    
    // 扩展数组容量
    if (buf_mgr->count >= buf_mgr->capacity) {
        size_t new_capacity = buf_mgr->capacity == 0 ? 4 : buf_mgr->capacity * 2;
        void **new_buffers = realloc(buf_mgr->buffers, new_capacity * sizeof(void *));
        size_t *new_sizes = realloc(buf_mgr->sizes, new_capacity * sizeof(size_t));
        easylvgl_buffer_owner_t *new_owners = realloc(buf_mgr->owners, new_capacity * sizeof(easylvgl_buffer_owner_t));
        
        if (new_buffers == NULL || new_sizes == NULL || new_owners == NULL) {
            return NULL;
        }
        
        buf_mgr->buffers = new_buffers;
        buf_mgr->sizes = new_sizes;
        buf_mgr->owners = new_owners;
        buf_mgr->capacity = new_capacity;
    }
    
    // 分配缓冲
    void *buffer = NULL;
    if (owner == EASYLVGL_BUFFER_OWNER_SYSTEM) {
        buffer = malloc(size);
    } else if (owner == EASYLVGL_BUFFER_OWNER_LUA) {
        // TODO: 使用 Lua heap 分配（luat_heap_alloc）
        // 阶段一先使用系统 heap
        buffer = malloc(size);
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
void easylvgl_buffer_free(easylvgl_ctx_t *ctx, void *buffer)
{
    if (ctx == NULL || ctx->buffer == NULL || buffer == NULL) {
        return;
    }
    
    easylvgl_buffer_t *buf_mgr = ctx->buffer;
    for (size_t i = 0; i < buf_mgr->count; i++) {
        if (buf_mgr->buffers[i] == buffer) {
            if (buf_mgr->owners[i] == EASYLVGL_BUFFER_OWNER_SYSTEM ||
                buf_mgr->owners[i] == EASYLVGL_BUFFER_OWNER_LUA) {
                free(buf_mgr->buffers[i]);
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
easylvgl_buffer_t *easylvgl_buffer_create(void)
{
    easylvgl_buffer_t *buf_mgr = malloc(sizeof(easylvgl_buffer_t));
    if (buf_mgr == NULL) {
        return NULL;
    }
    
    memset(buf_mgr, 0, sizeof(easylvgl_buffer_t));
    return buf_mgr;
}

/**
 * 释放所有缓冲
 * @param ctx 上下文指针
 * @pre-condition ctx 必须非空
 * @post-condition 所有缓冲已按所有权释放
 */
void easylvgl_buffer_free_all(easylvgl_ctx_t *ctx)
{
    if (ctx == NULL || ctx->buffer == NULL) {
        return;
    }
    
    easylvgl_buffer_t *buf_mgr = ctx->buffer;
    
    // 按所有权释放缓冲
    for (size_t i = 0; i < buf_mgr->count; i++) {
        if (buf_mgr->buffers[i] != NULL) {
            if (buf_mgr->owners[i] == EASYLVGL_BUFFER_OWNER_SYSTEM) {
                free(buf_mgr->buffers[i]);
            } else if (buf_mgr->owners[i] == EASYLVGL_BUFFER_OWNER_LUA) {
                // TODO: 使用 Lua heap 释放（luat_heap_free）
                // 阶段一先使用系统 heap
                free(buf_mgr->buffers[i]);
            }
        }
    }
    
    // 释放数组
    free(buf_mgr->buffers);
    free(buf_mgr->sizes);
    free(buf_mgr->owners);
    
    // 释放管理器
    free(buf_mgr);
    ctx->buffer = NULL;
}

