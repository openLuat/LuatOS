
/*
@module  mcu
@summary 封装mcu一些特殊操作
@version core V0007
@date    2021.08.18
*/
#include "luat_base.h"
#include "luat_mcu.h"

/*
设置主频,单位MHZ. 请注意,主频与外设主频有关联性, 例如主频2M时SPI的最高只能1M
@api mcu.setClk(mhz)
@int 主频,根据设备的不同有不同的有效值,请查阅手册
@return bool 成功返回true,否则返回false
@usage
-- 设置到80MHZ
mcu.setClk(80)
sys.wait(1000)
-- 设置到240MHZ
mcu.setClk(240)
sys.wait(1000)
-- 设置到2MHZ
mcu.setClk(2)
sys.wait(1000)
*/
static int l_mcu_set_clk(lua_State* L) {
    int ret = luat_mcu_set_clk((size_t)luaL_checkinteger(L, 1));
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
获取主频,单位MHZ.
@api mcu.getClk()
@return int 若失败返回-1,否则返回主频数值,若等于0,可能处于32k晶振的省电模式
@usage
local mhz = mcu.getClk()
print("Boom", mhz)
*/
static int l_mcu_get_clk(lua_State* L) {
    int mhz = luat_mcu_get_clk();
    lua_pushinteger(L, mhz);
    return 1;
}

/*
获取设备唯一id. 注意,可能包含不可字符,如需查看建议toHex()后打印
@api mcu.unique_id()
@return string 设备唯一id.若不支持, 会返回空字符串.
@usage
local unique_id = mcu.unique_id()
print("unique_id", unique_id)
*/
static int l_mcu_unique_id(lua_State* L) {
    size_t len = 0;
    const char* id = luat_mcu_unique_id(&len);
    lua_pushlstring(L, id, len);
    return 1;
}

/*
获取启动后的tick数,注意会出现溢出会出现负数
@api mcu.ticks()
@return int 当前tick值
@usage
local tick = mcu.ticks()
print("ticks", tick)
*/
static int l_mcu_ticks(lua_State* L) {
    long tick = luat_mcu_ticks();
    lua_pushinteger(L, tick);
    return 1;
}


#include "rotable.h"
static const rotable_Reg reg_mcu[] =
{
    { "setClk" ,        l_mcu_set_clk, 0},
    { "getClk",         l_mcu_get_clk,  0},
    { "unique_id",      l_mcu_unique_id, 0},
    { "ticks",          l_mcu_ticks, 0},
	{ NULL,          NULL ,       0}
};

LUAMOD_API int luaopen_mcu( lua_State *L ) {
    luat_newlib(L, reg_mcu);
    return 1;
}
