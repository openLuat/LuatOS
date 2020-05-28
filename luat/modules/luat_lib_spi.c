/*
@module  spi
@summary spi操作库
@version 1.0
@data    2020.04.23
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_sys.h"
#include "luat_msgbus.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_spi.h"

static int l_spi_setup(lua_State *L) {
    luat_spi_t *spi_config = (luat_spi_t *)luat_heap_malloc(sizeof(luat_spi_t));
    spi_config->id = luaL_checkinteger(L, 1);
    spi_config->cs = luaL_checkinteger(L, 2);
    spi_config->CPHA = luaL_checkinteger(L, 3);
    spi_config->CPOL = luaL_checkinteger(L, 4);
    spi_config->dataw = luaL_checkinteger(L, 5);
    spi_config->bandrate = luaL_checkinteger(L, 6);
    spi_config->bit_dict = luaL_optinteger(L, 7, 1);
    spi_config->master = luaL_optinteger(L, 8, 1);
    spi_config->mode = luaL_optinteger(L, 9, 1);

    luat_spi_setup(&spi_config);
    luat_heap_free(spi_config);
    return 0;
}
static int l_spi_close(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    luat_spi_close(id);
    return 0;
}
static int l_spi_transfer(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    size_t len;
    char* recv_buff;
    const char* send_buff;
    send_buff = lua_tolstring(L, 2, &len);
    len = luat_spi_transfer(id, send_buff, recv_buff, len);
    if (len > 0) {
        lua_pushlstring(L, recv_buff, len);
        return 1;
    }
    return 0;
}
static int l_spi_recv(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    char* recv_buff;
    int len = luaL_checkinteger(L, 2);
    luat_spi_recv(id, recv_buff, len);
    return 0;
}
static int l_spi_send(lua_State *L) {
    int id = luaL_checkinteger(L, 1);
    size_t len;
    char* recv_buff;
    const char* send_buff;
    send_buff = lua_tolstring(L, 2, &len);
    luat_spi_send(id, send_buff, len);
    return 0;
}


//------------------------------------------------------------------
#include "rotable.h"
static const rotable_Reg reg_spi[] =
{
    { "setup" ,           l_spi_setup,         0},
    { "close",            l_spi_close,         0},
    { "transfer",         l_spi_transfer,      0},
    { "recv",             l_spi_recv,         0},
    { "send",             l_spi_send,         0},

    { "MSB",               0,                  1},
    { "LSB",               0,                  2},
    { "master",            0,                  1},
    { "slave",             0,                  2},
    { "full",              0,                  1},
    { "half",              0,                  2},

	{ NULL,                 NULL,              0}
};

LUAMOD_API int luaopen_spi( lua_State *L ) {
    rotable_newlib(L, luaopen_spi);
    return 1;
}
