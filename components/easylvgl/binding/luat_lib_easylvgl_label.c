/*
@module  easylvgl.label
@summary EasyLVGL Label 组件 Lua 绑定
@version 0.1.0
@date    2025.12.02
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_component.h"
#include "../inc/luat_easylvgl_binding.h"
#include <string.h>

#define LUAT_LOG_TAG "easylvgl.label"
#include "luat_log.h"

// 元表名称
#define EASYLVGL_LABEL_MT "easylvgl.label"

/**
 * 创建 Label 组件
 * @api easylvgl.label(config)
 * @table config 配置表
 * @int config.x X 坐标，默认 0
 * @int config.y Y 坐标，默认 0
 * @int config.w 宽度，默认 100
 * @int config.h 高度，默认 40
 * @string config.text 文本内容，可选
 * @userdata config.parent 父对象，可选，默认当前屏幕
 * @return userdata Label 对象
 */
static int l_easylvgl_label(lua_State *L) {
    // 检查上下文是否已初始化（从注册表获取）
    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L, -1);
    }
    lua_pop(L, 1);
    
    if (ctx == NULL) {
        luaL_error(L, "easylvgl not initialized, call easylvgl.init() first");
        return 0;
    }
    
    luaL_checktype(L, 1, LUA_TTABLE);
    
    lv_obj_t *label = easylvgl_label_create_from_config(L, 1);
    if (label == NULL) {
        lua_pushnil(L);
        return 1;
    }
    
    easylvgl_push_component_userdata(L, label, EASYLVGL_LABEL_MT);
    return 1;
}

/**
 * Label:set_text(text)
 * @api label:set_text(text)
 * @string text 文本内容
 * @return nil
 */
static int l_label_set_text(lua_State *L) {
    lv_obj_t *label = easylvgl_check_component(L, 1, EASYLVGL_LABEL_MT);
    const char *text = luaL_checkstring(L, 2);
    easylvgl_label_set_text(label, text);
    return 0;
}

static int l_label_set_symbol(lua_State *L) {
    lv_obj_t *label = easylvgl_check_component(L, 1, EASYLVGL_LABEL_MT);
    const char *symbol = luaL_checkstring(L, 2);
    if (symbol == NULL) {
        return 0;
    }
    lv_label_set_text(label, symbol);
    return 0;
}

static int l_label_set_on_click(lua_State *L) {
    lv_obj_t *label = easylvgl_check_component(L, 1, EASYLVGL_LABEL_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);

    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);

    lv_obj_add_flag(label, LV_OBJ_FLAG_CLICKABLE);

    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(label);
    if (meta != NULL) {
        easylvgl_component_bind_event(meta, EASYLVGL_EVENT_CLICKED, ref);
    } else {
        luaL_unref(L, LUA_REGISTRYINDEX, ref);
    }

    return 0;
}

/**
 * Label:get_text()
 * @api label:get_text()
 * @return string 文本内容
 */
static int l_label_get_text(lua_State *L) {
    lv_obj_t *label = easylvgl_check_component(L, 1, EASYLVGL_LABEL_MT);
    const char *text = easylvgl_label_get_text(label);
    if (text != NULL) {
        lua_pushstring(L, text);
    } else {
        lua_pushstring(L, "");
    }
    return 1;
}

/**
 * Label:destroy（手动销毁）
 */
static int l_label_destroy(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_LABEL_MT);
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

/**
 * 注册 Label 元表
 * @param L Lua 状态
 */
void easylvgl_register_label_meta(lua_State *L) {
    luaL_newmetatable(L, EASYLVGL_LABEL_MT);
    
    // 设置方法表
    static const luaL_Reg methods[] = {
        {"set_text", l_label_set_text},
        {"set_symbol", l_label_set_symbol},
        {"set_on_click", l_label_set_on_click},
        {"get_text", l_label_get_text},
        {"destroy", l_label_destroy},
        {NULL, NULL}
    };
    
    luaL_newlib(L, methods);
    lua_setfield(L, -2, "__index");
    
    lua_pop(L, 1);
}

/**
 * Label 创建函数（供主模块注册）
 */
int easylvgl_label_create(lua_State *L) {
    return l_easylvgl_label(L);
}

