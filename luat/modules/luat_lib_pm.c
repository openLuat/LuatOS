
#include "lua.h"
#include "lauxlib.h"
#include "luat_base.h"
#include "luat_pm.h"
#include "luat_msgbus.h"

static int lua_event_cb = 0;

static int l_pm_request(lua_State *L) {
    int mode = luaL_checkinteger(L, 1);
    if (luat_pm_request(mode) == 0)
        lua_pushboolean(L, 1);
    else
        lua_pushboolean(L, 0);
    return 1;
}

static int l_pm_release(lua_State *L) {
    int mode = luaL_checkinteger(L, 1);
    if (luat_pm_release(mode) == 0)
        lua_pushboolean(L, 1);
    else
        lua_pushboolean(L, 0);
    return 1;
}

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

static int l_pm_dtimer_stop(lua_State *L) {
    int dtimer_id = luaL_checkinteger(L, 1);
    luat_pm_dtimer_stop(dtimer_id);
    return 0;
}

static int l_pm_on(lua_State *L) {
    if (lua_isfunction(L, 1)) {
        if (lua_event_cb != 0) {
            luaL_unref(L, LUA_REGISTRYINDEX, lua_event_cb);
        }
        lua_event_cb = luaL_ref(L, LUA_REGISTRYINDEX);
    }
    else if (lua_event_cb != 0) {
        luaL_unref(L, LUA_REGISTRYINDEX, lua_event_cb);
    }
    return 0;
}

static int l_pm_last_reson(lua_State *L) {
    lua_pushinteger(L, luat_pm_last_state());
    return 1;
}

static int luat_pm_msg_handler(lua_State *L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    if (lua_event_cb == 0) {
        return 0;
    }
    lua_geti(L, LUA_REGISTRYINDEX, lua_event_cb);
    if (lua_isfunction(L, -1)) {
        lua_pushinteger(L, msg->arg1);
        lua_pushinteger(L, msg->arg2);
        lua_call(L, 2, 0);
    }
    return 0;
}

void luat_pm_cb(int event, int arg, void* args) {
    if (lua_event_cb != 0) {
        rtos_msg_t msg;
        msg.handler = luat_pm_msg_handler;
        msg.arg1 = event;
        msg.arg2 = arg;
        msg.ptr = NULL;
        luat_msgbus_put(&msg, 0);
    }
}

#include "rotable.h"
static const rotable_Reg reg_pm[] =
{
    { "request" ,       l_pm_request , 0},
    { "release" ,       l_pm_release,  0},
    { "dtimerStart",    l_pm_dtimer_start,0},
    { "dtimerStop" ,    l_pm_dtimer_stop, 0},
    { "on",             l_pm_on,   0},
    { "lastReson",      l_pm_last_reson, 0},
    { "IDLE",           NULL, LUAT_PM_SLEEP_MODE_IDLE},
    { "LIGHT",          NULL, LUAT_PM_SLEEP_MODE_LIGHT},
    { "DEEP",           NULL, LUAT_PM_SLEEP_MODE_DEEP},
    { "HIB",            NULL, LUAT_PM_SLEEP_MODE_STANDBY},
	{ NULL,          NULL ,       0}
};

LUAMOD_API int luaopen_pm( lua_State *L ) {
    rotable_newlib(L, reg_pm);
    return 1;
}
