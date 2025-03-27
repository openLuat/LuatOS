
/*
@module  pm
@summary 电源管理
@version 1.0
@date    2020.07.02
@demo pm
@tag LUAT_USE_PM
@usage
--[[
休眠模式简介

-- IDLE 正常运行模式
-- LIGHT 轻睡眠模式:
        CPU暂停
        RAM保持供电
        定时器/网络事件/IO中断均可自动唤醒
        唤醒后程序继续运行
        普通GPIO掉电,外设驱动掉电
        AON_GPIO保持电平
-- DEEP 深睡眠模式
        CPU暂停
        核心RAM掉电, 保留RAM维持供电
        普通GPIO掉电,外设驱动掉电
        AON_GPIO保持休眠前的电平
        dtimer定时器可唤醒
        wakeup脚可唤醒
        唤醒后程序从头运行,休眠前的运行时数据全丢
-- HIB 休眠模式
        CPU暂停
        RAM掉电, 保留RAM也掉电
        普通GPIO掉电,外设驱动掉电
        AON_GPIO保持休眠前的电平
        dtimer定时器可唤醒
        wakeup脚可唤醒
        唤醒后程序从头运行,休眠前的运行时数据全丢

对部分模块,例如Air780EXXX, DEEP/HIB对用户代码没有区别

除pm.shutdown()外, RTC总是运行的, 除非掉电
]]

-- 定时器唤醒, 请使用 pm.dtimerStart()
-- wakeup唤醒
    -- 如Air101/Air103, 有独立的wakeup脚, 不需要配置,可直接控制唤醒
    -- 如Air780EXXX系列, 有多个wakeup可用, 通过gpio.setup()配置虚拟GPIO进行唤醒配置,参考demo/gpio/virtualIO

pm.request(pm.IDLE) -- 通过切换不同的值请求进入不同的休眠模式
-- 对应Air780EXXX系列, 执行后并不一定马上进入休眠模式, 如无后续数据传输需求,可先进入飞行模式,然后快速休眠
*/
#include "lua.h"
#include "lauxlib.h"
#include "luat_base.h"
#include "luat_pm.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "pm"
#include "luat_log.h"

// static int lua_event_cb = 0;
/*
@sys_pub pm
deep sleep timer定时时间到回调
DTIMER_WAKEUP
@usage
sys.subscribe("DTIMER_WAKEUP", function(timer_id)
    log.info("deep sleep timer", timer_id)
end)
*/
int luat_dtimer_cb(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_getglobal(L, "sys_pub");
    if (lua_isfunction(L, -1)) {
        lua_pushstring(L, "DTIMER_WAKEUP");
        lua_pushinteger(L, msg->arg1);
        lua_call(L, 2, 0);
    }
    return 0;
}

/**
请求进入指定的休眠模式
@api pm.request(mode)
@int 休眠模式,例如pm.IDLE/LIGHT/DEEP/HIB.
@return boolean 处理结果,即使返回成功,也不一定会进入, 也不会马上进入
@usage
-- 请求进入休眠模式
--[[
IDLE   正常运行,就是无休眠
LIGHT  轻休眠, CPU停止, RAM保持, 外设保持, 可中断唤醒. 部分型号支持从休眠处继续运行
DEEP   深休眠, CPU停止, RAM掉电, 仅特殊引脚保持的休眠前的电平, 大部分管脚不能唤醒设备.
HIB    彻底休眠, CPU停止, RAM掉电, 仅复位/特殊唤醒管脚可唤醒设备.
]]

pm.request(pm.HIB)
 */
static int l_pm_request(lua_State *L) {
    int mode = luaL_checkinteger(L, 1);
    if (luat_pm_request(mode) == 0)
        lua_pushboolean(L, 1);
    else
        lua_pushboolean(L, 0);
    return 1;
}

