/**
 * @file luat_airui_keyboard.c
 * @summary Keyboard 组件实现
 * @responsible 虚拟键盘创建、目标绑定、事件与布局控制
 */

#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "luat_conf_bsp.h"
#include "luat_airui_conf.h"
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
#include "../../inc/luat_airui_binding.h"
#include <string.h>

#define LUAT_LOG_TAG "airui_keyboard"
#include "luat_log.h"

/**
 * 获取 AIRUI 上下文（简化访问注册表里预存的上下文指针）
 * @pre L_state 已初始化且已调用 airui.init
 * @post 返回 ctx 或 NULL
 */
static airui_ctx_t *airui_binding_get_ctx(lua_State *L_state) {
    if (L_state == NULL) {
        return NULL;
    }

    airui_ctx_t *ctx = NULL;
    lua_getfield(L_state, LUA_REGISTRYINDEX, "airui_ctx");
    if (lua_type(L_state, -1) == LUA_TLIGHTUSERDATA) {
        ctx = (airui_ctx_t *)lua_touserdata(L_state, -1);
    }
    lua_pop(L_state, 1);
    return ctx;
}

//自动隐藏键盘回调函数
static void airui_keyboard_target_auto_hide_cb(lv_event_t *e)
{
    if (e == NULL) {
        return;
    }

    lv_event_code_t code = lv_event_get_code(e);
    lv_obj_t *keyboard = (lv_obj_t *)lv_event_get_user_data(e);
    if (keyboard == NULL) {
        return;
    }

    switch (code) {
        case LV_EVENT_FOCUSED:
            airui_keyboard_show(keyboard);
            break;
        case LV_EVENT_DEFOCUSED:
            airui_keyboard_hide(keyboard);
            break;
        default:
            break;
    }
}

//刷新自动隐藏键盘
static void airui_keyboard_refresh_auto_hide(lv_obj_t *keyboard, airui_keyboard_data_t *data, lv_obj_t *old_target)
{
    if (keyboard == NULL || data == NULL) {
        return;
    }

    //移除旧目标的自动隐藏回调
    if (old_target != NULL) {
        lv_obj_remove_event_cb_with_user_data(old_target, airui_keyboard_target_auto_hide_cb, keyboard);
    }

    //如果配置了自动隐藏，则添加新目标的自动隐藏回调
    if (data->auto_hide && data->target != NULL) {
        lv_obj_add_event_cb(data->target, airui_keyboard_target_auto_hide_cb, LV_EVENT_FOCUSED, keyboard);
        lv_obj_add_event_cb(data->target, airui_keyboard_target_auto_hide_cb, LV_EVENT_DEFOCUSED, keyboard);
    }
}

//分离自动隐藏键盘目标
void airui_keyboard_detach_auto_hide_target(lv_obj_t *keyboard, airui_keyboard_data_t *data)
{
    if (keyboard == NULL || data == NULL || data->target == NULL) {
        return;
    }

    lv_obj_remove_event_cb_with_user_data(data->target, airui_keyboard_target_auto_hide_cb, keyboard);
}

/**
 * 将 Lua 方式传入的模式字符串转换为 LVGL 的枚举值
 * @param mode Lua 端模式，支持 "upper"/"special"/"numeric"
 * @return 对应的 lv_keyboard_mode_t，默认小写文本
 */
static lv_keyboard_mode_t airui_keyboard_mode_from_string(const char *mode)
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
lv_obj_t *airui_keyboard_create_from_config(void *L, int idx)
{
    if (L == NULL) {
        return NULL;
    }

    lua_State *L_state = (lua_State *)L;
    airui_ctx_t *ctx = airui_binding_get_ctx(L_state);
    if (ctx == NULL) {
        return NULL;
    }

    // 解析可选父对象，不存在时使用当前屏幕
    lv_obj_t *parent = airui_marshal_parent(L, idx);
    if (parent == NULL) {
        parent = lv_scr_act();
    }

    int x = airui_marshal_integer(L, idx, "x", 0);
    int default_y = ctx->height > 160 ? ctx->height - 160 : 0;
    int y = airui_marshal_integer(L, idx, "y", default_y);
    int w = airui_marshal_integer(L, idx, "w", ctx->width > 0 ? ctx->width : 480);
    int h = airui_marshal_integer(L, idx, "h", 160);
    const char *mode = airui_marshal_string(L, idx, "mode", "text");
    bool popovers = airui_marshal_bool(L, idx, "popovers", true);
    bool auto_hide = airui_marshal_bool(L, idx, "auto_hide", false);

    // 创建 LVGL 键盘对象，后续配置尺寸与样式
    lv_obj_t *keyboard = lv_keyboard_create(parent);
    if (keyboard == NULL) {
        return NULL;
    }

    lv_obj_set_pos(keyboard, x, y);
    lv_obj_set_size(keyboard, w, h);
    // 根据配置设置键盘模式与提示框开关
    lv_keyboard_set_mode(keyboard, airui_keyboard_mode_from_string(mode));
    lv_keyboard_set_popovers(keyboard, popovers);

    airui_component_meta_t *meta = airui_component_meta_alloc(
        ctx, keyboard, AIRUI_COMPONENT_KEYBOARD);
    if (meta == NULL) {
        lv_obj_delete(keyboard);
        return NULL;
    }

    // 元数据围绕回调存储与 Lua userdata
    airui_keyboard_data_t *data = (airui_keyboard_data_t *)luat_heap_malloc(sizeof(airui_keyboard_data_t));
    if (data == NULL) {
        airui_component_meta_free(meta);
        lv_obj_delete(keyboard);
        return NULL;
    }
    data->target = NULL;
    data->ime = NULL;
    data->auto_hide = auto_hide;
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
        LLOGI("打开中文输入法支持，词典数量：%d", dict_count);
#endif

    }
