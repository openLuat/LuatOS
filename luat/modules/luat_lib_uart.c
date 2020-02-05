#include "luat_base.h"
#include "luat_log.h"
#include "luat_uart.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"

static int l_uart_setup(lua_State *L) {
    luat_uart_t* uart_config = (luat_uart_t*)luat_heap_malloc(sizeof(luat_uart_t));
    uart_config->id = luaL_checkinteger(L, 1);
    uart_config->baud_rate = luaL_checkinteger(L, 2);
    uart_config->data_bits = luaL_checkinteger(L, 3);
    uart_config->stop_bits = luaL_checkinteger(L, 4);
    uart_config->parity = luaL_checkinteger(L, 5);
    uart_config->bit_order = luaL_checkinteger(L, 6);
    uart_config->bufsz = luaL_checkinteger(L, 7);

    lua_pushinteger(L, luat_uart_setup(uart_config));

    luat_heap_free(uart_config);
    return 1;
}

static int l_uart_write(lua_State *L) {
    size_t len;
    const char* buf;
    uint8_t id = luaL_checkinteger(L, 1);
    buf = lua_tolstring( L, 2, &len );
    //uint32_t length = len;
    uint8_t result = luat_uart_write(id,buf,len);
    lua_pushinteger(L, result);
    return 1;
}

static int l_uart_read(lua_State *L) {
    uint8_t id = luaL_checkinteger(L, 1);
    uint32_t length = luaL_checkinteger(L, 2);
    uint8_t* rev = (uint8_t*)luat_heap_malloc(length);
    uint8_t result = luat_uart_read(id,rev,length);
    luaL_Buffer b;
    luaL_buffinit( L, &b);
    luaL_addlstring(&b, rev, result);
    luaL_pushresult(&b);
    return 1;
}

static int l_uart_close(lua_State *L) {
    uint8_t result = luat_uart_close(luaL_checkinteger(L, 1));
    lua_pushinteger(L, result);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_uart[] =
{
    { "setup",l_uart_setup,0},
    { "close",l_uart_close,0},
    { "write",l_uart_write,0},
    { "read",l_uart_read,0},
    //校验位
    { "Odd",            NULL,           PARITY_ODD},
    { "Even",           NULL,           PARITY_EVEN},
    { "None",           NULL,           PARITY_NONE},
    //高低位顺序
    { "LSB",            NULL,           BIT_ORDER_LSB},
    { "MSB",            NULL,           BIT_ORDER_MSB},
	{ NULL,             NULL ,          0}
};

LUAMOD_API int luaopen_uart( lua_State *L ) {
    rotable_newlib(L, reg_uart);
    return 1;
}
