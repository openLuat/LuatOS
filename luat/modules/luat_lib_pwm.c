/*
@module  pwm
@summary PWM模块
@version 1.0
@date    2020.07.03
@demo pwm
@tag LUAT_USE_PWM
@usage
-- 本库支持2套API风格
-- 1. 传统API, open和close
-- 2. 新的API(推荐使用), setup,start,stop,setDuty,setFreq

-- 传统API
pwm.open(1, 1000, 50) -- 打开PWM1, 频率1kHz, 占空比50%
sys.wait(5000) -- 等待5秒
pwm.close(1) -- 关闭PWM1

-- 新API
pwm.setup(1, 1000, 50) -- 设置PWM1, 频率1kHz, 占空比50%
pwm.start(1) -- 启动PWM1
sys.wait(5000) -- 等待5秒
pwm.setFreq(1, 2000) -- 设置PWM1频率2kHz
sys.wait(5000) -- 等待5秒
pwm.setDuty(1, 25) -- 设置PWM1占空比25%
sys.wait(5000) -- 等待5秒
pwm.stop(1) -- 关闭PWM1
*/
#include "luat_base.h"
#include "luat_pwm.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "pwm"
#include "luat_log.h"

/**
开启指定的PWM通道
@api pwm.open(channel, period, pulse, pnum, precision)
@int PWM通道
@int 频率, 1-N,单位Hz. N受限于具体硬件能力
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

// 新的API系列, 封装老的版本, bsp层暂时不改
static luat_pwm_conf_t* confs[6];

/*
初始化指定的PWM通道
@api pwm.setup(channel, period, pulse, pnum, precision)
@int PWM通道
@int 频率, 1-N,单位Hz. N受限于具体硬件能力
@int 占空比 0-分频精度
@int 输出周期 0为持续输出, 1为单次输出, 其他为指定脉冲数输出
@int 分频精度, 100/256/1000, 默认为100, 若设备不支持会有日志提示
@return boolean 处理结果,成功返回true,失败返回false
@usage
-- 设置PWM5, 频率1kHz, 占空比50%
pwm.setup(5, 1000, 50)
*/
static int l_pwm_setup(lua_State *L) {
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
    if (conf.channel > 5 || conf.channel < 0) {
        return 0;
    }
    if (confs[conf.channel] == NULL) {
        confs[conf.channel] = luat_heap_malloc(sizeof(luat_pwm_conf_t));
        if (confs[conf.channel] == NULL) {
            LLOGE("pwm_setup malloc fail");
            return 0;
        }
    }
    memcpy(confs[conf.channel], &conf, sizeof(luat_pwm_conf_t));
    lua_pushboolean(L, 1);
    return 1;
}

static int check_channel(lua_State *L) {
    int channel = luaL_checkinteger(L, 1);
    if (channel > 5 || channel < 0) {
        return -1;
    }
    if (confs[channel] == NULL) {
        LLOGE("请先调用pwm.setup!! %d", channel);
        return -1;
    }
    return channel;
}

/*
启动指定的PWM通道
@api pwm.start(channel)
@int PWM通道
@return boolean 处理结果,成功返回true,失败返回false
@usage
-- 启动PWM1
pwm.start(1)
*/
static int l_pwm_start(lua_State *L) {
    int channel = check_channel(L);
    if (channel < 0) {
        return 0;
    }
    int ret = luat_pwm_setup(confs[channel]);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
停止指定的PWM通道
@api pwm.stop(channel)
@int PWM通道
@return boolean 处理结果,成功返回true,失败返回false
@usage
-- 停止PWM1
pwm.stop(1)
*/
static int l_pwm_stop(lua_State *L) {
    int channel = check_channel(L);
    if (channel < 0) {
        return 0;
    }
    luat_pwm_close(channel);
    luat_heap_free(confs[channel]);
    confs[channel] = NULL;
    lua_pushboolean(L, 1);
    return 1;
}

/*
设置指定PWM通道的占空比
@api pwm.setDuty(channel, duty)
@int PWM通道
@int 占空比
@return boolean 处理结果,成功返回true,失败返回false
@usage
-- 设置PWM1占空比25%
pwm.setDuty(1, 25)
*/
static int l_pwm_set_duty(lua_State *L) {
    int channel = check_channel(L);
    if (channel < 0) {
        return 0;
    }
    confs[channel]->pulse = luaL_checkinteger(L, 2);
    int ret = luat_pwm_setup(confs[channel]);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
设置指定PWM通道的频率
@api pwm.setFreq(channel, freq)
@int PWM通道
@int 频率, 1-N,单位Hz. N受限于具体硬件能力
@return boolean 处理结果,成功返回true,失败返回false
@usage
-- 设置PWM5频率2kHz
pwm.setFreq(5, 2000)
*/
static int l_pwm_set_freq(lua_State *L) {
    int channel = check_channel(L);
    if (channel < 0) {
        return 0;
    }
    confs[channel]->period = luaL_checkinteger(L, 2);
    int ret = luat_pwm_setup(confs[channel]);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_pwm[] =
{
    { "open" ,       ROREG_FUNC(l_pwm_open )},
    { "close" ,      ROREG_FUNC(l_pwm_close)},
    { "capture" ,    ROREG_FUNC(l_pwm_capture)},

    // 新api, setup,start,stop
    { "setup" ,      ROREG_FUNC(l_pwm_setup )},
    { "start" ,      ROREG_FUNC(l_pwm_start )},
    { "stop" ,       ROREG_FUNC(l_pwm_stop )},
    { "setDuty" ,    ROREG_FUNC(l_pwm_set_duty )},
    { "setFreq" ,    ROREG_FUNC(l_pwm_set_freq )},

	{ NULL,          ROREG_INT(0) }
};

LUAMOD_API int luaopen_pwm( lua_State *L ) {
    luat_newlib2(L, reg_pwm);
    return 1;
}
