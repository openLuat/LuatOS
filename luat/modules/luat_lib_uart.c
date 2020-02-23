#include "luat_base.h"
#include "luat_log.h"
#include "luat_uart.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"

int l_uart_handler(lua_State *L, void* ptr) {
    luaL_Buffer b;
    int *callback = (uint8_t *)ptr;
    if(*callback != LUA_REFNIL)
    {
        lua_geti(L, LUA_REGISTRYINDEX, *callback);
        if (!lua_isnil(L, -1))
        {
            lua_call(L, 0, 0);
        }
    }

    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}

static int l_uart_setup(lua_State *L)
{
    luat_uart_t *uart_config = (luat_uart_t *)luat_heap_malloc(sizeof(luat_uart_t));
    uart_config->id = luaL_checkinteger(L, 1);
    uart_config->baud_rate = luaL_checkinteger(L, 2);
    uart_config->data_bits = luaL_optinteger(L, 3, 8);
    uart_config->stop_bits = luaL_optinteger(L, 4, 1);
    uart_config->parity = luaL_optinteger(L, 5, LUAT_PARITY_NONE);
    uart_config->bit_order = luaL_optinteger(L, 6, LUAT_BIT_ORDER_LSB);
    uart_config->bufsz = luaL_optinteger(L, 7, 512);
    if(lua_isfunction(L, 8))
    {
        lua_pushvalue(L, 8);
        uart_config->callback = luaL_ref(L, LUA_REGISTRYINDEX);
    }
    else
    {
        uart_config->callback = LUA_REFNIL;//没传值
    }


    lua_pushinteger(L, luat_uart_setup(uart_config));

    luat_heap_free(uart_config);
    return 1;
}

static int l_uart_write(lua_State *L)
{
    size_t len;
    const char *buf;
    uint8_t id = luaL_checkinteger(L, 1);
    buf = lua_tolstring(L, 2, &len);//取出字符串数据
    //uint32_t length = len;
    uint8_t result = luat_uart_write(id, buf, len);
    lua_pushinteger(L, result);
    return 1;
}

static int l_uart_read(lua_State *L)
{
    uint8_t id = luaL_checkinteger(L, 1);
    uint32_t length = luaL_checkinteger(L, 2);
    uint8_t *rev = (uint8_t *)luat_heap_malloc(length);
    uint8_t result = luat_uart_read(id, rev, length);
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    luaL_addlstring(&b, rev, result);
    luaL_pushresult(&b);
    luat_heap_free(rev);
    return 1;
}

static int l_uart_close(lua_State *L)
{
    uint8_t result = luat_uart_close(luaL_checkinteger(L, 1));
    lua_pushinteger(L, result);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_uart[] =
{
    { "setup",  l_uart_setup,0},
    { "close",  l_uart_close,0},
    { "write",  l_uart_write,0},
    { "read",   l_uart_read,0},
    //校验位
    { "Odd",            NULL,           LUAT_PARITY_ODD},
    { "Even",           NULL,           LUAT_PARITY_EVEN},
    { "None",           NULL,           LUAT_PARITY_NONE},
    //高低位顺序
    { "LSB",            NULL,           LUAT_BIT_ORDER_LSB},
    { "MSB",            NULL,           LUAT_BIT_ORDER_MSB},
    { NULL,             NULL ,          0}
};

LUAMOD_API int luaopen_uart(lua_State *L)
{
    rotable_newlib(L, reg_uart);
    return 1;
}
