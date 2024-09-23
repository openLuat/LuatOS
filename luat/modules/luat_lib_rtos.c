/*
@module  rtos
@summary RTOS底层操作库
@version 1.0
@date    2020.03.30
@tag LUAT_USE_GPIO
*/
#include "luat_base.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "rtos"
#include "luat_log.h"
static uint32_t autogc_high_water = 90;
static uint32_t autogc_mid_water = 80;
static uint16_t autogc_config = 100; // TODO 通过API可配置
static uint16_t autogc_counter = 0;
#ifndef LUAT_COMPILER_NOWEAK
LUAT_WEAK uint8_t luat_msgbus_is_empty(void)
{
	return 0;
}
#endif
/*
接受并处理底层消息队列.
@api    rtos.receive(timeout)   
@int  超时时长,通常是-1,永久等待
@return msgid          如果是定时器消息,会返回定时器消息id及附加信息, 其他消息由底层决定,不向lua层进行任何保证.
--  本方法通过sys.run()调用, 普通用户不要使用
rtos.receive(-1)
*/
static int l_rtos_receive(lua_State *L) {
    rtos_msg_t msg = {0};
    int re = {0};
    size_t total = 0;
    size_t used = 0;
    size_t max_used = 0;
    //系统空闲且设置了自动收集功能
    if (luat_msgbus_is_empty() && autogc_config)
    {
    	//LLOGD("auto collect check %d,%d", luat_msgbus_is_empty(), autogc_config);
    	luat_meminfo_luavm(&total, &used, &max_used);
    	//达到强制线就直接收集了
        if ( (used * 100) >= (total * autogc_high_water))
        {
            //LLOGD("luavm ram too high! used %d, total %d. Trigger Force-GC", used, total);
            // 需要执行2次, 因为userdata在第二次才会被回收
            lua_gc(L, LUA_GCCOLLECT, 0);
            lua_gc(L, LUA_GCCOLLECT, 0);
        }
        else
        {

            if (autogc_counter >= autogc_config) {
                autogc_counter = 0;
                if ( (used * 100) >= (total * autogc_mid_water))
                {
                    //LLOGD("luavm ram too high! used %d, total %d. Trigger Force-GC", used, total);
                    // 需要执行2次, 因为userdata在第二次才会被回收
                    lua_gc(L, LUA_GCCOLLECT, 0);
                    lua_gc(L, LUA_GCCOLLECT, 0);
                }
            }
            else {
                autogc_counter ++;
            }
        }
    }
    else
    {
    	autogc_counter = 0;	//这里也许可以不清零
    }


    re = luat_msgbus_get(&msg, luaL_checkinteger(L, 1));
    if (!re) {
        //LLOGD("rtos_msg got, invoke it handler=%08X", msg.handler);
        lua_pushlightuserdata(L, (void*)(&msg));
        return msg.handler(L, msg.ptr);
    }
    else {
        //LLOGD("rtos_msg get timeout");
        lua_pushinteger(L, -1);
        return 1;
    }
}

//------------------------------------------------------------------
static int l_timer_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    luat_timer_t *timer = (luat_timer_t *)ptr;
    int timer_id = msg->arg1;
    if (timer_id > 0) {
        timer = luat_timer_get(timer_id);
    }
    else if (timer != NULL) {
        timer_id = timer->id;
        timer = luat_timer_get(timer_id);
    }
    if (timer == NULL)
        return 0;
    // LLOGD("l_timer_handler id=%ld\n", timer->id);
    lua_pushinteger(L, MSG_TIMER);
    lua_pushinteger(L, timer->id);
    lua_pushinteger(L, timer->repeat);
    //lua_pushinteger(L, timer->timeout);
    if (timer->repeat == 0) {
        // LLOGD("stop timer %d", timer_id);
        luat_timer_stop(timer);
        luat_heap_free(timer);
    }
    else if (timer->repeat > 0) {
        timer->repeat --;
    }
    return 3;
}

