/*
@module plcui.container
@summary XML 组件分组容器
@version 1.0.2
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"

/**
 * 注册 container 元表及其继承的公共组件方法。
 * @param L Lua 状态机
 * @note container 没有专属 Lua 方法，使用公共 set_hidden、set_disabled、set_pos、move、get_pos 和 state。
 * @note 容器显隐和禁用影响子树的有效状态；移动容器时子组件自然跟随，局部坐标不变。
 * @note 由模块初始化调用，不是公开 Lua 接口；注册完成后恢复原有栈高度。
 */
void luat_plcui_register_container_meta(lua_State *L)
{
    luaL_newmetatable(L, PLCUI_CONTAINER_MT);
    /* 公共显隐和禁用方法负责同步容器子树的有效状态。 */
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
