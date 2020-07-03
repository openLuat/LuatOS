
/*
@module  adc
@summary 数模转换
@version 1.0
@data    2020.07.03
*/
#include "luat_base.h"
#include "luat_adc.h"

static int l_adc_open(lua_State *L) {
    if (luat_adc_open(luaL_checkinteger(L, 1), NULL) == 0) {
        lua_pushboolean(L, 1);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}
static int l_adc_read(lua_State *L) {
    int val = 0xFF;
    int val2 = 0xFF;
    if (luat_adc_read(luaL_checkinteger(L, 1), &val, &val2) == 0) {
        lua_pushinteger(L, val);
        lua_pushinteger(L, val2);
        return 2;
    }
    else {
        lua_pushinteger(L, 0xFF);
        return 1;
    }
}

static int l_adc_close(lua_State *L) {
    luat_adc_close(luaL_checkinteger(L, 1));
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_adc[] =
{
    { "open" ,       l_adc_open , 0},
    { "read" ,       l_adc_read , 0},
    { "close" ,      l_adc_close, 0},
	{ NULL,          NULL ,       0}
};

LUAMOD_API int luaopen_adc( lua_State *L ) {
    rotable_newlib(L, reg_adc);
    return 1;
}
