
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "win32"
#include "luat_log.h"

extern int cmdline_argc;
extern char** cmdline_argv;

static int l_win32_args(lua_State *L) {
    int index = luaL_optinteger(L, 1, 2);
    lua_newtable(L);
    if (cmdline_argc > index) {
        for (size_t i = index; i < cmdline_argc; i++)
        {
            //printf("args[%d] %s\n", i, win32_argv[i]);
            lua_pushinteger(L, i + 1 - index);
            lua_pushstring(L, cmdline_argv[i]);
            lua_settable(L, -3);
        }
    }

    return 1;
}

static int timer_handler(lua_State *L, void* ptr) {
    luat_timer_t *timer = (luat_timer_t *)ptr;
    uint64_t* idp = (uint64_t*)timer->id;
    lua_pushboolean(L,1);
    luat_cbcwait(L, *idp, 1);
    return 0;
}

static int l_test_cwait_delay(lua_State *L) {
    lua_gettop(L);
    if (lua_isinteger(L, 1)) {
        lua_Integer ms = luaL_checkinteger(L, 1);
        if (ms)
        {
            uint64_t id = luat_pushcwait(L);
            luat_timer_t *timer = (luat_timer_t*)luat_heap_malloc(sizeof(luat_timer_t));

            uint64_t* idp = (uint64_t*)luat_heap_malloc(sizeof(uint64_t));
            memcpy(idp, &id, sizeof(uint64_t));

            timer->id = (size_t)idp;
            timer->timeout = ms;
            timer->repeat = 0;
            timer->func = &timer_handler;

            int re = luat_timer_start(timer);
            return 1;
        }
    }
    return 0;
}

static int l_test_cwait_error(lua_State *L) {
    lua_pushstring(L,"result1");
    lua_pushstring(L,"result2");
    lua_pushstring(L,"result3");
    luat_pushcwait_error(L,3);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_win32[] =
{
    { "args",      l_win32_args,   0},
    { "testCwaitDelay",      l_test_cwait_delay,   0},
    { "testCwaitError",      l_test_cwait_error,   0},
	{ NULL,                 NULL,   0}
};

LUAMOD_API int luaopen_win32( lua_State *L ) {
    luat_newlib(L, reg_win32);
    return 1;
}
