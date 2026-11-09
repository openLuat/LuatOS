/*
@module plcui.label
@summary XML label component Lua methods
@version 0.1.0
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "luat_plcui_font.h"
#include <string.h>

/**
 * 更新 label 显示的文本。
 * @api label:set_text(text)
 * @string text UTF-8 文本，最多 511 字节，可以为空字符串
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 显示区域由 XML 指定，超出区域的内容按组件配置裁剪。
 */
static int label_set_text(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_LABEL, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    size_t length;
    const char *text = luaL_checklstring(L, 2, &length);
    if (!luat_plcui_check_text(widget, text, length, &error)) return luat_plcui_push_error(L, &error);
    memcpy(widget->text, text, length);
    widget->text[length] = '\0';
    bool was_silent = widget->document->silent;
    widget->document->silent = true;
    lv_label_set_text(widget->obj, widget->text);
    widget->document->silent = was_silent;
    return luat_plcui_binding_success(L);
}

/**
 * 获取 label 当前显示的文本。
 * @api label:get_text()
 * @return string|nil 成功返回当前文本，运行错误返回 nil
 * @return table|nil 失败时返回错误表
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
 * @int font_size 字号，范围 1～255
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回错误表
 * @note 仅适用于 font="hzfont" 或引用 HZFont 资源的组件。
 * @note 更新字号保持 XML 位置和尺寸；字体过大时需在 XML 中预留足够区域。
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
    if (!luat_plcui_set_font_size(widget, (uint16_t)size, &error)) {
        return luat_plcui_push_error(L, &error);
    }
    return luat_plcui_binding_success(L);
}

/**
 * 注册 label 的文本方法与公共组件方法。
 */
void luat_plcui_register_label_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"set_font_size", label_set_font_size},
        {"set_text", label_set_text},
        {"get_text", label_get_text},
        {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_LABEL_MT);
    luaL_setfuncs(L, methods, 0);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
