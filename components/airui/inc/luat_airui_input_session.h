/**
 * @file luat_airui_input_session.h
 * @summary 统一输入会话 — 键盘/预览/IME/预编辑状态的单一真相源
 * @responsible 维护 target / edit_host / display_host / composing 状态, 提供查询与更新 API
 *
 * ## 设计要点
 *
 * 本模块的核心思想是将原先散落的多份状态统一到 airui_input_session_t 中。
 * 无论调用方来自 keyboard 组件、preview 运行时、IME 回调还是 SDL 事件，
 * 关于"当前输入目标是谁 / 键盘在向谁写 / 是否有未提交文本"这类问题，
 * 都应该从 session 查询而非从各对象的 hidden/focused/valid 等属性反推。
 *
 * ### 三宿主模型
 *   target       — 业务 textarea, 表单提交与外部读取面向它
 *   edit_host    — 键盘/IME/preedit 实际写入的 textarea
 *   display_host — 用户观察的主要编辑对象 (通常 = edit_host)
 *
 * ### 未提交文本 (composing) 统一
 *   拼音 IME 和 SDL 系统输入法的 preedit 统一为:
 *   composing_type / composing_pos / composing_len
 */

#ifndef AIRUI_INPUT_SESSION_H
#define AIRUI_INPUT_SESSION_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>
#include <stdbool.h>
#include "lvgl9/lvgl.h"

/**********************
 *      TYPEDEFS
 **********************/

/** 输入来源 */
typedef enum {
    AIRUI_INPUT_SOURCE_NONE = 0,
    AIRUI_INPUT_SOURCE_VIRTUAL_KEYBOARD,
    AIRUI_INPUT_SOURCE_SYSTEM_IME,
    AIRUI_INPUT_SOURCE_HARDWARE_KEY,
} airui_input_source_t;

/** 未提交文本 (composing) 类型 */
typedef enum {
    AIRUI_INPUT_COMPOSING_NONE = 0,
    AIRUI_INPUT_COMPOSING_PINYIN,
    AIRUI_INPUT_COMPOSING_SYSTEM_PREEDIT,
} airui_input_composing_type_t;

/** 键盘显示原因 */
typedef enum {
    AIRUI_INPUT_SHOW_REASON_TARGET_FOCUS = 0,
    AIRUI_INPUT_SHOW_REASON_MANUAL,
} airui_input_show_reason_t;

/** 键盘隐藏原因 */
typedef enum {
    AIRUI_INPUT_HIDE_REASON_TARGET_BLUR = 0,
    AIRUI_INPUT_HIDE_REASON_OUTSIDE_PRESS,
    AIRUI_INPUT_HIDE_REASON_MANUAL,
    AIRUI_INPUT_HIDE_REASON_DESTROY,
} airui_input_hide_reason_t;

/** 统一输入会话 */
typedef struct {
    lv_obj_t *keyboard;
    lv_obj_t *target;
    lv_obj_t *edit_host;        /* 真正承接键盘输入的对象 */
    lv_obj_t *display_host;     /* 用户可见的主要编辑对象 */
    lv_obj_t *preview_ta;
    lv_obj_t *ime;
    lv_obj_t *cand_panel;
    bool active;
    bool keyboard_visible;
    bool preview_visible;
    airui_input_source_t source;
    airui_input_composing_type_t composing_type;
    int32_t composing_pos;
    int32_t composing_len;
} airui_input_session_t;

/**********************
 * GLOBAL PROTOTYPES
 **********************/

/** 初始化会话 */
void airui_input_session_init(airui_input_session_t *session);

/** 设置键盘对象 */
void airui_input_session_set_keyboard(airui_input_session_t *session, lv_obj_t *keyboard);

/** 设置业务目标 textarea */
void airui_input_session_set_target(airui_input_session_t *session, lv_obj_t *target);

/** 设置 preview textarea */
void airui_input_session_set_preview_ta(airui_input_session_t *session, lv_obj_t *preview_ta);

/** 设置 IME 对象 */
void airui_input_session_set_ime(airui_input_session_t *session, lv_obj_t *ime);

/** 同步候选面板引用 */
void airui_input_session_set_cand_panel(airui_input_session_t *session, lv_obj_t *cand_panel);

/** 设置键盘可见性标记 */
void airui_input_session_set_keyboard_visible(airui_input_session_t *session, bool visible);

/** 设置预览可见性标记 */
void airui_input_session_set_preview_visible(airui_input_session_t *session, bool visible);

/** 根据 preview 可见性与 target 刷新 edit_host / display_host */
void airui_input_session_refresh_hosts(airui_input_session_t *session);

/** 开始拼音 composing */
void airui_input_session_begin_composing_pinyin(airui_input_session_t *session);

/** 开始系统预编辑 composing */
void airui_input_session_begin_composing_system_preedit(airui_input_session_t *session, int32_t pos, int32_t len);

/** 清空 composing 状态 */
void airui_input_session_clear_composing(airui_input_session_t *session);

/** 查询会话是否活跃 */
bool airui_input_session_is_active(const airui_input_session_t *session);

/** 获取当前目标 */
lv_obj_t *airui_input_session_get_target(const airui_input_session_t *session);

/** 获取当前编辑宿主 */
lv_obj_t *airui_input_session_get_edit_host(const airui_input_session_t *session);

/** 是否有未提交文本 */
bool airui_input_session_has_composing(const airui_input_session_t *session);

#ifdef __cplusplus
}
#endif

#endif /* AIRUI_INPUT_SESSION_H */
