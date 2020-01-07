
#include "luat_base.h"
#include "luat_log.h"

struct luat_lib_timer_t
{
    void* osTimer;
    int type;
    size_t timeout;
    size_t repeat;
};


static int l_timer_handler(lua_State *L, const void *ptr) {

}

static int l_timer_start(lua_State *L) {
    
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
