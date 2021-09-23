
#include "luat_base.h"
#include "luat_spi.h"
#include "sfud.h"

#define LUAT_LOG_TAG "luat.sfud"
#include "luat_log.h"

luat_spi_t sfud_spi_flash;

static int l_sfud_init(lua_State *L){

    sfud_spi_flash.id = luaL_checkinteger(L, 1);
    sfud_spi_flash.cs = luaL_checkinteger(L, 2);
    sfud_spi_flash.bandrate = luaL_checkinteger(L, 3);
    // sfud_spi_flash.id = 0;
    // sfud_spi_flash.cs = 20; // 默认无
    sfud_spi_flash.CPHA = 1; // CPHA0
    sfud_spi_flash.CPOL = 1; // CPOL0
    sfud_spi_flash.dataw = 8; // 8bit
    // sfud_spi_flash.bandrate = 20 * 1000 * 1000; // 2000000U
    sfud_spi_flash.bit_dict = 1; // MSB=1, LSB=0
    sfud_spi_flash.master = 1; // master=1,slave=0
    sfud_spi_flash.mode = 1; // FULL=1, half=0
    luat_spi_setup(&sfud_spi_flash);

    int re = sfud_init();
    lua_pushboolean(L, re == 0 ? 1 : 0);
    return 1;
}

static int l_sfud_get_device_num(lua_State *L){
    int re = sfud_get_device_num();
    lua_pushinteger(L, re);
    return 1;
}

static int l_sfud_get_device(lua_State *L){
    sfud_flash *flash = sfud_get_device(luaL_checkinteger(L, 1));
    lua_pushlightuserdata(L, flash);
    return 1;
}

static int l_sfud_get_device_table(lua_State *L){
    sfud_flash *flash = sfud_get_device_table();
    lua_pushlightuserdata(L, flash);
    return 1;
}

static int l_sfud_chip_erase(lua_State *L){
    const sfud_flash *flash = lua_touserdata(L, 1);
    sfud_err re = sfud_chip_erase(flash);
    lua_pushinteger(L, re);
    return 1;
}

static int l_sfud_erase(lua_State *L){
    const sfud_flash *flash = lua_touserdata(L, 1);
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = luaL_checkinteger(L, 3);
    sfud_err re = sfud_erase(flash,addr,size);
    lua_pushinteger(L, re);
    return 1;
}


static int l_sfud_read(lua_State *L){
    const sfud_flash *flash = lua_touserdata(L, 1);
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = luaL_checkinteger(L, 3);
    uint8_t* data = (uint8_t*)luat_heap_malloc(size);
    sfud_err re = sfud_read(flash, addr, size,data);
    if(re != SFUD_SUCCESS){
        size = 0;
        LLOGD("sfud_read re %d", re);
    }
    lua_pushlstring(L, data, size);
    luat_heap_free(data);
    return 1;
}
    
static int l_sfud_write(lua_State *L){
    const sfud_flash *flash = lua_touserdata(L, 1);
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = 0;
    const char* data = luaL_checklstring(L, 3, &size);
    sfud_err re = sfud_write(flash, addr, size,data);
    lua_pushinteger(L, re);
    return 1;
}

static int l_sfud_erase_write(lua_State *L){
    const sfud_flash *flash = lua_touserdata(L, 1);
    uint32_t addr = luaL_checkinteger(L, 2);
    size_t size = 0;
    const char* data = luaL_checklstring(L, 3, &size);
    sfud_err re = sfud_erase_write(flash, addr, size,data);
    lua_pushinteger(L, re);
    return 1;
}

#include "rotable.h"
static const rotable_Reg reg_sfud[] =
{
    { "init",       l_sfud_init,        0},
    { "get_device_num",       l_sfud_get_device_num,        0},
    { "get_device",       l_sfud_get_device,        0},
    { "get_device_table",       l_sfud_get_device_table,        0},
    { "erase",       l_sfud_erase,        0},
    { "chip_erase",       l_sfud_chip_erase,        0},
    { "read",       l_sfud_read,        0},
    { "write",       l_sfud_write,        0},
    { "erase_write",       l_sfud_erase_write,        0},
	{ NULL, NULL, 0}
};

LUAMOD_API int luaopen_sfud( lua_State *L ) {
    luat_newlib(L, reg_sfud);
    return 1;
}
