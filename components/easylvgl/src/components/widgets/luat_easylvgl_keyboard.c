/**
 * @file luat_easylvgl_keyboard.c
 * @summary Keyboard 组件实现
 * @responsible 虚拟键盘创建、目标绑定、事件与布局控制
 */

#include "luat_easylvgl_component.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "luat_conf_bsp.h"
#include "luat_easylvgl_conf.h"
#include "lvgl9/src/widgets/keyboard/lv_keyboard.h"
#include "lvgl9/src/widgets/textarea/lv_textarea.h"
#include "lvgl9/src/misc/lv_event.h"
#if LV_USE_IME_PINYIN
    #include "lvgl9/src/others/ime/lv_ime_pinyin.h"
    // 如果定义了LUAT_USE_PINYIN，则使用自己的pinyin字典
    #if defined(LUAT_USE_PINYIN)
        #include "luat_pinyin.h"
    #endif
#endif
#include "../../inc/luat_easylvgl_binding.h"
#include <string.h>

#define LUAT_LOG_TAG "easylvgl_keyboard"
#include "luat_log.h"

/**
 * 获取 EasyLVGL 上下文（简化访问注册表里预存的上下文指针）
 * @pre L_state 已初始化且已调用 easylvgl.init
 * @post 返回 ctx 或 NULL
 */
static easylvgl_ctx_t *easylvgl_binding_get_ctx(lua_State *L_state) {
    if (L_state == NULL) {
        return NULL;
    }

    easylvgl_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "easylvgl_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (easylvgl_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);
    return ctx;
}

/**
 * 将 Lua 方式传入的模式字符串转换为 LVGL 的枚举值
 * @param mode Lua 端模式，支持 "upper"/"special"/"numeric"
 * @return 对应的 lv_keyboard_mode_t，默认小写文本
 */
static lv_keyboard_mode_t easylvgl_keyboard_mode_from_string(const char *mode)
{
    if (mode == NULL) {
        return LV_KEYBOARD_MODE_TEXT_LOWER;
    }

    if (strcmp(mode, "upper") == 0) {
        return LV_KEYBOARD_MODE_TEXT_UPPER;
    }

    if (strcmp(mode, "special") == 0) {
        return LV_KEYBOARD_MODE_SPECIAL;
    }

    if (strcmp(mode, "numeric") == 0) {
        return LV_KEYBOARD_MODE_NUMBER;
    }

    return LV_KEYBOARD_MODE_TEXT_LOWER;
}

/**
 * 从 Lua 配置表创建 Keyboard 实例
 * @param L Lua 状态
 * @param idx 配置表索引
 * @return Keyboard LVGL 对象或者 NULL
 * @pre ctx 已初始化
 * @post 组件元数据已分配、可以指定 target textarea/on_commit 回调
 */
lv_obj_t *easylvgl_keyboard_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    easylvgl_ctx_t *ctx = easylvgl_binding_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    // 解析可选父对象，不存在时使用当前屏幕
    lv_obj_t *parent = easylvgl_marshal_parent(L, idx);
    if (parent == NULL) {
        parent = lv_scr_act();
    }

    int x = easylvgl_marshal_integer(L, idx, "x", 0);
    int default_y = ctx->height > 160 ? ctx->height - 160 : 0;
    int y = easylvgl_marshal_integer(L, idx, "y", default_y);
    int w = easylvgl_marshal_integer(L, idx, "w", ctx->width > 0 ? ctx->width : 480);
    int h = easylvgl_marshal_integer(L, idx, "h", 160);
    const char *mode = easylvgl_marshal_string(L, idx, "mode", "text");
    bool popovers = easylvgl_marshal_bool(L, idx, "popovers", true);

    // 创建 LVGL 键盘对象，后续配置尺寸与样式
    lv_obj_t *keyboard = lv_keyboard_create(parent);
    if (keyboard == NULL) {
        return NULL;
    }

    lv_obj_set_pos(keyboard, x, y);
    lv_obj_set_size(keyboard, w, h);
    // 根据配置设置键盘模式与提示框开关
    lv_keyboard_set_mode(keyboard, easylvgl_keyboard_mode_from_string(mode));
    lv_keyboard_set_popovers(keyboard, popovers);

    easylvgl_component_meta_t *meta = easylvgl_component_meta_alloc(
        ctx, keyboard, EASYLVGL_COMPONENT_KEYBOARD);
    if (meta == NULL) {
        lv_obj_delete(keyboard);
        return NULL;
    }

    // 元数据围绕回调存储与 Lua userdata
    easylvgl_keyboard_data_t *data = (easylvgl_keyboard_data_t *)luat_heap_malloc(sizeof(easylvgl_keyboard_data_t));
    if (data == NULL) {
        easylvgl_component_meta_free(meta);
        lv_obj_delete(keyboard);
        return NULL;
    }
    data->target = NULL;
    data->ime = NULL;
    meta->user_data = data;

    // 支持拼音输入法
