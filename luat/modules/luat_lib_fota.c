
/*
@module  fota
@summary 底层固件升级
@version core V0007
@date    2022.05.26
@demo ota
*/
#include "luat_base.h"
#include "luat_fota.h"
#include "luat_zbuff.h"
#include "luat_spi.h"
#define LUAT_LOG_TAG "fota"
#include "luat_log.h"

/**
初始化fota流程，目前只有105能使用
@api mcu.fotaInit(storge_location, param1)
@int or string fota数据存储的起始位置，如果是int，则是由芯片平台具体判断，如果是string，则存储在文件系统中，如果为nil，则由底层决定存储位置
@int 数据存储的最大空间
@userdata param1，如果数据存储在spiflash时,为spi_device
@return 成功返回true, 失败返回false
@usage
-- 初始化fota流程
local result = mcu.fotaInit(0, 0x00300000, spi_device)	--由于105的flash从0x01000000开始，所以0就是外部spiflash
*/
static int l_fota_init(lua_State* L)
{
	uint32_t address = 0xffffffff;
    size_t len = 0;
    uint32_t length;
    const char *buf = NULL;
    luat_spi_device_t* spi_device = NULL;
    if (lua_type(L, 1) == LUA_TSTRING)
    {
    	buf = lua_tolstring(L, 1, &len);//取出字符串数据
    }
    else
    {
    	address = luaL_optinteger(L, 1, 0xffffffff);
    }
    length = luaL_optinteger(L, 2, 0);
    if (lua_isuserdata(L, 3))
    {
    	spi_device = (luat_spi_device_t*)lua_touserdata(L, 3);
    }
	lua_pushboolean(L, !luat_fota_init(address, length, spi_device, buf, len));
	return 1;
}

/**
等待底层fota流程准备好，目前只有105能使用
@api mcu.fotaWait()
@boolean 是否完整走完流程，true 表示正确走完流程了
@return
@boolean 准备好返回true
@usage
local isDone = mcu.fotaWait()
*/
static int l_fota_wait(lua_State* L)
{
    lua_pushboolean(L, luat_fota_wait_ready());
	return 1;
}

/**
写入fota数据，目前只有105能使用
@api mcu.fotaRun(buff)
@zbuff or string fota数据，尽量用zbuff，如果传入的是zbuff，写入成功后，自动清空zbuff内的数据
@return
@boolean 有异常返回true
@boolean 接收到最后一块返回true
@int 还未写入的数据量，超过64K必须做等待
@usage
-- 写入fota流程
local isError, isDone, cache = mcu.fotaRun(buf)
*/
static int l_fota_write(lua_State* L)
{
	int result;
    size_t len;
    const char *buf;
    if(lua_isuserdata(L, 1))
    {
        luat_zbuff_t *buff = ((luat_zbuff_t *)luaL_checkudata(L, 1, LUAT_ZBUFF_TYPE));
        result = luat_fota_write(buff->addr, buff->used);
    }
    else
    {
        buf = lua_tolstring(L, 1, &len);//取出字符串数据
        result = luat_fota_write((uint8_t*)buf, len);
    }
    if (result > 0)
    {
    	lua_pushboolean(L, 0);
    	lua_pushboolean(L, 0);
    }
    else if (result == 0)
    {
    	lua_pushboolean(L, 0);
    	lua_pushboolean(L, 1);
    }
    else
    {
    	lua_pushboolean(L, 1);
    	lua_pushboolean(L, 1);
    }
    lua_pushinteger(L, result);
	return 3;
}

/**
等待底层fota流程完成，目前只有105能使用
@api mcu.fotaDone()
@boolean 是否完整走完流程，true 表示正确走完流程了
@return
@boolean 有异常返回true
@boolean 写入到最后一块返回true
@usage
local isError, isDone = mcu.fotaDone()
*/
static int l_fota_done(lua_State* L)
{
	int result = luat_fota_done();
    if (result > 0)
    {
    	lua_pushboolean(L, 0);
    	lua_pushboolean(L, 0);
    }
    else if (result == 0)
    {
    	lua_pushboolean(L, 0);
    	lua_pushboolean(L, 1);
    }
    else
    {
    	lua_pushboolean(L, 1);
    	lua_pushboolean(L, 1);
    }
	return 2;
}

/**
结束fota流程，目前只有105能使用
@api mcu.fotaEnd(is_ok)
@boolean 是否完整走完流程，true 表示正确走完流程了
@return 成功返回true, 失败返回false
@usage
-- 结束fota流程
local result = mcu.fotaEnd(true)
*/
static int l_fota_end(lua_State* L)
{
	lua_pushboolean(L, !luat_fota_end(lua_toboolean(L, 1)));
	return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_fota[] =
{
	{ "init",		ROREG_FUNC(l_fota_init)},
	{ "wait",		ROREG_FUNC(l_fota_wait)},
	{ "run",		ROREG_FUNC(l_fota_write)},
	{ "isDone",		ROREG_FUNC(l_fota_done)},
	{ "finish",		ROREG_FUNC(l_fota_end)},
	{ NULL,         ROREG_INT(0) }
};

LUAMOD_API int luaopen_fota( lua_State *L ) {
    luat_newlib2(L, reg_fota);
    return 1;
}
