/**
 * @file luat_easylvgl_binding.h
 * @summary EasyLVGL Lua 绑定公共头文件
 * @responsible 定义通用组件辅助函数和数据结构
 */

#ifndef LUAT_EASYLVGL_BINDING_H
#define LUAT_EASYLVGL_BINDING_H

#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/core/lv_obj.h"

#define EASYLVGL_TEXTAREA_MT "easylvgl.textarea"
#define EASYLVGL_KEYBOARD_MT "easylvgl.keyboard"
#define EASYLVGL_CONTAINER_MT "easylvgl.container"

#ifdef __cplusplus
extern "C" {
#endif

// 组件 userdata 结构（所有组件共享）
typedef struct {
    lv_obj_t *obj;
} easylvgl_component_ud_t;

/**
 * 推送组件 userdata 到 Lua 栈
 * @param L Lua 状态
 * @param obj LVGL 对象指针
 * @param mt 元表名称
 */
void easylvgl_push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt);

/**
 * 检查并获取组件 userdata
 * @param L Lua 状态
 * @param index 栈索引
 * @param mt 元表名称
 * @return LVGL 对象指针，失败时抛出错误
 */
lv_obj_t *easylvgl_check_component(lua_State *L, int index, const char *mt);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_EASYLVGL_BINDING_H */

