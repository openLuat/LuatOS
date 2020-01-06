
#include "luat_base.h"
#include "luat_log.h"
#include "luat_gpio.h"

static int l_gpio_handler(lua_State *L, const void *ptr) {

}

static int l_gpio_setup(lua_State *L) {
    
    return 0;
}

static int l_gpio_set(lua_State *L) {
    return 0;
}

static int l_gpio_get(lua_State *L) {
    return 0;
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
