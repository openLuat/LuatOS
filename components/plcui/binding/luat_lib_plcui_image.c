/*
@module plcui.image
@summary XML image component Lua methods
@version 0.1.0
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"
#include <stdio.h>
#include <string.h>

/**
 * 设置 image 的默认图片资源。
 * @api image:set_src(resource_id)
 * @string resource_id XML resources 中已声明的图片资源 ID
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 参数是资源 ID，不是图片文件路径。
 * @note 禁用、按下、选中状态仍优先使用其对应图片。
 */
static int image_set_src(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_IMAGE, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    const char *id = luaL_checkstring(L, 2);
    if (strlen(id) >= PLCUI_ID_MAX || !luat_plcui_resource(widget->document, id, PLCUI_RES_IMAGE)) {
        return luat_plcui_binding_error(L, "E_RESOURCE", "Image resource does not exist");
    }
    snprintf(widget->source[0], sizeof(widget->source[0]), "%s", id);
    luat_plcui_apply_image(widget);
    return luat_plcui_binding_success(L);
}

/**
 * 设置 image 的业务选中状态。
 * @api image:set_checked(checked)
 * @bool checked true 为选中，false 为未选中
 * @return bool|nil 成功返回 true，运行错误返回 nil
 * @return table|nil 失败时返回包含 code、message 的错误表
 * @note 选中时使用 src-checked，未配置时回退默认图。
 * @note 状态图片优先级为禁用、按下、选中、默认。
 */
static int image_set_checked(lua_State *L)
{
    plcui_error_t error;
    plcui_widget_t *widget = luat_plcui_binding_check_type(L, PLCUI_IMAGE, &error);
    if (!widget) return luat_plcui_push_error(L, &error);
    luaL_checktype(L, 2, LUA_TBOOLEAN);
    widget->checked = lua_toboolean(L, 2) != 0;
    luat_plcui_apply_image(widget);
    return luat_plcui_binding_success(L);
}

/**
 * 注册 image 的专属方法与公共组件方法。
 */
void luat_plcui_register_image_meta(lua_State *L)
{
    static const luaL_Reg methods[] = {
        {"set_src", image_set_src},
        {"set_checked", image_set_checked},
        {NULL, NULL}
    };
    luaL_newmetatable(L, PLCUI_IMAGE_MT);
    luaL_setfuncs(L, methods, 0);
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
