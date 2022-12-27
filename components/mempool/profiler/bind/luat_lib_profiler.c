#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_malloc.h"
#include "luat_timer.h"

static int l_profiler_start(lua_State *L) {
    luat_profiler_start();
    return 0;
}

static int l_profiler_stop(lua_State *L) {
    luat_profiler_stop();
    return 0;
}

static int l_profiler_print(lua_State *L) {
    luat_profiler_print();
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_profiler[] =
{
    { "start" ,        ROREG_FUNC(l_profiler_start)},
    { "stop" ,         ROREG_FUNC(l_profiler_stop)},
    { "print",         ROREG_FUNC(l_profiler_print)},
	{ NULL,            ROREG_INT(0)}
};

LUAMOD_API int luaopen_profiler( lua_State *L ) {
    luat_newlib2(L, reg_profiler);
    return 1;
}
