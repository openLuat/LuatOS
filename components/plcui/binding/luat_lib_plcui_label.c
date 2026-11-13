/*
@module plcui.label
@summary XML 文本标签与溢出滚动
@version 1.0.2
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "luat_plcui_component.h"
#include "luat_plcui_font.h"
#include <string.h>

/**
 * 更新 label 的完整正文，并按当前长文本模式重新显示。
 * @api label:set_text(text)
 * @string text 必填，UTF-8 文本，可为空字符串，最多 511 字节，不允许 NUL 字节
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 显示区域保持不变；clip 裁剪，scroll 往返，scroll_circular 循环滚动。
 * @note 文本真正变化时从起点重播；相同文本直接成功，不重新分配或重启滚动。
 * @usage
 * local title = xml:find("main", "title")
 * title:set_text("当前温度：24.6℃")
 */
static int label_set_text(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_LABEL, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    size_t length;
    const char *text = luaL_checklstring(L, 2, &length);
    if (!luat_plcui_check_text(widget, text, length, &error)) return luat_plcui_push_error(L, &error);
    if (!strcmp(widget->text, text)) return luat_plcui_binding_success(L);
    if (widget->label) {
        lv_label_set_long_mode(widget->obj, LV_LABEL_LONG_MODE_CLIP);
        widget->label->running = false;
    }
    memcpy(widget->text, text, length);
    widget->text[length] = '\0';
    bool was_silent = widget->document->silent;
    widget->document->silent = true;
    lv_label_set_text(widget->obj, widget->text);
    widget->document->silent = was_silent;
    luat_plcui_label_sync(widget);
    return luat_plcui_binding_success(L);
}

/**
 * 读取 label 保存的完整正文。
 * @api label:get_text()
 * @return string|nil 成功返回完整 UTF-8 文本，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 即使显示被裁剪或正在滚动，返回值仍是全文，不是当前可见片段。
 * @usage
 * local title = xml:find("main", "title")
 * local text = title:get_text()
 * log.info("title", text)
 */
static int label_get_text(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_LABEL, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_pushstring(L, lv_label_get_text(widget->obj));
    return 1;
}

/**
 * 设置 label 使用的 HZFont 像素字号。
 * @api label:set_font_size(font_size)
 * @int font_size 必填，像素字号，范围 1～255
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 仅适用于 XML 中 font="hzfont" 或引用 HZFont 资源的标签。
 * @note 保持组件位置和尺寸；字号实际变化时，滚动文字重新从起点播放。
 * @note 字体变大不会自动扩大文字框，应提前在 XML 中留出足够区域。
 * @usage
 * local title = xml:find("main", "title")
 * title:set_font_size(24)
 */
static int label_set_font_size(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_LABEL, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer size = luaL_checkinteger(L, 2);
    if (size < 1 || size > 255) {
        return luat_plcui_binding_error(L, "E_SCHEMA", "font_size must be between 1 and 255");
    }
    if (widget->font_size == size) return luat_plcui_binding_success(L);
    if (!luat_plcui_set_font_size(widget, (uint16_t)size, &error)) {
        return luat_plcui_push_error(L, &error);
    }
    return luat_plcui_binding_success(L);
}

/**
 * 设置正文超出固定文字框时的显示方式。
 * @api label:set_long_mode(mode)
 * @string mode 必填，clip 表示裁剪，scroll 表示往返滚动，scroll_circular 表示循环滚动
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 未配置时默认 clip；正文未溢出时保持静止，不移动 label 组件本身。
 * @note 滚动优先处理水平溢出；仅未超宽而超高时按垂直方向滚动。
 * @note 模式变化时从起点重播，相同模式不主动重启；clip 会停止滚动并归位。
 * @note 隐藏、禁用或完全离屏时停止实际滚动，再次可用时从起点播放。
 * @usage
 * local notice = xml:find("main", "notice")
 * notice:set_long_mode("scroll_circular")
 */
