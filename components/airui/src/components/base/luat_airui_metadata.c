/**
 * @file luat_airui_metadata.c
 * @summary 组件元数据管理
 * @responsible metadata 分配/释放，Lua callback ref 管理
 */

#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lvgl9/src/misc/lv_event.h"
#include <stdint.h>
#include <string.h>

#define LUAT_LOG_TAG "airui.meta"
#include "luat_log.h"

static const char *airui_component_type_name(uint8_t component_type)
{
    switch (component_type) {
        case AIRUI_COMPONENT_BUTTON:
            return "button";
        case AIRUI_COMPONENT_LABEL:
            return "label";
        case AIRUI_COMPONENT_IMAGE:
            return "image";
        case AIRUI_COMPONENT_WIN:
            return "win";
        case AIRUI_COMPONENT_DROPDOWN:
            return "dropdown";
        case AIRUI_COMPONENT_SWITCH:
            return "switch";
        case AIRUI_COMPONENT_MSGBOX:
            return "msgbox";
        case AIRUI_COMPONENT_CONTAINER:
            return "container";
        case AIRUI_COMPONENT_BAR:
            return "bar";
        case AIRUI_COMPONENT_TABLE:
            return "table";
        case AIRUI_COMPONENT_TABVIEW:
            return "tabview";
        case AIRUI_COMPONENT_TEXTAREA:
            return "textarea";
        case AIRUI_COMPONENT_KEYBOARD:
            return "keyboard";
        case AIRUI_COMPONENT_LOTTIE:
            return "lottie";
        case AIRUI_COMPONENT_CHART:
            return "chart";
        case AIRUI_COMPONENT_QRCODE:
            return "qrcode";
        default:
            return "unknown";
    }
}

static void airui_component_meta_delete_event_cb(lv_event_t *e)
{
    if (lv_event_get_code(e) != LV_EVENT_DELETE) {
        return;
    }

    lv_obj_t *obj = lv_event_get_target(e);
    airui_component_meta_t *meta = airui_component_meta_get(obj);
    if (meta != NULL) {
        airui_component_meta_free(meta);
    }
}

/**
 * 分配组件元数据
 * @param ctx 上下文指针
 * @param obj LVGL 对象指针
 * @param component_type 组件类型
 * @return 元数据指针，失败返回 NULL
 */
airui_component_meta_t *airui_component_meta_alloc(
    airui_ctx_t *ctx,
    lv_obj_t *obj,
    airui_component_type_t component_type)
{
    if (ctx == NULL || obj == NULL) {
        return NULL;
    }
    
    airui_component_meta_t *meta = luat_heap_malloc(sizeof(airui_component_meta_t));
    if (meta == NULL) {
        return NULL;
    }
    
    memset(meta, 0, sizeof(airui_component_meta_t));
    
    meta->obj = obj;
    meta->ctx = ctx;
    meta->component_type = component_type;
    
    // 初始化回调引用数组为 LUA_NOREF
    // 注意：LUA_NOREF 通常定义为 -1，但这里避免直接依赖 Lua 头文件
    for (int i = 0; i < AIRUI_CALLBACK_MAX; i++) {
        meta->callback_refs[i] = -1;  // LUA_NOREF
    }
    
    // 将元数据关联到 LVGL 对象
    lv_obj_set_user_data(obj, meta);

    // 绑定对象删除事件，兜底释放 metadata
    lv_obj_add_event_cb(obj, airui_component_meta_delete_event_cb, LV_EVENT_DELETE, NULL);

    // 增加组件计数
    if (ctx->debug_component_count < UINT32_MAX) {
        ctx->debug_component_count++;
    }

    // 打印调试信息
    if (ctx->debug_enabled) {
        LLOGI("[airui][debug][comp] create type=%s obj=%p count=%u",
              airui_component_type_name(component_type),
              obj,
              (unsigned int)ctx->debug_component_count);
    }
    
    return meta;
}

/**
 * 释放组件元数据
 * @param meta 元数据指针
 */
void airui_component_meta_free(airui_component_meta_t *meta)
{
    if (meta == NULL) {
        return;
    }
    
    // 释放 Lua 回调引用
    if (meta->ctx != NULL && meta->ctx->L != NULL) {
        extern void airui_component_release_callbacks(airui_component_meta_t *meta, void *L);
        airui_component_release_callbacks(meta, meta->ctx->L);
    }

    // 释放二维码数据（二维码组件会缓存数据，需要手动释放）
    if (meta->component_type == AIRUI_COMPONENT_QRCODE && meta->user_data != NULL) {
        extern void airui_qrcode_release_data(airui_component_meta_t *meta);
        airui_qrcode_release_data(meta);
    }

    if (meta->user_data != NULL && meta->user_data_free != NULL) {
        meta->user_data_free(meta->user_data);
        meta->user_data = NULL;
        meta->user_data_free = NULL;
    }

    // 减少组件计数
    if (meta->ctx != NULL) {
        if (meta->ctx->debug_component_count > 0) {
            meta->ctx->debug_component_count--;
        }
        // 打印调试信息
        if (meta->ctx->debug_enabled) {
            LLOGI("[airui][debug][comp] destroy type=%s obj=%p count=%u",
                  airui_component_type_name(meta->component_type),
                  meta->obj,
                  (unsigned int)meta->ctx->debug_component_count);
        }
    }
    
    // 清除 LVGL 对象的用户数据
    if (meta->obj != NULL) {
        lv_obj_set_user_data(meta->obj, NULL);
    }
    
    // 释放元数据
    luat_heap_free(meta);
}

void airui_component_meta_set_user_data(
    airui_component_meta_t *meta,
    void *user_data,
    airui_component_user_data_free_cb_t user_data_free)
{
    if (meta == NULL) {
        return;
    }

    meta->user_data = user_data;
    meta->user_data_free = user_data_free;
}

/**
 * 从 LVGL 对象获取元数据
 * @param obj LVGL 对象指针
 * @return 元数据指针，未找到返回 NULL
 */
airui_component_meta_t *airui_component_meta_get(lv_obj_t *obj)
{
    if (obj == NULL) {
        return NULL;
    }
    
    void *user_data = lv_obj_get_user_data(obj);
    if (user_data == NULL) {
        return NULL;
    }
    
    return (airui_component_meta_t *)user_data;
}
