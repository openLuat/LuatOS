/*
@module  easylvgl.xml
@summary EasyLVGL XML 支持 (LVGL 9.4)
@version 0.1.0
@date    2025.12.31
@tag     LUAT_USE_EASYLVGL
*/

#include "luat_base.h"
#define LUAT_LOG_TAG "easylvgl.xml"
#include "luat_log.h"
#include "lua.h"
#include "lauxlib.h"
#include "luat_malloc.h"
#include "lvgl9/src/widgets/keyboard/lv_keyboard.h"
#include "../inc/luat_easylvgl.h"
#include "../inc/luat_easylvgl_binding.h"
#include "../inc/luat_easylvgl_xml.h"

typedef struct {
    lua_State *L;
    int lua_ref;
} easylvgl_xml_event_ref_t;

typedef struct {
    lv_obj_t *keyboard;
} easylvgl_xml_keyboard_binding_t;

// trampoline + release helper 声明
static void easylvgl_xml_event_trampoline(lv_event_t *event);
static void easylvgl_xml_event_release(lv_event_t *event);
static void easylvgl_xml_keyboard_focus_cb(lv_event_t *event);
static void easylvgl_xml_keyboard_defocus_cb(lv_event_t *event);
static void easylvgl_xml_keyboard_release(lv_event_t *event);
/**
 * 初始化 LVGL XML 模块，保证后续可以注册/加载 XML。
 * @api easylvgl.xml_init()
 * @return bool 永远返回 true（如果 XML 被禁用则只记录警告）。
 */
int l_easylvgl_xml_init(lua_State *L) {
    (void)L;
    easylvgl_xml_init();
    return 0;
}

/**
 * 关闭 LVGL XML 模块并释放资源。
 * @api easylvgl.xml_deinit()
 * @return bool 永远返回 true，供 Lua 判断是否执行。
 */
int l_easylvgl_xml_deinit(lua_State *L) {
    (void)L;
    easylvgl_xml_deinit();
    return 0;
}

/**
 * Lua 层按文件注册 XML 组件定义。
 * @api easylvgl.xml_register_from_file(path)
 * @string path XML 文件路径
 * @return bool 成功返回 true，失败返回 false（或 XML 功能不可用）。
 */
int l_easylvgl_xml_register_from_file(lua_State *L) {
    const char *path = luaL_checkstring(L, 1);
    if (!easylvgl_xml_register_from_file(path)) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * Lua 层按字符串注册 XML 内容，适用于内嵌或压缩资源。
 * @api easylvgl.xml_register_from_data(name, data)
 * @string name 注册名称（可作为 `xml_create_screen` 的参数）
 * @string data XML 文本
 * @return bool 成功返回 true，失败返回 false。
 */
int l_easylvgl_xml_register_from_data(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    const char *data = luaL_checkstring(L, 2);
    if (!easylvgl_xml_register_from_data(name, data)) {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * 提前注册 XML 中使用的图片资源。
 * @api easylvgl.xml_register_image(name, src)
 * @string name XML 中 `<image src="name">` 的引用名
 * @string|userdata src 路径字符串或 `lv_img_dsc_t` userdata
 * @return bool 成功返回 true，否则返回 false 并附加错误描述。
 */
int l_easylvgl_xml_register_image(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    const void *src = NULL;
    if (!lua_isnoneornil(L, 2)) {
        if (lua_isstring(L, 2)) {
            src = lua_tostring(L, 2);
        }
        else {
            src = lua_touserdata(L, 2);
        }
    }

    if (src == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "xml_register_image: src is nil or unsupported type");
        return 2;
    }

    if (!easylvgl_xml_register_image(name, src)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "xml_register_image: registration failed");
        return 2;
    }
    lua_pushboolean(L, 1);
    return 1;
}

/**
 * 创建已经注册的 XML 屏幕并返回包裹的 `easylvgl.container`。
 * @api easylvgl.xml_create_screen(name)
 * @string name `register_from_*` 时指定的名称
 * @return userdata `easylvgl.container` 或 nil（失败）。
 */
int l_easylvgl_xml_create_screen(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    lv_obj_t *screen = easylvgl_xml_create_screen(name);
    if (screen == NULL) {
        lua_pushnil(L);
        return 1;
    }
    easylvgl_push_component_userdata(L, screen, EASYLVGL_CONTAINER_MT);
    return 1;
}

/**
 * 给 XML 名称对应的控件绑定 LVGL 事件与 Lua 回调。
 * @api easylvgl.xml_bind_event(name, event_code, callback)
 * @string name 注册时的控件名称
 * @int event_code LVGL 事件码（默认为 `LV_EVENT_CLICKED`）
 * @function callback Lua 回调
 * @return bool 成功返回 true，否则返回 false + 错误信息。
 */
int l_easylvgl_xml_bind_event(lua_State *L) {
    const char *name = luaL_checkstring(L, 1);
    lv_event_code_t code = (lv_event_code_t)luaL_optinteger(L, 2, LV_EVENT_CLICKED);
    luaL_checktype(L, 3, LUA_TFUNCTION);

    lv_obj_t *target = easylvgl_xml_find_object(name);
    if (target == NULL) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "xml_bind_event: object '%s' not found", name);
        return 2;
    }

    easylvgl_xml_event_ref_t *ref = (easylvgl_xml_event_ref_t *)luat_heap_malloc(sizeof(*ref));
    if (ref == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "xml_bind_event: allocation failed");
        return 2;
    }

    lua_pushvalue(L, 3);
    ref->lua_ref = luaL_ref(L, LUA_REGISTRYINDEX);
    ref->L = L;

    if (!easylvgl_xml_add_event_cb(target, code, easylvgl_xml_event_trampoline, ref, easylvgl_xml_event_release)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "xml_bind_event: register event callback failed");
        luat_heap_free(ref);
        return 2;
    }

    lua_pushboolean(L, 1);
    return 1;
}