#endif

    // 如果配置里提供了 Textarea userdata，立即绑定方可让默认按钮生效
    lua_getfield(L_state, idx, "target");
    if (lua_type(L_state, -1) == LUA_TUSERDATA) {
        airui_component_ud_t *ud = (airui_component_ud_t *)lua_touserdata(L_state, -1);
        if (ud != NULL && ud->obj != NULL) {
            airui_keyboard_set_target(keyboard, ud->obj);
        }
    }
    lua_pop(L_state, 1);

    // 捕获 Lua commit 回调、通过 Ready 事件分发
    int callback_ref = airui_component_capture_callback(L, idx, "on_commit");
    if (callback_ref != LUA_NOREF) {
        airui_keyboard_set_on_commit(keyboard, callback_ref);
    }

    //如果配置了自动隐藏，则立即隐藏键盘
    if (auto_hide) {
        airui_keyboard_hide(keyboard);
    }

    return keyboard;
}

/**
 * 绑定 Keyboard 与 Textarea
 * @param keyboard Keyboard 对象
 * @param textarea 目标 textarea
 * @return AIRUI_OK/ERR
 * @pre 两个对象均非 NULL
 */
int airui_keyboard_set_target(lv_obj_t *keyboard, lv_obj_t *textarea)
{
    if (keyboard == NULL || textarea == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    // 通知 LVGL 该 keyboard 操作哪个 textarea，便自动插入字符
    lv_keyboard_set_textarea(keyboard, textarea);

    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    // 如果还没有 data 块，先分配保留 target 指针
    airui_keyboard_data_t *data = (airui_keyboard_data_t *)meta->user_data;
    if (data == NULL) {
        data = (airui_keyboard_data_t *)luat_heap_malloc(sizeof(airui_keyboard_data_t));
        if (data == NULL) {
            return AIRUI_ERR_NO_MEM;
        }
        data->target = NULL;
        data->ime = NULL;
        data->auto_hide = false;
        meta->user_data = data;
    }
    lv_obj_t *old_target = data->target;
    data->target = textarea;
    //刷新自动隐藏键盘
    airui_keyboard_refresh_auto_hide(keyboard, data, old_target);
    return AIRUI_OK;
}

// 更新拼音候选框的可见性
static void airui_keyboard_update_pinyin_panel(lv_obj_t *keyboard, bool visible)
{
#if LV_USE_IME_PINYIN
    if (keyboard == NULL) {
        return;
    }
    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    if (meta == NULL || meta->user_data == NULL) {
        return;
    }
    airui_keyboard_data_t *data = (airui_keyboard_data_t *)meta->user_data;
    if (data == NULL || data->ime == NULL) {
        return;
    }
    lv_obj_t *cand_panel = lv_ime_pinyin_get_cand_panel(data->ime);
    if (cand_panel == NULL) {
        return;
    }
    if (visible) {
        lv_obj_clear_flag(cand_panel, LV_OBJ_FLAG_HIDDEN);
    } else {
        lv_obj_add_flag(cand_panel, LV_OBJ_FLAG_HIDDEN);
    }
#else
    (void)keyboard;
    (void)visible;
#endif
}

//显示键盘
int airui_keyboard_show(lv_obj_t *keyboard)
{
    if (keyboard == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    //更新拼音候选框的可见性
    airui_keyboard_update_pinyin_panel(keyboard, true);
    // 使键盘可见并置于最前
    lv_obj_clear_flag(keyboard, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(keyboard);
    return AIRUI_OK;
}

//隐藏键盘
int airui_keyboard_hide(lv_obj_t *keyboard)
{
    if (keyboard == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    //更新拼音候选框的可见性
    airui_keyboard_update_pinyin_panel(keyboard, false);
    // 隐藏键盘，不销毁对象
    lv_obj_add_flag(keyboard, LV_OBJ_FLAG_HIDDEN);
    return AIRUI_OK;
}

//设置提交回调
int airui_keyboard_set_on_commit(lv_obj_t *keyboard, int callback_ref)
{
    if (keyboard == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    if (meta == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    // READY 事件用于 commit 回调，复用 Event 系统
    return airui_component_bind_event(meta, AIRUI_EVENT_READY, callback_ref);
}

//设置键盘布局
int airui_keyboard_set_layout(lv_obj_t *keyboard, const char *layout)
{
    if (keyboard == NULL || layout == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    lv_keyboard_mode_t mode = airui_keyboard_mode_from_string(layout);
    // 切换键盘布局（包括数值/特殊字符）
    lv_keyboard_set_mode(keyboard, mode);
    return AIRUI_OK;
}

