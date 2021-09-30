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
@int 输出周期 0为持续输出
@return boolean 处理结果,成功返回true,失败返回false
@usage
-- 打开PWM5, 频率1kHz, 占空比50%
pwm.open(5, 1000, 50)
 */
static int l_pwm_open(lua_State *L) {
    int pnum = 0;
    int channel = luaL_checkinteger(L, 1);
    size_t period = luaL_checkinteger(L, 2);
    size_t pulse = luaL_checkinteger(L, 3);
    if (lua_type(L, 4) == LUA_TNUMBER){
        pnum = luaL_checkinteger(L, 4);
    }
    int ret = luat_pwm_open(channel, period, pulse,pnum);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
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

/**
PWM捕获
@api pwm.capture(channel)
@int PWM通道
@int 捕获频率
@return boolean 处理结果,成功返回true,失败返回false
@usage
-- PWM0捕获
log.info("pwm.get(0)",pwm.capture(0,1000))
log.info("PWM_CAPTURE",sys.waitUntil("PWM_CAPTURE", 2000))
 */
static int l_pwm_capture(lua_State *L) {
    int ret = luat_pwm_capture(luaL_checkinteger(L, 1),luaL_checkinteger(L, 2));
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_pwm[] =
{
    { "open" ,       l_pwm_open , 0},
    { "close" ,      l_pwm_close, 0},
    { "capture" ,      l_pwm_capture, 0},
	{ NULL,          NULL ,       0}
};

LUAMOD_API int luaopen_pwm( lua_State *L ) {
    luat_newlib(L, reg_pwm);
    return 1;
}
