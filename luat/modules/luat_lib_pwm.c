/*
@module  pwm
@summary PWM模块
@version 1.0
@date    2020.07.03
*/
#include "luat_base.h"
#include "luat_pwm.h"

/**
开启指定的PWM通道
@api pwm.open(channel, period, pulse)
@int PWM通道
@int 频率, 1-1000000hz
@int 占空比 0-100
@return boolean 处理结果,成功返回true,失败返回false
@usage
-- 打开PWM5, 频率1kHz, 占空比50%
pwm.open(5, 1000, 50)
 */
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

/**
关闭指定的PWM通道
@api pwm.close(channel)
@int PWM通道
@return nil 无处理结果
@usage
-- 关闭PWM5
pwm.close(5)
 */
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
    luat_newlib(L, reg_pwm);
    return 1;
}
