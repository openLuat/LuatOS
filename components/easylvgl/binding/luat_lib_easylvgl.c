/*
@module  easylvgl
@summary EasyLVGL图像库 (LVGL 9.4)
@version 0.0.2
@date    2024.11.07
@tag     LUAT_USE_EASYLVGL
@usage
-- 初始化 EasyLVGL
easylvgl.init(480, 320)

-- 创建按钮
local btn = easylvgl.button()
easylvgl.button_set_callback(btn, function(obj)
    print("Button clicked!")
end)

-- 创建标签
local label = easylvgl.label()
easylvgl.label_set_text(label, "Hello EasyLVGL!")
*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_log.h"
#include "rotable2.h"
#include "../inc/easylvgl.h"

#define LUAT_LOG_TAG "easylvgl"
#include "luat_log.h"

static lua_State *g_L = NULL;

/**
 * 初始化 EasyLVGL
 * @api easylvgl.init(w, h, buff_size, buff_mode)
 * @int 屏幕宽,可选,默认480
 * @int 屏幕高,可选,默认320
 * @int 缓冲区大小,可选,默认宽*10, 不含色深
 * @int 缓冲模式,可选,默认0x06, bit0:是否使用lcdbuff bit1:buff1 bit2:buff2 bit3:是否使用lua heap
 * @return bool 成功返回true,否则返回false
 */
static int l_easylvgl_init(lua_State *L) {
    g_L = L;
    easylvgl_set_lua_state(L);
    
    int w = luaL_optinteger(L, 1, 480);
    int h = luaL_optinteger(L, 2, 320);
    size_t buf_size = 0;
    uint8_t buff_mode = 0x06;  // 默认双缓冲，使用 heap
    
    if (lua_isinteger(L, 3)) {
        buf_size = luaL_checkinteger(L, 3);
    }
    
    if (lua_isinteger(L, 4)) {
        buff_mode = luaL_checkinteger(L, 4);
    }
    
    int ret = easylvgl_init_internal(w, h, buf_size, buff_mode);
    lua_pushboolean(L, ret == 0);
    return 1;
}

/**
 * 创建按钮对象
 * @api easylvgl.button(parent)
 * @userdata 父对象,可选,默认使用屏幕
 * @return userdata 按钮对象指针
 */
static int l_easylvgl_button(lua_State *L) {
    lv_obj_t *parent = NULL;
    
    if (lua_isuserdata(L, 1)) {
        parent = (lv_obj_t *)lua_touserdata(L, 1);
    }
    
    lv_obj_t *btn = easylvgl_button_create(parent);
    if (btn == NULL) {
        lua_pushnil(L);
        return 1;
    }
    
    lua_pushlightuserdata(L, btn);
    return 1;
}

/**
 * 设置按钮点击回调
 * @api easylvgl.button_set_callback(btn, callback)
 * @userdata 按钮对象
 * @function 回调函数,接收按钮对象作为参数
 * @return nil
 */
static int l_easylvgl_button_set_callback(lua_State *L) {
    if (!lua_isuserdata(L, 1)) {
        luaL_error(L, "expect userdata for button");
        return 0;
    }
    
    if (!lua_isfunction(L, 2)) {
        luaL_error(L, "expect function for callback");
        return 0;
    }
    
    lv_obj_t *btn = (lv_obj_t *)lua_touserdata(L, 1);
    
    // 将回调函数保存到注册表
    int callback_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    
    easylvgl_button_set_callback(btn, callback_ref);
    
    return 0;
}

/**
 * 创建标签对象
 * @api easylvgl.label(parent)
 * @userdata 父对象,可选,默认使用屏幕
 * @return userdata 标签对象指针
 */
static int l_easylvgl_label(lua_State *L) {
    lv_obj_t *parent = NULL;
    
    if (lua_isuserdata(L, 1)) {
        parent = (lv_obj_t *)lua_touserdata(L, 1);
    }
    
    lv_obj_t *label = easylvgl_label_create(parent);
    if (label == NULL) {
        lua_pushnil(L);
        return 1;
    }
    
    lua_pushlightuserdata(L, label);
    return 1;
}

/**
 * 设置标签文本
 * @api easylvgl.label_set_text(label, text)
 * @userdata 标签对象
 * @string 文本内容
 * @return nil
 */
static int l_easylvgl_label_set_text(lua_State *L) {
    if (!lua_isuserdata(L, 1)) {
        luaL_error(L, "expect userdata for label");
        return 0;
    }
    
    const char *text = luaL_checkstring(L, 2);
    lv_obj_t *label = (lv_obj_t *)lua_touserdata(L, 1);
    
    easylvgl_label_set_text(label, text);
    
    return 0;
}

/**
 * 获取标签文本
 * @api easylvgl.label_get_text(label)
 * @userdata 标签对象
 * @return string 文本内容
 */
static int l_easylvgl_label_get_text(lua_State *L) {
    if (!lua_isuserdata(L, 1)) {
        luaL_error(L, "expect userdata for label");
        return 0;
    }
    
    lv_obj_t *label = (lv_obj_t *)lua_touserdata(L, 1);
    const char *text = easylvgl_label_get_text(label);
    
    if (text == NULL) {
        lua_pushnil(L);
    } else {
        lua_pushstring(L, text);
    }
    
    return 1;
}

static const rotable_Reg_t reg_easylvgl[] = {
    {"init", ROREG_FUNC(l_easylvgl_init)},
    {"button", ROREG_FUNC(l_easylvgl_button)},
    {"button_set_callback", ROREG_FUNC(l_easylvgl_button_set_callback)},
    {"label", ROREG_FUNC(l_easylvgl_label)},
    {"label_set_text", ROREG_FUNC(l_easylvgl_label_set_text)},
    {"label_get_text", ROREG_FUNC(l_easylvgl_label_get_text)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_easylvgl(lua_State *L) {
    luat_newlib2(L, reg_easylvgl);
    return 1;
}

