
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_malloc.h"

static int l_timer_handler(lua_State *L) {
    luat_printf("l_timer_handler\n");
    struct luat_timer_t *timer = (struct luat_timer_t *)lua_touserdata(L, 1);
    if (timer->repeat == 0) {
        luat_timer_stop(timer);
    }
    else if (timer->repeat > 0) {
        timer->repeat --;
    }
    return 0;
}

static int l_timer_start(lua_State *L) {
    lua_gettop(L);
    if (lua_isinteger(L, 1)) {
        lua_Integer ms = luaL_checkinteger(L, 1);
        if (ms > 0) {
            struct luat_timer_t *t = luat_heap_malloc(sizeof(struct luat_timer_t));
            t->type = 0;
            t->timeout = ms;
            t->repeat = 0;
            t->func = &l_timer_handler;

            if (lua_gettop(L) > 1) {
                if (lua_isnumber(L, 2)) {
                    lua_Integer repeat = luaL_checkinteger(L, 2);
                    t->repeat = repeat;
                }
                else if (lua_isfunction(L, 2)) {
                    //t->ptr = lua_
                }
            }

            luat_timer_start(t);
            lua_pushlightuserdata(L, t);
            return 1;
        }
    }
    return 0;
}

static int l_timer_stop(lua_State *L) {
    return 0;
}


static int l_timer_mdelay(lua_State *L) {
    lua_gettop(L);
    if (lua_isinteger(L, 1)) {
        lua_Integer ms = luaL_checkinteger(L, 1);
        if (ms)
            luat_timer_mdelay(ms);
    }
    return 0;
}

static const luaL_Reg reg_timer[] =
{
    { "start" , l_timer_start },
    { "stop" , l_timer_stop },
    { "mdelay" , l_timer_mdelay },
	{ NULL, NULL }
};

LUAMOD_API int luaopen_timer( lua_State *L ) {
    luaL_newlib(L, reg_timer);
    return 1;
}
