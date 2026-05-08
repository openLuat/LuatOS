/**
 * @file luat_airui_keyboard.c
 * @summary Keyboard 组件实现
 * @responsible 虚拟键盘创建、目标绑定、事件与布局控制
 */

#include "luat_airui_component.h"
#include "luat_airui_input_session.h"
#include "luat_airui_input_coordinator.h"
#include "luat_malloc.h"
#include "lua.h"
#include "lauxlib.h"
#include "luat_conf_bsp.h"
#include "luat_airui_conf.h"
#include "lvgl9/src/widgets/keyboard/lv_keyboard.h"
#include "lvgl9/src/widgets/textarea/lv_textarea.h"
#include "lvgl9/src/widgets/label/lv_label.h"
#include "lvgl9/src/misc/lv_event.h"
#include "lvgl9/src/core/lv_group.h"
#include "lvgl9/src/core/lv_obj_pos.h"
#include "lvgl9/src/core/lv_obj_scroll.h"
#include "lvgl9/src/core/lv_obj_style.h"
#include "lvgl9/src/core/lv_obj_style_gen.h"
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

// 输入预览框运行时数据
typedef struct {
    lv_obj_t *keyboard;
    lv_obj_t *target;
    lv_obj_t *owner;
    lv_obj_t *container;
    lv_obj_t *preview_ta;
    int32_t height;
    int32_t ime_panel_height;
    bool syncing;
} airui_keyboard_preview_runtime_t;

static void airui_keyboard_preview_set_visible(airui_keyboard_data_t *data, bool visible);
static void airui_keyboard_update_pinyin_panel(lv_obj_t *keyboard, bool visible);
#if LV_USE_IME_PINYIN
static lv_obj_t *airui_keyboard_get_valid_cand_panel(airui_keyboard_data_t *data);
#endif

// 初始化键盘数据
static void airui_keyboard_data_init_defaults(airui_keyboard_data_t *data, lv_obj_t *keyboard)
{
    if (data == NULL) {
        return;
    }

    data->target = NULL;
    data->ime = NULL;
    data->auto_hide = false;
    data->auto_hide_indev_hooked = false;
    data->font_size = 0;
    data->preview_enabled = false;
    data->preview_height = 40;
    data->bg_color = lv_color_hex(0xffffff);
    data->preview_runtime = NULL;
    airui_input_session_init(&data->session);
    airui_input_coordinator_init(&data->coord, &data->session, data, keyboard);
}

static void airui_keyboard_session_attach_keyboard(airui_keyboard_data_t *data, lv_obj_t *keyboard)
{
    if (data == NULL) {
        return;
    }
    airui_input_session_set_keyboard(&data->session, keyboard);
}

static void airui_keyboard_session_clear_composing(airui_keyboard_data_t *data)
{
    if (data == NULL) {
        return;
    }
    airui_input_session_clear_composing(&data->session);
}

static void airui_keyboard_session_set_pinyin_composing(airui_keyboard_data_t *data, bool active)
{
    if (data == NULL) {
        return;
    }
    airui_input_coordinator_on_pinyin_composing_change(&data->coord, active);
}

static void airui_keyboard_session_set_target(airui_keyboard_data_t *data, lv_obj_t *target)
{
    if (data == NULL) {
        return;
    }
    data->target = target;
    airui_input_session_set_target(&data->session, target);
}

static void airui_keyboard_session_set_preview_ta(airui_keyboard_data_t *data, lv_obj_t *preview_ta)
{
    if (data == NULL) {
        return;
    }
    airui_input_session_set_preview_ta(&data->session, preview_ta);
}

static void airui_keyboard_session_set_ime(airui_keyboard_data_t *data, lv_obj_t *ime)
{
    if (data == NULL) {
        return;
    }
    data->ime = ime;
    airui_input_session_set_ime(&data->session, ime);
}

static void airui_keyboard_session_set_keyboard_visible(airui_keyboard_data_t *data, bool visible)
{
    if (data == NULL) {
        return;
    }
    airui_input_session_set_keyboard_visible(&data->session, visible);
}

static void airui_keyboard_session_set_preview_visible(airui_keyboard_data_t *data, bool visible)
{
    if (data == NULL) {
        return;
    }
    airui_input_session_set_preview_visible(&data->session, visible);
}

static lv_obj_t *airui_keyboard_session_get_target(const airui_keyboard_data_t *data)
{
    if (data == NULL) {
        return NULL;
    }
    return airui_input_session_get_target(&data->session);
}

static lv_obj_t *airui_keyboard_session_get_active_host(const airui_keyboard_data_t *data)
{
    if (data == NULL) {
        return NULL;
    }
    return airui_input_session_get_edit_host(&data->session);
}

static void airui_keyboard_session_refresh_hosts(airui_keyboard_data_t *data)
{
    if (data == NULL) {
        return;
    }
    airui_input_session_refresh_hosts(&data->session);
}

static void airui_keyboard_session_bind_active_host(lv_obj_t *keyboard, airui_keyboard_data_t *data)
{
    if (keyboard == NULL || data == NULL) {
        return;
    }
    airui_input_coordinator_bind_active_host(&data->coord);
}

static void airui_keyboard_session_sync_runtime(airui_keyboard_data_t *data)
{
    if (data == NULL) {
        return;
    }
    airui_input_coordinator_sync_runtime(&data->coord);
}


static airui_keyboard_data_t *airui_keyboard_get_data(lv_obj_t *keyboard)
{
    if (keyboard == NULL || !lv_obj_is_valid(keyboard)) {
        return NULL;
    }

    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    if (meta == NULL || meta->user_data == NULL) {
        return NULL;
    }

    return (airui_keyboard_data_t *)meta->user_data;
}


static lv_obj_t *airui_keyboard_get_valid_cand_panel(airui_keyboard_data_t *data)
{
#if LV_USE_IME_PINYIN
    if (data == NULL || data->ime == NULL || !lv_obj_is_valid(data->ime)) {
        return NULL;
    }

    lv_obj_t *cand_panel = lv_ime_pinyin_get_cand_panel(data->ime);
    if (cand_panel == NULL || !lv_obj_is_valid(cand_panel)) {
        return NULL;
    }

    return cand_panel;
#else
    (void)data;
    return NULL;
#endif
}

