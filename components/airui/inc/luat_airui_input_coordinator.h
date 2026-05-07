/**
 * @file luat_airui_input_coordinator.h
 * @summary 输入协调层 — 统一接收事件、驱动 session 状态、调度 UI 应用
 * @responsible 键盘 show/hide 请求、焦点事件、外部点击、composing 同步
 *
 * ## 设计定位
 *
 * coordinator 是 AirUI 键盘事件系统的中枢。它的职责不是直接操作 LVGL
 * 对象，而是：
 *   1. 接收来自各回调的原始事件
 *   2. 更新 airui_input_session_t 的状态
 *   3. 调用键盘层的渲染函数将状态应用到 UI
 *
 * 这样做的好处是：
 *   - show/hide / focus / blur / composing 的决策逻辑集中在一处
 *   - keyboard binding 和 preview 可见性不再被多处直接修改
 *   - 后续 debug 时可以追踪一条完整的状态变更链
 */

#ifndef AIRUI_INPUT_COORDINATOR_H
#define AIRUI_INPUT_COORDINATOR_H

#ifdef __cplusplus
extern "C" {
#endif

#include "luat_airui_input_session.h"

typedef struct airui_keyboard_data airui_keyboard_data_t;

typedef struct {
    airui_input_session_t *session;
    airui_keyboard_data_t *kb_data;
    lv_obj_t *keyboard;
} airui_input_coordinator_t;

/** 初始化协调器 */
void airui_input_coordinator_init(airui_input_coordinator_t *coord,
                                  airui_input_session_t *session,
                                  airui_keyboard_data_t *kb_data,
                                  lv_obj_t *keyboard);

/** 请求显示键盘 (统一入口, 替代直接调用 airui_keyboard_show) */
int airui_input_coordinator_request_show(airui_input_coordinator_t *coord,
                                         airui_input_show_reason_t reason);

/** 请求隐藏键盘 (统一入口, 替代直接调用 airui_keyboard_hide) */
int airui_input_coordinator_request_hide(airui_input_coordinator_t *coord,
                                         airui_input_hide_reason_t reason);

/** 目标 textarea 获得焦点 */
int airui_input_coordinator_on_target_focused(airui_input_coordinator_t *coord);

/** 目标 textarea 失去焦点 */
int airui_input_coordinator_on_target_defocused(airui_input_coordinator_t *coord);

/** 目标 textarea 离开 (LV_EVENT_LEAVE) */
int airui_input_coordinator_on_target_leave(airui_input_coordinator_t *coord);

/** 外部区域被点击 (用于 auto_hide) */
int airui_input_coordinator_on_outside_press(airui_input_coordinator_t *coord,
                                             lv_obj_t *pressed);

/** 判断 obj 是否属于键盘体系的关联对象 (键盘/预览/候选/IME/目标) */
bool airui_input_coordinator_is_related_obj(const airui_input_coordinator_t *coord,
                                            lv_obj_t *obj);

/** 判断键盘体系内是否有焦点 */
bool airui_input_coordinator_is_focus_within(const airui_input_coordinator_t *coord);

/** 拼音 IME composing 状态变化 */
void airui_input_coordinator_on_pinyin_composing_change(airui_input_coordinator_t *coord,
                                                        bool active);

/** 系统预编辑 composing 状态变化 */
void airui_input_coordinator_on_system_preedit_change(airui_input_coordinator_t *coord,
                                                      bool active,
                                                      int32_t pos,
                                                      int32_t len);

/** 同步运行时数据 (preview_ta / cand_panel) 到 session */
void airui_input_coordinator_sync_runtime(airui_input_coordinator_t *coord);

/** 绑定当前活跃宿主到 LVGL 键盘 (内部渲染步骤, 调用方通常不需要直接调用) */
void airui_input_coordinator_bind_active_host(airui_input_coordinator_t *coord);

#ifdef __cplusplus
}
#endif

#endif /* AIRUI_INPUT_COORDINATOR_H */
