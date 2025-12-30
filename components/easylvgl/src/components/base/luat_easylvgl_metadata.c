/**
 * @file luat_easylvgl_metadata.c
 * @summary 组件元数据管理
 * @responsible metadata 分配/释放，Lua callback ref 管理
 */

#include "luat_easylvgl_component.h"
#include "luat_malloc.h"
#include <string.h>

/**
 * 分配组件元数据
 * @param ctx 上下文指针
 * @param obj LVGL 对象指针
 * @param component_type 组件类型
 * @return 元数据指针，失败返回 NULL
 */
easylvgl_component_meta_t *easylvgl_component_meta_alloc(
    easylvgl_ctx_t *ctx,
    lv_obj_t *obj,
    easylvgl_component_type_t component_type)
{
    if (ctx == NULL || obj == NULL) {
        return NULL;
    }
    
    easylvgl_component_meta_t *meta = luat_heap_malloc(sizeof(easylvgl_component_meta_t));
    if (meta == NULL) {
        return NULL;
    }
    
    memset(meta, 0, sizeof(easylvgl_component_meta_t));
    
    meta->obj = obj;
    meta->ctx = ctx;
    meta->component_type = component_type;
    
    // 初始化回调引用数组为 LUA_NOREF
    // 注意：LUA_NOREF 通常定义为 -1，但这里避免直接依赖 Lua 头文件
    for (int i = 0; i < EASYLVGL_CALLBACK_MAX; i++) {
        meta->callback_refs[i] = -1;  // LUA_NOREF
    }
    
    // 将元数据关联到 LVGL 对象
    lv_obj_set_user_data(obj, meta);
    
    return meta;
}

/**
 * 释放组件元数据
 * @param meta 元数据指针
 */
void easylvgl_component_meta_free(easylvgl_component_meta_t *meta)
{
    if (meta == NULL) {
        return;
    }
    
    // 释放 Lua 回调引用
    if (meta->ctx != NULL && meta->ctx->L != NULL) {
        extern void easylvgl_component_release_callbacks(easylvgl_component_meta_t *meta, void *L);
        easylvgl_component_release_callbacks(meta, meta->ctx->L);
    }
    
    // 清除 LVGL 对象的用户数据
    if (meta->obj != NULL) {
        lv_obj_set_user_data(meta->obj, NULL);
    }
    
    // 释放元数据
    luat_heap_free(meta);
}

/**
 * 从 LVGL 对象获取元数据
 * @param obj LVGL 对象指针
 * @return 元数据指针，未找到返回 NULL
 */
easylvgl_component_meta_t *easylvgl_component_meta_get(lv_obj_t *obj)
{
    if (obj == NULL) {
        return NULL;
    }
    
    void *user_data = lv_obj_get_user_data(obj);
    if (user_data == NULL) {
        return NULL;
    }
    
    return (easylvgl_component_meta_t *)user_data;
}