/*
启动一个定时器
@api    rtos.timer_start(id,timeout,_repeat)   
@int  定时器id
@int  超时时长,单位毫秒
@int  重复次数,默认是0
@return id 如果是定时器消息,会返回定时器消息id及附加信息, 其他消息由底层决定,不向lua层进行任何保证.
@usage
-- 用户代码请使用 sys.timerStart
-- 启动一个3秒的循环定时器
rtos.timer_start(10000, 3000, -1)
*/
static int l_rtos_timer_start(lua_State *L) {
    lua_gettop(L);
    size_t timeout = 0;
    size_t type = 0;
    size_t id = (size_t)luaL_checkinteger(L, 1) / 1;
#if 0
    if (lua_isnumber(L, 2)) {
    	timeout = lua_tonumber(L, 2) * 1000;
    	type = 1;
    } else
#endif
    	timeout = (size_t)luaL_checkinteger(L, 2);
    int repeat = (size_t)luaL_optinteger(L, 3, 0);
    // LLOGD("start timer id=%ld", id);
    // LLOGD("timer timeout=%ld", timeout);
    // LLOGD("timer repeat=%ld", repeat);
    if (timeout < 1) {
        lua_pushinteger(L, 0);
        return 1;
    }
    luat_timer_t *timer = (luat_timer_t*)luat_heap_malloc(sizeof(luat_timer_t));
    if (timer == NULL){
        LLOGE("timer malloc fail");
        lua_pushinteger(L, 0);
        return 1;
    }
    
    timer->id = id;
    timer->timeout = timeout;
    timer->repeat = repeat;
    timer->func = &l_timer_handler;
    timer->type = type;
    int re = luat_timer_start(timer);
    if (re == 0) {
        lua_pushinteger(L, 1);
    }
    else {
        LLOGD("start timer fail, free timer %p", timer);
        luat_heap_free(timer);
        lua_pushinteger(L, 0);
    }
    return 1;
}

/*
关闭并释放一个定时器
@api    rtos.timer_stop(id)   
@int  定时器id
@return nil            无返回值
@usage
-- 用户代码请使用sys.timerStop
rtos.timer_stop(id)
*/
static int l_rtos_timer_stop(lua_State *L) {
    int timerid = -1;
    luat_timer_t *timer = NULL;
    if (!lua_isinteger(L, 1)) {
        return 0;
    }
    timerid = lua_tointeger(L, 1);
    timer = luat_timer_get(timerid);
    if (timer != NULL) {
        // LLOGD("timer stop, free timer %d", timerid);
        luat_timer_stop(timer);
        luat_heap_free(timer);
    }
    return 0;
}

/*
设备重启
@api    rtos.reboot()   
@return nil          无返回值
-- 立即重启设备
rtos.reboot()
*/
int l_rtos_reboot(lua_State *L) {
    luat_os_reboot(luaL_optinteger(L, 1, 0));
    return 0;
}

//-----------------------------------------------------------------

/*
获取固件编译日期
@api    rtos.buildDate()
@return string 固件编译日期
@usage
-- 获取编译日期
local d = rtos.buildDate()
*/
static int l_rtos_build_date(lua_State *L) {
    lua_pushstring(L, __DATE__);
    return 1;
}

/*
获取硬件bsp型号
@api    rtos.bsp()
@return string 硬件bsp型号
@usage
-- 获取硬件bsp型号
local bsp = rtos.bsp()
*/
static int l_rtos_bsp(lua_State *L) {
    lua_pushstring(L, luat_os_bsp());
    return 1;
}

/*
 获取固件版本号
@api    rtos.version()        
@return string  固件版本号,例如"V0001"
@usage
-- 读取版本号
local luatos_version = rtos.version()
*/
static int l_rtos_version(lua_State *L) {
    lua_pushstring(L, luat_version_str());
    return 1;
}