static int label_set_long_mode(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_LABEL, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    const char *name = luaL_checkstring(L, 2);
    lv_label_long_mode_t mode;
    if (!strcmp(name, "clip")) mode = LV_LABEL_LONG_MODE_CLIP;
    else if (!strcmp(name, "scroll")) mode = LV_LABEL_LONG_MODE_SCROLL;
    else if (!strcmp(name, "scroll_circular")) mode = LV_LABEL_LONG_MODE_SCROLL_CIRCULAR;
    else return luat_plcui_binding_error(L, "E_SCHEMA", "long-mode must be clip, scroll or scroll_circular");
    plcui_label_t *label = luat_plcui_label_config(widget, &error);
    if (!label) return luat_plcui_push_error(L, &error);
    if (label->mode == mode) return luat_plcui_binding_success(L);
    label->mode = mode;
    luat_plcui_label_restart(widget);
    return luat_plcui_binding_success(L);
}

/**
 * 设置滚动文字单次行程的目标耗时。
 * @api label:set_scroll_duration(ms)
 * @int ms 必填，毫秒，范围 100～600000；未配置时默认 4000
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note scroll 的往返包含两次行程及端点停顿；此值不是整个来回的总时长，也不是像素速度。
 * @note 有效时长变化会从起点重播，相同值不主动重启；clip 模式下仅保存配置。
 * @note 实际播放受刷新率和界面负载影响，不保证物理显示精确到毫秒。
 * @usage
 * local notice = xml:find("main", "notice")
 * notice:set_scroll_duration(6000)
 */
static int label_set_scroll_duration(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_LABEL, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer duration = luaL_checkinteger(L, 2);
    if (duration < 100 || duration > 600000)
        return luat_plcui_binding_error(L, "E_SCHEMA", "Scroll duration must be between 100 and 600000 milliseconds");
    plcui_label_t *label = luat_plcui_label_config(widget, &error);
    if (!label) return luat_plcui_push_error(L, &error);
    if (label->duration_ms == duration) return luat_plcui_binding_success(L);
    label->duration_ms = (uint32_t)duration;
    luat_plcui_label_restart(widget);
    return luat_plcui_binding_success(L);
}

/**
 * 设置滚动开始及每轮衔接处的停顿时间。
 * @api label:set_scroll_delay(ms)
 * @int ms 必填，毫秒，范围 0～60000；未配置时默认 500，0 表示不增加停顿
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 首次开始和重复播放起点使用此停顿；往返模式还在另一端停顿。
 * @note 停顿实际变化会从起点重播，相同值不主动重启；clip 模式下仅保存配置。
 * @usage
 * local notice = xml:find("main", "notice")
 * notice:set_scroll_delay(0)
 */
static int label_set_scroll_delay(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_LABEL, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer delay = luaL_checkinteger(L, 2);
    if (delay < 0 || delay > 60000)
        return luat_plcui_binding_error(L, "E_SCHEMA", "Scroll delay must be between 0 and 60000 milliseconds");
    plcui_label_t *label = luat_plcui_label_config(widget, &error);
    if (!label) return luat_plcui_push_error(L, &error);
    if (label->delay_ms == delay) return luat_plcui_binding_success(L);
    label->delay_ms = (uint32_t)delay;
    luat_plcui_label_restart(widget);
    return luat_plcui_binding_success(L);
}

/**
 * 注册 label 专属方法、公共组件方法和元表索引。
 * @param L Lua 状态机
 * @note 由模块初始化调用，不是公开 Lua 接口；注册完成后恢复原有栈高度。
 */
void luat_plcui_register_label_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"set_font_size", label_set_font_size},
        {"set_text", label_set_text},
        {"get_text", label_get_text},
        {"set_long_mode", label_set_long_mode},
        {"set_scroll_duration", label_set_scroll_duration},
        {"set_scroll_delay", label_set_scroll_delay},
        {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_LABEL_MT);
    luat_plcui_binding_register_methods(L, methods);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
