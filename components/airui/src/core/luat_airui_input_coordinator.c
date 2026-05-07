/**
 * @file luat_airui_input_coordinator.c
 * @summary 输入协调层 — 会话状态机、事件分发、渲染调度
 * ## 核心设计 — 状态驱动式架构
 *
 *   新模式（状态驱动式）:
 *     回调收到事件 → 上报 coordinator
 *       → coordinator 更新 session 状态
 *         → 调用 renderer 把状态落到 UI
 *
 *   show/hide 的单一入口:
 *     airui_input_coordinator_request_show(coord, reason)
 *     airui_input_coordinator_request_hide(coord, reason)
 *
 *   不再在各处直接操作:
 *     lv_obj_add_flag(keyboard, HIDDEN)
 *     lv_keyboard_set_textarea(keyboard, ...)
 *     airui_keyboard_preview_set_visible(...)
 *
 * ## 状态机（顶层相位）
 *
 *   IDLE     — 没有激活目标，keyboard/preview/cand 都不显示
 *   FOCUSED  — 已有 target，但 keyboard 可见性取决于 auto_hide 策略
 *   EDITING  — keyboard 可见，edit_host 已确定，用户正在输入
 *   COMPOSING — 处于拼音串或 SDL preedit 阶段，有未提交临时文本
 *
 *   关键迁移:
 *     target focused   → IDLE → FOCUSED (auto_hide 时自动 → EDITING)
 *     keyboard show    → FOCUSED → EDITING (设定 edit_host, 绑定 keyboard)
 *     拼音/SDL preedit → EDITING → COMPOSING
 *     候选提交/preedit commit → COMPOSING → EDITING
 *     keyboard hide    → 任意态 → IDLE 或 FOCUSED (清 composing, flush preview)
 *
 * ## 模块关系
 *
 *   本模块依赖 airui_input_session (状态存储) 和
 *   airui_keyboard_apply_visibility (UI 应用)。
 *   不直接操作 LVGL 对象，所有 UI 变更通过 keyboard 层的渲染函数完成。
 *
 * ## show/hide reason 语义
 *
 *   show:  TARGET_FOCUS — 目标 textarea 获得焦点 (auto_hide 策略)
 *          MANUAL       — Lua 层显式调用 keyboard:show()
 *
 *   hide:  TARGET_BLUR    — 目标 textarea 失去焦点 (含 leave)
 *          OUTSIDE_PRESS  — 点击键盘体系外的区域 (auto_hide 策略)
 *          MANUAL         — Lua 层显式调用 keyboard:hide()
 *          DESTROY        — keyboard 本身被销毁
 *
 *   reason 的作用是让 coordinator 在不同场景下采取不同策略:
 *   - TARGET_BLUR/OUTSIDE_PRESS: 隐藏前先 flush preview → target
 *   - MANUAL: 不做 flush (调用者自行管理)
 */

#include "luat_airui_input_coordinator.h"
#include "luat_airui_component.h"
#include "luat_malloc.h"
#include "lvgl9/src/widgets/keyboard/lv_keyboard.h"
#include "lvgl9/src/widgets/textarea/lv_textarea.h"
#include "lvgl9/src/misc/lv_event.h"
#include "lvgl9/src/core/lv_group.h"
#include "lvgl9/src/core/lv_obj_pos.h"
#include "lvgl9/src/core/lv_obj_style.h"

#if LV_USE_IME_PINYIN
#include "lvgl9/src/others/ime/lv_ime_pinyin.h"
#endif

#include <string.h>

#define LUAT_LOG_TAG "airui_coord"
#include "luat_log.h"

/* ---- 内部引用: keyboard 层的渲染函数 ---- */
void airui_keyboard_apply_visibility(lv_obj_t *keyboard, airui_keyboard_data_t *data, bool visible);

/* ---- 内部引用: preview 运行时类型 (与 keyboard.c 保持一致) ---- */
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

/* ---- 内部辅助 ---- */