/**
 * 绑定 XML 定义的键盘和输入框，自动处理 focus/defocus。
 * @api easylvgl.xml_keyboard_bind(keyboard_name, textarea_name)
 * @string keyboard_name `<lv_keyboard name="..."/>` 的名称
 * @string textarea_name `<lv_textarea name="..."/>` 的名称
 * @return bool 成功返回 true，否则返回 false + 错误信息。
 */
int l_easylvgl_xml_keyboard_bind(lua_State *L) {
    const char *keyboard_name = luaL_checkstring(L, 1);
    const char *textarea_name = luaL_checkstring(L, 2);

    lv_obj_t *keyboard = easylvgl_xml_find_object(keyboard_name);
    if (keyboard == NULL) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "xml_keyboard_bind: keyboard '%s' not found", keyboard_name);
        return 2;
    }

    lv_obj_t *textarea = easylvgl_xml_find_object(textarea_name);
    if (textarea == NULL) {
        lua_pushboolean(L, 0);
        lua_pushfstring(L, "xml_keyboard_bind: textarea '%s' not found", textarea_name);
        return 2;
    }

    easylvgl_xml_keyboard_binding_t *binding = (easylvgl_xml_keyboard_binding_t *)luat_heap_malloc(sizeof(*binding));
    if (binding == NULL) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "xml_keyboard_bind: allocation failed");
        return 2;
    }
    binding->keyboard = keyboard;

    if (!easylvgl_xml_bind_keyboard_events(textarea, easylvgl_xml_keyboard_focus_cb, easylvgl_xml_keyboard_defocus_cb, easylvgl_xml_keyboard_release, binding)) {
        lua_pushboolean(L, 0);
        lua_pushstring(L, "xml_keyboard_bind: register focus failed");
        luat_heap_free(binding);
        return 2;
    }

    lua_pushboolean(L, 1);
    return 1;
}

/*
 * 事件 trampoline：通过 registry 拿回 Lua 函数并执行。
 */
static void easylvgl_xml_event_trampoline(lv_event_t *event) {
    easylvgl_xml_event_ref_t *ref = lv_event_get_user_data(event);
    if (ref == NULL || ref->lua_ref == LUA_REFNIL) {
        return;
    }
    lua_State *L = ref->L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref->lua_ref);
    if (lua_pcall(L, 0, 0, 0) != LUA_OK) {
        const char *msg = lua_tostring(L, -1);
        LLOGE("xml event callback error: %s", msg ? msg : "unknown");
        lua_pop(L, 1);
    }
}

/*
 * 事件释放：LVGL target 删除时释放 Lua 引用与堆内存。
 */
static void easylvgl_xml_event_release(lv_event_t *event) {
    easylvgl_xml_event_ref_t *ref = lv_event_get_user_data(event);
    if (ref == NULL) {
        return;
    }
    luaL_unref(ref->L, LUA_REGISTRYINDEX, ref->lua_ref);
    luat_heap_free(ref);
}

static void easylvgl_xml_keyboard_focus_cb(lv_event_t *event) {
    easylvgl_xml_keyboard_binding_t *binding = lv_event_get_user_data(event);
    if (binding == NULL || binding->keyboard == NULL) {
        return;
    }
    lv_keyboard_set_textarea(binding->keyboard, lv_event_get_target(event));
}

static void easylvgl_xml_keyboard_defocus_cb(lv_event_t *event) {
    easylvgl_xml_keyboard_binding_t *binding = lv_event_get_user_data(event);
    if (binding == NULL || binding->keyboard == NULL) {
        return;
    }
    lv_keyboard_set_textarea(binding->keyboard, NULL);
}

static void easylvgl_xml_keyboard_release(lv_event_t *event) {
    easylvgl_xml_keyboard_binding_t *binding = lv_event_get_user_data(event);
    if (binding == NULL) {
        return;
    }
    if (binding->keyboard != NULL) {
        lv_keyboard_set_textarea(binding->keyboard, NULL);
    }
    luat_heap_free(binding);
}