static void airui_keyboard_session_sync_cand_panel(airui_keyboard_data_t *data)
{
    if (data == NULL) {
        return;
    }
    airui_input_session_set_cand_panel(&data->session, airui_keyboard_get_valid_cand_panel(data));
}

#if LV_USE_IME_PINYIN
static void airui_keyboard_ime_delete_event_cb(lv_event_t *e)
{
    if (e == NULL || lv_event_get_code(e) != LV_EVENT_DELETE) {
        return;
    }

    airui_keyboard_data_t *data = (airui_keyboard_data_t *)lv_event_get_user_data(e);
    if (data != NULL) {
        airui_keyboard_session_set_ime(data, NULL);
        airui_input_session_set_cand_panel(&data->session, NULL);
        airui_input_session_clear_composing(&data->session);
    }
}
#endif

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

// 输入预览框目标事件回调
static void airui_keyboard_preview_target_event_cb(lv_event_t *e);
static void airui_keyboard_preview_proxy_event_cb(lv_event_t *e);
static void airui_keyboard_preview_owner_event_cb(lv_event_t *e);
static void airui_keyboard_preview_container_event_cb(lv_event_t *e);
static void airui_keyboard_owner_auto_hide_cb(lv_event_t *e);
static void airui_keyboard_indev_auto_hide_cb(lv_event_t *e);
static void airui_keyboard_apply_font(lv_obj_t *keyboard, airui_keyboard_data_t *data);

static airui_keyboard_data_t *airui_keyboard_preview_get_data(airui_keyboard_preview_runtime_t *runtime)
{
    if (runtime == NULL || runtime->keyboard == NULL || !lv_obj_is_valid(runtime->keyboard)) {
        return NULL;
    }

    airui_component_meta_t *meta = airui_component_meta_get(runtime->keyboard);
    if (meta == NULL || meta->user_data == NULL) {
        return NULL;
    }

    return (airui_keyboard_data_t *)meta->user_data;
}

static void airui_keyboard_preview_detach_target(airui_keyboard_preview_runtime_t *runtime)
{
    if (runtime == NULL) {
        return;
    }

    if (runtime->target != NULL && lv_obj_is_valid(runtime->target)) {
        lv_obj_remove_event_cb_with_user_data(runtime->target, airui_keyboard_preview_target_event_cb, runtime);
    }

    runtime->target = NULL;
}

static bool airui_keyboard_preview_is_visible(airui_keyboard_preview_runtime_t *runtime)
{
    if (runtime == NULL || runtime->container == NULL) {
        return false;
    }
    if (!lv_obj_is_valid(runtime->container)) {
        return false;
    }

    return !lv_obj_has_flag(runtime->container, LV_OBJ_FLAG_HIDDEN);
}

// 隐藏输入框光标
static void airui_keyboard_hide_textarea_cursor(lv_obj_t *textarea)
{
    if (textarea == NULL || !lv_obj_is_valid(textarea)) {
        return;
    }

    lv_style_selector_t sel = (lv_style_selector_t)LV_PART_CURSOR | LV_STATE_FOCUSED;
    lv_obj_set_style_bg_opa(textarea, LV_OPA_0, sel);
    lv_obj_set_style_border_opa(textarea, LV_OPA_0, sel);
    lv_obj_set_style_text_opa(textarea, LV_OPA_0, sel);
    lv_obj_set_style_anim_duration(textarea, 0, sel);
}

// 恢复输入框光标
static void airui_keyboard_restore_textarea_cursor(lv_obj_t *textarea)
{
    if (textarea == NULL || !lv_obj_is_valid(textarea)) {
        return;
    }

    lv_style_selector_t sel = (lv_style_selector_t)LV_PART_CURSOR | LV_STATE_FOCUSED;
    lv_obj_remove_local_style_prop(textarea, LV_STYLE_BG_OPA, sel);
    lv_obj_remove_local_style_prop(textarea, LV_STYLE_BORDER_OPA, sel);
    lv_obj_remove_local_style_prop(textarea, LV_STYLE_TEXT_OPA, sel);
    lv_obj_remove_local_style_prop(textarea, LV_STYLE_ANIM_DURATION, sel);
}

// 输入预览框重新布局
static void airui_keyboard_preview_relayout(airui_keyboard_preview_runtime_t *runtime)
{
    if (runtime == NULL || runtime->keyboard == NULL || runtime->container == NULL || runtime->preview_ta == NULL) {
        return;
    }
    if (!lv_obj_is_valid(runtime->keyboard) || !lv_obj_is_valid(runtime->container) || !lv_obj_is_valid(runtime->preview_ta)) {
        return;
    }

    lv_obj_t *keyboard = runtime->keyboard;

#if LV_USE_IME_PINYIN
    airui_component_meta_t *meta = airui_component_meta_get(runtime->keyboard);
    if (meta != NULL && meta->user_data != NULL) {
        airui_keyboard_data_t *data = (airui_keyboard_data_t *)meta->user_data;
        if (data != NULL && data->ime != NULL) {
            lv_obj_t *cand_panel = airui_keyboard_get_valid_cand_panel(data);
            if (cand_panel != NULL && lv_obj_is_valid(cand_panel)) {
                lv_obj_update_layout(cand_panel);
                int32_t cand_h = lv_obj_get_height(cand_panel);
                if (cand_h > 0) {
                    runtime->ime_panel_height = cand_h;
                }
            }
        }
    }
#endif

    int32_t ime_reserved_h = runtime->ime_panel_height > 0 ? runtime->ime_panel_height : 0;

    int32_t width = lv_obj_get_width(keyboard);
    if (width < 20) {
        width = 20;
    }

    lv_obj_set_width(runtime->container, width);
    lv_obj_set_width(runtime->preview_ta, LV_PCT(100));
    lv_obj_set_height(runtime->preview_ta, LV_SIZE_CONTENT);
    if (runtime->height <= 0) {
        lv_obj_add_flag(runtime->container, LV_OBJ_FLAG_HIDDEN);
        return;
    }
    lv_obj_set_height(runtime->container, runtime->height);

    lv_obj_align_to(runtime->container, keyboard, LV_ALIGN_OUT_TOP_MID, 0, -ime_reserved_h);

    lv_obj_update_layout(keyboard);
    lv_obj_update_layout(runtime->container);

    lv_area_t keyboard_coords;
    lv_obj_get_coords(keyboard, &keyboard_coords);
    int32_t available_h = keyboard_coords.y1 - ime_reserved_h;
    if (available_h < runtime->height) {
        lv_obj_add_flag(runtime->container, LV_OBJ_FLAG_HIDDEN);
        return;
    }
}