// static int l_pm_release(lua_State *L) {
//     int mode = luaL_checkinteger(L, 1);
//     if (luat_pm_release(mode) == 0)
//         lua_pushboolean(L, 1);
//     else
//         lua_pushboolean(L, 0);
//     return 1;
// }

/**
启动底层定时器,在休眠模式下依然生效. 只触发一次，关机状态下无效
@api pm.dtimerStart(id, timeout)
@int 定时器id,通常是0-5
@int 定时时长,单位毫秒
@return boolean 处理结果
@usage
-- 添加底层定时器
pm.dtimerStart(0, 300 * 1000) -- 5分钟后唤醒
-- 针对Air780EXXX有如下限制
-- id = 0 或者 id = 1 是, 最大休眠时长是2.5小时
-- id >= 2是, 最大休眠时长是740小时
 */
static int l_pm_dtimer_start(lua_State *L) {
    int dtimer_id = luaL_checkinteger(L, 1);
    int timeout = luaL_checkinteger(L, 2);
    if (luat_pm_dtimer_start(dtimer_id, timeout)) {
        lua_pushboolean(L, 0);
    }
    else {
        lua_pushboolean(L, 1);
    }
    return 1;
}

/**
关闭底层定时器
@api pm.dtimerStop(id)
@int 定时器id
@usage
-- 关闭底层定时器
pm.dtimerStop(0) -- 关闭id=0的底层定时器
 */
static int l_pm_dtimer_stop(lua_State *L) {
    int dtimer_id = luaL_checkinteger(L, 1);
    luat_pm_dtimer_stop(dtimer_id);
    return 0;
}

#ifndef LUAT_COMPILER_NOWEAK
LUAT_WEAK uint32_t luat_pm_dtimer_remain(int id){
	return -1;
}
#endif

/**
检查底层定时器是不是在运行
@api pm.dtimerCheck(id)
@int 定时器id
@return boolean 处理结果,true还在运行，false不在运行
@return number 如果运行,运行剩余时间,单位毫秒(需bsp支持)
@usage
-- 检查底层定时器是不是在运行
pm.dtimerCheck(0) -- 检查id=0的底层定时器
 */
static int l_pm_dtimer_check(lua_State *L) {
    int dtimer_id = luaL_checkinteger(L, 1);
    if (luat_pm_dtimer_check(dtimer_id)){
        uint32_t remain = luat_pm_dtimer_remain(dtimer_id);
    	lua_pushboolean(L, 1);
        lua_pushinteger(L, remain);
        return 2;
    }else{
    	lua_pushboolean(L, 0);
        return 1;
    }
}

static int l_pm_dtimer_list(lua_State *L) {
    size_t c = 0;
    size_t dlist[24];

    luat_pm_dtimer_list(&c, dlist);

    lua_createtable(L, c, 0);
    for (size_t i = 0; i < c; i++)
    {
        if (dlist[i] > 0) {
            lua_pushinteger(L, dlist[i]);
            lua_seti(L, -3, i+1);
        }
    }

    return 1;
}

/**
检查定时唤醒是哪一个定时器，如果不是定时唤醒的，返回-1
@api dtimerWkId()
@return int 处理结果 >=0 是本次定时唤醒的定时器ID，其他错误，说明不是定时唤醒的
@usage
local timer_id = pm.dtimerWkId()
 */
static int l_pm_dtimer_wakeup_id(lua_State *L) {
    int dtimer_id = 0xFF;

    luat_pm_dtimer_wakeup_id(&dtimer_id);

    if (dtimer_id != 0xFF) {
        lua_pushinteger(L, dtimer_id);
    }
    else {
        lua_pushinteger(L, -1);
    }
    return 1;
}

// static int l_pm_on(lua_State *L) {
//     if (lua_isfunction(L, 1)) {
//         if (lua_event_cb != 0) {
//             luaL_unref(L, LUA_REGISTRYINDEX, lua_event_cb);
//         }
//         lua_event_cb = luaL_ref(L, LUA_REGISTRYINDEX);
//     }
//     else if (lua_event_cb != 0) {
//         luaL_unref(L, LUA_REGISTRYINDEX, lua_event_cb);
//     }
//     return 0;
// }

