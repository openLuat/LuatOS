
#include "luat_base.h"
#include "luat_log.h"
#include "luat_gpio.h"
#include "luat_malloc.h"

static int l_gpio_handler(lua_State *L, void* ptr) {
    luat_printf("l_gpio_handler\n");
    struct luat_gpio_t *gpio = (struct luat_gpio_t *)ptr;
    lua_pushinteger(L, MSG_GPIO);
    lua_pushinteger(L, gpio->pin);
    lua_pushinteger(L, luat_gpio_get(gpio->pin));
    return 3;
}

static int l_gpio_setup(lua_State *L) {
    lua_gettop(L);
    luat_gpio_t* conf = (luat_gpio_t*)luat_heap_malloc(sizeof(struct luat_gpio_t));
    conf->pin = luaL_checkinteger(L, 1);
    conf->mode = luaL_checkinteger(L, 2);
    int is_irq = lua_isfunction(L, 3);
    if (is_irq) {
        conf->callback = &l_gpio_handler;
        conf->irqmode = luaL_optinteger(L, 4, Luat_GPIO_RISING_FALLING);
        luat_printf("gpio.setup enable irq pin=%d\n", conf->pin);
    }
    else {
        conf->callback = NULL;
        conf->irqmode = 0;
    }
    int re = luat_gpio_setup(conf);
    if (is_irq) {
        if (re) {
            luat_heap_free(conf);
        }
    }
    else {
        luat_heap_free(conf);
    }
    return 0;
}

static int l_gpio_set(lua_State *L) {
    lua_gettop(L);
    luat_gpio_set(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2));
    return 0;
}

static int l_gpio_get(lua_State *L) {
    lua_gettop(L);
    lua_pushinteger(L, luat_gpio_get(luaL_checkinteger(L, 1)) & 0x01 ? 1 : 0);
    return 1;
}

static const luaL_Reg reg_gpio[] =
{
    { "setup" , l_gpio_setup },
    { "set" , l_gpio_set },
    { "get" , l_gpio_get },
    { "LOW",     NULL},
    { "HIGH",     NULL},
    { "OUTPUT",     NULL},
    { "INPUT",     NULL},
    { "INPUT_PULLUP",     NULL},
    { "INPUT_PULLDOWN",     NULL},
    { "OUTPUT_OD",     NULL},
    { "RISING",     NULL},
    { "FALLING",     NULL},
    { "RISING_FALLING",     NULL},
	{ NULL, NULL }
};

LUAMOD_API int luaopen_gpio( lua_State *L ) {
    luaL_newlib(L, reg_gpio);

    lua_pushnumber(L, Luat_GPIO_LOW);
    lua_setfield(L, -2, "LOW");
    lua_pushnumber(L, Luat_GPIO_HIGH);
    lua_setfield(L, -2, "HIGH");
    lua_pushnumber(L, Luat_GPIO_OUTPUT);
    lua_setfield(L, -2, "OUTPUT");
    lua_pushnumber(L, Luat_GPIO_INPUT);
    lua_setfield(L, -2, "INPUT");
    lua_pushnumber(L, Luat_GPIO_INPUT_PULLUP);
    lua_setfield(L, -2, "INPUT_PULLUP");
    lua_pushnumber(L, Luat_GPIO_INPUT_PULLDOWN);
    lua_setfield(L, -2, "INPUT_PULLDOWN");
    lua_pushnumber(L, Luat_GPIO_OUTPUT_OD);
    lua_setfield(L, -2, "OUTPUT_OD");
    lua_pushnumber(L, Luat_GPIO_RISING);
    lua_setfield(L, -2, "RISING");
    lua_pushnumber(L, Luat_GPIO_FALLING);
    lua_setfield(L, -2, "FALLING");
    lua_pushnumber(L, Luat_GPIO_RISING_FALLING);
    lua_setfield(L, -2, "RISING_FALLING");

    return 1;
}
