/**
 * @file luat_airui_component.h
 * @summary AIRUI 组件基类接口
 * @responsible 组件元数据、事件绑定、配置表解析
 */

#ifndef AIRUI_COMPONENT_H
#define AIRUI_COMPONENT_H

#ifdef __cplusplus
extern "C" {
#endif

#include "luat_airui.h"

/*********************
 *      DEFINES
 *********************/

/** 组件类型 */
typedef enum {
    AIRUI_COMPONENT_BUTTON = 1,
    AIRUI_COMPONENT_LABEL,
    AIRUI_COMPONENT_IMAGE,
    AIRUI_COMPONENT_WIN,
    AIRUI_COMPONENT_DROPDOWN,
    AIRUI_COMPONENT_SWITCH,
    AIRUI_COMPONENT_MSGBOX,
    AIRUI_COMPONENT_CONTAINER,
    AIRUI_COMPONENT_BAR,
    AIRUI_COMPONENT_TABLE,
    AIRUI_COMPONENT_TABVIEW,
    AIRUI_COMPONENT_TEXTAREA,
    AIRUI_COMPONENT_KEYBOARD,
    AIRUI_COMPONENT_LOTTIE
} airui_component_type_t;

/** TabView 对齐常量 */
typedef enum {
    AIRUI_TABVIEW_PAD_ALL = 0,
    AIRUI_TABVIEW_PAD_HOR,
    AIRUI_TABVIEW_PAD_VER,
    AIRUI_TABVIEW_PAD_TOP,
    AIRUI_TABVIEW_PAD_BOTTOM,
    AIRUI_TABVIEW_PAD_LEFT,
    AIRUI_TABVIEW_PAD_RIGHT,
    AIRUI_TABVIEW_PAD_MAX
} airui_tabview_pad_method_t;

/** 事件类型 */
typedef enum {
    AIRUI_EVENT_CLICKED = 0,
    AIRUI_EVENT_PRESSED,
    AIRUI_EVENT_RELEASED,
    AIRUI_EVENT_VALUE_CHANGED,
    AIRUI_EVENT_ACTION,
    AIRUI_EVENT_READY,
    AIRUI_EVENT_CLOSE,
    AIRUI_EVENT_COMPLETE,
    AIRUI_EVENT_MAX
} airui_event_type_t;

/**********************
 *      TYPEDEFS
 *********************/

/**
 * 组件元数据
 */
struct airui_component_meta {
    lv_obj_t *obj;                      /**< LVGL 对象指针 */
    airui_ctx_t *ctx;                /**< 上下文引用 */
    
    // 回调引用（Lua registry）
    int callback_refs[AIRUI_CALLBACK_MAX];  /**< 事件回调引用数组 */
    
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
} airui_msgbox_data_t;

/**
 * Textarea 私有数据
 */
typedef struct {
    lv_obj_t *keyboard;
} airui_textarea_data_t;

/**
 * Keyboard 私有数据
 */
typedef struct {
    lv_obj_t *target;
    lv_obj_t *ime;   /**< LVGL 词库对象，可能为 lv_ime_pinyin */
    bool auto_hide; /**< Keyboard 是否自动跟随 textarea 焦点显示/隐藏 */
    bool has_bg_color; /**< 是否由 Lua 配置或 API 设置了背景色 */
    lv_color_t bg_color; /**< 背景颜色 */
} airui_keyboard_data_t;

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
airui_component_meta_t *airui_component_meta_alloc(
    airui_ctx_t *ctx,
    lv_obj_t *obj,
    airui_component_type_t component_type);

/**
 * 释放组件元数据
 * @param meta 元数据指针
 * @pre-condition meta 必须非空
 * @post-condition 元数据及关联资源已释放
 */
void airui_component_meta_free(airui_component_meta_t *meta);

/**
 * 捕获配置表中的回调函数
 * @param L Lua 状态
 * @param idx 配置表在栈中的索引
 * @param key 回调函数键名（如 "on_click"）
 * @return Lua registry 引用，未找到返回 LUA_NOREF
 */
int airui_component_capture_callback(void *L, int idx, const char *key);

/**
 * 调用 Lua 回调函数
 * @param meta 组件元数据
 * @param event_type 事件类型
 * @param L Lua 状态
 * @pre-condition meta 必须非空
 */
void airui_component_call_callback(
    airui_component_meta_t *meta,
    airui_event_type_t event_type,
    void *L);

/**
 * 调用 Msgbox Action 回调（额外传递按钮文本）
 */
void airui_component_call_action_callback(
    airui_component_meta_t *meta,
    const char *action_text);

/**
 * 绑定组件事件
 * @param meta 组件元数据
 * @param event_type 事件类型
 * @param callback_ref Lua 回调引用
 * @return 0 成功，<0 失败
 */
int airui_component_bind_event(
    airui_component_meta_t *meta,
    airui_event_type_t event_type,
    int callback_ref);

/**
 * 释放组件所有回调引用
 * @param meta 组件元数据
 * @param L Lua 状态
 */
void airui_component_release_callbacks(airui_component_meta_t *meta, void *L);

/**
 * 从配置表读取整数字段
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param default_value 默认值
 * @return 整数值
 */
int airui_marshal_integer(void *L, int idx, const char *key, int default_value);
/**
 * 获取表字段的长度（仅支持数组）
 */
int airui_marshal_table_length(void *L, int idx, const char *key);

/**
 * 在表字段中获取指定位置的字符串
 */
const char *airui_marshal_table_string_at(void *L, int idx, const char *key, int position);


/**
 * 从配置表读取布尔字段
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param default_value 默认值
 * @return 布尔值
 */
bool airui_marshal_bool(void *L, int idx, const char *key, bool default_value);

/**
 * 从配置表读取字符串字段
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param default_value 默认值
 * @return 字符串指针（内部字符串，不需要释放），未找到返回 default_value
 */
const char *airui_marshal_string(void *L, int idx, const char *key, const char *default_value);

/**
 * 从配置表读取颜色字段（仅支持整型 Hex）
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param out 颜色输出
 * @return true 成功解析，false 未指定或类型错误
 */
bool airui_marshal_color(void *L, int idx, const char *key, lv_color_t *out);

/**
 * 从配置表读取父对象
 * @param L Lua 状态
 * @param idx 配置表索引
 * @return LVGL 父对象指针，未指定返回 NULL
 */
lv_obj_t *airui_marshal_parent(void *L, int idx);

/**
 * 从配置表读取点坐标（用于 pivot 等）
 * @param L Lua 状态
 * @param idx 配置表索引
 * @param key 字段名
 * @param out 输出点坐标
 * @return true 成功读取，false 未找到或格式错误
 */
bool airui_marshal_point(void *L, int idx, const char *key, lv_point_t *out);

/**
 * 从 LVGL 对象获取元数据
 * @param obj LVGL 对象指针
 * @return 元数据指针，未找到返回 NULL
 */
airui_component_meta_t *airui_component_meta_get(lv_obj_t *obj);

/**
 * Button 组件：从配置表创建
 */
lv_obj_t *airui_button_create_from_config(void *L, int idx);
int airui_button_set_text(lv_obj_t *btn, const char *text); //设置按钮文本
int airui_button_set_on_click(lv_obj_t *btn, int callback_ref); //设置点击回调

/**
 * Label 组件：从配置表创建
 */
lv_obj_t *airui_label_create_from_config(void *L, int idx);
int airui_label_set_text(lv_obj_t *label, const char *text); //设置标签文本
const char *airui_label_get_text(lv_obj_t *label); //获取标签文本

/**
 * Dropdown 组件创建
 */
lv_obj_t *airui_dropdown_create_from_config(void *L, int idx);
int airui_dropdown_set_selected(lv_obj_t *dropdown, int index); //设置下拉框选中项
int airui_dropdown_get_selected(lv_obj_t *dropdown); //获取下拉框选中项
int airui_dropdown_set_on_change(lv_obj_t *dropdown, int callback_ref); //设置改变回调

/**
 * Switch 组件创建
 */
lv_obj_t *airui_switch_create_from_config(void *L, int idx);
int airui_switch_set_state(lv_obj_t *sw, bool checked); //设置开关状态
bool airui_switch_get_state(lv_obj_t *sw); //获取开关状态
int airui_switch_set_on_change(lv_obj_t *sw, int callback_ref); //设置改变回调

/**
 * Container 组件创建
 */
lv_obj_t *airui_container_create_from_config(void *L, int idx);
int airui_container_set_color(lv_obj_t *container, uint32_t color); //设置背景颜色
int airui_container_set_hidden(lv_obj_t *container, bool hidden); //设置隐藏状态
int airui_container_open(lv_obj_t *container); //显示并置顶容器
int airui_container_destroy(lv_obj_t *container); //销毁容器及关联资源

/**
 * Bar 组件创建
 */
lv_obj_t *airui_bar_create_from_config(void *L, int idx);
int airui_bar_set_value(lv_obj_t *bar, lv_coord_t value, bool animated); //设置当前值
int airui_bar_set_range(lv_obj_t *bar, lv_coord_t min, lv_coord_t max); //设置范围
int airui_bar_set_indicator_color(lv_obj_t *bar, lv_color_t color); //设置进度颜色
int airui_bar_set_bg_color(lv_obj_t *bar, lv_color_t color); //设置背景颜色
int airui_bar_get_value(lv_obj_t *bar); //获取当前值

/**
 * Table 组件创建
 */
lv_obj_t *airui_table_create_from_config(void *L, int idx);
int airui_table_set_cell_text(lv_obj_t *table, uint16_t row, uint16_t col, const char *text); //设置单元格文本
int airui_table_set_col_width(lv_obj_t *table, uint16_t col, lv_coord_t width); //调整列宽   
int airui_table_set_border_color(lv_obj_t *table, lv_color_t color); //设置边框颜色

/**
 * TabView 组件创建
 */
lv_obj_t *airui_tabview_create_from_config(void *L, int idx);
int airui_tabview_set_active(lv_obj_t *tabview, uint32_t idx); //激活某页
lv_obj_t *airui_tabview_get_content(lv_obj_t *tabview, int idx); //获取某页容器
void airui_tabview_release_data(airui_component_meta_t *meta); //释放内部页容器数据

/**
 * Msgbox 组件
 */
lv_obj_t *airui_msgbox_create_from_config(void *L, int idx);
int airui_msgbox_set_on_action(lv_obj_t *msgbox, int callback_ref); //设置消息框按钮回调
int airui_msgbox_show(lv_obj_t *msgbox); //显示消息框
int airui_msgbox_hide(lv_obj_t *msgbox); //隐藏消息框
lv_timer_t *airui_msgbox_release_user_data(airui_component_meta_t *meta); //释放消息框用户数据（定时器等）

/**
 * Image 组件
 */
lv_obj_t *airui_image_create_from_config(void *L, int idx);
int airui_image_set_src(lv_obj_t *img, const char *src); //设置图片源
int airui_image_set_zoom(lv_obj_t *img, int zoom); //设置缩放比例
int airui_image_set_opacity(lv_obj_t *img, int opacity); //设置透明度

/**
 * Win 组件
 */
lv_obj_t *airui_win_create_from_config(void *L, int idx);
int airui_win_set_title(lv_obj_t *win, const char *title); //设置窗口标题
int airui_win_add_content(lv_obj_t *win, lv_obj_t *child); //添加子组件到内容容器

/**
 * Textarea组件
 */
lv_obj_t *airui_textarea_create_from_config(void *L, int idx);
int airui_textarea_set_text(lv_obj_t *textarea, const char *text); //设置文本内容
const char *airui_textarea_get_text(lv_obj_t *textarea); //获取文本内容
int airui_textarea_set_cursor(lv_obj_t *textarea, uint32_t pos); //设置光标位置
int airui_textarea_set_on_text_change(lv_obj_t *textarea, int callback_ref); //设置文本改变回调
int airui_textarea_attach_keyboard(lv_obj_t *textarea, lv_obj_t *keyboard); //关联键盘
lv_obj_t *airui_textarea_get_keyboard(lv_obj_t *textarea); //获取关联键盘

/**
 * Keyboard组件
 */
lv_obj_t *airui_keyboard_create_from_config(void *L, int idx);
int airui_keyboard_set_target(lv_obj_t *keyboard, lv_obj_t *textarea); //设置目标组件
int airui_keyboard_show(lv_obj_t *keyboard); //显示键盘
int airui_keyboard_hide(lv_obj_t *keyboard); //隐藏键盘
int airui_keyboard_set_on_commit(lv_obj_t *keyboard, int callback_ref); //设置提交回调
int airui_keyboard_set_layout(lv_obj_t *keyboard, const char *layout); //设置键盘布局
int airui_keyboard_set_bg_color(lv_obj_t *keyboard, lv_color_t color); //设置键盘背景颜色
void airui_keyboard_detach_auto_hide_target(lv_obj_t *keyboard, airui_keyboard_data_t *data);

/**
 * Lottie组件
 */
lv_obj_t *airui_lottie_create_from_config(void *L, int idx);
int airui_lottie_play(lv_obj_t *lottie);
int airui_lottie_pause(lv_obj_t *lottie);
int airui_lottie_stop(lv_obj_t *lottie);
int airui_lottie_set_src_file(lv_obj_t *lottie, const char *path);
int airui_lottie_set_src_data(lv_obj_t *lottie, const void *data, size_t size);
int airui_lottie_set_loop(lv_obj_t *lottie, bool loop);
int airui_lottie_set_speed(lv_obj_t *lottie, float speed);
int airui_lottie_set_progress(lv_obj_t *lottie, float progress);
int airui_lottie_destroy(lv_obj_t *lottie);

#ifdef __cplusplus
}
#endif

#endif /* AIRUI_COMPONENT_H */