static lv_obj_t *coord_get_valid_cand_panel(airui_keyboard_data_t *data)
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

static bool coord_is_obj_or_ancestor(lv_obj_t *obj, lv_obj_t *candidate)
{
    if (obj == NULL || candidate == NULL || !lv_obj_is_valid(obj) || !lv_obj_is_valid(candidate)) {
        return false;
    }

    lv_obj_t *current = candidate;
    while (current != NULL && lv_obj_is_valid(current)) {
        if (current == obj) {
            return true;
        }
        current = lv_obj_get_parent(current);
    }

    return false;
}

/* ================================================================
 *  公开 API
 * ================================================================ */

void airui_input_coordinator_init(airui_input_coordinator_t *coord,
                                  airui_input_session_t *session,
                                  airui_keyboard_data_t *kb_data,
                                  lv_obj_t *keyboard)
{
    if (coord == NULL) {
        return;
    }
    coord->session = session;
    coord->kb_data = kb_data;
    coord->keyboard = keyboard;
}

/* ---- Show / Hide ---- */

int airui_input_coordinator_request_show(airui_input_coordinator_t *coord,
                                         airui_input_show_reason_t reason)
{
    if (coord == NULL || coord->session == NULL || coord->kb_data == NULL || coord->keyboard == NULL) {
        return -1;
    }

    airui_input_session_t *s = coord->session;
    airui_keyboard_data_t *data = coord->kb_data;
    lv_obj_t *kb = coord->keyboard;

    /* 状态更新 */
    s->active = true;
    s->keyboard_visible = true;
    if (s->source == AIRUI_INPUT_SOURCE_NONE) {
        s->source = AIRUI_INPUT_SOURCE_VIRTUAL_KEYBOARD;
    }

    airui_input_session_refresh_hosts(s);
    airui_input_coordinator_sync_runtime(coord);

    /* 应用 UI */
    airui_keyboard_apply_visibility(kb, data, true);

    (void)reason;
    return 0;
}

int airui_input_coordinator_request_hide(airui_input_coordinator_t *coord,
                                         airui_input_hide_reason_t reason)
{
    if (coord == NULL || coord->session == NULL || coord->kb_data == NULL || coord->keyboard == NULL) {
        return -1;
    }

    airui_input_session_t *s = coord->session;
    airui_keyboard_data_t *data = coord->kb_data;
    lv_obj_t *kb = coord->keyboard;

    /* 非手动隐藏时，先 flush preview 文本回 target */
    if (reason != AIRUI_INPUT_HIDE_REASON_MANUAL) {
        if (data->preview_runtime != NULL) {
            airui_keyboard_preview_runtime_t *runtime = (airui_keyboard_preview_runtime_t *)data->preview_runtime;
            if (runtime->target != NULL && runtime->preview_ta != NULL &&
                lv_obj_is_valid(runtime->target) && lv_obj_is_valid(runtime->preview_ta)) {
                runtime->syncing = true;
                lv_textarea_set_text(runtime->target, lv_textarea_get_text(runtime->preview_ta));
                lv_textarea_set_cursor_pos(runtime->target, lv_textarea_get_cursor_pos(runtime->preview_ta));
                runtime->syncing = false;
            }
        }
    }

    /* 清空 composing */
    airui_input_session_clear_composing(s);

    /* 状态更新 */
    s->keyboard_visible = false;
    s->active = false;

    /* 应用 UI */
    airui_keyboard_apply_visibility(kb, data, false);

    (void)reason;
    return 0;
}

/* ---- 焦点事件 ---- */

int airui_input_coordinator_on_target_focused(airui_input_coordinator_t *coord)
{
    if (coord == NULL || coord->kb_data == NULL) {
        return -1;
    }

    if (coord->kb_data->auto_hide) {
        return airui_input_coordinator_request_show(coord, AIRUI_INPUT_SHOW_REASON_TARGET_FOCUS);
    }
    return 0;
}