// 输入预览框同步文本
static void airui_keyboard_preview_sync_text(airui_keyboard_preview_runtime_t *runtime)
{
    if (runtime == NULL || runtime->preview_ta == NULL || runtime->container == NULL) {
        return;
    }
    if (!lv_obj_is_valid(runtime->preview_ta) || !lv_obj_is_valid(runtime->container)) {
        return;
    }

    const char *text = "";
    uint32_t cursor_pos = 0;
    if (runtime->target != NULL && lv_obj_is_valid(runtime->target)) {
        const char *value = lv_textarea_get_text(runtime->target);
        text = value != NULL ? value : "";
        cursor_pos = lv_textarea_get_cursor_pos(runtime->target);
    }

    runtime->syncing = true;
    lv_textarea_set_text(runtime->preview_ta, text);
    lv_textarea_set_cursor_pos(runtime->preview_ta, cursor_pos);
    runtime->syncing = false;
    if (runtime->keyboard != NULL && lv_obj_is_valid(runtime->keyboard)) {
        airui_component_meta_t *meta = airui_component_meta_get(runtime->keyboard);
        if (meta != NULL && meta->user_data != NULL) {
            airui_keyboard_apply_font(runtime->keyboard, (airui_keyboard_data_t *)meta->user_data);
        }
    }
    airui_keyboard_preview_relayout(runtime);
    if (!lv_obj_has_flag(runtime->container, LV_OBJ_FLAG_HIDDEN)) {
        int32_t overflow_top = lv_obj_get_scroll_top(runtime->container);
        int32_t overflow_bottom = lv_obj_get_scroll_bottom(runtime->container);
        if (overflow_top > 0 || overflow_bottom > 0) {
            lv_obj_scroll_to_y(runtime->container, LV_COORD_MAX, LV_ANIM_OFF);
        }
        else {
            lv_obj_scroll_to_y(runtime->container, 0, LV_ANIM_OFF);
        }
    }
}

static void airui_keyboard_apply_font(lv_obj_t *keyboard, airui_keyboard_data_t *data)
{
    if (keyboard == NULL || data == NULL || data->font_size == 0) {
        return;
    }

    (void)airui_text_font_apply_hzfont(keyboard, data->font_size,
        ((lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT));
    (void)airui_text_font_apply_hzfont(keyboard, data->font_size,
        ((lv_style_selector_t)LV_PART_ITEMS | LV_STATE_PRESSED));

    if (data->preview_runtime != NULL) {
        airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)data->preview_runtime;
        if (runtime->preview_ta != NULL && lv_obj_is_valid(runtime->preview_ta)) {
            lv_obj_t *preview_label = lv_textarea_get_label(runtime->preview_ta);
            if (preview_label != NULL) {
                (void)airui_text_font_apply_hzfont(preview_label, data->font_size,
                    ((lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT));
            }
            (void)airui_text_font_apply_hzfont(runtime->preview_ta, data->font_size,
                ((lv_style_selector_t)LV_PART_TEXTAREA_PLACEHOLDER | LV_STATE_DEFAULT));
        }
    }

#if LV_USE_IME_PINYIN
    if (data->ime != NULL) {
        lv_obj_t *cand_panel = airui_keyboard_get_valid_cand_panel(data);
        if (cand_panel != NULL && lv_obj_is_valid(cand_panel)) {
            (void)airui_text_font_apply_hzfont(cand_panel, data->font_size,
                ((lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT));
            (void)airui_text_font_apply_hzfont(cand_panel, data->font_size,
                ((lv_style_selector_t)LV_PART_ITEMS | LV_STATE_DEFAULT));
        }
    }
#endif
}

// 输入预览框绑定目标
static void airui_keyboard_preview_bind_target(airui_keyboard_preview_runtime_t *runtime, lv_obj_t *target)
{
    if (runtime == NULL) {
        return;
    }

    if (runtime->target == target && target != NULL) {
        airui_keyboard_preview_sync_text(runtime);
        return;
    }

    airui_keyboard_preview_detach_target(runtime);

    runtime->target = target;
    if (runtime->target != NULL && lv_obj_is_valid(runtime->target)) {
        lv_obj_add_event_cb(runtime->target, airui_keyboard_preview_target_event_cb, LV_EVENT_VALUE_CHANGED, runtime);
        lv_obj_add_event_cb(runtime->target, airui_keyboard_preview_target_event_cb, LV_EVENT_DELETE, runtime);
    }

    airui_keyboard_preview_sync_text(runtime);
}

static void airui_keyboard_preview_sync_back(airui_keyboard_preview_runtime_t *runtime)
{
    if (runtime == NULL || runtime->target == NULL || runtime->preview_ta == NULL) {
        return;
    }
    if (!lv_obj_is_valid(runtime->target) || !lv_obj_is_valid(runtime->preview_ta)) {
        return;
    }

    runtime->syncing = true;
    lv_textarea_set_text(runtime->target, lv_textarea_get_text(runtime->preview_ta));
    lv_textarea_set_cursor_pos(runtime->target, lv_textarea_get_cursor_pos(runtime->preview_ta));
    runtime->syncing = false;
}

static void airui_keyboard_preview_flush(airui_keyboard_data_t *data)
{
    if (data == NULL || data->preview_runtime == NULL) {
        return;
    }

    airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)data->preview_runtime;
    airui_keyboard_preview_sync_back(runtime);
}

void airui_keyboard_apply_visibility(lv_obj_t *keyboard, airui_keyboard_data_t *data, bool visible)
{
    if (keyboard == NULL || data == NULL) {
        return;
    }

    airui_keyboard_session_set_keyboard_visible(data, visible);
    airui_keyboard_update_pinyin_panel(keyboard, visible);
    airui_keyboard_preview_set_visible(data, visible);
    airui_keyboard_session_sync_runtime(data);
    airui_keyboard_session_bind_active_host(keyboard, data);

    if (visible) {
        lv_obj_clear_flag(keyboard, LV_OBJ_FLAG_HIDDEN);
        lv_obj_move_foreground(keyboard);
    }
    else {
        lv_obj_add_flag(keyboard, LV_OBJ_FLAG_HIDDEN);
    }
}

// 输入预览框设置可见性
static void airui_keyboard_preview_set_visible(airui_keyboard_data_t *data, bool visible)
{
    if (data == NULL || data->preview_runtime == NULL) {
        return;
    }

    airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)data->preview_runtime;
    if (runtime->container == NULL || !lv_obj_is_valid(runtime->container)) {
        return;
    }

    if (visible) {
        airui_keyboard_session_set_preview_visible(data, true);
        lv_obj_clear_flag(runtime->container, LV_OBJ_FLAG_HIDDEN);
        airui_keyboard_preview_sync_text(runtime);
        if (runtime->target != NULL && lv_obj_is_valid(runtime->target)) {
            airui_keyboard_hide_textarea_cursor(runtime->target);
        }
        if (runtime->preview_ta != NULL && lv_obj_is_valid(runtime->preview_ta)) {
            airui_keyboard_session_bind_active_host(runtime->keyboard, data);
            lv_obj_add_state(runtime->preview_ta, LV_STATE_FOCUSED);
            lv_obj_move_foreground(runtime->preview_ta);
        }
        lv_obj_move_foreground(runtime->container);
    }
    else {
        airui_keyboard_preview_sync_back(runtime);
        airui_keyboard_session_set_preview_visible(data, false);
        if (runtime->target != NULL && lv_obj_is_valid(runtime->target)) {
            airui_keyboard_session_bind_active_host(runtime->keyboard, data);
            airui_keyboard_restore_textarea_cursor(runtime->target);
        }
        else if (runtime->keyboard != NULL && lv_obj_is_valid(runtime->keyboard)) {
            airui_keyboard_session_bind_active_host(runtime->keyboard, data);
        }
        if (runtime->preview_ta != NULL && lv_obj_is_valid(runtime->preview_ta)) {
            lv_obj_clear_state(runtime->preview_ta, LV_STATE_FOCUSED);
        }
        lv_obj_add_flag(runtime->container, LV_OBJ_FLAG_HIDDEN);
    }
}

