/*
@module  pwm
@summary PWM模块
@version 1.0
@date    2020.07.03
@demo pwm
@tag LUAT_USE_PWM
*/
#include "luat_base.h"
#include "luat_pwm.h"

/**
开启指定的PWM通道
@api pwm.open(channel, period, pulse, pnum, precision)
@int PWM通道
@int 频率, 1-1000000hz
@int 占空比 0-分频精度
@int 输出周期 0为持续输出, 1为单次输出, 其他为指定脉冲数输出
@int 分频精度, 100/256/1000, 默认为100, 若设备不支持会有日志提示
@return boolean 处理结果,成功返回true,失败返回false
@usage
-- 打开PWM5, 频率1kHz, 占空比50%
pwm.open(5, 1000, 50)
-- 打开PWM5, 频率10kHz, 分频为 31/256
pwm.open(5, 10000, 31, 0, 256)
 */
static int l_pwm_open(lua_State *L) {
    luat_pwm_conf_t conf = {
        .pnum = 0,
        .precision = 100
    };
    conf.channel = luaL_checkinteger(L, 1);
    conf.period = luaL_checkinteger(L, 2);
    conf.pulse = luaL_optnumber(L, 3,0);
    if (lua_isnumber(L, 4) || lua_isinteger(L, 4)){
        conf.pnum = luaL_checkinteger(L, 4);
    }
    if (lua_isnumber(L, 5) || lua_isinteger(L, 5)){
        conf.precision = luaL_checkinteger(L, 5);
    }
    int ret = luat_pwm_setup(&conf);
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
while 1 do
    pwm.capture(0,1000)
    local ret,channel,pulse,pwmH,pwmL  = sys.waitUntil("PWM_CAPTURE", 2000)
    if ret then
        log.info("PWM_CAPTURE","channel"..channel,"pulse"..pulse,"pwmH"..pwmH,"pwmL"..pwmL)
    end
end
 */
static int l_pwm_capture(lua_State *L) {
    int ret = luat_pwm_capture(luaL_checkinteger(L, 1),luaL_checkinteger(L, 2));
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_pwm[] =
{
    { "open" ,       ROREG_FUNC(l_pwm_open )},
    { "close" ,      ROREG_FUNC(l_pwm_close)},
    { "capture" ,    ROREG_FUNC(l_pwm_capture)},
	{ NULL,          ROREG_INT(0) }
};

LUAMOD_API int luaopen_pwm( lua_State *L ) {
    luat_newlib2(L, reg_pwm);
    return 1;
}
