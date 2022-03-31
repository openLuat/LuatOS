/*
@module  timer
@summary 操作底层定时器
@version 1.0
@date    2020.03.30
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_malloc.h"

/*
硬阻塞指定时长,期间没有任何luat代码会执行,包括底层消息处理机制
@api    timer.mdelay(timeout)
@int 阻塞时长
@return nil 无返回值
-- 本方法通常不会使用,除非你很清楚会发生什么
timer.mdelay(10)
*/
static int l_timer_mdelay(lua_State *L) {
    lua_gettop(L);
    if (lua_isinteger(L, 1)) {
        lua_Integer ms = luaL_checkinteger(L, 1);
        if (ms)
            luat_timer_mdelay(ms);
    }
    return 0;
}

//TODO 支持hwtimer

#include "rotable2.h"
static const rotable_Reg_t reg_timer[] =
{
    { "mdelay", ROREG_FUNC(l_timer_mdelay)},
	{ NULL,     ROREG_INT(0) }
};

LUAMOD_API int luaopen_timer( lua_State *L ) {
    luat_newlib2(L, reg_timer);
    return 1;
}
