/*
@module  pwm
@summary PWM模块
@version 1.0
@date    2020.07.03
*/
#include "luat_base.h"
#include "luat_pwm.h"

static int l_pwm_open(lua_State *L) {
    int channel = luaL_checkinteger(L, 1);
    size_t period = luaL_checkinteger(L, 2);
    size_t pulse = luaL_checkinteger(L, 3);
    if (luat_pwm_open(channel, period, pulse) == 0) {
        lua_pushboolean(L, 1);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}


static int l_pwm_close(lua_State *L) {
    luat_pwm_close(luaL_checkinteger(L, 1));
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_pwm[] =
{
    { "open" ,       l_pwm_open , 0},
    { "close" ,      l_pwm_close, 0},
	{ NULL,          NULL ,       0}
};

LUAMOD_API int luaopen_pwm( lua_State *L ) {
    rotable_newlib(L, reg_pwm);
    return 1;
}