// 输入预览框目标事件回调
static void airui_keyboard_preview_target_event_cb(lv_event_t *e)
{
    if (e == NULL) {
        return;
    }

    airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)lv_event_get_user_data(e);
    if (runtime == NULL) {
        return;
    }

    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_VALUE_CHANGED) {
        if (runtime->syncing) {
            return;
        }
        airui_keyboard_preview_sync_text(runtime);
    }
    else if (code == LV_EVENT_DELETE) {
        airui_keyboard_preview_detach_target(runtime);

        airui_keyboard_data_t *data = airui_keyboard_preview_get_data(runtime);
        if (data != NULL) {
            airui_keyboard_preview_set_visible(data, false);
        }
    }
}

static void airui_keyboard_preview_owner_event_cb(lv_event_t *e)
{
    if (e == NULL || lv_event_get_code(e) != LV_EVENT_DELETE) {
        return;
    }

    airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)lv_event_get_user_data(e);
    if (runtime == NULL) {
        return;
    }

    airui_keyboard_preview_detach_target(runtime);
    runtime->owner = NULL;

    if (runtime->keyboard != NULL && lv_obj_is_valid(runtime->keyboard)) {
        airui_component_meta_t *meta = airui_component_meta_get(runtime->keyboard);
        airui_keyboard_data_t *data = meta != NULL ? (airui_keyboard_data_t *)meta->user_data : NULL;
        if (data != NULL) {
            airui_keyboard_session_set_preview_visible(data, false);
            airui_keyboard_session_bind_active_host(runtime->keyboard, data);
        }
        else {
            lv_keyboard_set_textarea(runtime->keyboard, NULL);
        }
    }
}

static void airui_keyboard_preview_container_event_cb(lv_event_t *e)
{
    if (e == NULL || lv_event_get_code(e) != LV_EVENT_DELETE) {
        return;
    }

    airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)lv_event_get_user_data(e);
    if (runtime == NULL) {
        return;
    }

    runtime->container = NULL;
    runtime->preview_ta = NULL;
}

static void airui_keyboard_owner_auto_hide_cb(lv_event_t *e)
{
    if (e == NULL || lv_event_get_code(e) != LV_EVENT_PRESSED) {
        return;
    }

    lv_obj_t *keyboard = (lv_obj_t *)lv_event_get_user_data(e);
    lv_obj_t *pressed = lv_event_get_target(e);
    if (keyboard == NULL || !lv_obj_is_valid(keyboard) || pressed == NULL || !lv_obj_is_valid(pressed)) {
        return;
    }

    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    airui_keyboard_data_t *data = meta != NULL ? (airui_keyboard_data_t *)meta->user_data : NULL;
    if (data == NULL) {
        return;
    }

    airui_input_coordinator_on_outside_press(&data->coord, pressed);
}

static void airui_keyboard_indev_auto_hide_cb(lv_event_t *e)
{
    if (e == NULL || lv_event_get_code(e) != LV_EVENT_PRESSED) {
        return;
    }

    lv_obj_t *keyboard = (lv_obj_t *)lv_event_get_user_data(e);
    if (keyboard == NULL || !lv_obj_is_valid(keyboard)) {
        return;
    }

    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    airui_keyboard_data_t *data = meta != NULL ? (airui_keyboard_data_t *)meta->user_data : NULL;
    if (data == NULL) {
        return;
    }

    lv_obj_t *pressed = lv_indev_get_active_obj();
    if (pressed == NULL || !lv_obj_is_valid(pressed)) {
        return;
    }

    airui_input_coordinator_on_outside_press(&data->coord, pressed);
}

// 输入预览框代理事件回调
static void airui_keyboard_preview_proxy_event_cb(lv_event_t *e)
{
    if (e == NULL) {
        return;
    }

    airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)lv_event_get_user_data(e);
    if (runtime == NULL || runtime->syncing) {
        return;
    }

    lv_event_code_t code = lv_event_get_code(e);
    if (code == LV_EVENT_VALUE_CHANGED) {
        airui_keyboard_preview_sync_back(runtime);
    }
    else if (code == LV_EVENT_FOCUSED || code == LV_EVENT_PRESSED || code == LV_EVENT_CLICKED) {
        airui_keyboard_data_t *data = airui_keyboard_preview_get_data(runtime);
        if (runtime->keyboard != NULL && lv_obj_is_valid(runtime->keyboard) &&
            runtime->preview_ta != NULL && lv_obj_is_valid(runtime->preview_ta) &&
            data != NULL) {
            airui_keyboard_session_set_preview_visible(data, true);
            airui_keyboard_session_bind_active_host(runtime->keyboard, data);
        }

        if (runtime->preview_ta != NULL && lv_obj_is_valid(runtime->preview_ta) &&
            !lv_obj_has_state(runtime->preview_ta, LV_STATE_FOCUSED)) {
            lv_obj_add_state(runtime->preview_ta, LV_STATE_FOCUSED);
            if (code != LV_EVENT_FOCUSED) {
                lv_obj_send_event(runtime->preview_ta, LV_EVENT_FOCUSED, NULL);
            }
        }
    }
}

