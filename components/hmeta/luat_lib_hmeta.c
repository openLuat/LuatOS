/*
@module  hmeta
@summary 硬件元数据
@version 1.0
@date    2022.01.11
@usage
-- 本库开发中
--[[
    这个库的作用是展示当前硬件的能力, 例如:
1. 有多少GPIO, 各GPIO默认模式是什么, 是否支持上拉/下拉
2. 有多少I2C,支持哪些速率
3. 有多少SPI,支持哪些速率和模式
4. 扩展属性, 例如区分Air780E和Air600E

]]
*/
#include "luat_base.h"
#include "luat_hmeta.h"

static int l_hmeta_model(lua_State *L) {
    return 0;
}

static int l_hmeta_gpio(lua_State *L) {
    return 0;
}

static int l_hmeta_uart(lua_State *L) {
    return 0;
}

#include "rotable2.h"
static const rotable_Reg_t reg_hmeta[] =
{
    { "model" ,           ROREG_FUNC(l_hmeta_model)},
    { "gpio" ,            ROREG_FUNC(l_hmeta_gpio)},
    { "uart" ,            ROREG_FUNC(l_hmeta_uart)},
	{ NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_hmeta( lua_State *L ) {
    luat_newlib2(L, reg_hmeta);
    return 1;
}
