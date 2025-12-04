/*
@module  easylvgl
@summary EasyLVGL图像库 (LVGL 9.4) - 重构版本
@version 0.1.0
@date    2025.12.02
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "rotable2.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_task.h"
#include "../inc/luat_easylvgl_binding.h"
#include <string.h>

#define LUAT_LOG_TAG "easylvgl"
#include "luat_log.h"

// 全局上下文（单例模式）
static easylvgl_ctx_t *g_ctx = NULL;

// 函数声明
static int l_easylvgl_init(lua_State *L);
static int l_easylvgl_deinit(lua_State *L);
static int l_easylvgl_refresh(lua_State *L);

// Button 模块声明
extern void easylvgl_register_button_meta(lua_State *L);
extern int easylvgl_button_create(lua_State *L);

// 模块注册表
static const rotable_Reg_t reg_easylvgl[] = {
    {"init", ROREG_FUNC(l_easylvgl_init)},
    {"deinit", ROREG_FUNC(l_easylvgl_deinit)},
    {"refresh", ROREG_FUNC(l_easylvgl_refresh)},
    {"button", ROREG_FUNC(easylvgl_button_create)},
    // 颜色格式常量
    {"COLOR_FORMAT_RGB565", ROREG_INT(EASYLVGL_COLOR_FORMAT_RGB565)},
    {"COLOR_FORMAT_ARGB8888", ROREG_INT(EASYLVGL_COLOR_FORMAT_ARGB8888)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_easylvgl(lua_State *L) {
    // 注册各组件元表
    easylvgl_register_button_meta(L);
    
    // 注册模块函数
    luat_newlib2(L, reg_easylvgl);
    return 1;
}

/**
 * 初始化 EasyLVGL
 * @api easylvgl.init(width, height, color_format)
 * @int width 屏幕宽度，默认 480
 * @int height 屏幕高度，默认 320
 * @int color_format 颜色格式，可选，默认 RGB565
 *                   可用值：easylvgl.COLOR_FORMAT_RGB565（嵌入式，节省内存）
 *                          easylvgl.COLOR_FORMAT_ARGB8888（默认，高质量）
 * @return bool 成功返回 true，失败返回 false
 */
static int l_easylvgl_init(lua_State *L) {
    if (g_ctx != NULL) {
        LLOGE("easylvgl already initialized");
        lua_pushboolean(L, 0);
        return 1;
    }
    
    int w = luaL_optinteger(L, 1, 480);
    int h = luaL_optinteger(L, 2, 320);
    
    // 获取颜色格式参数，默认为RGB565
    lv_color_format_t color_format = (lv_color_format_t)luaL_optinteger(L, 3, EASYLVGL_COLOR_FORMAT_RGB565);
    
    // 验证颜色格式是否有效，需要和lvgl的颜色格式对应（只支持 RGB565 和 ARGB8888）
    if (color_format != EASYLVGL_COLOR_FORMAT_RGB565 && 
        color_format != EASYLVGL_COLOR_FORMAT_ARGB8888) {
        LLOGE("easylvgl.init: invalid color format %d, using RGB565", color_format);
        color_format = EASYLVGL_COLOR_FORMAT_RGB565;
    }
    
    // 分配上下文
    g_ctx = luat_heap_malloc(sizeof(easylvgl_ctx_t));
    if (g_ctx == NULL) {
        lua_pushboolean(L, 0);
        return 1;
    }
    
    // 创建上下文（自动选择平台驱动）
    int ret = easylvgl_ctx_create(g_ctx, NULL);
    if (ret != 0) {
        luat_heap_free(g_ctx);
        g_ctx = NULL;
        lua_pushboolean(L, 0);
        return 1;
    }
    
    // 存储 Lua 状态
    g_ctx->L = L;
    
    // 将上下文存储到注册表
    lua_pushlightuserdata(L, g_ctx);
    lua_setfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    
    // 初始化 EasyLVGL（使用指定的颜色格式）
    ret = easylvgl_init(g_ctx, w, h, color_format);
    if (ret != 0) {
        easylvgl_ctx_create(g_ctx, NULL);  // 清理
        luat_heap_free(g_ctx);
        g_ctx = NULL;
        lua_pushboolean(L, 0);
        return 1;
    }
    
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * 反初始化 EasyLVGL
 * @api easylvgl.deinit()
 * @return nil
 */
static int l_easylvgl_deinit(lua_State *L) {
    (void)L;
    
    if (g_ctx != NULL) {
        easylvgl_deinit(g_ctx);
        luat_heap_free(g_ctx);
        g_ctx = NULL;
        
        // 清除注册表中的上下文
        lua_pushnil(L);
        lua_setfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    }
    
    return 0;
}

/**
 * 刷新 LVGL 显示（执行定时器处理）
 * @api easylvgl.refresh()
 * @return nil
 */
static int l_easylvgl_refresh(lua_State *L) {
    (void)L;
    
    if (g_ctx == NULL) {
        luaL_error(L, "easylvgl not initialized, call easylvgl.init() first");
        return 0;
    }
    
    // 执行 LVGL 定时器处理（处理重绘、动画、事件等）
    lv_timer_handler();
    
    return 0;
}

/**
 * 推送组件 userdata（通用辅助函数）
 */
void easylvgl_push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)lua_newuserdata(L, sizeof(easylvgl_component_ud_t));
    ud->obj = obj;
    luaL_getmetatable(L, mt);
    lua_setmetatable(L, -2);
}

/**
 * 检查组件 userdata（通用辅助函数）
 */
lv_obj_t *easylvgl_check_component(lua_State *L, int index, const char *mt) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, index, mt);
    if (ud == NULL || ud->obj == NULL) {
        luaL_error(L, "invalid %s object", mt);
    }
    return ud->obj;
}

