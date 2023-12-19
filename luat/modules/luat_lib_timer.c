/*
@module  timer
@summary 操作底层定时器
@version 1.0
@date    2020.03.30
@tag LUAT_USE_TIMER
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_mem.h"

/*
硬阻塞指定时长
@api    timer.mdelay(timeout)
@int    阻塞时长,单位ms, 最高1024ms, 实际使用强烈建议不要超过200ms
@return nil 无返回值
@usage
-- 期间没有任何luat代码会执行,包括底层消息处理机制
-- 本方法通常不会使用,除非你很清楚会发生什么
timer.mdelay(10)
*/
static int l_timer_mdelay(lua_State *L) {
    if (lua_isinteger(L, 1)) {
        lua_Integer ms = luaL_checkinteger(L, 1);
        if (ms > 0 && ms < 1024)
            luat_timer_mdelay(ms);
    }
    return 0;
}

/*
硬阻塞指定时长但us级别,不会很精准
@api    timer.udelay(timeout)
@int    阻塞时长,单位us, 最大3000us
@return nil 无返回值
@usage
-- 本方法通常不会使用,除非你很清楚会发生什么
-- 本API在 2023.05.18 添加
timer.udelay(10)
-- 实际阻塞时长是有波动的
*/
static int l_timer_udelay(lua_State *L) {
    if (lua_isinteger(L, 1)) {
        lua_Integer us = luaL_checkinteger(L, 1);
        if (us > 0 && us <= 3000)
            luat_timer_us_delay(us);
    }
    return 0;
}

//TODO 支持hwtimer

#include "rotable2.h"
static const rotable_Reg_t reg_timer[] =
{
    { "mdelay", ROREG_FUNC(l_timer_mdelay)},
    { "udelay", ROREG_FUNC(l_timer_udelay)},
	{ NULL,     ROREG_INT(0) }
};

LUAMOD_API int luaopen_timer( lua_State *L ) {
    luat_newlib2(L, reg_timer);
    return 1;
}
