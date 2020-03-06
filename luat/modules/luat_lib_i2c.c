
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_i2c.h"

static int l_i2c_exist(lua_State *L) {
    int re = luat_i2c_exist(luaL_checkinteger(L, 1));
    lua_pushinteger(L, re);
    return 1;
}

static int l_i2c_setup(lua_State *L) {
    int re = luat_i2c_setup(luaL_checkinteger(L, 1), luaL_optinteger(L, 2, 0), luaL_optinteger(L, 3, 0));
    lua_pushinteger(L, re == 0 ? 1 : 0);
    return 1;
}

static int l_i2c_send(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int addr = luaL_checkinteger(L, 2);
    size_t len;
    if (lua_isstring(L, 3)) {
        const char* buff = luaL_checklstring(L, 3, &len);
        luat_i2c_send(id, addr, (char*)buff, len);
    }
    else if (lua_isinteger(L, 3)) {
        len = lua_gettop(L) - 2;
        char buff[len+1];
        for (size_t i = 0; i < len; i++)
        {
            buff[i] = lua_tointeger(L, 3+i);
        }
        luat_i2c_send(id, addr, buff, len);
    }
    return 0;
}

static int l_i2c_recv(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int addr = luaL_checkinteger(L, 2);
    int len = luaL_checkinteger(L, 3);
    char buf[len];
    luat_i2c_recv(id, addr, &buf[0], len);
    lua_pushlstring(L, buf, len);
    return 1;
}

static int l_i2c_write_reg(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    int addr = luaL_checkinteger(L, 2);
    int reg = luaL_checkinteger(L, 3);
    size_t len;
    if (lua_isstring(L, 4)) {
        const char* buff = luaL_checklstring(L, 4, &len);
        luat_i2c_write_reg(id, addr, reg, (char*)buff, len);
    }
    else if (lua_isinteger(L, 4)) {
        len = lua_gettop(L) - 2;
        char buff[len+1];
        for (size_t i = 0; i < len; i++)
        {
            buff[i] = lua_tointeger(L, 3+i);
        }
        luat_i2c_write_reg(id, addr, reg, buff, len);
    }
    return 0;
}

static int l_i2c_close(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    luat_ic2_close(id);
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_i2c[] =
{
    { "exist", l_i2c_exist, 0},
    { "setup", l_i2c_setup, 0},
    { "send", l_i2c_send, 0},
    { "recv", l_i2c_recv, 0},
    { "writeReg", l_i2c_write_reg, 0},
    // { "readReg", l_i2c_read_reg, 0},
    { "close", l_i2c_close, 0},
    { "FAST",  NULL, 1},
    { "SLOW",  NULL, 0},
	{ NULL, NULL, 0}
};

LUAMOD_API int luaopen_i2c( lua_State *L ) {
    rotable_newlib(L, reg_i2c);
    return 1;
}
