/*
@module plcui.keyboard
@summary XML 原生键盘与简版中文拼音输入
@version 1.0.2
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include "luat_plcui_font.h"

/**
 * 设置 keyboard 键面及拼音候选行使用的 HZFont 像素字号。
 * @api keyboard:set_font_size(font_size)
 * @int font_size 必填，像素字号，范围 1～255
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 仅适用于 XML 中 font="hzfont" 或引用 HZFont 资源的键盘，不修改关联输入框的字号。
 * @note 保持键盘的位置和尺寸；ime="pinyin" 时会根据实际字体重新校验键面和候选行的空间。
 * @note 拼音键盘区域不足时返回 E_SCHEMA，保留原字号与布局，不自动扩大键盘。
 * @usage
 * local keyboard = xml:find("main", "cn_keys")
 * keyboard:set_font_size(20)
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
 * 注册 keyboard 的字号方法和公共组件方法。
 * @param L Lua 状态机
 * @note 由模块初始化调用，不是公开 Lua 接口；显隐和禁用遵循公共输入会话规则。
 * @note 键盘输入和拼音选择由原生事件处理，不在此元表中增加独立文本写入接口。
 */
void luat_plcui_register_keyboard_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"set_font_size", keyboard_set_font_size},
        {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_KEYBOARD_MT);
    luat_plcui_binding_register_methods(L, methods);
    /* 显隐和禁用共用输入会话规则，避免绕过关联输入框的会话管理。 */
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
