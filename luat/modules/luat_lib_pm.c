
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
-- 全速模式
-- PRO低功耗模式
-- PSM+模式

以上模式均使用 pm.power(pm.WORK_MODE, mode) 来设置
-- mode=0   正常运行,就是无休眠
-- mode=1   轻度休眠, CPU停止, RAM保持, 可中断唤醒, 可定时器唤醒, 可网络唤醒. 支持从休眠处继续运行
-- mode=3   彻底休眠, CPU停止, RAM掉电, 支持特殊唤醒管脚唤醒, 支持定时器唤醒. 唤醒后脚本从头开始执行
]]
*/
#include "lua.h"
#include "lauxlib.h"
#include "luat_base.h"
#include "luat_pm.h"
#include "luat_msgbus.h"
#include "luat_hmeta.h"

#define LUAT_LOG_TAG "pm"
#include "luat_log.h"

#ifdef LUAT_USE_DRV_PM
#include "luat_airlink.h"
#include "luat/drv_pm.h"

extern uint32_t g_airlink_pause;
#endif

#ifdef LUAT_USE_YHM27XX
#include "luat_gpio.h"
#include "luat_zbuff.h"
#include "luat_msgbus.h"
#include "luat_gpio.h"
#ifdef LUAT_USE_DRV_GPIO
#include "luat/drv_gpio.h"
#endif

static uint8_t yhm27xx_reg_infos[9] = {0};
#endif



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
@api pm.request(mode, chip)
@int 休眠模式,例如pm.IDLE/LIGHT/DEEP/HIB.
@int 休眠芯片的ID, 默认是0, 大部分型号都只有0
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
    int ret = 0;
    #ifdef LUAT_USE_DRV_PM
    int chip = 0;
    if (lua_isinteger(L, 2)) {
        chip = luaL_checkinteger(L, 2);
        if (chip > 0) {
            g_airlink_pause = 1;    // wifi进入休眠自动暂停airlink工作
        }
    }
    ret = luat_drv_pm_request(chip, mode);
    #else
    ret = luat_pm_request(mode);
    #endif

    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

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

LUAT_WEAK int luat_pm_get_last_req_mode(void){
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
@api pm.dtimerWkId()
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
@api pm.power(id, onoff, chip)
@int 电源控制id,pm.USB pm.GPS之类
@boolean/int 开关true/1开，false/0关，默认关，部分选项支持数值
@int 休眠芯片的ID, 默认是0, 大部分型号都只有0
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
    int ret = 0;
    if (lua_isboolean(L, 2)) {
    	onoff = lua_toboolean(L, 2);
    }
    else
    {
    	onoff = lua_tointeger(L, 2);
    }
    #ifdef LUAT_USE_DRV_PM
    int chip = 0;
    if (lua_isinteger(L, 3)) {
        chip = luaL_checkinteger(L, 3);
    }
    ret = luat_drv_pm_power_ctrl(chip, id, onoff);
    #else
    ret = luat_pm_power_ctrl(id, onoff);
    #endif
    lua_pushboolean(L, !ret);
    return 1;
}

