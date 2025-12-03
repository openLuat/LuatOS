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
#include <string.h>

#define LUAT_LOG_TAG "easylvgl"
#include "luat_log.h"

// 全局上下文（单例模式）
static easylvgl_ctx_t *g_ctx = NULL;

// 元表名称
#define EASYLVGL_BUTTON_MT "easylvgl.button"

// 组件 userdata 结构
typedef struct {
    lv_obj_t *obj;
} easylvgl_component_ud_t;

// 函数声明
static int l_easylvgl_init(lua_State *L);
static int l_easylvgl_deinit(lua_State *L);
static int l_easylvgl_refresh(lua_State *L);
static int l_easylvgl_button(lua_State *L);
static void register_button_meta(lua_State *L);
static void push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt);
static lv_obj_t *check_component(lua_State *L, int index, const char *mt);
static int l_button_set_text(lua_State *L);
static int l_button_set_on_click(lua_State *L);
static int l_button_gc(lua_State *L);

// 模块注册表
static const rotable_Reg_t reg_easylvgl[] = {
    {"init", ROREG_FUNC(l_easylvgl_init)},
    {"deinit", ROREG_FUNC(l_easylvgl_deinit)},
    {"refresh", ROREG_FUNC(l_easylvgl_refresh)},
    {"button", ROREG_FUNC(l_easylvgl_button)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_easylvgl(lua_State *L) {
    register_button_meta(L);
    luat_newlib2(L, reg_easylvgl);
    return 1;
}

/**
 * 初始化 EasyLVGL
 * @api easylvgl.init(width, height)
 * @int width 屏幕宽度，默认 480
 * @int height 屏幕高度，默认 320
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
    
    // 初始化 EasyLVGL（ARGB8888 格式）
    ret = easylvgl_init(g_ctx, w, h, LV_COLOR_FORMAT_ARGB8888);
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
 * 创建 Button 组件
 * @api easylvgl.button(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 100
 * @int config.h 高度，默认 40
 * @string config.text 文本内容，可选
 * @function config.on_click 点击回调函数，可选
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Button 对象
 */
static int l_easylvgl_button(lua_State *L) {
    if (g_ctx == NULL) {
        luaL_error(L, "easylvgl not initialized, call easylvgl.init() first");
        return 0;
    }
    
    luaL_checktype(L, 1, LUA_TTABLE);
    
    lv_obj_t *btn = easylvgl_button_create_from_config(L, 1);
    if (btn == NULL) {
        lua_pushnil(L);
        return 1;
    }
    
    push_component_userdata(L, btn, EASYLVGL_BUTTON_MT);
    return 1;
}

/**
 * 注册 Button 元表
 */
static void register_button_meta(lua_State *L) {
    luaL_newmetatable(L, EASYLVGL_BUTTON_MT);
    
    // 设置元方法
    lua_pushcfunction(L, l_button_gc);
    lua_setfield(L, -2, "__gc");
    
    // 设置方法表
    static const luaL_Reg methods[] = {
        {"set_text", l_button_set_text},
        {"set_on_click", l_button_set_on_click},
        {NULL, NULL}
    };
    
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    
    lua_pop(L, 1);
}

/**
 * 推送组件 userdata
 */
static void push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)lua_newuserdata(L, sizeof(easylvgl_component_ud_t));
    ud->obj = obj;
    luaL_getmetatable(L, mt);
    lua_setmetatable(L, -2);
}

/**
 * 检查组件 userdata
 */
static lv_obj_t *check_component(lua_State *L, int index, const char *mt) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, index, mt);
    if (ud == NULL || ud->obj == NULL) {
        luaL_error(L, "invalid %s object", mt);
    }
    return ud->obj;
}

/**
 * Button:set_text(text)
 * @api button:set_text(text)
 * @string text 文本内容
 * @return nil
 */
static int l_button_set_text(lua_State *L) {
    lv_obj_t *btn = check_component(L, 1, EASYLVGL_BUTTON_MT);
    const char *text = luaL_checkstring(L, 2);
    easylvgl_button_set_text(btn, text);
    return 0;
}

/**
 * Button:set_on_click(callback)
 * @api button:set_on_click(callback)
 * @function callback 回调函数
 * @return nil
 */
static int l_button_set_on_click(lua_State *L) {
    lv_obj_t *btn = check_component(L, 1, EASYLVGL_BUTTON_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    
    // 保存回调函数到 registry
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    
    easylvgl_button_set_on_click(btn, ref);
    return 0;
}

/**
 * Button GC
 */
static int l_button_gc(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_BUTTON_MT);
    if (ud != NULL && ud->obj != NULL) {
        // 获取元数据并释放
        easylvgl_component_meta_t *meta = easylvgl_component_meta_get(ud->obj);
        if (meta != NULL) {
            easylvgl_component_meta_free(meta);
        }
        
        // 删除 LVGL 对象
        lv_obj_delete(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

