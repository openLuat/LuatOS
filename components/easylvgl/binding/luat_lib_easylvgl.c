/*
@module  easylvgl
@summary EasyLVGL图像库 (LVGL 9.4)
@version 0.0.3
@date    2025.11.26
@tag     LUAT_USE_EASYLVGL
@usage
-- 初始化 EasyLVGL
easylvgl.init(480, 320)

-- 组件化创建按钮
local btn = easylvgl.button({
    text = "LuatOS!",
    x = 20, y = 80, w = 160, h = 48,
    on_click = function(self)
        log.info("Button clicked")
    end
})

-- 调用组件方法
btn:set_text("更新后的文本")

-- 创建标签并设置文本
local label = easylvgl.label({
    text = "Hello EasyLVGL!",
    x = 10, y = 150
})
label:set_text("新的文字")
*/

#include "luat_base.h"
#include "luat_mem.h"
#include "luat_log.h"
#include "rotable2.h"
#include "lua.h"
#include "lauxlib.h"
#include "../inc/easylvgl.h"
#include "../inc/easylvgl_component.h"
#include "../lvgl9/src/widgets/button/lv_button.h"

#define LUAT_LOG_TAG "easylvgl"
#include "luat_log.h"

static lua_State *g_L = NULL;

static int l_easylvgl_init(lua_State *L);
static int l_easylvgl_button(lua_State *L);
static int l_easylvgl_label(lua_State *L);
static int l_easylvgl_handler(lua_State *L);
static void register_button_meta(lua_State *L);
static void register_label_meta(lua_State *L);
static void push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt);
static lv_obj_t *check_component(lua_State *L, int index, const char *mt);
static int l_button_set_text(lua_State *L);
static int l_button_set_on_click(lua_State *L);
static int l_button_gc(lua_State *L);
static int l_label_set_text(lua_State *L);
static int l_label_get_text(lua_State *L);
static int l_label_gc(lua_State *L);

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

static int l_easylvgl_button(lua_State *L) {
    lv_obj_t *btn = easylvgl_button_create_from_config(L, 1);
    if (btn == NULL) {
        lua_pushnil(L);
        return 1;
    }

    push_component_userdata(L, btn, EASYLVGL_BUTTON_MT);
    return 1;
}

static int l_easylvgl_label(lua_State *L) {
    lv_obj_t *label = easylvgl_label_create_from_config(L, 1);
    if (label == NULL) {
        lua_pushnil(L);
        return 1;
    }

    push_component_userdata(L, label, EASYLVGL_LABEL_MT);
    return 1;
}

static int l_easylvgl_handler(lua_State *L) {
    uint32_t time_till_next = lv_timer_handler();
    lua_pushinteger(L, time_till_next);
    return 1;
}

static const rotable_Reg_t reg_easylvgl[] = {
    {"init", ROREG_FUNC(l_easylvgl_init)},
    {"handler", ROREG_FUNC(l_easylvgl_handler)},
    {"button", ROREG_FUNC(l_easylvgl_button)},
    {"label", ROREG_FUNC(l_easylvgl_label)},
    {NULL, ROREG_INT(0)}
};

LUAMOD_API int luaopen_easylvgl(lua_State *L) {
    register_button_meta(L);
    register_label_meta(L);
    luat_newlib2(L, reg_easylvgl);
    return 1;
}

static void push_component_userdata(lua_State *L, lv_obj_t *obj, const char *mt) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)lua_newuserdata(L, sizeof(easylvgl_component_ud_t));
    ud->obj = obj;
    luaL_getmetatable(L, mt);
    lua_setmetatable(L, -2);
}

static lv_obj_t *check_component(lua_State *L, int index, const char *mt) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, index, mt);
    if (ud == NULL || ud->obj == NULL) {
        luaL_error(L, "invalid %s object", mt);
    }
    return ud->obj;
}

static int l_button_set_text(lua_State *L) {
    lv_obj_t *btn = check_component(L, 1, EASYLVGL_BUTTON_MT);
    const char *text = luaL_checkstring(L, 2);
    easylvgl_button_set_text(btn, text);
    return 0;
}

static int l_button_set_on_click(lua_State *L) {
    lv_obj_t *btn = check_component(L, 1, EASYLVGL_BUTTON_MT);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    lua_pushvalue(L, 2);
    int ref = luaL_ref(L, LUA_REGISTRYINDEX);
    easylvgl_button_set_callback(btn, ref);
    return 0;
}

static int l_button_gc(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_BUTTON_MT);
    if (ud != NULL && ud->obj != NULL) {
        lv_obj_t *btn = ud->obj;
        int *callback_ref = (int *)lv_obj_get_user_data(btn);
        if (callback_ref != NULL) {
            if (g_L != NULL && *callback_ref != LUA_NOREF) {
                luaL_unref(g_L, LUA_REGISTRYINDEX, *callback_ref);
            }
            luat_heap_free(callback_ref);
            lv_obj_set_user_data(btn, NULL);
        }
        lv_obj_del(btn);
        ud->obj = NULL;
    }
    return 0;
}

static int l_label_set_text(lua_State *L) {
    lv_obj_t *label = check_component(L, 1, EASYLVGL_LABEL_MT);
    const char *text = luaL_checkstring(L, 2);
    easylvgl_label_set_text(label, text);
    return 0;
}

static int l_label_get_text(lua_State *L) {
    lv_obj_t *label = check_component(L, 1, EASYLVGL_LABEL_MT);
    const char *text = easylvgl_label_get_text(label);
    if (text == NULL) {
        lua_pushnil(L);
    } else {
        lua_pushstring(L, text);
    }
    return 1;
}

static int l_label_gc(lua_State *L) {
    easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)luaL_checkudata(L, 1, EASYLVGL_LABEL_MT);
    if (ud != NULL && ud->obj != NULL) {
        lv_obj_del(ud->obj);
        ud->obj = NULL;
    }
    return 0;
}

static void register_button_meta(lua_State *L) {
    if (luaL_newmetatable(L, EASYLVGL_BUTTON_MT)) {
        luaL_Reg methods[] = {
            {"set_text", l_button_set_text},
            {"set_on_click", l_button_set_on_click},
            {NULL, NULL}
        };
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        luaL_setfuncs(L, methods, 0);
        lua_pushcfunction(L, l_button_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
}

static void register_label_meta(lua_State *L) {
    if (luaL_newmetatable(L, EASYLVGL_LABEL_MT)) {
        luaL_Reg methods[] = {
            {"set_text", l_label_set_text},
            {"get_text", l_label_get_text},
            {NULL, NULL}
        };
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
        luaL_setfuncs(L, methods, 0);
        lua_pushcfunction(L, l_label_gc);
        lua_setfield(L, -2, "__gc");
    }
    lua_pop(L, 1);
}