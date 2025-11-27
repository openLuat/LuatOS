/**
 * @file easylvgl.h
 * @summary EasyLVGL 核心接口头文件 (LVGL 9.4)
 * @version 0.0.2
 */

#ifndef EASYLVGL_H
#define EASYLVGL_H

#ifdef __cplusplus
extern "C" {
#endif

#include "luat_base.h"
#include "../lvgl9/lvgl.h"

/*********************
 *      DEFINES
 *********************/

/**
 * 用于 Lua userdata 的元表名称
 */
#define EASYLVGL_BUTTON_MT "easylvgl.button"
#define EASYLVGL_LABEL_MT "easylvgl.label"
#define EASYLVGL_IMAGE_MT "easylvgl.image"
#define EASYLVGL_WIN_MT "easylvgl.win"

/**********************
 *      TYPEDEFS
 **********************/

/**
 * EasyLVGL 显示驱动结构
 */
typedef struct {
    lv_display_t *display;      /**< LVGL 9 显示对象 */
    void *buf1;                 /**< 缓冲区1 */
    void *buf2;                 /**< 缓冲区2 */
    uint32_t buf_size;          /**< 缓冲区大小（字节） */
    int buf1_ref;               /**< Lua 引用（如果使用 Lua heap） */
    int buf2_ref;               /**< Lua 引用（如果使用 Lua heap） */
} easylvgl_display_t;

/**********************
 * GLOBAL PROTOTYPES
 **********************/

/**
 * 初始化 EasyLVGL
 * @param w 屏幕宽度
 * @param h 屏幕高度
 * @param buf_size 缓冲区大小（像素数，不含色深）
 * @param buff_mode 缓冲模式 bit0:是否使用lcdbuff bit1:buff1 bit2:buff2 bit3:是否使用lua heap
 * @return 成功返回0，失败返回-1
 */
int easylvgl_init_internal(int w, int h, size_t buf_size, uint8_t buff_mode);

/**
 * 反初始化 EasyLVGL
 * 释放所有资源，包括显示对象、缓冲区和 SDL2 资源（如果启用）
 */
void easylvgl_deinit(void);

/**
 * 显示刷新回调（LVGL 9 格式）
 * @param disp 显示对象
 * @param area 刷新区域
 * @param px_map 像素数据（uint8_t* 格式）
 */
void easylvgl_disp_flush(lv_display_t *disp, const lv_area_t *area, uint8_t *px_map);

/**
 * 初始化面向 LuatOS 文件系统的 LVGL 9 文件驱动，注册后通过 `L:/` 或 `/` 调用 LVGL fs。
 */
void easylvgl_fs_init(void);

/**
 * 创建按钮对象
 * @param parent 父对象
 * @return 按钮对象指针
 */
lv_obj_t *easylvgl_button_create(lv_obj_t *parent);

/**
 * 根据 Lua 配置创建按钮对象
 * @param L Lua 状态
 * @param table_index 参数表索引
 */
lv_obj_t *easylvgl_button_create_from_config(lua_State *L, int table_index);

/**
 * 设置按钮点击回调
 * @param btn 按钮对象
 * @param callback Lua 回调函数引用
 */
void easylvgl_button_set_callback(lv_obj_t *btn, int callback_ref);

/**
 * 设置按钮文本内容
 * @param btn 按钮对象
 * @param text 文本
 */
void easylvgl_button_set_text(lv_obj_t *btn, const char *text);

/**
 * 设置全局 Lua 状态（用于回调）
 * @param L Lua 状态指针
 */
void easylvgl_set_lua_state(lua_State *L);

/**
 * 根据 Lua 配置创建标签对象
 * @param L Lua 状态
 * @param table_index 参数表索引
 */
lv_obj_t *easylvgl_label_create_from_config(lua_State *L, int table_index);

/**
 * 根据 Lua 配置创建 image 对象
 */
lv_obj_t *easylvgl_image_create_from_config(lua_State *L, int table_index);

/**
 * 根据 Lua 配置创建 window 对象
 */
lv_obj_t *easylvgl_win_create_from_config(lua_State *L, int table_index);

/**
 * 创建标签对象
 * @param parent 父对象
 * @return 标签对象指针
 */
lv_obj_t *easylvgl_label_create(lv_obj_t *parent);

/**
 * 根据 Lua 配置创建标签对象
 * @param L Lua 状态
 * @param table_index 参数表索引
 */
lv_obj_t *easylvgl_label_create_from_config(lua_State *L, int table_index);

/**
 * 设置标签文本
 * @param label 标签对象
 * @param text 文本内容
 */
void easylvgl_label_set_text(lv_obj_t *label, const char *text);

/**
 * 获取标签文本
 * @param label 标签对象
 * @return 文本内容指针
 */
const char *easylvgl_label_get_text(lv_obj_t *label);

#ifdef __cplusplus
} /*extern "C"*/
#endif

#endif /*EASYLVGL_H*/

