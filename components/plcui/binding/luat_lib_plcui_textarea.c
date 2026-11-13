/*
@module plcui.textarea
@summary XML 文本输入框与编辑会话
@version 1.0.2
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "luat_plcui_font.h"
#include <string.h>

/**
 * 校验并设置 textarea 的文本。
 * @api textarea:set_text(text)
 * @string text 必填，UTF-8 文本，可为空，最多 511 字节，须符合 one-line、max-length 和 accepted-chars
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note max-length 按 Unicode 字符数限制，511 字节是额外的运行时上限；校验失败保留旧文和编辑会话。
 * @note 校验通过后，若正在编辑该组件，先取消原会话再写入；相同文本也保留此取消语义。
 * @note 程序写入不触发 on-change；取消原会话仍可触发 on-cancel，并清除拼音组合及候选。
 * @note 写入后清除文本选择并将光标移到末尾。
 * @usage
 * local input = xml:find("main", "setpoint")
 * input:set_text("75.0")
 */
static int textarea_set_text(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_TEXTAREA, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    size_t length;
    const char *text = luaL_checklstring(L, 2, &length);
    if (!luat_plcui_check_text(widget, text, length, &error)) return luat_plcui_push_error(L, &error);
    if (widget->document->editing == widget) luat_plcui_input_finish(widget->document, false, true);
    memcpy(widget->text, text, length);
    widget->text[length] = '\0';
    bool was_silent = widget->document->silent;
    widget->document->silent = true;
    luat_plcui_textarea_write(widget->obj, widget->text);
    widget->document->silent = was_silent;
    return luat_plcui_binding_success(L);
}

/**
 * 读取 textarea 当前稳定正文或编辑草稿。
 * @api textarea:get_text()
 * @return string|nil 成功返回当前 UTF-8 文本，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 编辑期间返回已写入输入框的草稿；尚未选字的拼音组合不包含在返回值中。
 * @note 读取不会提交或取消编辑会话。
 * @usage
 * local input = xml:find("main", "setpoint")
 * local text = input:get_text()
 * log.info("input", text)
 */
static int textarea_get_text(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_TEXTAREA, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_pushstring(L, lv_textarea_get_text(widget->obj));
    return 1;
}

/**
 * 开始编辑 textarea，并尝试显示关联的可用键盘。
 * @api textarea:focus()
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 关联 keyboard 由 XML 的 keyboard 属性指定，须位于同一页面；没有关联或键盘当前不可用时不显示键盘。
 * @note 开始新输入框的编辑前，按原规则取消另一输入框的会话；重复聚焦当前输入框不重建会话。
 * @note 输入框或其祖先隐藏、禁用时返回 E_INPUT_SESSION；页面 prepare 阶段返回 E_BUSY。
 * @note 会话记录进入编辑前的完整原文，之后取消编辑时恢复该快照。
 * @usage
 * local input = xml:find("main", "setpoint")
 * input:focus()
 */
static int textarea_focus(lua_State *L)
{
    if (luat_plcui_runtime()->preparing_document)
        return luat_plcui_binding_error(L, "E_BUSY", "Cannot start input during page preparation");
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_TEXTAREA, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    if (!luat_plcui_component_interactive(widget)) {
        return luat_plcui_binding_error(L, "E_INPUT_SESSION", "Hidden or disabled textarea hierarchy cannot receive focus");
    }
    luat_plcui_input_begin(widget);
    return luat_plcui_binding_success(L);
}

/**
 * 设置 textarea 使用的 HZFont 像素字号。
 * @api textarea:set_font_size(font_size)
 * @int font_size 必填，像素字号，范围 1～255
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 仅适用于 XML 中 font="hzfont" 或引用 HZFont 资源的输入框。
 * @note 保持组件位置、尺寸和正文，不自动调整关联键盘字号；应为新字号预留足够显示区域。
 * @usage
 * local input = xml:find("main", "setpoint")
 * input:set_font_size(22)
 */
static int textarea_set_font_size(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_TEXTAREA, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    lua_Integer size = luaL_checkinteger(L, 2);
    if (size < 1 || size > 255) {
        return luat_plcui_binding_error(L, "E_SCHEMA", "font_size must be between 1 and 255");
    }
    if (!luat_plcui_set_font_size(widget, (uint16_t)size, &error)) {
        return luat_plcui_push_error(L, &error);
    }
    return luat_plcui_binding_success(L);
}

/**
 * 注册 textarea 的正文、字号、焦点及公共组件方法。
 * @param L Lua 状态机
 * @note 由模块初始化调用，不是公开 Lua 接口；注册完成后恢复原有栈高度。
 */
void luat_plcui_register_textarea_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"set_font_size", textarea_set_font_size},
        {"set_text", textarea_set_text},
        {"get_text", textarea_get_text},
        {"focus", textarea_focus},
        {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_TEXTAREA_MT);
    luat_plcui_binding_register_methods(L, methods);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
