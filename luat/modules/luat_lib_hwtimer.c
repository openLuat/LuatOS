#include "luat_base.h"
#include "luat_hwtimer.h"

static int l_hwtimer_create(lua_State* L) {
    luat_hwtimer_conf_t conf = {0};
    conf.unit = luaL_checkinteger(L, 1);
    conf.timeout = luaL_checkinteger(L, 2);
    if (!lua_isnoneornil(L, 3))
        conf.is_repeat = lua_toboolean(L, 3);
    int id = luat_hwtimer_create(&conf);
    lua_pushinteger(L, id);
    return 1;
}

static int l_hwtimer_start(lua_State* L) {
    int id = luaL_checkinteger(L, 1);
    int ret = luat_hwtimer_start(id);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

static int l_hwtimer_stop(lua_State* L) {
    int id = luaL_checkinteger(L, 1);
    int ret = luat_hwtimer_stop(id);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

static int l_hwtimer_read(lua_State* L) {
    int id = luaL_checkinteger(L, 1);
    uint32_t ret = luat_hwtimer_read(id);
    lua_pushinteger(L, ret);
    return 1;
}

static int l_hwtimer_change(lua_State* L) {
    int id = luaL_checkinteger(L, 1);
    uint32_t newtimeout = luaL_checkinteger(L, 2);
    int ret = luat_hwtimer_change(id, newtimeout);
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

static int l_hwtimer_destroy(lua_State* L) {
    int id = luaL_checkinteger(L, 1);
    uint32_t ret = luat_hwtimer_destroy(id);
    lua_pushinteger(L, ret);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_hwtimer[] =
{
    { "create" ,        l_hwtimer_create, 0},
    { "start",          l_hwtimer_start,  0},
    { "stop",           l_hwtimer_stop,   0},
    { "read",           l_hwtimer_read,   0},
    { "change",         l_hwtimer_change, 0},
    { "destroy",        l_hwtimer_destroy,0},
	{ NULL,          NULL ,       0}
};

LUAMOD_API int luaopen_hwtimer( lua_State *L ) {
    luat_newlib(L, reg_hwtimer);
    return 1;
}
