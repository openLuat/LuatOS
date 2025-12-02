/**
 * @file luat_easylvgl_component.h
 * @summary EasyLVGL 组件基类接口
 * @responsible 组件元数据、事件绑定、配置表解析
 */

#ifndef EASYLVGL_COMPONENT_H
#define EASYLVGL_COMPONENT_H

#ifdef __cplusplus
extern "C" {
#endif

#include "luat_easylvgl.h"

/*********************
 *      DEFINES
 *********************/

/** 组件类型 */
typedef enum {
    EASYLVGL_COMPONENT_BUTTON = 1,
    EASYLVGL_COMPONENT_LABEL,
    EASYLVGL_COMPONENT_IMAGE,
    EASYLVGL_COMPONENT_WIN
} easylvgl_component_type_t;

/** 事件类型 */
typedef enum {
    EASYLVGL_EVENT_CLICKED = 0,
    EASYLVGL_EVENT_PRESSED,
    EASYLVGL_EVENT_RELEASED,
    EASYLVGL_EVENT_VALUE_CHANGED,
    EASYLVGL_EVENT_CLOSE,
    EASYLVGL_EVENT_MAX
} easylvgl_event_type_t;

/**********************
 *      TYPEDEFS
 *********************/

/**
 * 组件元数据
 */
struct easylvgl_component_meta {
    lv_obj_t *obj;                      /**< LVGL 对象指针 */
    easylvgl_ctx_t *ctx;                /**< 上下文引用 */
    
    // 回调引用（Lua registry）
    int callback_refs[EASYLVGL_CALLBACK_MAX];  /**< 事件回调引用数组 */
    
    // 组件类型
    uint8_t component_type;
    
    // 私有数据
    void *user_data;
};

/**********************
 * GLOBAL PROTOTYPES
 **********************/

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
    easylvgl_component_type_t component_type);

/**
 * 释放组件元数据
 * @param meta 元数据指针
 * @pre-condition meta 必须非空
 * @post-condition 元数据及关联资源已释放
 */
void easylvgl_component_meta_free(easylvgl_component_meta_t *meta);

/**
 * 捕获配置表中的回调函数
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @param key 回调函数键名（如 "on_click"）
 * @return Lua registry 引用，未找到返回 LUA_NOREF
 */
int easylvgl_component_capture_callback(void *L, int idx, const char *key);

/**
 * 调用 Lua 回调函数
 * @param meta 组件元数据
 * @param event_type 事件类型
 * @param L Lua 状态
 * @pre-condition meta 必须非空
 */
void easylvgl_component_call_callback(
    easylvgl_component_meta_t *meta,
    easylvgl_event_type_t event_type,
    void *L);

/**
 * 绑定组件事件
 * @param meta 组件元数据
 * @param event_type 事件类型
 * @param callback_ref Lua 回调引用
 * @return 0 成功，<0 失败
 */
int easylvgl_component_bind_event(
    easylvgl_component_meta_t *meta,
    easylvgl_event_type_t event_type,
    int callback_ref);

/**
 * 释放组件所有回调引用
 * @param meta 组件元数据
 * @param L Lua 状态
 */
void easylvgl_component_release_callbacks(easylvgl_component_meta_t *meta, void *L);

/**
 * 从配置表读取整数字段
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param default_value 默认值
 * @return 整数值
 */
int easylvgl_marshal_integer(void *L, int idx, const char *key, int default_value);

/**
 * 从配置表读取布尔字段
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param default_value 默认值
 * @return 布尔值
 */
bool easylvgl_marshal_bool(void *L, int idx, const char *key, bool default_value);

/**
 * 从配置表读取字符串字段
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param default_value 默认值
 * @return 字符串指针（内部字符串，不需要释放），未找到返回 default_value
 */
const char *easylvgl_marshal_string(void *L, int idx, const char *key, const char *default_value);

/**
 * 从配置表读取父对象
 * @param L Lua 状态
 * @param idx 配置表索引
 * @return LVGL 父对象指针，未指定返回 NULL
 */
lv_obj_t *easylvgl_marshal_parent(void *L, int idx);

/**
 * 从 LVGL 对象获取元数据
 * @param obj LVGL 对象指针
 * @return 元数据指针，未找到返回 NULL
 */
easylvgl_component_meta_t *easylvgl_component_meta_get(lv_obj_t *obj);

/**
 * Button 组件：从配置表创建
 * @param L Lua 状态
 * @param idx 配置表索引
 * @return LVGL 对象指针
 */
lv_obj_t *easylvgl_button_create_from_config(void *L, int idx);

/**
 * Button 组件：设置文本
 * @param btn Button 对象指针
 * @param text 文本内容
 * @return 0 成功，<0 失败
 */
int easylvgl_button_set_text(lv_obj_t *btn, const char *text);

/**
 * Button 组件：设置点击回调
 * @param btn Button 对象指针
 * @param callback_ref Lua 回调引用
 * @return 0 成功，<0 失败
 */
int easylvgl_button_set_on_click(lv_obj_t *btn, int callback_ref);

#ifdef __cplusplus
}
#endif

#endif /* EASYLVGL_COMPONENT_H */

