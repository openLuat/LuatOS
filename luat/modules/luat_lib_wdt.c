/*
@module  wdt
@summary watchdog操作库
@version 1.0
@date    2021.08.06
@demo wdt
@tag LUAT_USE_WDT
*/
#include "luat_base.h"
#include "luat_wdt.h"

/*
初始化watchdog并马上启用.大部分设备的watchdog一旦启用就无法关闭.
@api    wdt.init(timeout)
@int 超时时长,单位为毫秒
@return bool 成功返回true,否则返回false(例如底层不支持)
@usage
wdt.init(9000)
sys.timerLoopStart(wdt.feed, 3000)
*/
static int l_wdt_init(lua_State *L) {
    int timeout = luaL_optinteger(L, 1, 10);
    int ret = luat_wdt_init(timeout);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
部分设备支持重新设置watchdog超时时长
@api    wdt.setTimeout(timeout)
@int 超时时长,单位为毫秒
@return bool 成功返回true,否则返回false(例如底层不支持)
@usage
wdt.init(10000)
sys.timerLoopStart(wdt.feed, 3000)
sys.wait(5000)
sys.setTimeout(5000)
*/
static int l_wdt_set_timeout(lua_State *L) {
    int timeout = luaL_optinteger(L, 1, 10);
    int ret = luat_wdt_set_timeout(timeout);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
喂狗,使得超时计时复位,重新计时
@api    wdt.feed()
@return bool 成功返回true,否则返回false(例如底层不支持)
@usage
wdt.init(10000)
-- 定时喂狗,或者根据业务按需喂狗
sys.timerLoopStart(wdt.feed, 3000)
*/
static int l_wdt_feed(lua_State *L) {
    int ret = luat_wdt_feed();
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
关闭watchdog,通常不被支持
@api    wdt.close()
@return bool 成功返回true,否则返回false(例如底层不支持)
@usage
wdt.init(10000)
sys.wait(9000)
wdt.close()
*/
static int l_wdt_close(lua_State *L) {
    int ret = luat_wdt_feed();
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_wdt[] =
{
    { "init",       ROREG_FUNC(l_wdt_init)},
    { "setTimeout", ROREG_FUNC(l_wdt_set_timeout)},
    { "feed",       ROREG_FUNC(l_wdt_feed)},
    { "close",      ROREG_FUNC(l_wdt_close)},
	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_wdt( lua_State *L ) {
    luat_newlib2(L, reg_wdt);
    return 1;
}