/**
开机原因,用于判断是从休眠模块开机,还是电源/复位开机
@api pm.lastReson()
@return int 0-上电/复位开机, 1-RTC开机, 2-WakeupIn/Pad/IO开机, 3-未知原因(Wakeup/RTC皆有可能)开机,目前只有air101,air103会有这个返回值
@return int 0-普通开机(上电/复位),3-深睡眠开机,4-休眠开机
@return int 复位开机详细原因：0-powerkey或者上电开机 1-充电或者AT指令下载完成后开机 2-闹钟开机 3-软件重启 4-未知原因 5-RESET键 6-异常重启 7-工具控制重启 8-内部看门狗重启 9-外部重启 10-充电开机
@usage
-- 是哪种方式开机呢
log.info("pm", "last power reson", pm.lastReson())
 */
static int l_pm_last_reson(lua_State *L) {
    int lastState = 0;
    int rtcOrPad = 0;
    luat_pm_last_state(&lastState, &rtcOrPad);
    lua_pushinteger(L, rtcOrPad);
    lua_pushinteger(L, lastState);
    lua_pushinteger(L, luat_pm_get_poweron_reason());
    return 3;
}

/**
强制进入指定的休眠模式，忽略某些外设的影响，比如USB
@api pm.force(mode)
@int 休眠模式
@return boolean 处理结果,若返回成功,大概率会马上进入该休眠模式
@usage
-- 请求进入休眠模式
pm.force(pm.HIB)
-- 针对Air780EXXX, 该操作会关闭USB通信
-- 唤醒后如需开启USB, 请打开USB电压
--pm.power(pm.USB, true)
 */
static int l_pm_force(lua_State *L) {
    lua_pushinteger(L, luat_pm_force(luaL_checkinteger(L, 1)));
    return 1;
}

/**
检查休眠状态
@api pm.check()
@return boolean 处理结果,如果能顺利进入休眠,返回true,否则返回false
@return int 底层返回值,0代表能进入最底层休眠,其他值代表最低可休眠级别
@usage
-- 请求进入休眠模式,然后检查是否能真的休眠
pm.request(pm.HIB)
if pm.check() then
    log.info("pm", "it is ok to hib")
else
    -- 针对Air780EXXX, 该操作会关闭USB通信
    pm.force(pm.HIB) -- 强制休眠
    -- 唤醒后如需开启USB, 请打开USB电压
    --sys.wait(100)
    --pm.power(pm.USB, true)
end
 */
static int l_pm_check(lua_State *L) {
    int ret = luat_pm_check();
    lua_pushboolean(L, luat_pm_check() == 0 ? 1 : 0);
    lua_pushinteger(L, ret);
    return 2;
}


#ifndef LUAT_COMPILER_NOWEAK
LUAT_WEAK int luat_pm_poweroff(void) {
    LLOGW("powerOff is not supported");
    return -1;
}
#else
extern int luat_pm_poweroff(void);
#endif

/**
关机
@api pm.shutdown()
@return nil 无返回值
@usage
-- 当前支持移芯CAT1平台系列(Air780E/Air700E/Air780EP等等)
-- 需要2022-12-22之后编译的固件
pm.shutdown()
 */
static int l_pm_power_off(lua_State *L) {
    (void)L;
    luat_pm_poweroff();
    return 0;
}

/**
重启
@api pm.reboot()
@return nil          无返回值
-- 立即重启设备, 本函数的行为与rtos.reboot()完全一致,只是在pm库做个别名
pm.reboot()
 */
int l_rtos_reboot(lua_State *L);
int l_rtos_standby(lua_State *L);

