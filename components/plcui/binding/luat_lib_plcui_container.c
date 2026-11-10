/*
@module plcui.container
@summary XML container component Lua methods
@version 0.1.0
@tag LUAT_USE_PLCUI
*/
#include "luat_base.h"
#include "luat_plcui_binding.h"

/**
 * 注册 container 元表，公共显隐和禁用操作作用于组件子树。
 */
void luat_plcui_register_container_meta(lua_State *L)
{
    luaL_newmetatable(L, PLCUI_CONTAINER_MT);
    /* Shared hidden/disabled methods propagate to the container's subtree. */
    luat_plcui_binding_register_common(L);
    lua_pop(L, 1);
}