/*
进入待机模式, 仅部分设备可用, 本API已废弃, 推荐使用pm库
@api    rtos.standy(timeout)
@int    休眠时长,单位毫秒
@return nil  无返回值
@usage
-- 进入待机模式
rtos.standby(5000)
*/
static int l_rtos_standy(lua_State *L) {
    int timeout = luaL_checkinteger(L, 1);
    luat_os_standy(timeout);
    return 0;
}

/*
获取内存信息
@api    rtos.meminfo(type)
@type   "sys"系统内存, "lua"虚拟机内存,"psram"psram内存, 默认为lua虚拟机内存
@return int 总内存大小,单位字节
@return int 当前已使用的内存大小,单位字节
@return int 历史最高已使用的内存大小,单位字节
@usage
-- 打印内存占用
log.info("mem.lua", rtos.meminfo())
log.info("mem.sys", rtos.meminfo("sys"))
*/
static int l_rtos_meminfo(lua_State *L) {
    size_t len = 0;
    size_t total = 0;
    size_t used = 0;
    size_t max_used = 0;
    const char * str = luaL_optlstring(L, 1, "lua", &len);
    if (strcmp("sys", str) == 0) {
        luat_meminfo_opt_sys(LUAT_HEAP_SRAM, &total, &used, &max_used);
    }
    else if(strcmp("psram", str) == 0){
        luat_meminfo_opt_sys(LUAT_HEAP_PSRAM, &total, &used, &max_used);
    }
    else {
        luat_meminfo_luavm(&total, &used, &max_used);
    }
    
    lua_pushinteger(L, total);
    lua_pushinteger(L, used);
    lua_pushinteger(L, max_used);
    return 3;
}

/*
返回底层描述信息,格式为 LuatOS_$VERSION_$BSP,可用于OTA升级判断底层信息
@api    rtos.firmware()
@return string 底层描述信息
@usage
-- 打印底层描述信息
log.info("firmware", rtos.firmware())
*/
static int l_rtos_firmware(lua_State *L) {
    lua_pushfstring(L, "LuatOS-SoC_%s_%s", luat_version_str(), luat_os_bsp());
    return 1;
}

extern char custom_search_paths[4][24];

/*
设置自定义lua脚本搜索路径,优先级高于内置路径
@api    rtos.setPaths(pathA, pathB, pathC, pathD)
@string 路径A, 例如 "/sdcard/%s.luac",若不传值,将默认为"",另外,最大长度不能超过23字节
@string 路径B, 例如 "/sdcard/%s.lua"
@string 路径C, 例如 "/lfs2/%s.luac"
@string 路径D, 例如 "/lfs2/%s.lua"
@usage
-- 挂载sd卡或者spiflash后
rtos.setPaths("/sdcard/user/%s.luac", "/sdcard/user/%s.lua")
require("sd_user_main") -- 将搜索并加载 /sdcard/user/sd_user_main.luac 和 /sdcard/user/sd_user_main.lua
*/
static int l_rtos_set_paths(lua_State *L) {
    size_t len = 0;
    const char* str = NULL;
    for (size_t i = 0; i < 4; i++)
    {
        if (lua_isstring(L, i +1)) {
            str = luaL_checklstring(L, i+1, &len);
            memcpy(custom_search_paths[i], str, len + 1);
        }
        else {
            custom_search_paths[i][0] = 0x00;
        }
    }
    return 0;
}

/*
空函数,什么都不做
@api    rtos.nop()
@return nil 无返回值
@usage
-- 这个函数单纯就是 lua -> c -> lua 走一遍
-- 没有参数,没有返回值,没有逻辑处理
-- 在绝大多数情况下,不会遇到这个函数的调用
-- 它通常只会出现在性能测试的代码里, 因为它什么都不干.
rtos.nop()
*/
static int l_rtos_nop(lua_State *L) {
    (void)L;
    return 0;
}