// 输入预览框清理事件回调
static void airui_keyboard_preview_cleanup_event_cb(lv_event_t *e)
{
    if (e == NULL || lv_event_get_code(e) != LV_EVENT_DELETE) {
        return;
    }

    airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)lv_event_get_user_data(e);
    if (runtime == NULL) {
        return;
    }

    airui_keyboard_data_t *data = airui_keyboard_preview_get_data(runtime);
    if (data != NULL && data->preview_runtime == runtime) {
        data->preview_runtime = NULL;
        airui_keyboard_session_set_preview_visible(data, false);
        airui_keyboard_session_set_preview_ta(data, NULL);
        airui_keyboard_session_bind_active_host(runtime->keyboard, data);
    }

    airui_keyboard_preview_detach_target(runtime);

    if (runtime->owner != NULL && lv_obj_is_valid(runtime->owner)) {
        lv_obj_remove_event_cb_with_user_data(runtime->owner, airui_keyboard_preview_owner_event_cb, runtime);
    }

    if (runtime->keyboard != NULL && lv_obj_is_valid(runtime->keyboard)) {
        airui_component_meta_t *meta = airui_component_meta_get(runtime->keyboard);
        airui_keyboard_data_t *data = meta != NULL ? (airui_keyboard_data_t *)meta->user_data : NULL;
        if (data != NULL && data->auto_hide && runtime->owner != NULL && lv_obj_is_valid(runtime->owner)) {
            lv_obj_remove_event_cb_with_user_data(runtime->owner, airui_keyboard_owner_auto_hide_cb, runtime->keyboard);
        }
        if (data != NULL && data->auto_hide_indev_hooked && meta != NULL && meta->ctx != NULL && meta->ctx->indev != NULL) {
            lv_indev_remove_event_cb_with_user_data(meta->ctx->indev, airui_keyboard_indev_auto_hide_cb, runtime->keyboard);
            data->auto_hide_indev_hooked = false;
        }
    }

    if (runtime->container != NULL && lv_obj_is_valid(runtime->container)) {
        lv_obj_remove_event_cb_with_user_data(runtime->container, airui_keyboard_preview_container_event_cb, runtime);
    }

    if (runtime->keyboard != NULL && lv_obj_is_valid(runtime->keyboard)) {
        airui_component_meta_t *meta = airui_component_meta_get(runtime->keyboard);
        airui_keyboard_data_t *keyboard_data = meta != NULL ? (airui_keyboard_data_t *)meta->user_data : NULL;
        if (keyboard_data != NULL) {
            airui_keyboard_session_bind_active_host(runtime->keyboard, keyboard_data);
        }
        else {
            lv_keyboard_set_textarea(runtime->keyboard, NULL);
        }
    }

    runtime->owner = NULL;
    runtime->container = NULL;
    runtime->preview_ta = NULL;

    luat_heap_free(runtime);
}

