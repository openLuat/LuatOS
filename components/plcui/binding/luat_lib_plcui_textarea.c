/*
@module plcui.textarea
@summary XML textarea component Lua methods
@version 0.1.0
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "luat_plcui_font.h"
#include <string.h>

/**
 * 设置 textarea 的文本。
 * @api textarea:set_text(text)
 * @string text UTF-8 文本，须符合 XML 中 one-line、max-length 和 accepted-chars 约束
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 正在编辑该组件时先取消编辑会话，再写入新文本。
 * @note 程序更新不触发 on-change；取消原会话时仍可产生 on-cancel。
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
    lv_textarea_set_text(widget->obj, widget->text);
    widget->document->silent = was_silent;
    return luat_plcui_binding_success(L);
}

/**
 * 获取 textarea 当前文本。
 * @api textarea:get_text()
 * @return string|nil 成功返回当前文本，运行错误返回 nil
 * @return table|nil 失败时返回错误表
 * @note 编辑期间返回当前可见的编辑草稿。
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
 * 开始编辑 textarea，并显示可用的关联键盘。
 * @api textarea:focus()
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 关联 keyboard 由 XML 指定，且须位于同一页面。
 * @note 组件或祖先被隐藏、禁用时返回 E_INPUT_SESSION。
 */
static int textarea_focus(lua_State *L)
{
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
 * @int font_size 字号，范围 1～255
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回错误表
 * @note 仅适用于 font="hzfont" 或引用 HZFont 资源的组件。
 * @note 更新字号保持 XML 位置和尺寸；字体过大时需在 XML 中预留足够区域。
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
 * 注册 textarea 的文本、焦点与公共组件方法。
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
    luaL_setfuncs(L, methods, 0);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