/**
IO高电平和对外输出LDO的电压控制
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
配置唤醒引脚
@api pm.wakeupPin(pin,level)
@int gpio引脚
@int 唤醒方式, 例如gpio.RISING (上升沿), gpio.FALLING (下降沿)
@int 芯片的ID, 默认是0, 大部分型号都只有0
@return boolean 处理结果
@usage
-- 本函数仅Air8101有效
pm.wakeupPin(8, gpio.RISING)
-- 对Air780xx系列, Air8000, Air72x系列均无效
-- 对于这些系列，使用gpio.setup即可, 例如使用 WAKEUP0引脚实现唤醒操作
gpio.setup(gpio.WAKEUP0, function() end, gpio.PULLUP, gpio.RISING)
-- 注意, 对于PSM+休眠, 唤醒相当于重启, 回调函数是不会执行的
-- 对于PRO休眠, 回调函数会执行
-- 唤醒原因, 可以通过 pm.lastReson()获取
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
        #ifdef LUAT_USE_DRV_PM
        int chip = 0;
        if (lua_isinteger(L, 3)) {
            chip = luaL_checkinteger(L, 3);
        }
        luat_drv_pm_wakeup_pin(chip, luaL_checkinteger(L, 1), level);
        #else
        luat_pm_wakeup_pin(luaL_checkinteger(L, 1), level);
        #endif
    }
    lua_pushboolean(L, 1);
    return 1;
}

// yhm27xx
#ifdef LUAT_USE_YHM27XX
/* 
@sys_pub pm 
YHM27XX芯片寄存器信息更新回调
YHM27XX_REG
@usage 
sys.subscribe("YHM27XX_REG", function(data)
    -- 注意, 会一次性读出0-9,总共8个寄存器值
    log.info("yhm27xx", data and data:toHex())
end)
*/
static int l_yhm_27xx_cb(lua_State *L, void *ptr)
{
    lua_getglobal(L, "sys_pub");
    if (lua_isfunction(L, -1))
    {
        lua_pushstring(L, "YHM27XX_REG");
        lua_pushlstring(L, (const char *)yhm27xx_reg_infos, 9);
        lua_call(L, 2, 0);
    }
    return 0;
}

static void luat_gpio_driver_yhm27xx_reqinfo(uint8_t pin, uint8_t chip_id)
{
    for (uint8_t i = 0; i < 9; i++)
    {
        luat_gpio_driver_yhm27xx(pin, chip_id, i, 1, &(yhm27xx_reg_infos[i]));
    }
    rtos_msg_t msg = {0};
    msg.handler = l_yhm_27xx_cb;
    luat_msgbus_put(&msg, 0);
}

// 根据模组型号匹配YHM27XX引脚
static uint8_t get_default_yhm27xx_pin(void)
{
    char model[32] = {0};
    luat_hmeta_model_name(model);
    if (memcmp("Air8000\0", model, 8) == 0 || memcmp("Air8000XB\0", model, 10) == 0 || memcmp("Air8000U\0", model, 9) == 0 || memcmp("Air8000N\0", model, 9) == 0) {
        return 152;
    }
    if (memcmp("Air8000G\0", model, 9) == 0) {
        return 22;
    }
    return 0;
}

/**
单总线命令读写YHM27XX
@api    pm.chgcmd(pin, chip_id, reg, data)
@int    yhm27xx_CMD引脚(可选,若传入nil则根据模组型号自动选择)
@int    芯片ID
@int    读写寄存器地址
@int    要写入的数据，如果没填，则表示从寄存器读取数据
@return boolean 成功返回true,失败返回false
@return int 读取成功返回寄存器值，写入成功无返回
@usage
-- 读取寄存器0x01的值
local ret = pm.chgcmd(pin, chip_id, 0x01)
-- 写入寄存器0x01的值为0x55
local ret = pm.chgcmd(pin, chip_id, 0x01, 0x55)
*/
int l_pm_chgcmd(lua_State *L)
{
    uint8_t pin = 0;
    // 第一个参数可选，若传入nil则根据模组型号自动选择
    if (!lua_isnoneornil(L, 1))
    {
        pin = luaL_checkinteger(L, 1);
    }
    else
    {
        // 根据模组型号设置默认值
        pin = get_default_yhm27xx_pin();
    }

    uint8_t chip_id = luaL_checkinteger(L, 2);
    uint8_t reg = luaL_checkinteger(L, 3);
    uint8_t data = 0;
    uint8_t is_read = 1;
    int ret = 0;
    if (!lua_isnone(L, 4))
    {
        is_read = 0;
        data = luaL_checkinteger(L, 4);
    }
    #ifdef LUAT_USE_DRV_GPIO
    ret = luat_drv_gpio_driver_yhm27xx(pin, chip_id, reg, is_read, &data);
    #else
    ret = luat_gpio_driver_yhm27xx(pin, chip_id, reg, is_read, &data);
    #endif
    if (ret != 0)
    {
        lua_pushboolean(L, 0);
        return 1;
    }
    lua_pushboolean(L, 1);
    if (is_read)
    {
        lua_pushinteger(L, data);
        return 2;
    }
    return 1;
}

