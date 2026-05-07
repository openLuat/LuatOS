/**
 * @file luat_airui_input_session.c
 * @summary 统一输入会话 — 键盘输入状态的单一真相源
 * ## 核心设计
 *
 * ### 三个宿主概念
 *
 *    target       — 业务最终持有文本的 textarea (表单提交/校验面向它)
 *    edit_host    — 当前真正承接键盘输入的对象 (keyboard/IME/preedit 写入它)
 *    display_host — 用户当前观察的主要编辑对象
 *
 *   无 preview:  target == edit_host == display_host
 *   有 preview:  target != edit_host == display_host (preview_ta)
 *
 * ### 三类文本（概念分层）
 *
 *    committed_text — 已提交的稳定文本 (业务最终数据)
 *    preview_text   — 当前显示给用户看的编辑文本 (可能来自 preview_ta)
 *    composing_text — 尚未提交的临时串 (拼音串 / SDL preedit)
 *
 * ### composing 统一
 *
 *    lv_ime_pinyin 拼音串 和 SDL preedit 串统一映射为:
 *      composing_type  — AIRUI_INPUT_COMPOSING_PINYIN / SYSTEM_PREEDIT
 *      composing_pos   — 临时文本在 edit_host 中的起始位置
 *      composing_len   — 临时文本长度
 *
 *    上游逻辑不再需要区分"这次是拼音还是系统输入法"，
 *    只需要理解"当前是否有 composing 段"。
 *
 * ## 与其他层的关系
 *
 *    底层控件层 (lv_keyboard/lv_textarea/lv_ime_pinyin)
 *      ↑ 复用 LVGL, 不重写
 *    输入会话层 (本模块)
 *      ↑ 统一所有输入状态, 提供 get/set/clear/refresh API
 *    输入协调层 (luat_airui_input_coordinator)
 *      ↑ 接收事件, 更新 session, 调度 UI 应用
 *    UI 应用层   (airui_keyboard_apply_visibility)
 *      ↑ 读取 session 状态, 写入 LVGL 对象
 */

#include "luat_airui_input_session.h"
#include <string.h>

#define LUAT_LOG_TAG "airui_session"
#include "luat_log.h"

void airui_input_session_init(airui_input_session_t *session)
{
    if (session == NULL) {
        return;
    }
    memset(session, 0, sizeof(*session));
}

void airui_input_session_set_keyboard(airui_input_session_t *session, lv_obj_t *keyboard)
{
    if (session == NULL) {
        return;
    }
    session->keyboard = keyboard;
}

void airui_input_session_set_target(airui_input_session_t *session, lv_obj_t *target)
{
    if (session == NULL) {
        return;
    }
    session->target = target;
}

void airui_input_session_set_preview_ta(airui_input_session_t *session, lv_obj_t *preview_ta)
{
    if (session == NULL) {
        return;
    }
    session->preview_ta = preview_ta;
}

void airui_input_session_set_ime(airui_input_session_t *session, lv_obj_t *ime)
{
    if (session == NULL) {
        return;
    }
    session->ime = ime;
}

void airui_input_session_set_cand_panel(airui_input_session_t *session, lv_obj_t *cand_panel)
{
    if (session == NULL) {
        return;
    }
    session->cand_panel = cand_panel;
}

void airui_input_session_set_keyboard_visible(airui_input_session_t *session, bool visible)
{
    if (session == NULL) {
        return;
    }
    session->keyboard_visible = visible;
}

void airui_input_session_set_preview_visible(airui_input_session_t *session, bool visible)
{
    if (session == NULL) {
        return;
    }
    session->preview_visible = visible;
}

void airui_input_session_refresh_hosts(airui_input_session_t *session)
{
    if (session == NULL) {
        return;
    }

    /* 当 preview 可见且有有效 preview_ta 时，edit_host 指向 preview_ta */
    if (session->preview_visible && session->preview_ta != NULL && lv_obj_is_valid(session->preview_ta)) {
        session->edit_host = session->preview_ta;
    }
    else if (session->target != NULL && lv_obj_is_valid(session->target)) {
        session->edit_host = session->target;
    }
    else {
        session->edit_host = NULL;
    }

    session->display_host = session->edit_host;
}

void airui_input_session_begin_composing_pinyin(airui_input_session_t *session)
{
    if (session == NULL) {
        return;
    }
    session->composing_type = AIRUI_INPUT_COMPOSING_PINYIN;
    session->composing_pos = 0;
    session->composing_len = 0;
    session->source = AIRUI_INPUT_SOURCE_VIRTUAL_KEYBOARD;
}

void airui_input_session_begin_composing_system_preedit(airui_input_session_t *session, int32_t pos, int32_t len)
{
    if (session == NULL) {
        return;
    }
    session->composing_type = AIRUI_INPUT_COMPOSING_SYSTEM_PREEDIT;
    session->composing_pos = pos;
    session->composing_len = len;
    session->source = AIRUI_INPUT_SOURCE_SYSTEM_IME;
}

void airui_input_session_clear_composing(airui_input_session_t *session)
{
    if (session == NULL) {
        return;
    }
    session->composing_type = AIRUI_INPUT_COMPOSING_NONE;
    session->composing_pos = 0;
    session->composing_len = 0;
}

bool airui_input_session_is_active(const airui_input_session_t *session)
{
    return session != NULL && session->active;
}

lv_obj_t *airui_input_session_get_target(const airui_input_session_t *session)
{
    if (session == NULL) {
        return NULL;
    }
    return session->target;
}

lv_obj_t *airui_input_session_get_edit_host(const airui_input_session_t *session)
{
    if (session == NULL) {
        return NULL;
    }
    return session->edit_host;
}

bool airui_input_session_has_composing(const airui_input_session_t *session)
{
    return session != NULL && session->composing_type != AIRUI_INPUT_COMPOSING_NONE;
}
