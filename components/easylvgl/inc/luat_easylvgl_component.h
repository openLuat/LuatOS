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
    EASYLVGL_COMPONENT_WIN,
    EASYLVGL_COMPONENT_DROPDOWN,
    EASYLVGL_COMPONENT_SWITCH,
    EASYLVGL_COMPONENT_MSGBOX,
    EASYLVGL_COMPONENT_CONTAINER,
    EASYLVGL_COMPONENT_TEXTAREA,
    EASYLVGL_COMPONENT_KEYBOARD
} easylvgl_component_type_t;

/** 事件类型 */
typedef enum {
    EASYLVGL_EVENT_CLICKED = 0,
    EASYLVGL_EVENT_PRESSED,
    EASYLVGL_EVENT_RELEASED,
    EASYLVGL_EVENT_VALUE_CHANGED,
    EASYLVGL_EVENT_ACTION,
    EASYLVGL_EVENT_READY,
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

/**
 * Msgbox 私有数据
 */
typedef struct {
    lv_timer_t *timeout_timer;
} easylvgl_msgbox_data_t;

/**
 * Textarea 私有数据
 */
typedef struct {
    lv_obj_t *keyboard;
} easylvgl_textarea_data_t;

/**
 * Keyboard 私有数据
 */
typedef struct {
    lv_obj_t *target;
} easylvgl_keyboard_data_t;

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
 * 调用 Msgbox Action 回调（额外传递按钮文本）
 */
void easylvgl_component_call_action_callback(
    easylvgl_component_meta_t *meta,
    const char *action_text);

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
 * 获取表字段的长度（仅支持数组）
 */
int easylvgl_marshal_table_length(void *L, int idx, const char *key);

/**
 * 在表字段中获取指定位置的字符串
 */
const char *easylvgl_marshal_table_string_at(void *L, int idx, const char *key, int position);


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
 * 从配置表读取点坐标（用于 pivot 等）
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param out 输出点坐标
 * @return true 成功读取，false 未找到或格式错误
 */
bool easylvgl_marshal_point(void *L, int idx, const char *key, lv_point_t *out);

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

/**
 * Label 组件：从配置表创建
 * @param L Lua 状态
 * @param idx 配置表索引
 * @return LVGL 对象指针
 */
lv_obj_t *easylvgl_label_create_from_config(void *L, int idx);

/**
 * Label 组件：设置文本
 * @param label Label 对象指针
 * @param text 文本内容
 * @return 0 成功，<0 失败
 */
int easylvgl_label_set_text(lv_obj_t *label, const char *text);

/**
 * Label 组件：获取文本
 * @param label Label 对象指针
 * @return 文本内容指针，失败返回 NULL
 */
const char *easylvgl_label_get_text(lv_obj_t *label);
/**
 * Dropdown 组件创建
 */
lv_obj_t *easylvgl_dropdown_create_from_config(void *L, int idx);

int easylvgl_dropdown_set_selected(lv_obj_t *dropdown, int index);
int easylvgl_dropdown_get_selected(lv_obj_t *dropdown);
int easylvgl_dropdown_set_on_change(lv_obj_t *dropdown, int callback_ref);

/**
 * Switch 组件创建
 */
lv_obj_t *easylvgl_switch_create_from_config(void *L, int idx);
int easylvgl_switch_set_state(lv_obj_t *sw, bool checked);
bool easylvgl_switch_get_state(lv_obj_t *sw);
int easylvgl_switch_set_on_change(lv_obj_t *sw, int callback_ref);

/**
 * Container 组件创建
 */
lv_obj_t *easylvgl_container_create_from_config(void *L, int idx);
/**
 * Container 组件：设置背景颜色
 */
int easylvgl_container_set_color(lv_obj_t *container, uint32_t color);

/**
 * Msgbox 组件创建与控制
 */
lv_obj_t *easylvgl_msgbox_create_from_config(void *L, int idx);
int easylvgl_msgbox_set_on_action(lv_obj_t *msgbox, int callback_ref);
int easylvgl_msgbox_show(lv_obj_t *msgbox);
int easylvgl_msgbox_hide(lv_obj_t *msgbox);
/**
 * 释放 msgbox 用户数据（定时器等）
 */
lv_timer_t *easylvgl_msgbox_release_user_data(easylvgl_component_meta_t *meta);

/**
 * Image 组件：从配置表创建
 * @param L Lua 状态
 * @param idx 配置表索引
 * @return LVGL 对象指针
 */
lv_obj_t *easylvgl_image_create_from_config(void *L, int idx);

/**
 * Image 组件：设置图片源
 * @param img Image 对象指针
 * @param src 图片路径或符号
 * @return 0 成功，<0 失败
 */
int easylvgl_image_set_src(lv_obj_t *img, const char *src);

/**
 * Image 组件：设置缩放比例
 * @param img Image 对象指针
 * @param zoom 缩放比例，256 = 100%
 * @return 0 成功，<0 失败
 */
int easylvgl_image_set_zoom(lv_obj_t *img, int zoom);

/**
 * Image 组件：设置透明度
 * @param img Image 对象指针
 * @param opacity 透明度，0-255
 * @return 0 成功，<0 失败
 */
int easylvgl_image_set_opacity(lv_obj_t *img, int opacity);

/**
 * Win 组件：从配置表创建
 * @param L Lua 状态
 * @param idx 配置表索引
 * @return LVGL 对象指针
 */
lv_obj_t *easylvgl_win_create_from_config(void *L, int idx);

/**
 * Win 组件：设置标题
 * @param win Win 对象指针
 * @param title 标题文本
 * @return 0 成功，<0 失败
 */
int easylvgl_win_set_title(lv_obj_t *win, const char *title);

/**
 * Win 组件：添加子组件到内容容器
 * @param win Win 对象指针
 * @param child 子对象指针
 * @return 0 成功，<0 失败
 */
int easylvgl_win_add_content(lv_obj_t *win, lv_obj_t *child);

/**
 * Textarea 组件创建与控制
 */
lv_obj_t *easylvgl_textarea_create_from_config(void *L, int idx);
int easylvgl_textarea_set_text(lv_obj_t *textarea, const char *text);
const char *easylvgl_textarea_get_text(lv_obj_t *textarea);
int easylvgl_textarea_set_cursor(lv_obj_t *textarea, uint32_t pos);
int easylvgl_textarea_set_on_text_change(lv_obj_t *textarea, int callback_ref);
int easylvgl_textarea_attach_keyboard(lv_obj_t *textarea, lv_obj_t *keyboard);
lv_obj_t *easylvgl_textarea_get_keyboard(lv_obj_t *textarea);

/**
 * Keyboard 组件创建与控制
 */
lv_obj_t *easylvgl_keyboard_create_from_config(void *L, int idx);
int easylvgl_keyboard_set_target(lv_obj_t *keyboard, lv_obj_t *textarea);
int easylvgl_keyboard_show(lv_obj_t *keyboard);
int easylvgl_keyboard_hide(lv_obj_t *keyboard);
int easylvgl_keyboard_set_on_commit(lv_obj_t *keyboard, int callback_ref);
int easylvgl_keyboard_set_layout(lv_obj_t *keyboard, const char *layout);

#ifdef __cplusplus
}
#endif

#endif /* EASYLVGL_COMPONENT_H */

