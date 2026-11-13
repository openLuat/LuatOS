/*
@module plcui.animimg
@summary XML 图片帧动画
@version 1.0.2
@tag LUAT_USE_PLCUI
*/
#include "luat_plcui_binding.h"

/**
 * 播放、恢复或显式重试图片帧动画。
 * @api animimg:play()
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note paused 状态保留当前帧并恢复剩余间隔；stopped 或 finished 状态从第 1 帧重新开始。
 * @note error 状态重试上次失败的目标帧；可见资源准备失败时返回错误，保留最后有效画面。
 * @note 已在 playing 状态时直接成功；隐藏、禁用或完全离屏时保留播放意图，恢复可见/启用后才继续。
 * @note 页面 prepare 中只设置播放意图；首帧成功展示后开始计时，不会预解码全部帧。
 * @usage
 * local animation = xml:find("main", "fan")
 * animation:play()
 */
static int animation_play(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_ANIMIMG, &error);
    if (!widget || !luat_plcui_animimg_play(widget, &error)) return luat_plcui_push_error(L, &error);
    return luat_plcui_binding_success(L);
}
/**
 * 暂停图片帧动画，保留当前帧、已完成轮数和剩余间隔。
 * @api animimg:pause()
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 仅 playing 状态转为 paused，其他状态保持不变；不会触发 on-finished。
 * @note 显式暂停不会因组件重新显示而解除，须调用 play 恢复。
 * @usage
 * local animation = xml:find("main", "fan")
 * animation:pause()
 * local frame = animation:get_frame()
 */
static int animation_pause(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_ANIMIMG, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    luat_plcui_animimg_pause(widget);
    return luat_plcui_binding_success(L);
}
/**
 * 停止图片帧动画、清零已完成轮数，并尝试恢复第 1 帧。
 * @api animimg:stop()
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 首帧资源恢复失败仍保持 stopped，画面保留最后有效帧；下一次 play 会重新尝试首帧。
 * @note 隐藏或 prepare 阶段延后首帧资源准备；stop 不派发 on-finished。
 * @usage
 * local animation = xml:find("main", "fan")
 * animation:stop()
 */
static int animation_stop(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_ANIMIMG, &error);
    if (!widget || !luat_plcui_animimg_stop(widget, &error)) return luat_plcui_push_error(L, &error);
    return luat_plcui_binding_success(L);
}
/**
 * 获取动画当前的逻辑帧编号。
 * @api animimg:get_frame()
 * @return int|nil 成功返回从 1 开始的帧编号，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 帧范围为 1～XML frame 节点数量；不是资源 ID 或已完成播放轮数。
 * @note 该方法不推进动画；完整播放状态和已完成轮数可通过 state() 查询。
 * @usage
 * local animation = xml:find("main", "fan")
 * log.info("animation", "frame", animation:get_frame())
 */
static int animation_frame(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_ANIMIMG, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_pushinteger(L, widget->animation->frame + 1);
    return 1;
}
/**
 * 注册 animimg 的播放控制方法与公共组件方法。
 * @param L Lua 状态机。
 * @note 仅为 C 层注册入口；Lua 通过 xml:find 获取 animimg 句柄。
 */
void luat_plcui_register_animimg_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"play", animation_play}, {"pause", animation_pause}, {"stop", animation_stop},
        {"get_frame", animation_frame}, {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_ANIMIMG_MT);
    luat_plcui_binding_register_methods(L, methods);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
