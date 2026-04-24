/**
 * @file luat_airui_binding.h
 * @summary AIRUI Lua 绑定公共头文件
 * @responsible 定义通用组件辅助函数和数据结构
 */

#ifndef LUAT_AIRUI_BINDING_H
#define LUAT_AIRUI_BINDING_H

#include <stdint.h>
#include "lua.h"
#include "lauxlib.h"
#include "lvgl9/src/core/lv_obj.h"

#ifdef __cplusplus
extern "C" {
#endif

// 组件引用结构体
typedef struct airui_component_ref {
    lv_obj_t *obj;
    uint8_t alive;
    uint32_t id;
} airui_component_ref_t;

// 组件 userdata 结构（所有组件共享）
typedef struct {
    airui_component_ref_t *ref;
} airui_component_ud_t;

/**
 * 推送组件 userdata 到 Lua 栈
 * @param L Lua 状态
 * @param obj LVGL 对象指针
 * @param mt 元表名称
 */
void airui_push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt);

/**
 * 检查并获取组件 userdata
 * @param L Lua 状态
 * @param index 栈索引
 * @param mt 元表名称
 * @return LVGL 对象指针，失败时抛出错误
 */
lv_obj_t *airui_check_component(lua_State *L, int index, const char *mt);

// 获取组件对象
lv_obj_t *airui_component_userdata_obj(airui_component_ud_t *ud);

// 无效化组件引用
void airui_component_invalidate_ref(airui_component_ref_t *ref);

// 销毁组件 userdata
int airui_component_destroy_userdata(lua_State *L, int index, const char *mt);

// 检查组件是否被销毁
int airui_component_is_destroyed(lua_State *L);

#ifdef __cplusplus
}
#endif

#endif /* LUAT_AIRUI_BINDING_H */