int airui_input_coordinator_on_target_defocused(airui_input_coordinator_t *coord)
{
    if (coord == NULL || coord->kb_data == NULL) {
        return -1;
    }

    if (!coord->kb_data->auto_hide) {
        return 0;
    }

    if (airui_input_coordinator_is_focus_within(coord)) {
        return 0;
    }

    return airui_input_coordinator_request_hide(coord, AIRUI_INPUT_HIDE_REASON_TARGET_BLUR);
}

int airui_input_coordinator_on_target_leave(airui_input_coordinator_t *coord)
{
    /* 处理方式与 defocused 一致 */
    return airui_input_coordinator_on_target_defocused(coord);
}

/* ---- 外部点击 ---- */

int airui_input_coordinator_on_outside_press(airui_input_coordinator_t *coord,
                                             lv_obj_t *pressed)
{
    if (coord == NULL || coord->kb_data == NULL) {
        return -1;
    }

    if (!coord->kb_data->auto_hide) {
        return 0;
    }

    if (airui_input_coordinator_is_related_obj(coord, pressed)) {
        return 0;
    }

    return airui_input_coordinator_request_hide(coord, AIRUI_INPUT_HIDE_REASON_OUTSIDE_PRESS);
}

/* ---- 关联对象判断 ---- */

bool airui_input_coordinator_is_related_obj(const airui_input_coordinator_t *coord,
                                            lv_obj_t *obj)
{
    if (coord == NULL || coord->session == NULL || coord->kb_data == NULL || obj == NULL || !lv_obj_is_valid(obj)) {
        return false;
    }

    const airui_input_session_t *s = coord->session;
    const airui_keyboard_data_t *data = coord->kb_data;

    if (coord_is_obj_or_ancestor(coord->keyboard, obj) ||
        coord_is_obj_or_ancestor(s->target, obj) ||
        coord_is_obj_or_ancestor(s->ime, obj)) {
        return true;
    }

    if (data->preview_runtime != NULL) {
        const airui_keyboard_preview_runtime_t *runtime =
            (const airui_keyboard_preview_runtime_t *)data->preview_runtime;
        if (coord_is_obj_or_ancestor(runtime->container, obj) ||
            coord_is_obj_or_ancestor(runtime->preview_ta, obj)) {
            return true;
        }

#if LV_USE_IME_PINYIN
        if (s->ime != NULL && lv_obj_is_valid(s->ime)) {
            lv_obj_t *cand_panel = coord_get_valid_cand_panel((airui_keyboard_data_t *)data);
            if (coord_is_obj_or_ancestor(cand_panel, obj)) {
                return true;
            }
        }
#endif
    }

    return false;
}