// 输入预览框初始化
static void airui_keyboard_preview_init(lv_obj_t *keyboard, airui_keyboard_data_t *data)
{
    if (keyboard == NULL || data == NULL || !data->preview_enabled || data->preview_runtime != NULL) {
        return;
    }

    airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)luat_heap_malloc(sizeof(airui_keyboard_preview_runtime_t));
    if (runtime == NULL) {
        return;
    }
    memset(runtime, 0, sizeof(airui_keyboard_preview_runtime_t));

    runtime->keyboard = keyboard;
    runtime->height = data->preview_height;

    lv_obj_t *parent = lv_obj_get_parent(keyboard);
    runtime->owner = parent;
    runtime->container = lv_obj_create(parent);
    if (runtime->container == NULL) {
        luat_heap_free(runtime);
        return;
    }

    runtime->preview_ta = lv_textarea_create(runtime->container);
    if (runtime->preview_ta == NULL) {
        lv_obj_delete(runtime->container);
        luat_heap_free(runtime);
        return;
    }

    lv_obj_set_style_pad_hor(runtime->container, 8, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_ver(runtime->container, 6, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_color(runtime->container, lv_color_hex(0xffffff), (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(runtime->container, LV_OPA_COVER, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_color(runtime->container, lv_color_hex(0xcbd5e1), (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_border_width(runtime->container, 1, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_radius(runtime->container, 6, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_shadow_opa(runtime->container, LV_OPA_0, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_scroll_dir(runtime->container, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(runtime->container, LV_SCROLLBAR_MODE_AUTO);

    lv_obj_set_style_text_align(runtime->preview_ta, LV_TEXT_ALIGN_LEFT, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_width(runtime->preview_ta, LV_PCT(100));
    lv_obj_set_height(runtime->preview_ta, LV_SIZE_CONTENT);
    lv_obj_set_style_border_width(runtime->preview_ta, 0, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(runtime->preview_ta, LV_OPA_0, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_all(runtime->preview_ta, 0, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_pad_left(runtime->preview_ta, 0, (lv_style_selector_t)LV_PART_CURSOR | LV_STATE_FOCUSED);
    lv_textarea_set_placeholder_text(runtime->preview_ta, "");
    lv_textarea_set_text(runtime->preview_ta, "");
    lv_textarea_set_text_selection(runtime->preview_ta, true);
    lv_obj_add_event_cb(runtime->preview_ta, airui_keyboard_preview_proxy_event_cb, LV_EVENT_VALUE_CHANGED, runtime);
    lv_obj_add_event_cb(runtime->preview_ta, airui_keyboard_preview_proxy_event_cb, LV_EVENT_FOCUSED, runtime);
    lv_obj_add_event_cb(runtime->preview_ta, airui_keyboard_preview_proxy_event_cb, LV_EVENT_PRESSED, runtime);
    lv_obj_add_event_cb(runtime->preview_ta, airui_keyboard_preview_proxy_event_cb, LV_EVENT_CLICKED, runtime);

    lv_obj_set_style_bg_color(runtime->container, data->bg_color, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(runtime->container, LV_OPA_COVER, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);

    if (runtime->owner != NULL && lv_obj_is_valid(runtime->owner)) {
        lv_obj_add_event_cb(runtime->owner, airui_keyboard_preview_owner_event_cb, LV_EVENT_DELETE, runtime);
    }
    lv_obj_add_event_cb(runtime->container, airui_keyboard_preview_container_event_cb, LV_EVENT_DELETE, runtime);
    lv_obj_add_event_cb(keyboard, airui_keyboard_preview_cleanup_event_cb, LV_EVENT_DELETE, runtime);
    lv_obj_add_flag(runtime->container, LV_OBJ_FLAG_HIDDEN);

    /* 预览框仅供键盘绑定与显示，不参与与业务 textarea 相同的 lv_group，避免收起预览时
     * lv_group_focus_next 把焦点/session 甩到组内下一个输入框。组焦点仍留在业务框。 */
    lv_group_remove_obj(runtime->preview_ta);

    data->preview_runtime = runtime;
    airui_keyboard_session_set_preview_ta(data, runtime->preview_ta);
}

//自动隐藏键盘回调函数
static void airui_keyboard_target_auto_hide_cb(lv_event_t *e)
{
    if (e == NULL) {
        return;
    }

    lv_event_code_t code = lv_event_get_code(e);
    lv_obj_t *keyboard = (lv_obj_t *)lv_event_get_user_data(e);
    lv_obj_t *target = lv_event_get_target(e);
    if (keyboard == NULL) {
        return;
    }

    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    airui_keyboard_data_t *data = meta != NULL ? (airui_keyboard_data_t *)meta->user_data : NULL;
    if (data == NULL) {
        return;
    }

    switch (code) {
        case LV_EVENT_FOCUSED:
            airui_input_coordinator_on_target_focused(&data->coord);
            break;
        case LV_EVENT_DEFOCUSED:
            airui_input_coordinator_on_target_defocused(&data->coord);
            break;
        case LV_EVENT_LEAVE:
            airui_input_coordinator_on_target_leave(&data->coord);
            break;
        default:
            break;
    }
}

static void airui_keyboard_refresh_auto_hide(lv_obj_t *keyboard, airui_keyboard_data_t *data, lv_obj_t *old_target)
{
    if (keyboard == NULL || data == NULL) {
        return;
    }

    /* target 未变化时跳过：避免在 FOCUSED 事件处理链中，textarea_focus_cb 先执行 bind_shared_keyboard
     * 导致 remove 我们的回调，使后续本应执行的 auto_hide_cb 被提前移除而无法触发 */
    lv_obj_t *target = airui_keyboard_session_get_target(data);
    if (old_target == target && old_target != NULL) {
        return;
    }

    //移除旧目标的自动隐藏回调
    if (old_target != NULL) {
        lv_obj_remove_event_cb_with_user_data(old_target, airui_keyboard_target_auto_hide_cb, keyboard);
    }

    if (data->preview_runtime != NULL) {
        airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)data->preview_runtime;
        if (runtime->preview_ta != NULL && lv_obj_is_valid(runtime->preview_ta)) {
            lv_obj_remove_event_cb_with_user_data(runtime->preview_ta, airui_keyboard_target_auto_hide_cb, keyboard);
        }
    }

    //如果配置了自动隐藏，则添加新目标的自动隐藏回调
    if (data->auto_hide && target != NULL) {
        lv_obj_add_event_cb(target, airui_keyboard_target_auto_hide_cb, LV_EVENT_FOCUSED, keyboard);
        lv_obj_add_event_cb(target, airui_keyboard_target_auto_hide_cb, LV_EVENT_DEFOCUSED, keyboard);
        lv_obj_add_event_cb(target, airui_keyboard_target_auto_hide_cb, LV_EVENT_LEAVE, keyboard);

        if (data->preview_runtime != NULL) {
            airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)data->preview_runtime;
            if (runtime->preview_ta != NULL && lv_obj_is_valid(runtime->preview_ta)) {
                lv_obj_add_event_cb(runtime->preview_ta, airui_keyboard_target_auto_hide_cb, LV_EVENT_FOCUSED, keyboard);
                lv_obj_add_event_cb(runtime->preview_ta, airui_keyboard_target_auto_hide_cb, LV_EVENT_DEFOCUSED, keyboard);
                lv_obj_add_event_cb(runtime->preview_ta, airui_keyboard_target_auto_hide_cb, LV_EVENT_LEAVE, keyboard);
            }
        }
    }
}

//分离自动隐藏键盘目标
void airui_keyboard_detach_auto_hide_target(lv_obj_t *keyboard, airui_keyboard_data_t *data)
{
    if (keyboard == NULL || data == NULL) {
        return;
    }

    lv_obj_t *target = airui_keyboard_session_get_target(data);
    if (target != NULL) {
        lv_obj_remove_event_cb_with_user_data(target, airui_keyboard_target_auto_hide_cb, keyboard);
    }
    if (data->preview_runtime != NULL) {
        airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)data->preview_runtime;
        if (runtime->preview_ta != NULL && lv_obj_is_valid(runtime->preview_ta)) {
            lv_obj_remove_event_cb_with_user_data(runtime->preview_ta, airui_keyboard_target_auto_hide_cb, keyboard);
        }
    }
}

/**
 * 将 Lua 方式传入的模式字符串转换为 LVGL 的枚举值
 * @param mode Lua 端模式，支持 "text"/"upper"/"special"/"numeric"/"pinyin_26"/"pinyin_9"
 * @return 对应的 lv_keyboard_mode_t，默认小写文本
 */
static lv_keyboard_mode_t airui_keyboard_mode_from_string(const char *mode)
{
    if (mode == NULL || strcmp(mode, "text") == 0) {
        LLOGI("键盘设置为默认小写文本模式: \"text\"");
        return LV_KEYBOARD_MODE_TEXT_LOWER;
    }

    if (strcmp(mode, "pinyin_26") == 0) {
        LLOGI("键盘模式设置为拼音26键模式: \"pinyin_26\"");
        return LV_KEYBOARD_MODE_TEXT_LOWER;
    }

    if (strcmp(mode, "pinyin_9") == 0) {
        LLOGI("键盘模式设置为拼音9键模式: \"pinyin_9\"");
        return LV_KEYBOARD_MODE_TEXT_LOWER;
    }

    if (strcmp(mode, "pinyin_9_number") == 0) {
        LLOGI("键盘模式设置为拼音9键数字模式: \"pinyin_9_number\"");
        return LV_KEYBOARD_MODE_NUMBER;
    }

    if (strcmp(mode, "upper") == 0) {
        LLOGI("键盘模式设置为大写文本模式: \"upper\"");
        return LV_KEYBOARD_MODE_TEXT_UPPER;
    }

    if (strcmp(mode, "special") == 0) {
        LLOGI("键盘模式设置为特殊字符模式: \"special\"");
        return LV_KEYBOARD_MODE_SPECIAL;
    }

    if (strcmp(mode, "numeric") == 0) {
        LLOGI("键盘模式设置为数字模式: \"numeric\"");
        return LV_KEYBOARD_MODE_NUMBER;
    }

    LLOGI("mode 参数\"%s\"无效, 键盘模式设置为小写文本模式: \"text\"", mode);
    return LV_KEYBOARD_MODE_TEXT_LOWER;
}

static void airui_keyboard_apply_pinyin_mode(airui_keyboard_data_t *data, const char *mode)
{
#if LV_USE_IME_PINYIN
    if (data == NULL || data->ime == NULL || mode == NULL) {
        return;
    }

    if (strcmp(mode, "pinyin_9") == 0) {
        lv_ime_pinyin_set_mode(data->ime, LV_IME_PINYIN_MODE_K9);
        airui_keyboard_session_sync_cand_panel(data);
        return;
    }

    if (strcmp(mode, "pinyin_9_number") == 0) {
        lv_ime_pinyin_set_mode(data->ime, LV_IME_PINYIN_MODE_K9_NUMBER);
        lv_keyboard_set_mode(lv_ime_pinyin_get_kb(data->ime), LV_KEYBOARD_MODE_NUMBER);
        lv_obj_t *cand_panel = airui_keyboard_get_valid_cand_panel(data);
        if (cand_panel != NULL) {
            lv_obj_add_flag(cand_panel, LV_OBJ_FLAG_HIDDEN);
        }
        airui_keyboard_session_set_pinyin_composing(data, false);
        airui_keyboard_session_sync_cand_panel(data);
        return;
    }

    if (strcmp(mode, "pinyin_26") == 0) {
        lv_ime_pinyin_set_mode(data->ime, LV_IME_PINYIN_MODE_K26);
        lv_keyboard_set_mode(lv_ime_pinyin_get_kb(data->ime), LV_KEYBOARD_MODE_TEXT_LOWER);
        airui_keyboard_session_sync_cand_panel(data);
        return;
    }

    airui_keyboard_session_set_pinyin_composing(data, false);
    airui_keyboard_session_sync_cand_panel(data);
#else
    (void)data;
    (void)mode;
#endif
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

    int x = airui_marshal_floor_integer(L, idx, "x", 0);
    int y = airui_marshal_floor_integer(L, idx, "y", 0); // 键盘默认打开ALIGN_BOTTOM_MID，位置从中下方开始计算
    int w = airui_marshal_floor_integer(L, idx, "w", 300);
    int h = airui_marshal_floor_integer(L, idx, "h", 160);
    const char *mode = airui_marshal_string(L, idx, "mode", "text");
    bool popovers = airui_marshal_bool(L, idx, "popovers", true);
    bool auto_hide = airui_marshal_bool(L, idx, "auto_hide", false);
    int font_size = airui_marshal_integer(L, idx, "font_size", 0);
    bool preview_enabled = airui_marshal_bool(L, idx, "preview", false);
    int preview_height = airui_marshal_integer(L, idx, "preview_height", 40);
    if (preview_height < 0) {
        preview_height = 0;
    }
    // 解析背景颜色, 未配置时使用键盘默认主题色
    lv_color_t bg_color;
    lv_color_t parsed_color;

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

    /* 与 preview_ta 同理：键盘在 default group 内且获得组焦点时，隐藏键盘会触发 focus_next。
     * 触摸场景不依赖组内焦点，移出组避免 auto_hide 后光标乱跳。 */
    lv_group_remove_obj(keyboard);

    bg_color = lv_obj_get_style_bg_color(keyboard, LV_PART_MAIN);
    if (airui_marshal_color(L, idx, "bg_color", &parsed_color)) {
        bg_color = parsed_color;
    }

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
    airui_keyboard_data_init_defaults(data, keyboard);
    data->auto_hide = auto_hide;
    data->font_size = (uint16_t)(font_size > 0 ? font_size : 0);
    data->preview_enabled = preview_enabled;
    data->preview_height = preview_height;
    data->bg_color = bg_color;
    airui_component_meta_set_user_data(meta, data, luat_heap_free);

    // 支持拼音输入法
#if LV_USE_IME_PINYIN
    data->ime = lv_ime_pinyin_create(keyboard);
    if (data->ime != NULL) {
        airui_keyboard_session_set_ime(data, data->ime);
        lv_ime_pinyin_set_keyboard(data->ime, keyboard);
        lv_obj_add_event_cb(data->ime, airui_keyboard_ime_delete_event_cb, LV_EVENT_DELETE, data);

        // 如果定义了LUAT_USE_PINYIN，则使用自己的pinyin字典
#if defined(LUAT_USE_PINYIN)
        size_t dict_count = 0;
        const lv_pinyin_dict_t *dict = luat_pinyin_get_lv_dict(&dict_count);
        if (dict != NULL && dict_count > 0) {
            lv_ime_pinyin_set_dict(data->ime, (lv_pinyin_dict_t *)dict);
        }
        LLOGI("打开中文输入法支持，词典数量：%d", dict_count);
#endif

        airui_keyboard_apply_pinyin_mode(data, mode);
        airui_keyboard_session_sync_cand_panel(data);

    }
#endif

    // 设置键盘和预览框背景颜色
    airui_keyboard_set_bg_color(keyboard, bg_color);
    airui_keyboard_apply_font(keyboard, data);

    // 如果配置了输入预览框，则初始化
    if (preview_enabled) {
        airui_keyboard_preview_init(keyboard, data);
        if (!auto_hide) {
            airui_keyboard_preview_set_visible(data, true);
        }
    }

    if (auto_hide && parent != NULL && lv_obj_is_valid(parent)) {
        lv_obj_add_event_cb(parent, airui_keyboard_owner_auto_hide_cb, LV_EVENT_PRESSED, keyboard);
    }
    if (auto_hide && ctx->indev != NULL) {
        lv_indev_add_event_cb(ctx->indev, airui_keyboard_indev_auto_hide_cb, LV_EVENT_PRESSED, keyboard);
        data->auto_hide_indev_hooked = true;
    }

    // 如果配置里提供了 Textarea userdata，立即绑定方可让默认按钮生效
    lua_getfield(L_state, idx, "target");
    if (lua_type(L_state, -1) == LUA_TUSERDATA) {
        airui_component_ud_t *ud = (airui_component_ud_t *)lua_touserdata(L_state, -1);
        lv_obj_t *target = airui_component_userdata_obj(ud);
        if (target != NULL) {
            airui_keyboard_set_target(keyboard, target);
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
        airui_keyboard_data_init_defaults(data, keyboard);
        airui_component_meta_set_user_data(meta, data, luat_heap_free);
    }
    lv_obj_t *old_target = airui_keyboard_session_get_target(data);
    if (old_target != NULL && old_target != textarea && data->session.preview_visible) {
        airui_keyboard_preview_flush(data);
    }
    airui_keyboard_session_set_target(data, textarea);
    airui_keyboard_session_clear_composing(data);
    //刷新自动隐藏键盘
    airui_keyboard_refresh_auto_hide(keyboard, data, old_target);
    if (data->preview_runtime != NULL) {
        airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)data->preview_runtime;
        airui_keyboard_preview_bind_target(runtime, textarea);
        if (runtime->container != NULL && lv_obj_is_valid(runtime->container) &&
            !lv_obj_has_flag(runtime->container, LV_OBJ_FLAG_HIDDEN) &&
            runtime->preview_ta != NULL && lv_obj_is_valid(runtime->preview_ta)) {
            airui_keyboard_session_set_preview_visible(data, true);
            airui_keyboard_session_sync_runtime(data);
            airui_keyboard_session_bind_active_host(keyboard, data);
            return AIRUI_OK;
        }
    }

    // 通知 LVGL 该 keyboard 操作哪个 textarea，便自动插入字符
    airui_keyboard_session_set_preview_visible(data, false);
    airui_keyboard_session_sync_runtime(data);
    airui_keyboard_session_bind_active_host(keyboard, data);
    return AIRUI_OK;
}

// 设置拼音候选框背景颜色
static void airui_keyboard_apply_pinyin_bg(airui_keyboard_data_t *data, lv_obj_t *cand_panel)
{
#if LV_USE_IME_PINYIN
    if (data == NULL || cand_panel == NULL) {
        return;
    }
    lv_obj_set_style_bg_color(cand_panel, data->bg_color, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(cand_panel, LV_OPA_COVER, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
#else
    (void)data;
    (void)cand_panel;
#endif
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
    airui_keyboard_session_sync_cand_panel(data);
    lv_obj_t *cand_panel = airui_keyboard_get_valid_cand_panel(data);
    if (cand_panel == NULL) {
        return;
    }
    airui_keyboard_apply_pinyin_bg(data, cand_panel);
    if (visible) {
        if (!lv_obj_has_flag(cand_panel, LV_OBJ_FLAG_HIDDEN)) {
            lv_obj_move_foreground(cand_panel);
            airui_keyboard_session_set_pinyin_composing(data, true);
        }
        else {
            airui_keyboard_session_set_pinyin_composing(data, false);
        }
    } else {
        lv_obj_add_flag(cand_panel, LV_OBJ_FLAG_HIDDEN);
        airui_keyboard_session_set_pinyin_composing(data, false);
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

    airui_keyboard_data_t *data = airui_keyboard_get_data(keyboard);
    if (data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    return airui_input_coordinator_request_show(&data->coord, AIRUI_INPUT_SHOW_REASON_MANUAL);
}

//隐藏键盘
int airui_keyboard_hide(lv_obj_t *keyboard)
{
    if (keyboard == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_keyboard_data_t *data = airui_keyboard_get_data(keyboard);
    if (data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    return airui_input_coordinator_request_hide(&data->coord, AIRUI_INPUT_HIDE_REASON_MANUAL);
}

int airui_keyboard_set_system_preedit_state(lv_obj_t *keyboard, bool active, int32_t pos, int32_t len)
{
    if (keyboard == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    if (meta == NULL || meta->user_data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_keyboard_data_t *data = (airui_keyboard_data_t *)meta->user_data;
    if (data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_input_coordinator_on_system_preedit_change(&data->coord, active, pos, len);
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
    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    if (meta != NULL && meta->user_data != NULL) {
        airui_keyboard_apply_font(keyboard, (airui_keyboard_data_t *)meta->user_data);
    }
    return AIRUI_OK;
}

//设置键盘和拼音候选框背景颜色
int airui_keyboard_set_bg_color(lv_obj_t *keyboard, lv_color_t color)
{
    if (keyboard == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_component_meta_t *meta = airui_component_meta_get(keyboard);
    if (meta == NULL || meta->user_data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    airui_keyboard_data_t *data = (airui_keyboard_data_t *)meta->user_data;
    if (data == NULL) {
        return AIRUI_ERR_INVALID_PARAM;
    }

    data->bg_color = color;

#if LV_USE_IME_PINYIN
    if (data->ime != NULL) {
        lv_obj_t *cand_panel = airui_keyboard_get_valid_cand_panel(data);
        airui_keyboard_apply_pinyin_bg(data, cand_panel);
    }
#endif

    if (data->preview_runtime != NULL) {
        airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)data->preview_runtime;
        if (runtime->container != NULL && lv_obj_is_valid(runtime->container)) {
            lv_obj_set_style_bg_color(runtime->container, color, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
            lv_obj_set_style_bg_opa(runtime->container, LV_OPA_COVER, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
        }
    }

    lv_obj_set_style_bg_color(keyboard, color, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    lv_obj_set_style_bg_opa(keyboard, LV_OPA_COVER, (lv_style_selector_t)LV_PART_MAIN | LV_STATE_DEFAULT);
    return AIRUI_OK;
}