/**
开启内部的电源控制，注意不是所有的平台都支持，可能部分平台支持部分选项，看硬件
@api pm.power(id, onoff)
@int 电源控制id,pm.USB pm.GPS之类
@boolean/int 开关true/1开，false/0关，默认关，部分选项支持数值
@return boolean 处理结果true成功，false失败
@usage
-- 关闭USB电源, 反之开启就是传true
pm.power(pm.USB, false) 

-- Air780EG,为内置的GPS芯片上电. 注意, Air780EG的GPS和GPS_ANT是一起控制的,所以合并了.
pm.power(pm.GPS, true)

-- Air780EXXX开启pwrkey开机防抖
-- 注意: 开启后, 复位键就变成关机了!!! pwrkey要长按2秒才能开机
-- pm.power(pm.PWK_MODE, true)

-- Air780EXXX PSM+低功耗设置
-- Air780EXXX节能模式，0~3，0完全关闭，1~2普通低功耗，3超低功耗，深度休眠
-- 详情访问: https://airpsm.cn
-- pm.power(pm.WORK_MODE, 1)
 */
static int l_pm_power_ctrl(lua_State *L) {
	uint8_t onoff = 0;
    int id = luaL_checkinteger(L, 1);
    if (lua_isboolean(L, 2)) {
    	onoff = lua_toboolean(L, 2);
    }
    else
    {
    	onoff = lua_tointeger(L, 2);
    }
    lua_pushboolean(L, !luat_pm_power_ctrl(id, onoff));
    return 1;
}

/**
IO高电平电压控制
@api pm.ioVol(id, val)
@int 电平id,目前只有pm.IOVOL_ALL_GPIO
@int 电平值,单位毫伏
@return boolean 处理结果true成功，false失败
@usage
-- Air780EXXX设置IO电平, 范围 1650 ~ 2000，2650~3400 , 单位毫伏, 步进50mv
-- 注意, 这里的设置优先级会高于硬件IOSEL脚的配置
-- 但开机时依然先使用硬件配置,直至调用本API进行配置, 所以io电平会变化
-- pm.ioVol(pm.IOVOL_ALL_GPIO, 3300)    -- 所有GPIO高电平输出3.3V
-- pm.ioVol(pm.IOVOL_ALL_GPIO, 1800)    -- 所有GPIO高电平输出1.8V
*/
static int l_pm_iovolt_ctrl(lua_State *L) {
int val = 3300;
 int id = luaL_optinteger(L, 1, LUAT_PM_ALL_GPIO);
 if (lua_isboolean(L, 2)) {
	val = lua_toboolean(L, 2);
 }
 else if (lua_isinteger(L, 2)) {
	 val = luaL_checkinteger(L, 2);
 }
 lua_pushboolean(L, !luat_pm_iovolt_ctrl(id, val));
 return 1;
}

#ifndef LUAT_COMPILER_NOWEAK
LUAT_WEAK int luat_pm_iovolt_ctrl(int id, int val) {
 return -1;
}
#endif


/**
配置唤醒引脚 (当前仅仅esp系列可用)
@api pm.wakeupPin(pin,level)
@int/table gpio引脚
@int 唤醒电压 可选,默认低电平唤醒
@return boolean 处理结果
@usage
pm.wakeupPin(8,0)
 */
