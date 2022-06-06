
/*
@module  adc
@summary 数模转换
@version 1.0
@date    2020.07.03
@demo adc
*/
#include "luat_base.h"
#include "luat_adc.h"

/**
打开adc通道
@api adc.open(id)
@int 通道id,与具体设备有关,通常从0开始
@return boolean 打开结果
@usage
-- 打开adc通道2,并读取
if adc.open(2) then
    log.info("adc", adc.read(2))
end
adc.close(2)
 */
static int l_adc_open(lua_State *L) {
    if (luat_adc_open(luaL_checkinteger(L, 1), NULL) == 0) {
        lua_pushboolean(L, 1);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

/**
读取adc通道
@api adc.read(id)
@int 通道id,与具体设备有关,通常从0开始
@return int 原始值
@return int 从原始值换算得出的电压值，通常单位是mV
@usage
-- 打开adc通道2,并读取
if adc.open(2) then
    log.info("adc", adc.read(2))
end
adc.close(2)
 */
static int l_adc_read(lua_State *L) {
    int val = 0xFF;
    int val2 = 0xFF;
    if (luat_adc_read(luaL_checkinteger(L, 1), &val, &val2) == 0) {
        lua_pushinteger(L, val);
        lua_pushinteger(L, val2);
        return 2;
    }
    else {
        lua_pushinteger(L, 0xFF);
        return 1;
    }
}

/**
关闭adc通道
@api adc.close(id)
@int 通道id,与具体设备有关,通常从0开始
@usage
-- 打开adc通道2,并读取
if adc.open(2) then
    log.info("adc", adc.read(2))
end
adc.close(2)
 */
static int l_adc_close(lua_State *L) {
    luat_adc_close(luaL_checkinteger(L, 1));
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_adc[] =
{
    { "open" ,       ROREG_FUNC(l_adc_open)},
    { "read" ,       ROREG_FUNC(l_adc_read)},
    { "close" ,      ROREG_FUNC(l_adc_close)},
	{ NULL,          ROREG_INT(0) }
};

LUAMOD_API int luaopen_adc( lua_State *L ) {
    luat_newlib2(L, reg_adc);
    return 1;
}