/*
获取最新的寄存器信息(异步)
@api    pm.chginfo(pin, chip_id)
@int    yhm27xx_CMD引脚(可选,若传入nil则根据模组型号自动选择)
@int    芯片ID
@return nil 无返回值
@usage
sys.subscribe("YHM27XX_REG", function(data)
    -- 注意, 会一次性读出0-9,总共8个寄存器值
    log.info("yhm27xx", data and data:toHex())
end)
pm.chginfo(nil, 0x04)
*/
int l_pm_chginfo(lua_State *L)
{
    uint8_t pin = 0;
    // 第一个参数可选，若传入nil则根据模组型号自动选择
    if (!lua_isnoneornil(L, 1))
    {
        pin = luaL_checkinteger(L, 1);
    }
    else
    {
        // 根据模组型号设置默认值
        pin = get_default_yhm27xx_pin();
    }

    uint8_t chip_id = luaL_checkinteger(L, 2);
    #ifdef LUAT_USE_DRV_GPIO
    if (pin >= 128)
    {
        luat_drv_gpio_driver_yhm27xx_reqinfo(pin, chip_id);
        return 0;
    }
    #endif
    luat_gpio_driver_yhm27xx_reqinfo(pin, chip_id);
    return 0;
}
#endif

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
    { "ioVol",          ROREG_FUNC(l_pm_iovolt_ctrl)},
    { "wakeupPin",      ROREG_FUNC(l_pm_wakeup_pin)},
    // yhm27xx
    #ifdef LUAT_USE_YHM27XX
    { "chgcmd",         ROREG_FUNC(l_pm_chgcmd)},
    { "chginfo",        ROREG_FUNC(l_pm_chginfo)},
    #endif

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
    { "LDO_CTL",        ROREG_INT(LUAT_PM_POWER_LDO_CTL_PIN)},
    //@const PWK_MODE number 是否Air780EXXX的powerkey滤波模式，true开，注意滤波模式下reset变成直接关机
    { "PWK_MODE",       ROREG_INT(LUAT_PM_POWER_POWERKEY_MODE)},
    //@const WORK_MODE number Air780EXXX的节能模式，0~3，0完全关闭，1~2普通低功耗，3超低功耗，深度休眠
    { "WORK_MODE",      ROREG_INT(LUAT_PM_POWER_WORK_MODE)},
	//@const IOVOL_ALL_GPIO number 所有GPIO高电平电压控制,当前仅Air780EXXX可用
    { "IOVOL_ALL_GPIO", ROREG_INT(LUAT_PM_ALL_GPIO)},
	//@const IOVOL_SDIO number VMMC电压域IO
    { "IOVOL_SDIO", ROREG_INT(LUAT_PM_LDO_TYPE_VMMC)},
	//@const IOVOL_LCD number VLCD电压域IO
    { "IOVOL_LCD", ROREG_INT(LUAT_PM_LDO_TYPE_VLCD)},
	//@const IOVOL_CAMA number camera模拟电压
    { "IOVOL_CAMA", ROREG_INT(LUAT_PM_LDO_TYPE_CAMA)},
	//@const IOVOL_CAMD number camera数字电压
    { "IOVOL_CAMD", ROREG_INT(LUAT_PM_LDO_TYPE_CAMD)},
    //@const ID_NATIVE number PM控制的ID, 主芯片, 任意芯片的默认值就是它
    { "ID_NATIVE",      ROREG_INT(1)},
    //@const ID_WIFI number PM控制的ID, WIFI芯片, 仅Air8000可用
    { "ID_WIFI",        ROREG_INT(1)},

    //@const WIFI_STA_DTIM number wifi芯片控制STA模式下的DTIM间隔,单位100ms,默认值是1
    { "WIFI_STA_DTIM",  ROREG_INT(LUAT_PM_POWER_WIFI_STA_DTIM)},
    { "WIFI_AP_DTIM",   ROREG_INT(LUAT_PM_POWER_WIFI_AP_DTIM)},

	{ NULL,             ROREG_INT(0) }
};

LUAMOD_API int luaopen_pm( lua_State *L ) {
    luat_newlib2(L, reg_pm);
    return 1;
}