#if LV_USE_IME_PINYIN
    data->ime = lv_ime_pinyin_create(keyboard);
    if (data->ime != NULL) {
        lv_ime_pinyin_set_keyboard(data->ime, keyboard);

        // 如果定义了LUAT_USE_PINYIN，则使用自己的pinyin字典
#if defined(LUAT_USE_PINYIN)
        size_t dict_count = 0;
        const lv_pinyin_dict_t *dict = luat_pinyin_get_lv_dict(&dict_count);
        if (dict != NULL && dict_count > 0) {
            lv_ime_pinyin_set_dict(data->ime, (lv_pinyin_dict_t *)dict);
        }
        LLOGD(LUAT_LOG_TAG, "打开中文输入法支持，词典数量：%d", dict_count);
#endif

    }
#endif

    // 如果配置里提供了 Textarea userdata，立即绑定方可让默认按钮生效
    lua_getfield(L_state, idx, "target");
    if (lua_type(L_state, -1) == LUA_TUSERDATA) {
        easylvgl_component_ud_t *ud = (easylvgl_component_ud_t *)lua_touserdata(L_state, -1);
        if (ud != NULL && ud->obj != NULL) {
            easylvgl_keyboard_set_target(keyboard, ud->obj);
        }
    }
    lua_pop(L_state, 1);

    // 捕获 Lua commit 回调、通过 Ready 事件分发
    int callback_ref = easylvgl_component_capture_callback(L, idx, "on_commit");
    if (callback_ref != LUA_NOREF) {
        easylvgl_keyboard_set_on_commit(keyboard, callback_ref);
    }

    return keyboard;
}

/**
 * 绑定 Keyboard 与 Textarea
 * @param keyboard Keyboard 对象
 * @param textarea 目标 textarea
 * @return EASYLVGL_OK/ERR
 * @pre 两个对象均非 NULL
 */
int easylvgl_keyboard_set_target(lv_obj_t *keyboard, lv_obj_t *textarea)
{
    if (keyboard == NULL || textarea == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    // 通知 LVGL 该 keyboard 操作哪个 textarea，便自动插入字符
    lv_keyboard_set_textarea(keyboard, textarea);

    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(keyboard);
    if (meta == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    // 如果还没有 data 块，先分配保留 target 指针
    easylvgl_keyboard_data_t *data = (easylvgl_keyboard_data_t *)meta->user_data;
    if (data == NULL) {
        data = (easylvgl_keyboard_data_t *)luat_heap_malloc(sizeof(easylvgl_keyboard_data_t));
        if (data == NULL) {
            return EASYLVGL_ERR_NO_MEM;
        }
        data->target = NULL;
        data->ime = NULL;
        meta->user_data = data;
    }
    data->target = textarea;
    return EASYLVGL_OK;
}

int easylvgl_keyboard_show(lv_obj_t *keyboard)
{
    if (keyboard == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    // 使键盘可见并置于最前
    lv_obj_clear_flag(keyboard, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(keyboard);
    return EASYLVGL_OK;
}

int easylvgl_keyboard_hide(lv_obj_t *keyboard)
{
    if (keyboard == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    // 隐藏键盘，不销毁对象
    lv_obj_add_flag(keyboard, LV_OBJ_FLAG_HIDDEN);
    return EASYLVGL_OK;
}

int easylvgl_keyboard_set_on_commit(lv_obj_t *keyboard, int callback_ref)
{
    if (keyboard == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    easylvgl_component_meta_t *meta = easylvgl_component_meta_get(keyboard);
    if (meta == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    // READY 事件用于 commit 回调，复用 Event 系统
    return easylvgl_component_bind_event(meta, EASYLVGL_EVENT_READY, callback_ref);
}

int easylvgl_keyboard_set_layout(lv_obj_t *keyboard, const char *layout)
{
    if (keyboard == NULL || layout == NULL) {
        return EASYLVGL_ERR_INVALID_PARAM;
    }

    lv_keyboard_mode_t mode = easylvgl_keyboard_mode_from_string(layout);
    // 切换键盘布局（包括数值/特殊字符）
    lv_keyboard_set_mode(keyboard, mode);
    return EASYLVGL_OK;
}