static int l_pm_wakeup_pin(lua_State *L) {
    int level = luaL_optinteger(L, 2,0);
    if (lua_istable(L, 1)) {
        size_t count = lua_rawlen(L, 1);
		for (size_t i = 1; i <= count; i++){
			lua_geti(L, 1, i);
            luat_pm_wakeup_pin(luaL_checkinteger(L, -1), level);
			lua_pop(L, 1);
		}
    }else if(lua_isnumber(L, 1)){
        luat_pm_wakeup_pin(luaL_checkinteger(L, 1), level);
    }
    lua_pushboolean(L, 1);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_pm[] =
{
    { "request" ,       ROREG_FUNC(l_pm_request )},
    // { "release" ,    ROREG_FUNC(   l_pm_release)},
    { "dtimerStart",    ROREG_FUNC(l_pm_dtimer_start)},
    { "dtimerStop" ,    ROREG_FUNC(l_pm_dtimer_stop)},
	{ "dtimerCheck" ,   ROREG_FUNC(l_pm_dtimer_check)},
    { "dtimerList",     ROREG_FUNC(l_pm_dtimer_list)},
    { "dtimerWkId",     ROREG_FUNC(l_pm_dtimer_wakeup_id)},
    //{ "on",           ROREG_FUNC(l_pm_on)},
    { "force",          ROREG_FUNC(l_pm_force)},
    { "check",          ROREG_FUNC(l_pm_check)},
    { "lastReson",      ROREG_FUNC(l_pm_last_reson)},
    { "shutdown",       ROREG_FUNC(l_pm_power_off)},
    { "reboot",         ROREG_FUNC(l_rtos_reboot)},
	{ "power",          ROREG_FUNC(l_pm_power_ctrl)},
    { "ioVol",         ROREG_FUNC(l_pm_iovolt_ctrl)},
    { "wakeupPin",         ROREG_FUNC(l_pm_wakeup_pin)},


    //@const NONE number 不休眠模式
    { "NONE",           ROREG_INT(LUAT_PM_SLEEP_MODE_NONE)},
    //@const IDLE number IDLE模式
    { "IDLE",           ROREG_INT(LUAT_PM_SLEEP_MODE_IDLE)},
    //@const LIGHT number LIGHT模式
    { "LIGHT",          ROREG_INT(LUAT_PM_SLEEP_MODE_LIGHT)},
    //@const DEEP number DEEP模式
    { "DEEP",           ROREG_INT(LUAT_PM_SLEEP_MODE_DEEP)},
    //@const HIB number HIB模式
    { "HIB",            ROREG_INT(LUAT_PM_SLEEP_MODE_STANDBY)},
    //@const USB number USB电源
    { "USB",            ROREG_INT(LUAT_PM_POWER_USB)},
    //@const GPS number GPS电源
    { "GPS",            ROREG_INT(LUAT_PM_POWER_GPS)},
    //@const GPS_ANT number GPS的天线电源，有源天线才需要
    { "GPS_ANT",        ROREG_INT(LUAT_PM_POWER_GPS_ANT)},
    //@const CAMERA number camera电源，CAM_VCC输出
    { "CAMERA",         ROREG_INT(LUAT_PM_POWER_CAMERA)},
    //@const DAC_EN number Air780EXXX的DAC_EN(新版硬件手册的LDO_CTL，同一个PIN，命名变更)，注意audio的默认配置会自动使用这个脚来控制CODEC的使能
    { "DAC_EN",         ROREG_INT(LUAT_PM_POWER_DAC_EN_PIN)},
    //@const LDO_CTL number Air780EXXX的LDO_CTL(老版硬件手册的DAC_EN，同一个PIN，命名变更)，Air780EXXX的LDO_CTL, 注意audio的默认配置会自动使用这个脚来控制CODEC的使能
    { "LDO_CTL",         ROREG_INT(LUAT_PM_POWER_LDO_CTL_PIN)},
    //@const PWK_MODE number 是否Air780EXXX的powerkey滤波模式，true开，注意滤波模式下reset变成直接关机
    { "PWK_MODE",       ROREG_INT(LUAT_PM_POWER_POWERKEY_MODE)},
    //@const WORK_MODE number Air780EXXX的节能模式，0~3，0完全关闭，1~2普通低功耗，3超低功耗，深度休眠
    { "WORK_MODE",    ROREG_INT(LUAT_PM_POWER_WORK_MODE)},
	//@const IOVL number 所有GPIO高电平电压控制,当前仅Air780EXXX可用
    { "IOVOL_ALL_GPIO",    ROREG_INT(LUAT_PM_ALL_GPIO)},

	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_pm( lua_State *L ) {
    luat_newlib2(L, reg_pm);
    return 1;
}
