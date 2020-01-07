
#include "luat_base.h"
#include "luat_log.h"
#include "luat_gpio.h"

static int l_gpio_handler(lua_State *L, const void *ptr) {

}

static int l_gpio_setup(lua_State *L) {
    lua_gettop(L);
    luat_gpio_t conf;
    conf.pin = luaL_checkinteger(L, 1);
    conf.mode = luaL_optinteger(L, 2, LUAT_GPIO_MODE_OUTPUT);
    conf.pull = luaL_optinteger(L, 3, LUAT_GPIO_PULL_UP);
    luat_gpio_setup(conf);
    return 0;
}

static int l_gpio_set(lua_State *L) {
    lua_gettop(L);
    luat_gpio_t conf;
    conf.pin = luaL_checkinteger(L, 1);
    luat_gpio_set(conf, luaL_optinteger(L, 2, 1));
    return 0;
}

static int l_gpio_get(lua_State *L) {
    lua_gettop(L);
    luat_gpio_t conf;
    conf.pin = luaL_checkinteger(L, 1);
    lua_pushinteger(L, luat_gpio_get(conf));
    return 1;
}

static const luaL_Reg reg_gpio[] =
{
    { "setup" , l_gpio_setup },
    { "set" , l_gpio_set },
    { "get" , l_gpio_get },
	{ NULL, NULL }
};

LUAMOD_API int luaopen_gpio( lua_State *L ) {
    luaL_newlib(L, reg_gpio);
    return 1;
}