bool airui_input_coordinator_is_focus_within(const airui_input_coordinator_t *coord)
{
    if (coord == NULL || coord->session == NULL || coord->kb_data == NULL) {
        return false;
    }

    const airui_input_session_t *s = coord->session;
    const airui_keyboard_data_t *data = coord->kb_data;
    lv_obj_t *kb = coord->keyboard;
    lv_obj_t *target = s->target;

    lv_obj_t *focused = NULL;
    lv_group_t *group = lv_obj_get_group(kb);
    if (group == NULL && target != NULL && lv_obj_is_valid(target)) {
        group = lv_obj_get_group(target);
    }
    if (group != NULL) {
        focused = lv_group_get_focused(group);
    }

    if (focused != NULL && lv_obj_is_valid(focused)) {
        if (coord_is_obj_or_ancestor(kb, focused) ||
            coord_is_obj_or_ancestor(target, focused) ||
            coord_is_obj_or_ancestor(s->ime, focused)) {
            return true;
        }

        if (data->preview_runtime != NULL) {
            const airui_keyboard_preview_runtime_t *runtime =
                (const airui_keyboard_preview_runtime_t *)data->preview_runtime;
            if (coord_is_obj_or_ancestor(runtime->container, focused) ||
                coord_is_obj_or_ancestor(runtime->preview_ta, focused)) {
                return true;
            }

#if LV_USE_IME_PINYIN
            if (s->ime != NULL && lv_obj_is_valid(s->ime)) {
                lv_obj_t *cand_panel = coord_get_valid_cand_panel((airui_keyboard_data_t *)data);
                if (coord_is_obj_or_ancestor(cand_panel, focused)) {
                    return true;
                }
            }
#endif
        }
    }

    if (lv_obj_has_state(kb, LV_STATE_FOCUSED)) {
        return true;
    }
    if (target != NULL && lv_obj_is_valid(target) && lv_obj_has_state(target, LV_STATE_FOCUSED)) {
        return true;
    }
    if (s->ime != NULL && lv_obj_is_valid(s->ime) && lv_obj_has_state(s->ime, LV_STATE_FOCUSED)) {
        return true;
    }

    if (data->preview_runtime != NULL) {
        const airui_keyboard_preview_runtime_t *runtime =
            (const airui_keyboard_preview_runtime_t *)data->preview_runtime;
        if (runtime->container != NULL && lv_obj_is_valid(runtime->container) &&
            lv_obj_has_state(runtime->container, LV_STATE_FOCUSED)) {
            return true;
        }
        if (runtime->preview_ta != NULL && lv_obj_is_valid(runtime->preview_ta) &&
            lv_obj_has_state(runtime->preview_ta, LV_STATE_FOCUSED)) {
            return true;
        }

#if LV_USE_IME_PINYIN
        if (s->ime != NULL && lv_obj_is_valid(s->ime)) {
            lv_obj_t *cand_panel = coord_get_valid_cand_panel((airui_keyboard_data_t *)data);
            if (cand_panel != NULL && lv_obj_is_valid(cand_panel) &&
                lv_obj_has_state(cand_panel, LV_STATE_FOCUSED)) {
                return true;
            }
        }
#endif
    }

    return false;
}

/* ---- Composing 同步 ---- */

void airui_input_coordinator_on_pinyin_composing_change(airui_input_coordinator_t *coord,
                                                        bool active)
{
    if (coord == NULL || coord->session == NULL) {
        return;
    }

    if (!active) {
        if (coord->session->composing_type == AIRUI_INPUT_COMPOSING_PINYIN) {
            airui_input_session_clear_composing(coord->session);
        }
        return;
    }

    airui_input_session_begin_composing_pinyin(coord->session);
}

void airui_input_coordinator_on_system_preedit_change(airui_input_coordinator_t *coord,
                                                      bool active,
                                                      int32_t pos,
                                                      int32_t len)
{
    if (coord == NULL || coord->session == NULL) {
        return;
    }

    if (!active || len <= 0) {
        airui_input_session_clear_composing(coord->session);
        return;
    }

    airui_input_session_begin_composing_system_preedit(coord->session, pos, len);
}

/* ---- 运行时同步 ---- */

void airui_input_coordinator_sync_runtime(airui_input_coordinator_t *coord)
{
    if (coord == NULL || coord->session == NULL || coord->kb_data == NULL) {
        return;
    }

    airui_input_session_t *s = coord->session;
    airui_keyboard_data_t *data = coord->kb_data;

    if (data->preview_runtime != NULL) {
        airui_keyboard_preview_runtime_t *runtime =
            (airui_keyboard_preview_runtime_t *)data->preview_runtime;
        s->preview_ta = runtime->preview_ta;
    }
    else {
        s->preview_ta = NULL;
    }

    s->cand_panel = coord_get_valid_cand_panel(data);
    airui_input_session_refresh_hosts(s);
}

void airui_input_coordinator_bind_active_host(airui_input_coordinator_t *coord)
{
    if (coord == NULL || coord->session == NULL || coord->keyboard == NULL) {
        return;
    }

    airui_input_session_refresh_hosts(coord->session);
    lv_keyboard_set_textarea(coord->keyboard, coord->session->edit_host);
}