/*
内存自动收集配置，是lua本身收集机制的一种补充，不是必要的，而且只在luavm空闲时触发
@api    rtos.autoCollectMem(period, warning_level, force_level)
@int	自动收集的周期，等同于receive调用次数，0~60000。如果是0，则关闭自动收集功能，默认是100
@int	内存使用警戒水位线，是总luavm内存量的百分比，50~95，内存达到(>=)警戒线时才会开始判断是否要收集。默认是80
@int	内存使用强制收集水位线，是总luavm内存量的百分比，50~95，内存达到(>=)强制收集线时会强制收集。默认是90，必须比警戒水位线大
@return nil 无返回值
@usage
rtos.autoCollectMem(100, 80, 90)
*/
static int l_rtos_auto_colloect_mem(lua_State *L) {
    uint32_t period = luaL_optinteger(L, 1, 100);
    uint32_t mid = luaL_optinteger(L, 2, 80);
    uint32_t high = luaL_optinteger(L, 3, 90);
    if (period > 60000) {
    	return 0;
    }
    if (mid > 95 || high > 95) {
    	return 0;
    }
    if (mid < 50 || high < 50) {
    	return 0;
    }
    if (mid >= high) {
    	return 0;
    }
    LLOGD("mem collect param %u,%u,%u -> %u,%u,%u", autogc_config, autogc_mid_water, autogc_high_water, period, mid, high);
    autogc_config = period;
	autogc_mid_water = mid;
	autogc_high_water = high;
    return 0;
}

// TODO 部分平台不支持LUAT_WEAK
LUAT_WEAK int luat_poweron_reason(void) {
    return 0;
}

//uint32_t-高16位重启主原因,低16位详细原因
//高16位:0-上电/复位开机,1-用户主动软件重启,2-RTC开机,3-异常重启,4-唤醒开机
//低16位
//
// static int l_rtos_poweron_reason(lua_State *L) {
//     lua_pushinteger(L,luat_poweron_reason());
//     return 1;
// }

//------------------------------------------------------------------
#include "rotable2.h"
static const rotable_Reg_t reg_rtos[] =
{
    { "timer_start" ,      ROREG_FUNC(l_rtos_timer_start)},
    { "timer_stop",        ROREG_FUNC(l_rtos_timer_stop)},
    { "receive",           ROREG_FUNC(l_rtos_receive)},
    { "reboot",            ROREG_FUNC(l_rtos_reboot)},
    // { "poweron_reason",    ROREG_FUNC(l_rtos_poweron_reason)},
    { "standy",            ROREG_FUNC(l_rtos_standy)},

    { "buildDate",         ROREG_FUNC(l_rtos_build_date)},
    { "bsp",               ROREG_FUNC(l_rtos_bsp)},
    { "version",           ROREG_FUNC(l_rtos_version)},
    { "meminfo",           ROREG_FUNC(l_rtos_meminfo)},
    { "firmware",          ROREG_FUNC(l_rtos_firmware)},
    { "setPaths",          ROREG_FUNC(l_rtos_set_paths)},
    { "nop",               ROREG_FUNC(l_rtos_nop)},
	{ "autoCollectMem",          ROREG_FUNC(l_rtos_auto_colloect_mem)},
    { "INF_TIMEOUT",       ROREG_INT(-1)},

    { "MSG_TIMER",         ROREG_INT(MSG_TIMER)},
    // { "MSG_GPIO",           NULL,              MSG_GPIO},
    // { "MSG_UART_RX",        NULL,              MSG_UART_RX},
    // { "MSG_UART_TXDONE",    NULL,              MSG_UART_TXDONE},
	{ NULL,                ROREG_INT(0) }
};

LUAMOD_API int luaopen_rtos( lua_State *L ) {
    luat_newlib2(L, reg_rtos);
    return 1;
}

LUAT_WEAK const char* luat_version_str(void) {
    #ifdef LUAT_BSP_VERSION
    return LUAT_BSP_VERSION;
    #else
    return LUAT_VERSION;
    #endif
}
