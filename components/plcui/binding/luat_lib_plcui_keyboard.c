/*
@module plcui.keyboard
@summary XML keyboard component Lua methods
@version 0.1.0
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "luat_plcui_font.h"

/**
 * 设置 keyboard 使用的 HZFont 像素字号。
 * @api keyboard:set_font_size(font_size)
 * @int font_size 字号，范围 1～255
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回错误表
 * @note 仅适用于 font="hzfont" 或引用 HZFont 资源的组件。
 * @note 更新字号保持 XML 位置和尺寸；字体过大时需在 XML 中预留足够区域。
 */
static int keyboard_set_font_size(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_KEYBOARD, &error);
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
 * 注册 keyboard 元表，显隐和禁用遵循公共输入会话规则。
 */
void luat_plcui_register_keyboard_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"set_font_size", keyboard_set_font_size},
        {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_KEYBOARD_MT);
    luaL_setfuncs(L, methods, 0);
    /* Visibility and enabled state use the shared editing-session rules. */
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
