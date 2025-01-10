
/*
@module  netdrv
@summary 网络设备管理
@catalog 外设API
@version 1.0
@date    2025.01.07
@demo netdrv
@tag LUAT_USE_NETDRV
*/
#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_rtos.h"
#include "luat_netdrv.h"

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

/*
初始化指定netdrv设备
*/
static int l_netdrv_setup(lua_State *L) {
    luat_netdrv_conf_t conf = {0};
    conf.id = luaL_checkinteger(L, 1);
    conf.impl = luaL_optinteger(L, 2, 0);
    if (lua_istable(L, 3)) {
        if (lua_getfield(L, 3, "spi") == LUA_TNUMBER) {
            conf.spiid = luaL_checkinteger(L, -1);
        };
        lua_pop(L, 1);
        if (lua_getfield(L, 3, "cs") == LUA_TNUMBER) {
            conf.cspin = luaL_checkinteger(L, -1);
        };
        lua_pop(L, 1);

        if (lua_getfield(L, 3, "irq") == LUA_TNUMBER) {
            conf.irqpin = luaL_checkinteger(L, -1);
        };
        lua_pop(L, 1);
    }
    luat_netdrv_t* ret = luat_netdrv_setup(&conf);
    lua_pushboolean(L, ret != NULL);
    return 1;
}

static int l_netdrv_dhcp(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int enable = lua_toboolean(L, 2);
    int ret = luat_netdrv_dhcp(id, enable);
    lua_pushboolean(L, ret == 0);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_netdrv[] =
{
    { "setup" ,         ROREG_FUNC(l_netdrv_setup )},
    { "dhcp",           ROREG_FUNC(l_netdrv_dhcp)},

    { "CH390",          ROREG_INT(1)},
    { "W5500",          ROREG_INT(2)},
    { "W5100",          ROREG_INT(3)},
	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_netdrv( lua_State *L ) {
    luat_newlib2(L, reg_netdrv);
    return 1;
}
