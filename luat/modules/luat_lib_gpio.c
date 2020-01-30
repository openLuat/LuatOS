
#include "luat_base.h"
#include "luat_log.h"
#include "luat_gpio.h"
#include "luat_malloc.h"

static int l_gpio_handler(lua_State *L, void* ptr) {
    luat_gpio_t *gpio = (luat_gpio_t *)ptr;
    lua_getglobal(L, "sys_pub");
    if (!lua_isnil(L, -1)) {
        lua_pushfstring(L, "IRQ_%d", (char)gpio->pin);
        lua_pushinteger(L, luat_gpio_get(gpio->pin));
        lua_call(L, 2, 0);
        lua_pushinteger(L, 0);
        return 1;
    }
    //else {
    //    luat_print("_G.sys_pub is nil\n");
    //    lua_pop(L, 1);
    //}
    lua_pushinteger(L, MSG_GPIO);
    // lua_pushinteger(L, gpio->pin);
    // lua_pushinteger(L, luat_gpio_get(gpio->pin));
    // return 3;
    return 1;
}

static int l_gpio_setup(lua_State *L) {
    lua_gettop(L);
    luat_gpio_t* conf = (luat_gpio_t*)luat_heap_malloc(sizeof(luat_gpio_t));
    conf->pin = luaL_checkinteger(L, 1);
    conf->mode = luaL_checkinteger(L, 2);
    conf->pull = luaL_optinteger(L, 3, Luat_GPIO_DEFAULT);
    conf->irq = luaL_optinteger(L, 4, Luat_GPIO_BOTH);
    if (conf->mode == Luat_GPIO_IRQ) {
        conf->func = &l_gpio_handler;
    }
    else {
        conf->func = NULL;
        
    }
    int re = luat_gpio_setup(conf);
    if (conf->mode == Luat_GPIO_IRQ) {
        if (re) {
            luat_heap_free(conf);
        }
    }
    else {
        luat_heap_free(conf);
    }
    return re;
}

static int l_gpio_set(lua_State *L) {
    luat_gpio_set(luaL_checkinteger(L, 1), luaL_checkinteger(L, 2));
    return 0;
}

static int l_gpio_get(lua_State *L) {
    lua_pushinteger(L, luat_gpio_get(luaL_checkinteger(L, 1)) & 0x01 ? 1 : 0);
    return 1;
}


static int l_gpio_close(lua_State *L) {
    luat_gpio_close(luaL_checkinteger(L, 1));
    return 0;
}

#include "rotable.h"
static const rotable_Reg reg_gpio[] =
{
    { "setup" ,         l_gpio_setup ,0},
    { "set" ,           l_gpio_set,   0},
    { "get" ,           l_gpio_get,   0 },
    { "close" ,         l_gpio_close, 0 },
    { "LOW",            NULL,         Luat_GPIO_LOW},
    { "HIGH",           NULL,         Luat_GPIO_HIGH},

    { "OUTPUT",         NULL,         Luat_GPIO_OUTPUT},
    { "INPUT",          NULL,         Luat_GPIO_INPUT},
    { "IRQ",            NULL,         Luat_GPIO_IRQ},

    { "PULLUP",         NULL,         Luat_GPIO_PULLUP},
    { "PULLDOWN",       NULL,         Luat_GPIO_PULLDOWN},

    { "RISING",         NULL,         Luat_GPIO_RISING},
    { "FALLING",        NULL,         Luat_GPIO_FALLING},
    { "BOTH",           NULL,         Luat_GPIO_BOTH},
	{ NULL,             NULL ,        0}
};

LUAMOD_API int luaopen_gpio( lua_State *L ) {
    rotable_newlib(L, reg_gpio);
    return 1;
}
